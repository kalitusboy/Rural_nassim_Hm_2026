import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';

/// شاشة الإعداد — مرة واحدة فقط عند أول تشغيل
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  // IP الافتراضي لـ Android Hotspot (ثابت في 99% الأجهزة)
  static const _defaultIp = '192.168.43.1';

  final _passCtrl = TextEditingController();
  final _ipCtrl = TextEditingController(text: _defaultIp);
  String? _role;
  bool _saving = false;
  bool _showPass = false;

  @override
  void dispose() {
    _passCtrl.dispose();
    _ipCtrl.dispose();
    super.dispose();
  }

  // ── حفظ الإعداد ──────────────────────────────
  Future<void> _save() async {
    if (_role == null) { _snack('اختر نوع الجهاز أولاً'); return; }
    if (_passCtrl.text.trim().length < 4) {
      _snack('كلمة المرور يجب أن تكون 4 أحرف على الأقل'); return;
    }
    if (_role == 'agent' && _ipCtrl.text.trim().isEmpty) {
      _snack('أدخل IP هاتف المدير'); return;
    }

    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('device_role', _role!);
    await prefs.setString('sync_password', _passCtrl.text.trim());
    await prefs.setString('admin_ip',
        _role == 'admin' ? _defaultIp : _ipCtrl.text.trim());
    await prefs.setBool('setup_done', true);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  // ── مسح QR ───────────────────────────────────
  Future<void> _scanQr() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _QrScanScreen()),
    );
    if (result == null || !mounted) return;

    // تنسيق QR: nhsync://IP:PORT?pw=PASSWORD
    try {
      final uri = Uri.parse(result);
      if (uri.scheme == 'nhsync') {
        final ip = uri.host;
        final pw = uri.queryParameters['pw'] ?? '';
        setState(() {
          _ipCtrl.text = ip;
          _passCtrl.text = pw;
        });
        _snack('✅ تم استيراد الإعدادات بنجاح');
      } else {
        _snack('رمز QR غير صالح');
      }
    } catch (_) {
      _snack('تعذر قراءة رمز QR');
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Icon(Icons.sync_alt, size: 64, color: Color(0xFF0D47A1)),
              const SizedBox(height: 10),
              const Text('إعداد المزامنة',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0D47A1))),
              const Text('هذه الخطوة مرة واحدة فقط',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13)),

              const SizedBox(height: 32),

              // ── اختيار الدور ─────────────────
              const Align(
                alignment: Alignment.centerRight,
                child: Text('ما هو هذا الجهاز؟',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: _RoleCard(
                  icon: Icons.admin_panel_settings_rounded,
                  title: 'جهاز المدير',
                  subtitle: 'يشغّل السيرفر\nيجمع بيانات الكل',
                  color: const Color(0xFF0D47A1),
                  selected: _role == 'admin',
                  onTap: () => setState(() => _role = 'admin'),
                )),
                const SizedBox(width: 12),
                Expanded(
                    child: _RoleCard(
                  icon: Icons.person_pin_rounded,
                  title: 'جهاز عون',
                  subtitle: 'يتصل بالمدير\nيرفع ويستقبل',
                  color: Colors.green.shade700,
                  selected: _role == 'agent',
                  onTap: () => setState(() => _role = 'agent'),
                )),
              ]),

              const SizedBox(height: 24),

              // ── كلمة المرور ───────────────────
              TextField(
                controller: _passCtrl,
                obscureText: !_showPass,
                decoration: InputDecoration(
                  labelText: 'كلمة المرور المشتركة',
                  hintText: 'نفس الكلمة على جميع الأجهزة',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _showPass ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showPass = !_showPass),
                  ),
                ),
              ),

              // ── IP المدير (للأعوان) ───────────
              if (_role == 'agent') ...[
                const SizedBox(height: 16),

                // زر المسح السريع
                OutlinedButton.icon(
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('مسح رمز QR من هاتف المدير'),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  onPressed: _scanQr,
                ),

                const SizedBox(height: 10),
                const Row(children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('أو أدخل يدوياً',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ),
                  Expanded(child: Divider()),
                ]),
                const SizedBox(height: 10),

                // حقل IP مع IP افتراضي جاهز
                TextField(
                  controller: _ipCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'IP هاتف المدير',
                    prefixIcon: const Icon(Icons.wifi),
                    helperText:
                        'الافتراضي للـ Hotspot هو $_defaultIp — غيّره فقط إذا لزم',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      tooltip: 'استعادة الافتراضي',
                      onPressed: () => setState(() => _ipCtrl.text = _defaultIp),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('حفظ وبدء التطبيق',
                        style: TextStyle(fontSize: 16)),
              ),

              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: const Text(
                  '💡 كلمة المرور يجب أن تكون متطابقة على جميع الأجهزة.\n'
                  '📡 يجب أن يكون الـ Hotspot مشغّلاً من هاتف المدير.',
                  style: TextStyle(fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// شاشة مسح QR
// ─────────────────────────────────────────────────────────
class _QrScanScreen extends StatefulWidget {
  const _QrScanScreen();

  @override
  State<_QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<_QrScanScreen> {
  bool _scanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('امسح رمز QR')),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (_scanned) return;
              final barcode = capture.barcodes.firstOrNull;
              if (barcode?.rawValue != null) {
                setState(() => _scanned = true);
                Navigator.pop(context, barcode!.rawValue);
              }
            },
          ),
          // إطار توجيهي
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'وجّه الكاميرا نحو رمز QR على هاتف المدير',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// بطاقة اختيار الدور
// ─────────────────────────────────────────────────────────
class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? color : Colors.grey.shade300, width: 2),
          boxShadow: selected
              ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 12)]
              : [],
        ),
        child: Column(children: [
          Icon(icon, size: 36, color: selected ? Colors.white : color),
          const SizedBox(height: 8),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: selected ? Colors.white : Colors.black87)),
          const SizedBox(height: 4),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11,
                  color: selected ? Colors.white70 : Colors.grey)),
        ]),
      ),
    );
  }
}
