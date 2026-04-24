
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'package:open_file/open_file.dart';

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

  void _addLog(String message) {
    setState(() {
      _log += '$message\n';
    });
    print(message);
  }

  Future<void> _pickJsonFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      allowMultiple: true,
    );
    if (result != null) {
      setState(() {
        _jsonFiles = result.paths.map((path) => File(path!)).toList();
      });
      _addLog('✅ تم اختيار ${_jsonFiles.length} ملف JSON');
    }
  }

  Future<void> _pickZipFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      allowMultiple: true,
    );
    if (result != null) {
      setState(() {
        _zipFiles = result.paths.map((path) => File(path!)).toList();
      });
      _addLog('✅ تم اختيار ${_zipFiles.length} ملف ZIP');
    }
  }

  Future<void> _startMerge() async {
    if (_jsonFiles.isEmpty) {
      _addLog('❌ الرجاء اختيار ملفات JSON أولاً');
      return;
    }
    if (_zipFiles.isEmpty) {
      _addLog('❌ الرجاء اختيار ملفات ZIP أولاً');
      return;
    }

    setState(() {
      _isProcessing = true;
      _log = '';
    });

    // عرض مؤشر تحميل
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // 1. مجلد مؤقت لفك ضغط الصور
      final tempDir = await getTemporaryDirectory();
      final extractDir = Directory('${tempDir.path}/extracted_images_${DateTime.now().millisecondsSinceEpoch}');
      if (await extractDir.exists()) await extractDir.delete(recursive: true);
      await extractDir.create();

      // 2. فك ضغط جميع ملفات ZIP
      int imagesCount = 0;
      for (var zipFile in _zipFiles) {
        _addLog('📦 فك ضغط: ${zipFile.path.split('/').last}');
        final bytes = await zipFile.readAsBytes();
        final archive = ZipDecoder().decodeBytes(bytes);
        for (var file in archive) {
          if (file.isFile) {
            final outputFile = File('${extractDir.path}/${file.name}');
            await outputFile.create(recursive: true);
            await outputFile.writeAsBytes(file.content);
            imagesCount++;
          }
        }
      }
      _addLog('✅ تم فك ضغط $imagesCount ملف');

      // 3. بناء فهرس الصور
      final Map<String, String> imageIndex = {};
      await for (var entity in extractDir.list(recursive: true)) {
        if (entity is File) {
          final fileName = entity.path.split('/').last;
          final lowerName = fileName.toLowerCase();
          if (lowerName.endsWith('.jpg') || lowerName.endsWith('.jpeg') || lowerName.endsWith('.png')) {
            final nameWithoutExt = fileName.split('.').first;
            imageIndex[fileName] = entity.path;
            imageIndex[nameWithoutExt] = entity.path;
          }
        }
      }
      _addLog('✅ تم فهرسة ${imageIndex.length ~/ 2} صورة فريدة');

      // 4. المجلد الدائم للصور
      final appDir = await getApplicationDocumentsDirectory();
      final permanentImagesDir = Directory('${appDir.path}/merged_images');
      if (!await permanentImagesDir.exists()) {
        await permanentImagesDir.create(recursive: true);
      }
      _addLog('📁 المجلد الدائم للصور: ${permanentImagesDir.path}');

      // 5. دمج JSON
      final Map<String, Map<String, dynamic>> mergedBeneficiaries = {};
      for (var jsonFile in _jsonFiles) {
        _addLog('📄 قراءة JSON: ${jsonFile.path.split('/').last}');
        final content = await jsonFile.readAsString();
        final data = jsonDecode(content);
        final beneficiaries = data['beneficiaries'] as List? ?? [];
        for (var b in beneficiaries) {
          final firstName = b['first_name']?.toString() ?? '';
          final lastName = b['last_name']?.toString() ?? '';
          final birthDate = b['birth_date']?.toString() ?? '';
          final address = b['address']?.toString() ?? '';
          final key = '$firstName|$lastName|$birthDate|$address';
          if (!mergedBeneficiaries.containsKey(key)) {
            mergedBeneficiaries[key] = Map<String, dynamic>.from(b);
          } else {
            final existing = mergedBeneficiaries[key]!;
            final existingImagePath = existing['image_path']?.toString() ?? '';
            if (existingImagePath.isNotEmpty && await File(existingImagePath).exists()) {
              continue; // نحتفظ بالصورة الحالية
            } else {
              mergedBeneficiaries[key] = Map<String, dynamic>.from(b);
            }
          }
        }
      }
      _addLog('👥 إجمالي المستفيدين بعد الدمج: ${mergedBeneficiaries.length}');

      // 6. نقل الصور للمستفيدين الجدد أو الذين ليس لديهم صور
      int updatedCount = 0;
      int notFoundCount = 0;
      for (var entry in mergedBeneficiaries.entries) {
        final b = entry.value;
        final imageFileName = b['image_file_name']?.toString() ?? '';
        if (imageFileName.isEmpty) continue;
        final currentPath = b['image_path']?.toString() ?? '';
        if (currentPath.isNotEmpty && await File(currentPath).exists()) {
          continue; // موجودة وصالحة، لا نغيرها
        }
        final String? tempImagePath = imageIndex[imageFileName];
        if (tempImagePath != null && tempImagePath.isNotEmpty) {
          try {
            final fileExt = tempImagePath.split('.').last;
            final safeFileName = imageFileName.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
            final newFileName = '${DateTime.now().millisecondsSinceEpoch}_$safeFileName.$fileExt';
            final newPath = '${permanentImagesDir.path}/$newFileName';
            await File(tempImagePath).copy(newPath);
            b['image_path'] = newPath;
            b['image_file_name'] = newFileName;
            updatedCount++;
            _addLog('✅ تم نقل صورة لـ: ${b['full_name']}');
          } catch (e) {
            _addLog('⚠️ فشل نقل الصورة $imageFileName: $e');
          }
        } else {
          notFoundCount++;
          _addLog('❌ لم يتم العثور على صورة: $imageFileName');
        }
      }
      _addLog('📸 تم نقل $updatedCount صورة، لم يتم العثور على $notFoundCount صورة');

      // 7. حفظ JSON النهائي داخل مجلد التطبيق (آمن)
      final outputFileName = 'merged_database_${DateTime.now().millisecondsSinceEpoch}.json';
      final outputFile = File('${appDir.path}/$outputFileName');
      final outputData = {'beneficiaries': mergedBeneficiaries.values.toList()};
      await outputFile.writeAsString(jsonEncode(outputData));
      _addLog('💾 تم حفظ الملف: ${outputFile.path}');

      // 8. تنظيف المجلد المؤقت
      await extractDir.delete(recursive: true);
      _addLog('🗑️ تم حذف المجلد المؤقت');

      _addLog('✅ انتهت العملية بنجاح!');

      if (mounted) Navigator.pop(context);

      // عرض رسالة مع زر فتح الملف
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ تم الدمج بنجاح! الملف: $outputFileName'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'فتح',
            onPressed: () => OpenFile.open(outputFile.path),
          ),
        ),
      );
    } catch (e, stackTrace) {
      if (mounted) Navigator.pop(context);
      _addLog('❌ خطأ: $e');
      _addLog('📚 تفاصيل: $stackTrace');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('👥 دمج بيانات الأعوان (المدير)'),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _pickJsonFiles,
                      icon: const Icon(Icons.folder_open),
                      label: Text('اختر ملفات JSON (${_jsonFiles.length})'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0D47A1),
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _pickZipFiles,
                      icon: const Icon(Icons.folder_zip),
                      label: Text('اختر ملفات ZIP (${_zipFiles.length})'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE67E22),
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _startMerge,
                      icon: _isProcessing
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.merge_type),
                      label: const Text('بدء الدمج والصور'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'سجل العمليات:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.all(8),
                          child: SingleChildScrollView(
                            child: Text(
                              _log.isEmpty
                                  ? '⚠️ لم يتم تنفيذ أي عملية بعد.\n\nالخطوات:\n1. اختر ملفات JSON\n2. اختر ملفات ZIP\n3. اضغط بدء الدمج'
                                  : _log,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                            ),
                          ),
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
