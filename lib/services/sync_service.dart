
import 'dart:io';
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
    final done = ((local['done'] as int? ?? 0) == 1 ||
            (remote['done'] as int? ?? 0) == 1)
        ? 1
        : 0;

    final localTs = local['updated_at'] as int? ?? 0;
    final remoteTs = remote['updated_at'] as int? ?? 0;
    final winner = remoteTs > localTs ? remote : local;

    return {
      ...winner,
      'done': done,
      'id': local['id'],
    };
  }

  Future<Map<String, int>> mergeRecords(
      List<Map<String, dynamic>> incoming) async {
    final db = await _db.database;
    int added = 0;
    int updated = 0;

    final localList = await db.query('beneficiaries');
    final Map<String, Map<String, dynamic>> localMap = {};
    for (final r in localList) {
      localMap[_key(r)] = Map<String, dynamic>.from(r);
    }

    final imagesDir = await getImagesDir();

    for (final remote in incoming) {
      final k = _key(remote);

      if (!localMap.containsKey(k)) {
        final toInsert = Map<String, dynamic>.from(remote)..remove('id');
        if (toInsert['image_file_name'] != null) {
          toInsert['image_path'] =
              p.join(imagesDir.path, toInsert['image_file_name']);
        }
        await db.insert('beneficiaries', toInsert);
        added++;
      } else {
        final merged = _resolve(localMap[k]!, remote);
        if (merged['image_file_name'] != null) {
          merged['image_path'] =
              p.join(imagesDir.path, merged['image_file_name']);
        }
        final id = merged['id'];
        final toUpdate = Map<String, dynamic>.from(merged)..remove('id');
        await db.update('beneficiaries', toUpdate,
            where: 'id = ?', whereArgs: [id]);
        updated++;
      }
    }

    return {'added': added, 'updated': updated};
  }

  Future<List<Map<String, dynamic>>> getAllRecords() async {
    final db = await _db.database;
    return db.query('beneficiaries');
  }

  Future<String> backup() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final src = File(p.join(docsDir.path, 'ihsa_2026.db'));
    if (!await src.exists()) return '';

    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .substring(0, 19);
    final dst = p.join(docsDir.path, 'backup_$ts.db');
    await src.copy(dst);
    return dst;
  }

  Future<Directory> getImagesDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final imgDir = Directory(p.join(docsDir.path, 'images'));
    if (!await imgDir.exists()) {
      await imgDir.create(recursive: true);
    }
    return imgDir;
  }

  Future<List<String>> getLocalImageFilenames() async {
    final imgDir = await getImagesDir();
    final filenames = <String>[];

    if (await imgDir.exists()) {
      final files = await imgDir.list().toList();
      filenames.addAll(
        files
            .whereType<File>()
            .map((f) => p.basename(f.path))
            .where((name) =>
                name.endsWith('.jpg') ||
                name.endsWith('.jpeg') ||
                name.endsWith('.png')),
      );
    }

    final mergedDir = Directory(
        p.join((await getApplicationDocumentsDirectory()).path, 'merged_images'));
    if (await mergedDir.exists()) {
      final mergedFiles = await mergedDir.list().toList();
      filenames.addAll(
        mergedFiles
            .whereType<File>()
            .map((f) => p.basename(f.path))
            .where((name) =>
                name.endsWith('.jpg') ||
                name.endsWith('.jpeg') ||
                name.endsWith('.png')),
      );
    }

    return filenames.toSet().toList();
  }
}
