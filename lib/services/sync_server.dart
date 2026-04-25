
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
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

    router.post('/auth', (Request req) async {
      try {
        final body =
            jsonDecode(await req.readAsString()) as Map<String, dynamic>;
        if (body['password'] == password) {
          return _ok({'ok': true});
        }
        return _err(403, 'كلمة المرور خاطئة');
      } catch (_) {
        return _err(400, 'طلب غير صالح');
      }
    });

    router.post('/records', (Request req) async {
      if (!_auth(req, password)) return _err(401, 'غير مصرح');
      try {
        final body =
            jsonDecode(await req.readAsString()) as Map<String, dynamic>;
        final incoming =
            (body['records'] as List).cast<Map<String, dynamic>>();

        final stats = await _sync.mergeRecords(incoming);
        final all = await _sync.getAllRecords();

        return _ok({'ok': true, 'records': all, 'stats': stats});
      } catch (e) {
        return _err(500, 'خطأ في الدمج: $e');
      }
    });

    router.get('/images/list', (Request req) async {
      if (!_auth(req, password)) return _err(401, 'غير مصرح');
      final filenames = await _sync.getLocalImageFilenames();
      return _ok({'filenames': filenames});
    });

    router.post('/images/<name>', (Request req, String name) async {
      if (!_auth(req, password)) return _err(401, 'غير مصرح');
      try {
        final bytes = await req.read().fold<List<int>>(
            <int>[], (prev, chunk) => prev..addAll(chunk));
        final dir = await _sync.getImagesDir();
        final file = File(p.join(dir.path, name));
        await file.writeAsBytes(bytes);
        return _ok({'ok': true});
      } catch (e) {
        return _err(500, 'فشل الحفظ: $e');
      }
    });

    router.get('/images/<name>', (Request req, String name) async {
      if (!_auth(req, password)) return _err(401, 'غير مصرح');
      try {
        final dir = await _sync.getImagesDir();
        final file = File(p.join(dir.path, name));
        if (!await file.exists()) {
          return Response.notFound('الصورة غير موجودة');
        }
        final bytes = await file.readAsBytes();
        return Response.ok(bytes,
            headers: {'content-type': 'image/jpeg'});
      } catch (e) {
        return _err(500, 'فشل الإرسال: $e');
      }
    });

    router.get('/ping', (Request req) async {
      return _ok({'ok': true});
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

  Response _err(int code, String msg) => Response(
        code,
        body: jsonEncode({'ok': false, 'error': msg}),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }
}
