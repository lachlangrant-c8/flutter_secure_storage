/// Web library for flutter_secure_storage
library flutter_secure_storage_web;

import 'dart:convert';
import 'dart:js_interop' as js_interop;
import 'dart:js_interop_unsafe' as js_interop;
import 'dart:typed_data';

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_secure_storage_web/src/subtle.dart' as crypto;
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

/// Web implementation of FlutterSecureStorage
class FlutterSecureStorageWeb extends FlutterSecureStoragePlatform {
  static const _publicKey = 'publicKey';

  /// Registrar for FlutterSecureStorageWeb
  static void registerWith(Registrar registrar) {
    FlutterSecureStoragePlatform.instance = FlutterSecureStorageWeb();
  }

  /// Returns true if the storage contains the given [key].
  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) =>
      Future.value(
        web.window.localStorage.has("${options[_publicKey]!}.$key"),
      );

  /// Deletes associated value for the given [key].
  ///
  /// If the given [key] does not exist, nothing will happen.
  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    web.window.localStorage.removeItem("${options[_publicKey]!}.$key");
  }

  /// Deletes all keys with associated values.
  @override
  Future<void> deleteAll({
    required Map<String, String> options,
  }) =>
      Future.sync(
        () => web.window.localStorage.clear(),
      );

  /// Encrypts and saves the [key] with the given [value].
  ///
  /// If the key was already in the storage, its associated value is changed.
  /// If the value is null, deletes associated value for the given [key].
  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    final value = web.window.localStorage["${options[_publicKey]!}.$key"];

    return _decryptValue(value, options);
  }

  /// Decrypts and returns all keys with associated values.
  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async {
    final map = <String, String>{};
    final prefix = "${options[_publicKey]!}.";
    for (int j = 0; j < web.window.localStorage.length; j++) {
      final key = web.window.localStorage.key(j) ?? "";
      if (!key.startsWith(prefix)) {
        continue;
      }

      final value = await _decryptValue(web.window.localStorage.getItem(key), options);

      if (value == null) {
        continue;
      }

      map[key.substring(prefix.length)] = value;
    }

    return map;
  }

  js_interop.JSObject _getAlgorithm(Uint8List iv) {
    return {'name': 'AES-GCM', 'length': 256, 'iv': iv}.jsify()! as js_interop.JSObject;
  }

  Future<web.CryptoKey> _getEncryptionKey(
    js_interop.JSObject algorithm,
    Map<String, String> options,
  ) async {
    late web.CryptoKey encryptionKey;
    final key = options[_publicKey]!;

    if (web.window.localStorage.has(key)) {
      final jwk = base64Decode(web.window.localStorage[key]!);

      encryptionKey = await crypto.importKey("raw", jwk.toJS, algorithm, false, ["encrypt".toJS, "decrypt".toJS].toJS).toDart;
    } else {
      //final crypto.getRandomValues(Uint8List(256));

      encryptionKey = await crypto.generateKey(algorithm, true, ["encrypt".toJS, "decrypt".toJS].toJS).toDart;

      final jsonWebKey = await crypto.exportKey("raw", encryptionKey).toDart;
      web.window.localStorage[key] = base64Encode(jsonWebKey.toDart.asUint8List());
    }

    return encryptionKey;
  }

  /// Encrypts and saves the [key] with the given [value].
  ///
  /// If the key was already in the storage, its associated value is changed.
  /// If the value is null, deletes associated value for the given [key].
  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    final iv =
    (web.window.crypto.getRandomValues(Uint8List(12).toJS) as js_interop.JSUint8Array).toDart.buffer.asUint8List();

    final algorithm = _getAlgorithm(iv);

    final encryptionKey = await _getEncryptionKey(algorithm, options);

    final encryptedContent = await crypto.encrypt(
      algorithm,
      encryptionKey,
      Uint8List.fromList(
        utf8.encode(value),
      ).toJS,
    ).toDart;

    final encoded =
        "${base64Encode(iv)}.${base64Encode(encryptedContent.toDart.asUint8List())}";

    web.window.localStorage["${options[_publicKey]!}.$key"] = encoded;
  }

  Future<String?> _decryptValue(
    String? cypherText,
    Map<String, String> options,
  ) async {
    if (cypherText == null) {
      return null;
    }

    final parts = cypherText.split(".");

    final iv = base64Decode(parts[0]);
    final algorithm = _getAlgorithm(iv);

    final decryptionKey = await _getEncryptionKey(algorithm, options);

    final value = base64Decode(parts[1]);

    final decryptedContent = await crypto.decrypt(
      _getAlgorithm(iv),
      decryptionKey,
      Uint8List.fromList(value).toJS,
    ).toDart;

    final plainText = utf8.decode(decryptedContent.toDart.asUint8List());

    return plainText;
  }

  @override
  Future<bool> isCupertinoProtectedDataAvailable() async => true;

  @override
  Stream<bool> get onCupertinoProtectedDataAvailabilityChanged => const Stream.empty();
}
