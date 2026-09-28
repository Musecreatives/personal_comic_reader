import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'media_pool_config.dart';

class WebDavException implements Exception {
  final String message;
  const WebDavException(this.message);
  @override
  String toString() => message;
}

/// Minimal WebDAV client (PUT + MKCOL only) for uploading files to a
/// Nextcloud "external storage" mount or any other WebDAV server. Basic
/// auth, same as every WebDAV server accepts.
class WebDavClient {
  final Dio _dio;

  WebDavClient({required MediaPoolConfig config, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: config.baseUrl.endsWith('/')
                  ? config.baseUrl
                  : '${config.baseUrl}/',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
              // Big books take a while to upload - bound the connection, not
              // the whole transfer.
              sendTimeout: const Duration(minutes: 30),
              headers: {
                'Authorization':
                    'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}',
              },
              validateStatus: (_) => true,
            ));

  /// Confirms the server is reachable and the credentials work.
  Future<void> testConnection() async {
    final res = await _dio.request('', options: Options(method: 'PROPFIND'));
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const WebDavException('Those credentials were rejected.');
    }
    if (res.statusCode == null || res.statusCode! >= 400) {
      throw WebDavException('Server responded with ${res.statusCode}.');
    }
  }

  /// Uploads [bytes] to `<baseUrl>/<path>`, creating any missing parent
  /// folders first (WebDAV servers 409 a PUT into a folder that doesn't
  /// exist yet).
  Future<void> putFile(String path, Uint8List bytes) async {
    await _makeParents(path);
    await _put(path, bytes, bytes.length);
  }

  /// Streams [file] up to `<baseUrl>/<path>` without reading it into memory.
  Future<void> putFileFromDisk(String path, File file) async {
    await _makeParents(path);
    await _put(path, file.openRead(), await file.length());
  }

  Future<void> _makeParents(String path) async {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    var built = '';
    for (final segment in segments.sublist(0, segments.length - 1)) {
      built = built.isEmpty ? segment : '$built/$segment';
      final res = await _dio.request(
        Uri.encodeFull(built),
        options: Options(method: 'MKCOL'),
      );
      // 201 created, 405 already exists - anything else is a real problem.
      if (res.statusCode != 201 && res.statusCode != 405) {
        throw WebDavException(
            "Couldn't create folder \"$built\" (${res.statusCode}).");
      }
    }
  }

  Future<void> _put(String path, Object data, int length) async {
    final res = await _dio.put(
      Uri.encodeFull(path),
      data: data,
      options: Options(
        headers: {'Content-Length': length},
        contentType: 'application/octet-stream',
      ),
    );
    if (res.statusCode == null || res.statusCode! >= 300) {
      throw WebDavException('Upload failed (${res.statusCode}).');
    }
  }
}
