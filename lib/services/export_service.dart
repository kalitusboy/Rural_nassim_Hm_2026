
import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
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

    // اختيار مكان حفظ الملف
    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: "حفظ ملف الصور المضغوط",
      fileName: "صور_الميدان_${DateTime.now().millisecondsSinceEpoch}.zip",
      allowedExtensions: ['zip'],
    );
    if (outputFile == null) return;

    // استخدام ZipFileEncoder للإضافة المتدفقة
    final encoder = ZipFileEncoder();
    encoder.create(outputFile);

    for (var beneficiary in withImages) {
      final imageFile = File(beneficiary.imagePath!);
      final fileName = beneficiary.imageFileName ?? 
          '${beneficiary.displayName}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await encoder.addFile(imageFile, fileName);
    }

    await encoder.close();

    await Share.shareXFiles([XFile(outputFile)], text: 'صور الميدان - إحصاء 2026');
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
      
      int imported = 0;
      int duplicates = 0;
      
      for (var file in files) {
        try {
          final jsonString = await file.readAsString();
          final data = jsonDecode(jsonString);
          final list = data['beneficiaries'] as List? ?? [];
          
          final existing = await _dbService.getAllBeneficiaries();
          final existingKeys = existing
              .map((b) => '${b.firstName}|${b.lastName}|${b.birthDate}|${b.address}')
              .toSet();
          
          for (var item in list) {
            // تحويل من Map إلى Beneficiary
            final map = Map<String, dynamic>.from(item);
            final firstName = map['first_name']?.toString() ?? map['firstName']?.toString() ?? '';
            final lastName = map['last_name']?.toString() ?? map['lastName']?.toString() ?? '';
            final birthDate = map['birth_date']?.toString() ?? map['birthDate']?.toString() ?? '';
            final address = map['address']?.toString() ?? '';
            
            final key = '$firstName|$lastName|$birthDate|$address';
            
            if (!existingKeys.contains(key)) {
              // إدخال المستفيد الجديد مباشرة
              await _dbService.database.then((db) async {
                map['created_at'] = DateTime.now().millisecondsSinceEpoch;
                map['updated_at'] = DateTime.now().millisecondsSinceEpoch;
                map.remove('id');
                await db.insert('beneficiaries', map);
              });
              existingKeys.add(key);
              imported++;
            } else {
              duplicates++;
            }
          }
        } catch (e) {
          // تجاهل أخطاء الملفات الفردية
        }
      }
      
      return {'imported': imported, 'duplicates': duplicates};
    } catch (e) {
      throw Exception('فشل دمج قواعد البيانات: $e');
    }
  }
}
