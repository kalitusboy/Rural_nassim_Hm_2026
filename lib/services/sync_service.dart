
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'database_service.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final _db = DatabaseService();

  static String _key(Map<String, dynamic> r) {
    final fn = (r['first_name'] ?? '').toString().trim().toLowerCase();
    final ln = (r['last_name'] ?? '').toString().trim().toLowerCase();
    final bd = (r['birth_date'] ?? '').toString().trim();
    final ad = (r['address'] ?? '').toString().trim().toLowerCase();
    return '$fn|$ln|$bd|$ad';
  }

  static Map<String, dynamic> _resolve(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    final localDone = local['done'] as int? ?? 0;
    final remoteDone = remote['done'] as int? ?? 0;
    if (localDone == 1 && remoteDone == 0) return {...local, 'id': local['id']};
    if (remoteDone == 1 && localDone == 0) return {...remote, 'id': local['id']};
    final localTs = local['updated_at'] as int? ?? 0;
    final remoteTs = remote['updated_at'] as int? ?? 0;
    final winner = remoteTs > localTs ? remote : local;
    return {...winner, 'id': local['id']};
  }

  Future<Map<String, int>> mergeRecords(List<Map<String, dynamic>> incoming) async {
    final db = await _db.database;
    int added = 0, updated = 0;
    final localList = await db.query('beneficiaries');
    final Map<String, Map<String, dynamic>> localMap = {};
    for (final r in localList) {
      localMap[_key(r)] = Map<String, dynamic>.from(r);
    }
    final imgDir = await getImagesDir();
    for (final remote in incoming) {
      final k = _key(remote);
      if (!localMap.containsKey(k)) {
        final toInsert = Map<String, dynamic>.from(remote)..remove('id');
        if ((toInsert['image_file_name'] as String?)?.isNotEmpty == true) {
          toInsert['image_path'] = p.join(imgDir.path, toInsert['image_file_name']);
        }
        await db.insert('beneficiaries', toInsert);
        added++;
      } else {
        final merged = _resolve(localMap[k]!, remote);
        if ((merged['image_file_name'] as String?)?.isNotEmpty == true) {
          merged['image_path'] = p.join(imgDir.path, merged['image_file_name']);
        }
        final id = merged['id'];
        final toUpdate = Map<String, dynamic>.from(merged)..remove('id');
        await db.update('beneficiaries', toUpdate, where: 'id = ?', whereArgs: [id]);
        updated++;
      }
    }
    return {'added': added, 'updated': updated};
  }

  Future<List<Map<String, dynamic>>> getAllRecords() async {
    final db = await _db.database;
    return db.query('beneficiaries');
  }

  Future<List<Map<String, dynamic>>> getSummary() async {
    final db = await _db.database;
    final rows = await db.query('beneficiaries',
        columns: ['id', 'first_name', 'last_name', 'birth_date', 'address',
                  'updated_at', 'done', 'image_file_name']);
    return rows.map((r) => {
      'first_name': r['first_name'],
      'last_name': r['last_name'],
      'birth_date': r['birth_date'],
      'address': r['address'],
      'updated_at': r['updated_at'],
      'done': r['done'],
      'image_file_name': r['image_file_name'],
    }).toList();
  }

  Future<Map<String, dynamic>> compareAndGetMissing(List<Map<String, dynamic>> remoteSummary) async {
    final localRecords = await getAllRecords();
    final Map<String, Map<String, dynamic>> localMap = {};
    for (final r in localRecords) {
      localMap[_key(r)] = Map<String, dynamic>.from(r);
    }
    final List<Map<String, dynamic>> missingAtRemote = [];
    final Set<String> imageNamesToSend = {};

    for (final entry in localMap.entries) {
      final k = entry.key;
      final localItem = entry.value;
      final remoteItem = remoteSummary.firstWhere(
        (r) => _key(r) == k,
        orElse: () => <String, dynamic>{},
      );
      if (remoteItem.isEmpty) {
        missingAtRemote.add(localItem);
        final img = localItem['image_file_name'] as String?;
        if (img != null && img.isNotEmpty) imageNamesToSend.add(img);
      } else {
        final remoteTs = remoteItem['updated_at'] as int? ?? 0;
        final localTs = localItem['updated_at'] as int? ?? 0;
        if (localTs > remoteTs) {
          missingAtRemote.add(localItem);
          final img = localItem['image_file_name'] as String?;
          if (img != null && img.isNotEmpty) imageNamesToSend.add(img);
        }
      }
    }
    return {'records': missingAtRemote, 'images': imageNamesToSend.toList()};
  }

  Future<File> createZipForItems(List<Map<String, dynamic>> records, List<String> imageNames) async {
    final archive = Archive();
    final jsonStr = jsonEncode({'beneficiaries': records});
    archive.addFile(ArchiveFile('diff.json', jsonStr.length, utf8.encode(jsonStr)));
    final imgDir = await getImagesDir();

    for (final name in imageNames) {
      File file = File(p.join(imgDir.path, name));
      if (!await file.exists()) {
        final baseName = p.basenameWithoutExtension(name);
        FileSystemEntity? found;
        await for (final entity in imgDir.list()) {
          if (entity is File && p.basenameWithoutExtension(entity.path) == baseName) {
            found = entity;
            break;
          }
        }
        if (found != null) file = found as File;
      }
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        archive.addFile(ArchiveFile(p.basename(file.path), bytes.length, bytes));
      }
    }

    final zipData = ZipEncoder().encode(archive);
    final tmpDir = await getTemporaryDirectory();
    final zipFile = File(p.join(tmpDir.path, 'diff_${DateTime.now().millisecondsSinceEpoch}.zip'));
    await zipFile.writeAsBytes(zipData!);
    return zipFile;
  }

  Future<File> createZipPackage() async {
    final records = await getAllRecords();
    final jsonStr = jsonEncode({'beneficiaries': records});
    final archive = Archive();
    archive.addFile(ArchiveFile('data.json', jsonStr.length, utf8.encode(jsonStr)));

    final imgDir = await getImagesDir();
    final existingFiles = <String>[];
    await for (final entity in imgDir.list()) {
      if (entity is File) {
        final name = p.basename(entity.path);
        if (name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.png')) {
          existingFiles.add(name);
        }
      }
    }

    final Set<String> addedImages = {};
    for (final r in records) {
      final imgName = r['image_file_name'] as String?;
      if (imgName == null || imgName.isEmpty) continue;
      String? matchedFile;
      if (existingFiles.contains(imgName)) {
        matchedFile = imgName;
      } else {
        final baseName = p.basenameWithoutExtension(imgName);
        matchedFile = existingFiles.firstWhere(
          (f) => p.basenameWithoutExtension(f) == baseName,
          orElse: () => '',
        );
        if (matchedFile!.isEmpty) matchedFile = null;
      }
      if (matchedFile != null) {
        final file = File(p.join(imgDir.path, matchedFile));
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          archive.addFile(ArchiveFile(matchedFile, bytes.length, bytes));
          addedImages.add(matchedFile);
        }
      }
    }

    final zipData = ZipEncoder().encode(archive);
    final tmpDir = await getTemporaryDirectory();
    final zipFile = File(p.join(tmpDir.path, 'full_${DateTime.now().millisecondsSinceEpoch}.zip'));
    await zipFile.writeAsBytes(zipData!);
    return zipFile;
  }

  Future<Map<String, int>> processReceivedZip(File zipFile) async {
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    String? jsonContent;
    int imagesCopied = 0;
    final imgDir = await getImagesDir();

    for (final file in archive) {
      if (file.isFile) {
        if (file.name == 'data.json' || file.name == 'diff.json') {
          jsonContent = utf8.decode(file.content);
        } else if (file.name.endsWith('.jpg') || file.name.endsWith('.jpeg') || file.name.endsWith('.png')) {
          final targetFile = File(p.join(imgDir.path, file.name));
          await targetFile.writeAsBytes(file.content);
          imagesCopied++;
        }
      }
    }

    int added = 0, updated = 0;
    if (jsonContent != null) {
      final data = jsonDecode(jsonContent) as Map<String, dynamic>;
      final records = (data['beneficiaries'] as List).cast<Map<String, dynamic>>();

      for (final rec in records) {
        final imgName = rec['image_file_name'] as String?;
        if (imgName != null && imgName.isNotEmpty) {
          final candidate = File(p.join(imgDir.path, imgName));
          if (!await candidate.exists()) {
            final baseName = p.basenameWithoutExtension(imgName);
            FileSystemEntity? found;
            await for (final entity in imgDir.list()) {
              if (entity is File && p.basenameWithoutExtension(entity.path) == baseName) {
                found = entity;
                break;
              }
            }
            if (found != null) {
              rec['image_file_name'] = p.basename(found.path);
            }
          }
        }
      }

      final stats = await mergeRecords(records);
      added = stats['added'] ?? 0;
      updated = stats['updated'] ?? 0;
    }

    return {'added': added, 'updated': updated, 'images': imagesCopied};
  }

  Future<Directory> getImagesDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final imgDir = Directory(p.join(docsDir.path, 'images'));
    if (!await imgDir.exists()) await imgDir.create(recursive: true);
    return imgDir;
  }

  Future<void> backup() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      for (final dbName in ['ihsa_2026.db', 'rural_nassim.db', 'beneficiaries.db']) {
        final src = File(p.join(docsDir.path, dbName));
        if (await src.exists()) {
          final ts = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
          await src.copy(p.join(docsDir.path, 'backup_$ts.db'));
          break;
        }
      }
    } catch (_) {}
  }
}
