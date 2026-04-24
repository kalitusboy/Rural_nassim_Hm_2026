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
  final TextEditingController _outputFileNameController = TextEditingController(text: 'merged_database_final.json');
  String _log = '';

  void _addLog(String message) {
    setState(() {
      _log += '$message\n';
    });
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

    try {
      // 1. إنشاء مجلد مؤقت لفك ضغط الصور
      final tempDir = await getTemporaryDirectory();
      final extractDir = Directory('${tempDir.path}/merged_images');
      if (await extractDir.exists()) {
        await extractDir.delete(recursive: true);
      }
      await extractDir.create();

      // 2. فك ضغط جميع ملفات ZIP
      int imagesCount = 0;
      for (var zipFile in _zipFiles) {
        _addLog('📦 فك ضغط: ${zipFile.path.split('/').last}');
        final bytes = await zipFile.readAsBytes();
        final archive = ZipDecoder().decodeBytes(bytes);
        for (var file in archive) {
          if (file.isFile) {
            final filename = file.name;
            final outputFile = File('${extractDir.path}/$filename');
            await outputFile.create(recursive: true);
            await outputFile.writeAsBytes(file.content);
            imagesCount++;
          }
        }
      }
      _addLog('✅ تم فك ضغط $imagesCount صورة');

      // 3. بناء فهرس الصور (اسم الملف بدون امتداد -> المسار الكامل)
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

      // 4. قراءة ودمج جميع ملفات JSON
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
            // إذا كان موجوداً، نحاول تحديث مسار الصورة فقط إذا لم يكن هناك صورة حالية
            final existing = mergedBeneficiaries[key]!;
            final existingImagePath = existing['image_path']?.toString() ?? '';
            final newImagePath = b['image_path']?.toString() ?? '';
            
            if ((existingImagePath.isEmpty || !await File(existingImagePath).exists()) && newImagePath.isNotEmpty) {
              existing['image_path'] = newImagePath;
              _addLog('🔄 تم تحديث مسار صورة: ${b['full_name']}');
            }
          }
        }
      }
      _addLog('👥 إجمالي المستفيدين بعد الدمج: ${mergedBeneficiaries.length}');

      // 5. تحديث مسارات الصور للمستفيدين (البحث في الصور المستخرجة)
      int updatedCount = 0;
      int notFoundCount = 0;
      
      for (var entry in mergedBeneficiaries.entries) {
        final b = entry.value;
        final imageFileName = b['image_file_name']?.toString() ?? '';
        if (imageFileName.isEmpty) continue;
        
        final currentPath = b['image_path']?.toString() ?? '';
        if (currentPath.isNotEmpty && await File(currentPath).exists()) {
          continue; // الصورة موجودة بالفعل، لا نغيرها
        }
        
        if (imageIndex.containsKey(imageFileName)) {
          b['image_path'] = imageIndex[imageFileName];
          updatedCount++;
          _addLog('✅ تم تعيين صورة لـ: ${b['full_name']}');
        } else {
          notFoundCount++;
          _addLog('❌ لم يتم العثور على صورة: $imageFileName');
        }
      }
      _addLog('📸 تم تحديث $updatedCount مستفيد، لم يتم العثور على صور لـ $notFoundCount');

      // 6. حفظ النتيجة
      final outputDir = await getApplicationDocumentsDirectory();
      final outputPath = '${outputDir.path}/${_outputFileNameController.text}';
      final outputFile = File(outputPath);
      final outputData = {'beneficiaries': mergedBeneficiaries.values.toList()};
      await outputFile.writeAsString(jsonEncode(outputData));
      _addLog('💾 تم حفظ الملف النهائي: ${outputFile.path}');
      
      // 7. تنظيف المجلد المؤقت
      await extractDir.delete(recursive: true);
      
      _addLog('✅ انتهت العملية بنجاح!');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم الحفظ بنجاح في: ${outputFile.path.split('/').last}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      _addLog('❌ خطأ: $e');
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
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _pickJsonFiles,
                      icon: const Icon(Icons.folder_open),
                      label: Text('اختر ملفات JSON (${_jsonFiles.length})'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0D47A1),
                        minimumSize: const Size(double.infinity, 50),
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
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _outputFileNameController,
                      decoration: const InputDecoration(
                        labelText: 'اسم ملف الإخراج',
                        border: OutlineInputBorder(),
                        suffixText: '.json',
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _startMerge,
                      icon: _isProcessing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.merge_type),
                      label: const Text('بدء الدمج'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        minimumSize: const Size(double.infinity, 50),
                      ),
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
                      const SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Text(
                            _log.isEmpty ? 'انتظر بدء العملية...' : _log,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
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