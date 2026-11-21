import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class DriveUploadException implements Exception {
  DriveUploadException(this.message);
  final String message;
  @override
  String toString() => 'DriveUploadException: $message';
}

/// The guest's session folder on Drive (shared by link).
class DriveFolder {
  const DriveFolder({required this.id, required this.url});
  final String id;
  final Uri url;
}

/// One uploaded file, plus the session folder it went into.
class DriveFile {
  const DriveFile({
    required this.id,
    required this.name,
    required this.url,
    required this.folder,
  });
  final String id;
  final String name;
  final Uri url;
  final DriveFolder folder;
}

abstract class DriveUploadService {
  /// Finds or creates the session subfolder [session]; returns its link.
  Future<DriveFolder> folder(String session);

  /// Uploads [bytes] as [name] into the session subfolder [session].
  Future<DriveFile> upload(
    Uint8List bytes, {
    required String name,
    required String session,
    required String contentType,
  });

  static String contentTypeFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    return 'application/octet-stream';
  }
}

/// Talks to py-drive-uploader, which holds the Google credentials.
///
/// Contract:
/// ```
/// POST {server}/folder?name=<session>
///   → 201 {"folderId", "folderUrl"}
/// POST {server}/upload?name=<file>&folder=<session>
///   Content-Type: image/gif | image/png …   <bytes>
///   → 201 {"id", "name", "url", "folderId", "folderUrl"}
/// errors → 4xx/5xx {"error": "..."}
/// ```
class NetworkDriveUploadService implements DriveUploadService {
  NetworkDriveUploadService({
    required this.server,
    this.apiKey,
    this.connectTimeout = const Duration(seconds: 5),
    this.timeout = const Duration(seconds: 60),
  });

  /// e.g. `http://192.168.1.50:8766` or `https://drive.example.com`.
  final Uri server;
  final String? apiKey;
  final Duration connectTimeout;

  /// Whole request, including upload and the Drive round trip.
  final Duration timeout;

  Uri endpoint(String path, Map<String, String> query) => server.replace(
    path: '${server.path.replaceAll(RegExp(r'/+$'), '')}/$path',
    queryParameters: query,
  );

  @override
  Future<DriveFolder> folder(String session) async {
    final json = await _post(endpoint('folder', {'name': session}));
    return _folderFrom(json);
  }

  @override
  Future<DriveFile> upload(
    Uint8List bytes, {
    required String name,
    required String session,
    required String contentType,
  }) async {
    final json = await _post(
      endpoint('upload', {'name': name, 'folder': session}),
      body: bytes,
      contentType: ContentType.parse(contentType),
    );
    return DriveFile(
      id: json['id'] as String,
      name: json['name'] as String,
      url: Uri.parse(json['url'] as String),
      folder: _folderFrom(json),
    );
  }

  DriveFolder _folderFrom(Map<String, dynamic> json) => DriveFolder(
    id: json['folderId'] as String,
    url: Uri.parse(json['folderUrl'] as String),
  );

  Future<Map<String, dynamic>> _post(
    Uri uri, {
    Uint8List? body,
    ContentType? contentType,
  }) async {
    final client = HttpClient()..connectionTimeout = connectTimeout;
    try {
      return await () async {
        final request = await client.postUrl(uri);
        if (apiKey != null) request.headers.set('X-Api-Key', apiKey!);
        if (contentType != null) request.headers.contentType = contentType;
        request.contentLength = body?.length ?? 0;
        if (body != null) request.add(body);
        final response = await request.close();
        final text = await utf8.decodeStream(response);
        final Map<String, dynamic> json;
        try {
          json = jsonDecode(text) as Map<String, dynamic>;
        } on FormatException {
          throw DriveUploadException(
            'Drive server said ${response.statusCode}: ${text.trim()}',
          );
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw DriveUploadException(
            'Drive server said ${response.statusCode}: '
            '${json['error'] ?? text.trim()}',
          );
        }
        return json;
      }().timeout(timeout);
    } on DriveUploadException {
      rethrow;
    } on TimeoutException {
      throw DriveUploadException(
        'Drive server at $server did not answer in time',
      );
    } on SocketException catch (error) {
      throw DriveUploadException(
        'Drive server not reachable at $server (${error.message})',
      );
    } on HttpException catch (error) {
      throw DriveUploadException('Drive server error: ${error.message}');
    } finally {
      client.close(force: true);
    }
  }
}
