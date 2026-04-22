import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'database_service.dart';

class ExportService {
  final DatabaseService _dbService = DatabaseService();

  Future<void> exportFullDatabase() async {
    final jsonString = await _dbService.exportToJson();
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/ihsa_backup_${DateTime.now().millisecondsSinceEpoch}.json';
    await File(filePath).writeAsString(jsonString);
    await Share.shareXFiles([XFile(filePath)]);
  }

  Future<void> exportImagesAsZip() async {
    final beneficiaries = await _dbService.getCompletedBeneficiaries();
    final withImages = beneficiaries.where((b) => b.imagePath != null && File(b.imagePath!).existsSync()).toList();
    if (withImages.isEmpty) throw Exception('لا توجد صور');
    
    final archive = Archive();
    for (var b in withImages) {
      final bytes = await File(b.imagePath!).readAsBytes();
      final name = b.imageFileName ?? '${b.displayName}.jpg';
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }
    
    final zipData = ZipEncoder().encode(archive);
    final directory = await getApplicationDocumentsDirectory();
    final zipPath = '${directory.path}/صور_${DateTime.now().millisecondsSinceEpoch}.zip';
    await File(zipPath).writeAsBytes(zipData);
    await Share.shareXFiles([XFile(zipPath)]);
  }

  Future<Map<String, int>> mergeDatabases() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json'], allowMultiple: true);
    if (result == null || result.files.isEmpty) throw Exception('لم يتم اختيار ملفات');
    final files = result.files.map((f) => File(f.path!)).where((f) => f.existsSync()).toList();
    return await _dbService.mergeFromJsonFiles(files);
  }
}
