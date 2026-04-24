
import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import '../models/beneficiary.dart';
import 'database_service.dart';

class ExportService {
  final DatabaseService _dbService = DatabaseService();

  Future<void> exportFullDatabase() async {
    try {
      final jsonString = await _dbService.exportToJson();
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'ihsa_backup_${DateTime.now().millisecondsSinceEpoch}.json';
      final filePath = '${directory.path}/$fileName';
      
      final file = File(filePath);
      await file.writeAsString(jsonString);
      
      await Share.shareXFiles([XFile(filePath)], text: 'قاعدة بيانات إحصاء 2026');
    } catch (e) {
      throw Exception('فشل تصدير قاعدة البيانات: $e');
    }
  }

  Future<void> exportImagesAsZip() async {
    try {
      final beneficiaries = await _dbService.getCompletedBeneficiaries();
      final withImages = beneficiaries.where((b) {
        if (b.imagePath == null) return false;
        return File(b.imagePath!).existsSync();
      }).toList();
      
      if (withImages.isEmpty) {
        throw Exception('لا توجد صور للتصدير');
      }
      
      final archive = Archive();
      
      for (var beneficiary in withImages) {
        final imageFile = File(beneficiary.imagePath!);
        final imageBytes = await imageFile.readAsBytes();
        
        final fileName = beneficiary.imageFileName ?? 
            '${beneficiary.displayName}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        
        archive.addFile(ArchiveFile(fileName, imageBytes.length, imageBytes));
      }
      
      final zipData = ZipEncoder().encode(archive);
      if (zipData == null) {
        throw Exception('فشل إنشاء ملف ZIP');
      }
      
      final directory = await getApplicationDocumentsDirectory();
      final zipName = 'صور_الميدان_${DateTime.now().millisecondsSinceEpoch}.zip';
      final zipPath = '${directory.path}/$zipName';
      
      final zipFile = File(zipPath);
      await zipFile.writeAsBytes(zipData);
      
      await Share.shareXFiles([XFile(zipPath)], text: 'صور الميدان - إحصاء 2026');
    } catch (e) {
      throw Exception('فشل تصدير الصور: $e');
    }
  }

  Future<Map<String, int>> mergeDatabases() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        allowMultiple: true,
      );
      
      if (result == null || result.files.isEmpty) {
        throw Exception('لم يتم اختيار ملفات');
      }
      
      final files = result.files
          .map((f) => File(f.path!))
          .where((f) => f.existsSync())
          .toList();
      
      if (files.isEmpty) {
        throw Exception('لا توجد ملفات صالحة');
      }
      
      int imported = 0;   // سجلات جديدة
      int updated = 0;    // سجلات تم تحديثها (غير مكتمل + مكتمل بدون صورة)
      int skipped = 0;    // سجلات مكتملة تم تجاهلها (لديها صورة أو لا توجد صورة جديدة)

      for (var file in files) {
        try {
          final jsonString = await file.readAsString();
          final data = jsonDecode(jsonString);
          final list = data['beneficiaries'] as List? ?? [];
          
          for (var item in list) {
            final map = Map<String, dynamic>.from(item);
            
            // استخراج المفتاح الفريد
            final firstName = map['first_name']?.toString() ?? map['firstName']?.toString() ?? '';
            final lastName = map['last_name']?.toString() ?? map['lastName']?.toString() ?? '';
            final birthDate = map['birth_date']?.toString() ?? map['birthDate']?.toString() ?? '';
            final address = map['address']?.toString() ?? '';
            
            if (firstName.isEmpty || lastName.isEmpty) continue;
            
            // البحث عن سجل مطابق في قاعدة البيانات الحالية
            final existing = await _dbService.findBeneficiaryByKey(
              firstName, lastName, birthDate, address,
            );
            
            if (existing == null) {
              // غير موجود: إضافة جديدة
              final newBeneficiary = Beneficiary.fromMap(map);
              await _dbService.insertBeneficiary(newBeneficiary);
              imported++;
            } else {
              // موجود مسبقًا
              if (existing.done == 0) {
                // غير مكتمل: نحدثه من الملف (مع الاحتفاظ بالصورة القديمة إن وجدت وصالحة)
                final newMap = Map<String, dynamic>.from(map);
                // حفظ الصورة القديمة إذا كانت موجودة وصالحة
                if (existing.imagePath != null && 
                    existing.imagePath!.isNotEmpty && 
                    await File(existing.imagePath!).exists()) {
                  newMap['image_path'] = existing.imagePath;
                  newMap['image_file_name'] = existing.imageFileName;
                }
                newMap['id'] = existing.id;
                if (newMap['done'] == null) newMap['done'] = existing.done;
                await _dbService.updateBeneficiaryFromMap(existing.id!, newMap);
                updated++;
              } else {
                // مكتمل (done == 1): نتحقق من الصورة فقط
                final existingImagePath = existing.imagePath ?? '';
                final existingImageExists = existingImagePath.isNotEmpty && await File(existingImagePath).exists();
                final newImagePath = map['image_path']?.toString() ?? '';
                final newImageFileName = map['image_file_name']?.toString() ?? '';

                if (!existingImageExists && newImagePath.isNotEmpty) {
                  // المكتمل ليس لديه صورة صالحة، والملف الجديد يوفر صورة
                  await _dbService.updateBeneficiaryFromMap(existing.id!, {
                    'image_path': newImagePath,
                    'image_file_name': newImageFileName,
                    'updated_at': DateTime.now().millisecondsSinceEpoch,
                  });
                  updated++;
                } else {
                  skipped++;
                }
              }
            }
          }
        } catch (e) {
          debugPrint('خطأ في معالجة ملف $file: $e');
          // تابع للملف التالي
        }
      }
      
      return {'imported': imported, 'updated': updated, 'skipped': skipped};
    } catch (e) {
      throw Exception('فشل دمج قواعد البيانات: $e');
    }
  }
}
