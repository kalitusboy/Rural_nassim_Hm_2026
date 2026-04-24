
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';

class AdminMergeScreen extends StatefulWidget {
  const AdminMergeScreen({super.key});

  @override
  State<AdminMergeScreen> createState() => _AdminMergeScreenState();
}

class _AdminMergeScreenState extends State<AdminMergeScreen> {
  List<File> _jsonFiles = [];
  List<File> _zipFiles = [];
  bool _isProcessing = false;
  String _log = '';

  void _addLog(String msg) {
    setState(() => _log += '$msg\n');
  }

  Future<void> _pickFiles(String type) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [type == 'json' ? 'json' : 'zip'],
      allowMultiple: true,
    );
    if (result != null) {
      setState(() {
        if (type == 'json') {
          _jsonFiles = result.paths.map((p) => File(p!)).toList();
        } else {
          _zipFiles = result.paths.map((p) => File(p!)).toList();
        }
      });
      _addLog('✅ تم اختيار ${result.files.length} ملف $type');
    }
  }

  Future<void> _startMerge() async {
    if (_jsonFiles.isEmpty || _zipFiles.isEmpty) {
      _addLog('❌ اختر ملفات JSON و ZIP أولاً');
      return;
    }

    // اختيار مكان حفظ الملف النهائي
    String? outputPath = await FilePicker.platform.saveFile(
      dialogTitle: 'حفظ قاعدة البيانات المدمجة',
      fileName: 'merged_database_${DateTime.now().millisecondsSinceEpoch}.json',
      allowedExtensions: ['json'],
    );
    if (outputPath == null) {
      _addLog('❌ تم إلغاء الحفظ');
      return;
    }

    setState(() {
      _isProcessing = true;
      _log = '';
    });

    try {
      // مجلد مؤقت لفك الضغط
      final tempDir = await getTemporaryDirectory();
      final extractDir = Directory('${tempDir.path}/temp_images');
      if (await extractDir.exists()) await extractDir.delete(recursive: true);
      await extractDir.create();

      // فك ضغط ZIP
      int imgCount = 0;
      for (var zip in _zipFiles) {
        _addLog('📦 فك ضغط: ${zip.path.split('/').last}');
        final bytes = await zip.readAsBytes();
        final archive = ZipDecoder().decodeBytes(bytes);
        for (var file in archive) {
          if (file.isFile && file.name.toLowerCase().contains(RegExp(r'\.(jpg|jpeg|png)'))) {
            final out = File('${extractDir.path}/${file.name.split('/').last}');
            await out.create(recursive: true);
            await out.writeAsBytes(file.content);
            imgCount++;
          }
        }
      }
      _addLog('✅ تم فك ضغط $imgCount صورة');

      // فهرسة الصور
      final Map<String, String> imageMap = {};
      await for (var entity in extractDir.list()) {
        if (entity is File) {
          final name = entity.path.split('/').last;
          final nameNoExt = name.split('.').first;
          imageMap[name] = entity.path;
          imageMap[nameNoExt] = entity.path;
        }
      }

      // المجلد الدائم للصور
      final appDir = await getApplicationDocumentsDirectory();
      final permImageDir = Directory('${appDir.path}/merged_images');
      if (!await permImageDir.exists()) await permImageDir.create();

      // دمج JSON
      final Map<String, Map<String, dynamic>> merged = {};
      for (var jsonFile in _jsonFiles) {
        _addLog('📄 قراءة JSON: ${jsonFile.path.split('/').last}');
        final data = jsonDecode(await jsonFile.readAsString());
        final list = data['beneficiaries'] as List? ?? [];
        for (var b in list) {
          final key = '${b['first_name']}|${b['last_name']}|${b['birth_date']}|${b['address']}';
          if (!merged.containsKey(key)) merged[key] = Map.from(b);
        }
      }
      _addLog('👥 إجمالي المستفيدين: ${merged.length}');

      // تحديث مسارات الصور ونسخها إلى المجلد الدائم
      int updated = 0, notFound = 0;
      for (var b in merged.values) {
        final imgName = b['image_file_name'] ?? '';
        if (imgName.isEmpty) continue;
        final current = b['image_path'] ?? '';
        if (current.isNotEmpty && await File(current).exists()) continue;

        if (imageMap.containsKey(imgName)) {
          final src = imageMap[imgName]!;
          final destName = src.split('/').last;
          final dest = File('${permImageDir.path}/$destName');
          if (!await dest.exists()) {
            await File(src).copy(dest.path);
          }
          b['image_path'] = dest.path;
          updated++;
          _addLog('✅ صورة لـ ${b['full_name']}');
        } else {
          notFound++;
          _addLog('❌ صورة مفقودة: $imgName');
        }
      }
      _addLog('📸 تم تحديث $updated مستفيد، مفقود: $notFound');

      // حفظ الملف النهائي في المسار الذي اختاره المستخدم
      final outFile = File(outputPath);
      await outFile.writeAsString(jsonEncode({'beneficiaries': merged.values.toList()}));
      _addLog('💾 تم الحفظ: ${outFile.path}');

      // تنظيف
      await extractDir.delete(recursive: true);

      _addLog('✅ انتهى بنجاح');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم الحفظ في: ${outFile.path.split('/').last}'), backgroundColor: Colors.green),
      );
    } catch (e) {
      _addLog('❌ خطأ: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('👥 دمج بيانات الأعوان (المدير)'), backgroundColor: const Color(0xFF0D47A1)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _pickFiles('json'),
                      icon: const Icon(Icons.folder_open),
                      label: Text('JSON (${_jsonFiles.length})'),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () => _pickFiles('zip'),
                      icon: const Icon(Icons.folder_zip),
                      label: Text('ZIP (${_zipFiles.length})'),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _startMerge,
                      icon: _isProcessing ? const CircularProgressIndicator() : const Icon(Icons.merge),
                      label: const Text('بدء الدمج'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('سجل العمليات:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Text(_log.isEmpty ? '...' : _log, style: const TextStyle(fontFamily: 'monospace')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
