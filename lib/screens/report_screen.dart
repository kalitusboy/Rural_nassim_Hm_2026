import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import '../services/database_service.dart';
import '../services/report_service.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _db = DatabaseService();
  final _rs = ReportService();
  final _form = GlobalKey<FormState>();

  // ── حقول الإدخال ─────────────────────────────
  final _wilayaCtrl  = TextEditingController();
  final _dairaCtrl   = TextEditingController();
  final _baladiaCtrl = TextEditingController();
  final _placeCtrl   = TextEditingController();
  final _numCtrl     = TextEditingController();

  String? _selectedProgram;
  List<String> _programs = [];
  DateTime _date = DateTime.now();

  Map<String, dynamic>? _stats;
  bool _loading = false;
  bool _generating = false;
  bool _exportingZip = false;
  String _msg = '';
  bool _msgOk = true;

  @override
  void initState() {
    super.initState();
    _loadPrograms();
  }

  @override
  void dispose() {
    _wilayaCtrl.dispose();
    _dairaCtrl.dispose();
    _baladiaCtrl.dispose();
    _placeCtrl.dispose();
    _numCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPrograms() async {
    final p = await _db.getPrograms();
    setState(() => _programs = p);
  }

  Future<void> _loadStats() async {
    if (_selectedProgram == null) return;
    setState(() { _loading = true; _stats = null; });
    final s = await _db.getReportStats(_selectedProgram!);
    setState(() { _stats = s; _loading = false; });
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      locale: const Locale('ar'),
    );
    if (d != null) setState(() => _date = d);
  }

  String get _dateAr {
    const days    = ['الاثنين','الثلاثاء','الأربعاء','الخميس','الجمعة','السبت','الأحد'];
    const months  = ['يناير','فبراير','مارس','أبريل','مايو','يونيو',
                     'يوليو','أغسطس','سبتمبر','أكتوبر','نوفمبر','ديسمبر'];
    final day   = days[_date.weekday - 1];
    final month = months[_date.month - 1];
    return '$day ${_date.day} $month ${_date.year}';
  }

  // ── توليد Word ────────────────────────────────
  Future<void> _generate() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    if (_selectedProgram == null) {
      _showMsg('اختر البرنامج أولاً', false); return;
    }
    if (_stats == null) {
      _showMsg('اضغط "تحديث" لتحميل البيانات أولاً', false); return;
    }

    setState(() => _generating = true);
    try {
      final data = ReportData(
        wilaya:              _wilayaCtrl.text.trim(),
        daira:               _dairaCtrl.text.trim(),
        baladia:             _baladiaCtrl.text.trim(),
        program:             _selectedProgram!,
        place:               _placeCtrl.text.trim(),
        date:                _dateAr,
        reportNumber:        _numCtrl.text.trim(),
        quota:               _stats!['quota']               as int? ?? 0,
        inProgress:          _stats!['in_progress']         as int? ?? 0,
        pillars:             _stats!['pillars']             as int? ?? 0,
        finishedNotOccupied: _stats!['finished_not_occupied'] as int? ?? 0,
        finishedOccupied:    _stats!['finished_occupied']   as int? ?? 0,
        elecOcc:             _stats!['elec_occ']            as int? ?? 0,
        gasOcc:              _stats!['gas_occ']             as int? ?? 0,
        waterOcc:            _stats!['water_occ']           as int? ?? 0,
        sewOcc:              _stats!['sew_occ']             as int? ?? 0,
        fullyConnected:      _stats!['fully_connected']     as int? ?? 0,
      );
      final path = await _rs.generateDocx(data);
      _showMsg('✅ تم الحفظ في Download/محاضر_الإحصاء', true);
      await OpenFile.open(path);
    } catch (e) {
      _showMsg('❌ خطأ: $e', false);
    } finally {
      setState(() => _generating = false);
    }
  }

  // ── تصدير الصور كـ ZIP ──────────────────────
  Future<void> _exportPhotos() async {
    if (_selectedProgram == null) {
      _showMsg('اختر البرنامج أولاً', false); return;
    }
    setState(() => _exportingZip = true);
    try {
      final images = await _db.getProgramImages(_selectedProgram!);
      if (images.isEmpty) {
        _showMsg('لا توجد صور لهذا البرنامج', false);
        setState(() => _exportingZip = false);
        return;
      }
      final path = await _rs.exportPhotosZip(_selectedProgram!, images);
      _showMsg('✅ تم تصدير ${images.length} صورة', true);
      await Share.shareXFiles([XFile(path)],
          text: 'صور برنامج $_selectedProgram');
    } catch (e) {
      _showMsg('❌ $e', false);
    } finally {
      setState(() => _exportingZip = false);
    }
  }

  void _showMsg(String msg, bool ok) =>
      setState(() { _msg = msg; _msgOk = ok; });

  // ── مساعد: حقل إدخال ──────────────────────
  Widget _field(TextEditingController ctrl, String label, IconData icon,
      {bool required = true}) {
    return TextFormField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📄 محضر المعاينة'),
        centerTitle: true,
      ),
      // ── الحل: SingleChildScrollView + padding bottom ──
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16, 12, 16,
          MediaQuery.of(context).viewInsets.bottom + 80, // فراغ فوق الأزرار
        ),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              // ── قسم: بيانات الموقع ─────────────────────
              _SectionHeader('📍 بيانات الموقع', Colors.indigo),
              const SizedBox(height: 8),
              _field(_wilayaCtrl,  'الولاية',  Icons.location_city),
              const SizedBox(height: 8),
              _field(_dairaCtrl,   'الدائرة',  Icons.map_outlined),
              const SizedBox(height: 8),
              _field(_baladiaCtrl, 'البلدية',  Icons.location_on_outlined),

              const SizedBox(height: 16),

              // ── قسم: بيانات المحضر ─────────────────────
              _SectionHeader('📋 بيانات المحضر', Colors.teal),
              const SizedBox(height: 8),

              // رقم المحضر
              _field(_numCtrl, 'رقم المحضر', Icons.tag),
              const SizedBox(height: 8),

              // التاريخ
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'تاريخ المحضر',
                    prefixIcon: Icon(Icons.calendar_today, size: 18),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  child: Text(_dateAr,
                      style: const TextStyle(fontSize: 14)),
                ),
              ),
              const SizedBox(height: 8),

              // مكان التحرير
              _field(_placeCtrl, 'مكان التحرير', Icons.place_outlined),

              const SizedBox(height: 16),

              // ── قسم: اختيار البرنامج ────────────────────
              _SectionHeader('🏗️ البرنامج', Colors.orange.shade800),
              const SizedBox(height: 8),

              DropdownButtonFormField<String>(
                value: _selectedProgram,
                decoration: const InputDecoration(
                  labelText: 'اختر البرنامج',
                  prefixIcon: Icon(Icons.folder_outlined, size: 18),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: _programs
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    _selectedProgram = v;
                    _stats = null;
                    _msg = '';
                  });
                },
                validator: (v) => v == null ? 'اختر برنامجاً' : null,
              ),

              const SizedBox(height: 8),

              // زر تحديث البيانات
              OutlinedButton.icon(
                onPressed: _loading ? null : _loadStats,
                icon: _loading
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh, size: 18),
                label:
                    Text(_loading ? 'جاري التحميل...' : 'تحديث البيانات من DB'),
              ),

              // معاينة البيانات
              if (_stats != null) ...[
                const SizedBox(height: 12),
                _StatsPreview(stats: _stats!),
              ],

              const SizedBox(height: 16),

              // ── رسالة الحالة ────────────────────────────
              if (_msg.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _msgOk
                        ? Colors.green.shade50
                        : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: _msgOk
                            ? Colors.green.shade300
                            : Colors.red.shade300),
                  ),
                  child: Text(_msg,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: _msgOk
                              ? Colors.green.shade800
                              : Colors.red.shade800)),
                ),
            ],
          ),
        ),
      ),

      // ── أزرار الإجراءات — ثابتة في الأسفل ──
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            // زر تصدير الصور
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _exportingZip ? null : _exportPhotos,
                icon: _exportingZip
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.photo_library_outlined, size: 18),
                label: Text(
                    _exportingZip ? '...' : '📦 تصدير الصور ZIP',
                    style: const TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(color: Colors.orange),
                  foregroundColor: Colors.orange.shade800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // زر توليد Word
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: _generating ? null : _generate,
                icon: _generating
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : const Icon(Icons.description_outlined),
                label: Text(_generating ? 'جاري الإنشاء...' : '📄 توليد Word'),
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: const Color(0xFF1A237E)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// عنوان القسم
// ─────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;
  const _SectionHeader(this.title, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border(right: BorderSide(color: color, width: 4)),
      ),
      child: Text(title,
          style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 13, color: color)),
    );
  }
}

// ─────────────────────────────────────────────
// معاينة البيانات قبل التوليد
// ─────────────────────────────────────────────
class _StatsPreview extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _StatsPreview({required this.stats});

  @override
  Widget build(BuildContext context) {
    Widget row(String label, dynamic value, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(
                child: Text(label,
                    style: const TextStyle(fontSize: 12),
                    textAlign: TextAlign.right)),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: (color ?? Colors.blue).withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '[ $value ]',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color ?? Colors.blue.shade700,
                    fontSize: 12),
              ),
            ),
          ]),
        );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(children: [
        Text('معاينة البيانات',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade800,
                fontSize: 13)),
        const Divider(),
        row('الحصة الإجمالية', stats['quota'],
            color: Colors.indigo),
        row('في طور الإنجاز', stats['in_progress'],
            color: Colors.orange),
        row('على مستوى الأعمدة', stats['pillars'],
            color: Colors.blue),
        row('منتهية غير مشغولة', stats['finished_not_occupied'],
            color: Colors.green.shade700),
        row('منتهية ومشغولة', stats['finished_occupied'],
            color: Colors.teal),
        const Divider(),
        row('⚡ كهرباء (مشغولة)', stats['elec_occ'],
            color: Colors.amber.shade800),
        row('🔥 غاز (مشغولة)', stats['gas_occ'],
            color: Colors.orange),
        row('💧 مياه (مشغولة)', stats['water_occ'],
            color: Colors.blue),
        row('🚿 تطهير (مشغولة)', stats['sew_occ'],
            color: Colors.teal),
        row('✅ مربوطة بكافة الشبكات', stats['fully_connected'],
            color: Colors.green.shade800),
      ]),
    );
  }
}
