import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/sync_server.dart';
import '../services/sync_client.dart';
import 'setup_screen.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _server = SyncServer();
  final _client = SyncClient();

  String _role = '';
  String _password = '';
  String _adminIp = '';

  bool _serverRunning = false;
  String? _serverIp;
  bool _syncing = false;
  String _progress = '';
  String _lastSync = 'لم تتم بعد';
  _MsgType _msgType = _MsgType.info;

  @override
  void initState() {
    super.initState();
    _serverRunning = _server.isRunning;
    _serverIp = _server.localIp;
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _role = prefs.getString('device_role') ?? 'agent';
      _password = prefs.getString('sync_password') ?? '';
      _adminIp = prefs.getString('admin_ip') ?? '192.168.43.1';
      _lastSync = prefs.getString('last_sync') ?? 'لم تتم بعد';
    });
    _client.configure(ip: _adminIp, password: _password);
  }

  // ── رمز QR يحتوي كل ما يحتاجه العون ──────────
  String get _qrData => 'nhsync://$_serverIp:8080?pw=${Uri.encodeComponent(_password)}';

  // ── تشغيل / إيقاف السيرفر ────────────────────
  Future<void> _toggleServer() async {
    if (_serverRunning) {
      await _server.stop();
      setState(() {
        _serverRunning = false;
        _serverIp = null;
        _progress = 'السيرفر متوقف.';
        _msgType = _MsgType.warn;
      });
    } else {
      setState(() => _progress = '⏳ جاري تشغيل السيرفر...');
      final ip = await _server.start(password: _password);
      setState(() {
        _serverRunning = ip != null;
        _serverIp = ip;
        _msgType = ip != null ? _MsgType.ok : _MsgType.err;
        _progress = ip != null
            ? 'السيرفر يعمل ✅'
            : 'تعذر الحصول على IP — تأكد من تشغيل الـ Hotspot';
      });
    }
  }

  // ── مزامنة (للأعوان) ──────────────────────────
  Future<void> _sync() async {
    setState(() {
      _syncing = true;
      _msgType = _MsgType.info;
      _progress = '';
    });

    final result =
        await _client.sync(onProgress: (msg) => setState(() => _progress = msg));

    if (result.success) {
      final now = DateTime.now();
      final ts =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} — ${now.day}/${now.month}/${now.year}';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_sync', ts);
      setState(() {
        _lastSync = ts;
        _msgType = _MsgType.ok;
        _progress = '✅ تمت المزامنة بنجاح\n'
            '📋 +${result.added} سجل جديد  |  🔄 ${result.updated} محدَّث\n'
            '⬆️ ${result.imagesUp} صورة مرفوعة  |  ⬇️ ${result.imagesDown} صورة مستقبلة';
      });
    } else {
      setState(() {
        _msgType = _MsgType.err;
        _progress = result.error ?? 'فشلت المزامنة';
      });
    }
    setState(() => _syncing = false);
  }

  // ── تغيير IP يدوياً للعون ────────────────────
  Future<void> _changeIp() async {
    final ctrl = TextEditingController(text: _adminIp);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تغيير IP المدير'),
        content: TextField(
          controller: ctrl,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'IP',
            hintText: '192.168.43.1',
            prefixIcon: Icon(Icons.wifi),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('حفظ')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('admin_ip', result);
      setState(() => _adminIp = result);
      _client.configure(ip: result, password: _password);
    }
  }

  // ── إعادة الإعداد ────────────────────────────
  Future<void> _resetSetup() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إعادة الإعداد'),
        content: const Text(
            'سيُمسح إعداد المزامنة فقط.\nبيانات المستفيدين تبقى كما هي.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('إعادة',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    await _server.stop();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('setup_done');
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SetupScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = _role == 'admin';

    return Scaffold(
      appBar: AppBar(
        title: const Text('المزامنة'),
        actions: [
          if (!isAdmin)
            IconButton(
              icon: const Icon(Icons.edit_location_alt_outlined),
              tooltip: 'تغيير IP',
              onPressed: _changeIp,
            ),
          IconButton(
            icon: const Icon(Icons.settings_backup_restore),
            tooltip: 'إعادة الإعداد',
            onPressed: _resetSetup,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── شارة الدور ────────────────────
            _RoleBadge(isAdmin: isAdmin),
            const SizedBox(height: 16),

            // ════════════════════════════════════
            // جهاز المدير
            // ════════════════════════════════════
            if (isAdmin) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('🖥️ السيرفر',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 4),
                      const Text(
                          'شغّل السيرفر أولاً ثم أعطِ العون رمز QR',
                          style:
                              TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        onPressed: _toggleServer,
                        icon: Icon(_serverRunning
                            ? Icons.stop_circle_outlined
                            : Icons.play_circle_outlined),
                        label: Text(_serverRunning
                            ? 'إيقاف السيرفر'
                            : 'تشغيل السيرفر'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _serverRunning
                              ? Colors.red.shade700
                              : const Color(0xFF0D47A1),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),

                      // QR يظهر فقط عند تشغيل السيرفر
                      if (_serverRunning && _serverIp != null) ...[
                        const SizedBox(height: 20),
                        const Divider(),
                        const SizedBox(height: 12),
                        const Text('📱 رمز QR للأعوان',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        const SizedBox(height: 4),
                        const Text(
                            'وجّه العون كاميرته نحو هذا الرمز مرة واحدة فقط',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.grey, fontSize: 11)),
                        const SizedBox(height: 12),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 8)
                              ],
                            ),
                            child: QrImageView(
                              data: _qrData,
                              version: QrVersions.auto,
                              size: 200,
                              backgroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        // عرض الـ IP للكتابة اليدوية كاحتياط
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(
                                ClipboardData(text: _serverIp!));
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('تم نسخ الـ IP')));
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.grey.shade300),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.copy,
                                    size: 14, color: Colors.grey),
                                const SizedBox(width: 6),
                                Text(
                                  'IP: $_serverIp  —  احتياطي لو فشل QR',
                                  style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                      fontFamily: 'monospace'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],

            // ════════════════════════════════════
            // جهاز العون
            // ════════════════════════════════════
            if (!isAdmin) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('🔄 مزامنة البيانات',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 6),
                      Row(children: [
                        const Icon(Icons.wifi,
                            size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text('السيرفر: $_adminIp:8080',
                            style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                                fontFamily: 'monospace')),
                        const Spacer(),
                        GestureDetector(
                          onTap: _changeIp,
                          child: const Text('تعديل',
                              style: TextStyle(
                                  color: Color(0xFF0D47A1),
                                  fontSize: 12,
                                  decoration: TextDecoration.underline)),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.history,
                            size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text('آخر مزامنة: $_lastSync',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12)),
                      ]),
                      const SizedBox(height: 12),
                      const Text(
                        '• تأكد أنك متصل بـ Hotspot المدير\n'
                        '• تأكد أن المدير شغّل السيرفر',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        onPressed: _syncing ? null : _sync,
                        icon: _syncing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5))
                            : const Icon(Icons.sync),
                        label: Text(_syncing
                            ? 'جاري المزامنة...'
                            : '🔄 مزامنة الآن'),
                        style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                vertical: 14)),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // ── رسالة الحالة ──────────────────
            if (_progress.isNotEmpty) ...[
              const SizedBox(height: 14),
              _StatusBox(message: _progress, type: _msgType),
            ],

            // ── تذكير بالقواعد ────────────────
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: const Text(
                '🔒 قواعد المزامنة الآمنة\n'
                '• المُحصى (✅) لا يُمسح أبداً\n'
                '• السجل الأحدث يفوز في باقي الحقول\n'
                '• نسخة احتياطية تلقائية قبل كل مزامنة',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Widgets مساعدة
// ─────────────────────────────────────────────

class _RoleBadge extends StatelessWidget {
  final bool isAdmin;
  const _RoleBadge({required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isAdmin ? const Color(0xFF0D47A1) : Colors.green.shade700,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(
            isAdmin
                ? Icons.admin_panel_settings
                : Icons.person_pin_rounded,
            color: Colors.white),
        const SizedBox(width: 8),
        Text(isAdmin ? 'جهاز المدير' : 'جهاز العون',
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15)),
      ]),
    );
  }
}

enum _MsgType { info, ok, err, warn }

class _StatusBox extends StatelessWidget {
  final String message;
  final _MsgType type;
  const _StatusBox({required this.message, required this.type});

  @override
  Widget build(BuildContext context) {
    final colors = {
      _MsgType.info: [Colors.blue.shade50, Colors.blue.shade300],
      _MsgType.ok: [Colors.green.shade50, Colors.green.shade400],
      _MsgType.err: [Colors.red.shade50, Colors.red.shade300],
      _MsgType.warn: [Colors.orange.shade50, Colors.orange.shade300],
    };
    final c = colors[type]!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c[0],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c[1]),
      ),
      child: Text(message,
          textAlign: TextAlign.center,
          style: const TextStyle(height: 1.6)),
    );
  }
}
