import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
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

  // ─────────────────────────────────────────────
  // اختبار الاتصال
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

  // ─────────────────────────────────────────────
  // المزامنة الكاملة
  // ─────────────────────────────────────────────
  Future<SyncResult> sync({void Function(String)? onProgress}) async {
    try {
      onProgress?.call('🔌 جاري الاتصال بالسيرفر...');
      if (!await ping()) {
        return SyncResult.fail(
            'تعذر الاتصال بالسيرفر\nتأكد من:\n• أن جهاز المدير مفتوح\n• أن السيرفر يعمل\n• أنك متصل بنفس الـ WiFi');
      }

      onProgress?.call('🔑 جاري التحقق من كلمة المرور...');
      if (!await authenticate()) {
        return SyncResult.fail('كلمة المرور خاطئة');
      }

      onProgress?.call('💾 جاري النسخ الاحتياطي...');
      await _sync.backup();

      // ① رفع صور هذا الجهاز للسيرفر
      onProgress?.call('🖼️ جاري رفع الصور...');
      final imgUp = await _uploadImages(onProgress: onProgress);

      // ② رفع السجلات واستقبال الموحّدة
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

      onProgress?.call('🔄 جاري دمج البيانات...');
      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final allRecords =
          (data['records'] as List).cast<Map<String, dynamic>>();
      final stats = await _sync.mergeRecords(allRecords);

      // ③ تنزيل صور الأعوان الآخرين
      onProgress?.call('📥 جاري تنزيل صور الأعوان الآخرين...');
      final imgDown = await _downloadImages(onProgress: onProgress);

      return SyncResult.ok(
        added: stats['added'] ?? 0,
        updated: stats['updated'] ?? 0,
        imagesUp: imgUp,
        imagesDown: imgDown,
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
  // رفع الصور — يقرأ من DB مباشرة (الإصلاح الجذري)
  // ─────────────────────────────────────────────
  Future<int> _uploadImages({void Function(String)? onProgress}) async {
    int up = 0;
    try {
      // ① اجلب قائمة أسماء صور السيرفر لتجنب رفع ما هو موجود
      Set<String> serverNames = {};
      try {
        final listRes = await http
            .get(Uri.parse('$_base/images/list'), headers: _headers)
            .timeout(const Duration(seconds: 10));
        if (listRes.statusCode == 200) {
          serverNames = Set<String>.from(
              (jsonDecode(listRes.body)['filenames'] as List).cast<String>());
        }
      } catch (_) {}

      // ② الصور المرتبطة بالسجلات في قاعدة البيانات (المصدر الموثوق)
      final dbImages = await _sync.getDbImages();

      for (final img in dbImages) {
        final name = img['name']!;
        final path = img['path']!;

        // تجاوز ما هو موجود على السيرفر
        if (serverNames.contains(name)) continue;

        final file = File(path);
        if (!await file.exists()) continue;

        try {
          onProgress?.call('⬆️ رفع: $name');
          final bytes = await file.readAsBytes();
          final res = await http
              .post(
                Uri.parse('$_base/images/$name'),
                headers: {
                  'x-password': _password,
                  'content-type': 'application/octet-stream',
                },
                body: bytes,
              )
              .timeout(const Duration(seconds: 60));
          if (res.statusCode == 200) up++;
        } catch (_) {}
      }
    } catch (_) {}
    return up;
  }

  // ─────────────────────────────────────────────
  // تنزيل الصور الجديدة من السيرفر
  // ─────────────────────────────────────────────
  Future<int> _downloadImages({void Function(String)? onProgress}) async {
    int down = 0;
    try {
      // قائمة صور السيرفر
      final listRes = await http
          .get(Uri.parse('$_base/images/list'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (listRes.statusCode != 200) return 0;

      final serverNames = Set<String>.from(
          (jsonDecode(listRes.body)['filenames'] as List).cast<String>());

      // الصور الموجودة محلياً
      final localNames = await _sync.getLocalImageNames();

      // الفرق = ما عند السيرفر وليس عندي
      final toDownload = serverNames.difference(localNames);
      final imgDir = await _sync.getImagesDir();

      for (final name in toDownload) {
        try {
          onProgress?.call('⬇️ تنزيل: $name');
          final imgRes = await http
              .get(Uri.parse('$_base/images/$name'), headers: _headers)
              .timeout(const Duration(seconds: 60));
          if (imgRes.statusCode == 200) {
            final file = File(p.join(imgDir.path, name));
            await file.writeAsBytes(imgRes.bodyBytes);
            down++;
          }
        } catch (_) {}
      }
    } catch (_) {}
    return down;
  }
}
