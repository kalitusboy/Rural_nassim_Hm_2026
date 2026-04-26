
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'sync_service.dart';

class SyncResult {
  final bool success;
  final int added;
  final int updated;
  final int imagesUp;
  final int imagesDown;
  final String? error;

  const SyncResult._({
    required this.success,
    this.added = 0,
    this.updated = 0,
    this.imagesUp = 0,
    this.imagesDown = 0,
    this.error,
  });

  factory SyncResult.ok({
    required int added,
    required int updated,
    required int imagesUp,
    required int imagesDown,
  }) =>
      SyncResult._(
          success: true,
          added: added,
          updated: updated,
          imagesUp: imagesUp,
          imagesDown: imagesDown);

  factory SyncResult.fail(String error) =>
      SyncResult._(success: false, error: error);
}

class SyncClient {
  static final SyncClient _instance = SyncClient._internal();
  factory SyncClient() => _instance;
  SyncClient._internal();

  final _sync = SyncService();

  String _ip = '';
  String _password = '';
  String get _base => 'http://$_ip:8080';

  void configure({required String ip, required String password}) {
    _ip = ip.trim();
    _password = password.trim();
  }

  Map<String, String> get _headers => {
        'x-password': _password,
        'content-type': 'application/json; charset=utf-8',
      };

  Future<bool> ping() async {
    try {
      final res = await http
          .get(Uri.parse('$_base/ping'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate() async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/auth'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'password': _password}),
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return false;
      return (jsonDecode(res.body) as Map)['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<SyncResult> downloadFromServer({void Function(String)? onProgress}) async {
    try {
      onProgress?.call('🔌 جاري الاتصال...');
      if (!await ping()) return SyncResult.fail('تعذر الاتصال');
      onProgress?.call('🔑 جاري التحقق...');
      if (!await authenticate()) return SyncResult.fail('كلمة المرور خاطئة');

      onProgress?.call('📋 إعداد الملخص...');
      final mySummary = await _sync.getSummary();

      onProgress?.call('🔄 استقبال تحديثات المدير...');
      final response = await http.post(
        Uri.parse('$_base/metasync'),
        headers: _headers,
        body: jsonEncode({'summary': mySummary}),
      ).timeout(const Duration(minutes: 5));

      if (response.statusCode != 200) return SyncResult.fail('خطأ في metasync');

      if (response.headers['content-type'] == 'application/zip') {
        final tmpDir = await getTemporaryDirectory();
        final receivedZip = File(p.join(tmpDir.path, 'from_server.zip'));
        await receivedZip.writeAsBytes(response.bodyBytes);
        final stats = await _sync.processReceivedZip(receivedZip);
        await receivedZip.delete();
        return SyncResult.ok(
          added: stats['added'] ?? 0,
          updated: stats['updated'] ?? 0,
          imagesUp: 0,
          imagesDown: stats['images'] ?? 0,
        );
      } else {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['ok'] == true) {
          return SyncResult.ok(added: 0, updated: 0, imagesUp: 0, imagesDown: 0);
        }
        return SyncResult.fail(body['error'] ?? 'فشل');
      }
    } catch (e) {
      return SyncResult.fail('$e');
    }
  }

  Future<SyncResult> uploadToServer({void Function(String)? onProgress}) async {
    try {
      onProgress?.call('🔌 جاري الاتصال...');
      if (!await ping()) return SyncResult.fail('تعذر الاتصال');
      onProgress?.call('🔑 جاري التحقق...');
      if (!await authenticate()) return SyncResult.fail('كلمة المرور خاطئة');

      onProgress?.call('📦 تجهيز حزمة الرفع...');
      final myZip = await _sync.createZipPackage();

      onProgress?.call('⬆️ رفع البيانات والصور...');
      final res = await http.post(
        Uri.parse('$_base/upload_zip'),
        headers: {
          'x-password': _password,
          'content-type': 'application/octet-stream',
        },
        body: await myZip.readAsBytes(),
      ).timeout(const Duration(minutes: 5));

      if (res.statusCode != 200) return SyncResult.fail('فشل الرفع');

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['ok'] != true) return SyncResult.fail(body['error'] ?? 'فشل');

      final stats = body['stats'] as Map<String, dynamic>?;
      return SyncResult.ok(
        added: 0,
        updated: 0,
        imagesUp: stats?['images'] ?? 0,
        imagesDown: 0,
      );
    } catch (e) {
      return SyncResult.fail('$e');
    }
  }
}
