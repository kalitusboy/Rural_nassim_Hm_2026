import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/beneficiary.dart';
import '../services/database_service.dart';

class SurveyScreen extends StatefulWidget {
  final Beneficiary beneficiary;
  const SurveyScreen({super.key, required this.beneficiary});

  @override
  State<SurveyScreen> createState() => _SurveyScreenState();
}

class _SurveyScreenState extends State<SurveyScreen> {
  final _dbService = DatabaseService();
  final _picker = ImagePicker();
  late Beneficiary _b;
  bool _e = false, _g = false, _w = false, _s = false, _saving = false;
  String _status = 'في طور الانجاز';
  File? _img;
  final _statuses = ['في طور الانجاز', 'على مستوى الاعمدة', 'منتهية غير مشغولة', 'منتهية ومشغولة'];

  @override
  void initState() {
    super.initState();
    _b = widget.beneficiary;
    _e = _b.electricity == 1;
    _g = _b.gas == 1;
    _w = _b.water == 1;
    _s = _b.sewage == 1;
    _status = _b.status;
  }

  Future<void> _pickImage(ImageSource src) async {
    final img = await _picker.pickImage(source: src);
    if (img != null) setState(() => _img = File(img.path));
  }

  void _showPicker() {
    showModalBottomSheet(context: context, builder: (c) => SafeArea(
      child: Wrap(children: [
        ListTile(leading: const Icon(Icons.camera), title: const Text('كاميرا'), onTap: () { Navigator.pop(c); _pickImage(ImageSource.camera); }),
        ListTile(leading: const Icon(Icons.photo_library), title: const Text('معرض'), onTap: () { Navigator.pop(c); _pickImage(ImageSource.gallery); }),
      ]),
    ));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updated = _b.copyWith(
        done: 1, electricity: _e ? 1 : 0, gas: _g ? 1 : 0, water: _w ? 1 : 0, sewage: _s ? 1 : 0,
        status: _status, imagePath: _img?.path ?? _b.imagePath,
        imageFileName: _img != null ? _b.generateImageFileName() : _b.imageFileName,
      );
      await _dbService.updateBeneficiary(updated);
      if (mounted) { Navigator.pop(context, true); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ تم الحفظ'), backgroundColor: Colors.green)); }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ فشل: $e'), backgroundColor: Colors.red));
    }
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(title: const Text('📝 إتمام بيانات المستفيد')),
      body: _saving ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_b.displayName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1))),
            if (_b.birthInfo.isNotEmpty) Text(_b.birthInfo, style: const TextStyle(color: Color(0xFF475569))),
            Text('العنوان: ${_b.address} | البرنامج: ${_b.program}', style: const TextStyle(color: Color(0xFF475569))),
          ]))),
          const SizedBox(height: 18),
          Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('🔗 الربط بالشبكات:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Wrap(spacing: 16, children: [
              _chk('كهرباء', _e, (v) => setState(() => _e = v!)),
              _chk('غاز', _g, (v) => setState(() => _g = v!)),
              _chk('مياه', _w, (v) => setState(() => _w = v!)),
              _chk('تطهير', _s, (v) => setState(() => _s = v!)),
            ]),
          ]))),
          const SizedBox(height: 18),
          Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('🏗️ الحالة الفيزيائية:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            DropdownButtonFormField<String>(value: _status, items: _statuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(), onChanged: (v) => setState(() => _status = v!)),
          ]))),
          const SizedBox(height: 18),
          Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('📷 الصورة:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ElevatedButton.icon(onPressed: _showPicker, icon: const Icon(Icons.camera), label: const Text('التقاط صورة'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF475569))),
            if (_img != null || _b.imagePath != null) Container(margin: const EdgeInsets.only(top: 16), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)]), child: ClipRRect(borderRadius: BorderRadius.circular(12), child: _img != null ? Image.file(_img!) : Image.file(File(_b.imagePath!)))),
          ]))),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: ElevatedButton(onPressed: _save, child: const Text('💾 حفظ'))),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton(onPressed: () => Navigator.pop(context), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF94A3B8)), child: const Text('🔙 رجوع'))),
          ]),
        ]),
      ),
    );
  }

  Widget _chk(String label, bool val, Function(bool?) onChanged) {
    return SizedBox(width: 120, child: Row(children: [Checkbox(value: val, onChanged: onChanged), Text(label)]));
  }
}
