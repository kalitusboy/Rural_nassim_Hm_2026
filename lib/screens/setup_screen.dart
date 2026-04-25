import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';

/// شاشة الإعداد — تظهر مرة واحدة فقط عند أول تشغيل
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _passCtrl = TextEditingController();
  final _ipCtrl = TextEditingController();
  String? _role; // 'admin' | 'agent'
  bool _saving = false;
  bool _showPass = false;

  @override
  void dispose() {
    _passCtrl.dispose();
    _ipCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_role == null) {
      _snack('اختر نوع الجهاز أولاً');
      return;
    }
    if (_passCtrl.text.trim().length < 4) {
      _snack('كلمة المرور يجب أن تكون 4 أحرف على الأقل');
      return;
    }
    if (_role == 'agent' && _ipCtrl.text.trim().isEmpty) {
      _snack('أدخل IP هاتف المدير');
      return;
    }

    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('device_role', _role!);
    await prefs.setString('sync_password', _passCtrl.text.trim());
    if (_role == 'agent') {
      await prefs.setString('admin_ip', _ipCtrl.text.trim());
    }
    await prefs.setBool('setup_done', true);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

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
              const SizedBox(height: 32),

              // ── أيقونة وعنوان ──────────────────
              const Icon(Icons.sync_alt,
                  size: 72, color: Color(0xFF0D47A1)),
              const SizedBox(height: 12),
              const Text(
                'إعداد المزامنة',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0D47A1)),
              ),
              const Text(
                'هذه الخطوة مرة واحدة فقط',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),

              const SizedBox(height: 40),

              // ── اختيار نوع الجهاز ──────────────
              const Align(
                alignment: Alignment.centerRight,
                child: Text('ما هو هذا الجهاز؟',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
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
                ],
              ),

              const SizedBox(height: 28),

              // ── كلمة المرور المشتركة ────────────
              TextField(
                controller: _passCtrl,
                obscureText: !_showPass,
                decoration: InputDecoration(
                  labelText: 'كلمة المرور المشتركة',
                  hintText: 'نفس الكلمة على جميع الأجهزة',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_showPass
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setState(() => _showPass = !_showPass),
                  ),
                ),
              ),

              // ── IP المدير (للأعوان فقط) ─────────
              if (_role == 'agent') ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _ipCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'IP هاتف المدير',
                    hintText: 'مثال: 192.168.1.10',
                    prefixIcon: Icon(Icons.wifi),
                    helperText:
                        'ستجد الـ IP في شاشة المزامنة على هاتف المدير',
                  ),
                ),
              ],

              const SizedBox(height: 40),

              // ── زر الحفظ ───────────────────────
              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('حفظ وبدء التطبيق',
                        style: TextStyle(fontSize: 16)),
              ),

              const SizedBox(height: 16),

              // ملاحظة
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: Colors.amber.shade200),
                ),
                child: const Text(
                  '💡 تأكد أن كلمة المرور متطابقة على جميع الأجهزة، وإلا لن تتم المزامنة.',
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
        child: Column(
          children: [
            Icon(icon,
                size: 36, color: selected ? Colors.white : color),
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
                    color:
                        selected ? Colors.white70 : Colors.grey)),
          ],
        ),
      ),
    );
  }
}
