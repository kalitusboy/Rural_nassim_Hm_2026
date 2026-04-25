import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'sync_service.dart';

/// نتيجة المزامنة
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

/// عميل المزامنة — يعمل على هواتف الأعوان
/// يتصل بسيرفر المدير عبر WiFi المكتب
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

  // ─────────────────────────────────────────────
  // اختبار الاتصال بالسيرفر
  // ─────────────────────────────────────────────
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

  // ─────────────────────────────────────────────
  // تحقق من كلمة المرور
  // ─────────────────────────────────────────────
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
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  // ─────────────────────────────────────────────
  // المزامنة الكاملة
  // ─────────────────────────────────────────────
  Future<SyncResult> sync({void Function(String)? onProgress}) async {
    try {
      // 1. اتصال
      onProgress?.call('🔌 جاري الاتصال بالسيرفر...');
      if (!await ping()) {
        return SyncResult.fail(
            'تعذر الاتصال بالسيرفر\nتأكد من:\n• أن جهاز المدير مفتوح\n• أن السيرفر يعمل\n• أنك متصل بنفس الـ WiFi');
      }

      // 2. تحقق من كلمة المرور
      onProgress?.call('🔑 جاري التحقق من كلمة المرور...');
      if (!await authenticate()) {
        return SyncResult.fail('كلمة المرور خاطئة');
      }

      // 3. نسخة احتياطية
      onProgress?.call('💾 جاري النسخ الاحتياطي...');
      await _sync.backup();

      // 4. رفع السجلات المحلية + استقبال الكاملة
      onProgress?.call('📤 جاري رفع البيانات...');
      final localRecords = await _sync.getAllRecords();

      final res = await http
          .post(
            Uri.parse('$_base/records'),
            headers: _headers,
            body: jsonEncode({'records': localRecords}),
          )
          .timeout(const Duration(minutes: 3));

      if (res.statusCode != 200) {
        return SyncResult.fail('خطأ من السيرفر: ${res.statusCode}');
      }

      // 5. دمج السجلات المستقبلة
      onProgress?.call('🔄 جاري دمج البيانات...');
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final allRecords =
          (data['records'] as List).cast<Map<String, dynamic>>();
      final stats = await _sync.mergeRecords(allRecords);

      // 6. مزامنة الصور
      onProgress?.call('🖼️ جاري مزامنة الصور...');
      final imgStats = await _syncImages();

      return SyncResult.ok(
        added: stats['added'] ?? 0,
        updated: stats['updated'] ?? 0,
        imagesUp: imgStats['up'] ?? 0,
        imagesDown: imgStats['down'] ?? 0,
      );
    } on SocketException {
      return SyncResult.fail('لا يوجد اتصال بالشبكة');
    } on HttpException {
      return SyncResult.fail('خطأ في الاتصال بالسيرفر');
    } catch (e) {
      return SyncResult.fail('خطأ غير متوقع: $e');
    }
  }

  // ─────────────────────────────────────────────
  // مزامنة الصور (رفع + تنزيل)
  // ─────────────────────────────────────────────
  Future<Map<String, int>> _syncImages() async {
    int up = 0, down = 0;
    try {
      // قائمة صور السيرفر
      final listRes = await http
          .get(Uri.parse('$_base/images/list'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (listRes.statusCode != 200) return {'up': 0, 'down': 0};

      final listData =
          jsonDecode(listRes.body) as Map<String, dynamic>;
      final serverNames =
          Set<String>.from((listData['filenames'] as List).cast<String>());
      final localNames =
          Set<String>.from(await _sync.getLocalImageFilenames());
      final imagesDir = await _sync.getImagesDir();

      // رفع ما عندي وليس عند السيرفر
      for (final name in localNames.difference(serverNames)) {
        final file = File(p.join(imagesDir.path, name));
        if (!await file.exists()) continue;
        try {
          final bytes = await file.readAsBytes();
          await http
              .post(
                Uri.parse('$_base/images/$name'),
                headers: {
                  'x-password': _password,
                  'content-type': 'application/octet-stream',
                },
                body: bytes,
              )
              .timeout(const Duration(seconds: 30));
          up++;
        } catch (_) {}
      }

      // تنزيل ما عند السيرفر وليس عندي
      for (final name in serverNames.difference(localNames)) {
        try {
          final imgRes = await http
              .get(Uri.parse('$_base/images/$name'), headers: _headers)
              .timeout(const Duration(seconds: 30));
          if (imgRes.statusCode == 200) {
            final file = File(p.join(imagesDir.path, name));
            await file.writeAsBytes(imgRes.bodyBytes);
            down++;
          }
        } catch (_) {}
      }
    } catch (_) {
      // فشل مزامنة الصور لا يوقف العملية كلها
    }
    return {'up': up, 'down': down};
  }
}
