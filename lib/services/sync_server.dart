
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';  // ← مهم جداً
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'sync_service.dart';

class SyncServer {
  static final SyncServer _instance = SyncServer._internal();
  factory SyncServer() => _instance;
  SyncServer._internal();

  HttpServer? _server;
  final _sync = SyncService();

  static const int port = 8080;

  bool get isRunning => _server != null;
  String? _localIp;
  String? get localIp => _localIp;

  Future<String?> start({required String password}) async {
    if (_server != null) return _localIp;

    final router = Router();

    // ── ping ───────────────────────────────────
    router.get('/ping', (Request req) async => _ok({'ok': true}));

    // ── تحقق كلمة المرور ──────────────────────
    router.post('/auth', (Request req) async {
      try {
        final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
        if (body['password'] == password) return _ok({'ok': true});
        return _err(403, 'كلمة المرور خاطئة');
      } catch (_) {
        return _err(400, 'طلب غير صالح');
      }
    });

    // ── Metasync: استقبال ملخص العون وإرجاع ZIP الفروقات ─────
    router.post('/metasync', (Request req) async {
      if (!_auth(req, password)) return _err(401, 'غير مصرح');
      try {
        final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
        final clientSummary = (body['summary'] as List).cast<Map<String, dynamic>>();

        // حساب ما يحتاجه العون من المدير
        final serverDiff = await _sync.compareAndGetMissing(clientSummary);
        final recordsForClient = (serverDiff['records'] as List).cast<Map<String, dynamic>>();
        final imagesForClient = (serverDiff['images'] as List).cast<String>();

        // إنشاء ZIP للعون
        final zipFile = await _sync.createZipForItems(recordsForClient, imagesForClient);
        final zipBytes = await zipFile.readAsBytes();
        await zipFile.delete();

        return Response.ok(zipBytes,
            headers: {
              'content-type': 'application/zip',
              'x-sync-stats': jsonEncode({
                'records': recordsForClient.length,
                'images': imagesForClient.length
              })
            });
      } catch (e) {
        return _err(500, 'فشل metasync: $e');
      }
    });

    // ── استقبال حزمة ZIP من العون ومعالجتها (الاتجاه المعاكس) ────
    router.post('/upload_zip', (Request req) async {
      if (!_auth(req, password)) return _err(401, 'غير مصرح');
      try {
        final bytes = await req.read().fold<List<int>>(<int>[], (a, b) => a..addAll(b));
        if (bytes.isEmpty) return _err(400, 'الملف فارغ');
        final tmpDir = await getTemporaryDirectory();
        final tmpFile = File(p.join(tmpDir.path, 'upload_${DateTime.now().millisecondsSinceEpoch}.zip'));
        await tmpFile.writeAsBytes(bytes);
        final stats = await _sync.processReceivedZip(tmpFile);
        await tmpFile.delete();
        return _ok({'ok': true, 'stats': stats});
      } catch (e) {
        return _err(500, 'فشل معالجة الرفع: $e');
      }
    });

    final handler = Pipeline().addHandler(router.call);
    _server = await shelf_io.serve(handler, '0.0.0.0', port);
    _localIp = await _getLocalIp();
    return _localIp;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _localIp = null;
  }

  bool _auth(Request req, String password) =>
      req.headers['x-password'] == password;

  Response _ok(Map<String, dynamic> body) => Response.ok(
        jsonEncode(body),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  Response _err(int code, String msg) => Response(code,
      body: jsonEncode({'ok': false, 'error': msg}),
      headers: {'content-type': 'application/json; charset=utf-8'});

  Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.address.startsWith('192.168.43.')) return addr.address;
        }
      }
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return '192.168.43.1';
  }
}
