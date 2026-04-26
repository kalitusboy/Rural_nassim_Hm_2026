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

  // قاعدة حل التعارض المُحسَّنة
  static Map<String, dynamic> _resolve(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    final localDone = local['done'] as int? ?? 0;
    final remoteDone = remote['done'] as int? ?? 0;

    // ✅ إذا كان أحد الطرفين مُحصى (done=1) والآخر لا → المُحصى يفوز دائمًا
    if (localDone == 1 && remoteDone == 0) {
      return {...local, 'id': local['id']};
    }
    if (remoteDone == 1 && localDone == 0) {
      return {...remote, 'id': local['id']};
    }

    // غير ذلك نقارن updated_at (الأحدث هو الفائز)
    final localTs = local['updated_at'] as int? ?? 0;
    final remoteTs = remote['updated_at'] as int? ?? 0;
    final winner = remoteTs > localTs ? remote : local;
    return {...winner, 'id': local['id']};
  }

  Future<Map<String, int>> mergeRecords(
      List<Map<String, dynamic>> incoming) async {
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
        // سجل جديد
        final toInsert = Map<String, dynamic>.from(remote)..remove('id');
        if ((toInsert['image_file_name'] as String?)?.isNotEmpty == true) {
          toInsert['image_path'] =
              p.join(imgDir.path, toInsert['image_file_name']);
        }
        await db.insert('beneficiaries', toInsert);
        added++;
      } else {
        // سجل موجود – حل التعارض
        final merged = _resolve(localMap[k]!, remote);
        if ((merged['image_file_name'] as String?)?.isNotEmpty == true) {
          merged['image_path'] =
              p.join(imgDir.path, merged['image_file_name']);
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

  Future<List<Map<String, String>>> getDbImages() async {
    final db = await _db.database;
    final rows = await db.query(
      'beneficiaries',
      columns: ['image_file_name', 'image_path'],
      where: "image_file_name IS NOT NULL AND image_file_name != ''",
    );

    final imgDir = await getImagesDir();
    final result = <Map<String, String>>[];

    for (final row in rows) {
      final name = (row['image_file_name'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;

      final candidates = [
        row['image_path'] as String? ?? '',
        p.join(imgDir.path, name),
        p.join(p.dirname(imgDir.path), name),
      ];

      String foundPath = '';
      for (final c in candidates) {
        if (c.isNotEmpty && await File(c).exists()) {
          foundPath = c;
          break;
        }
      }

      if (foundPath.isNotEmpty) {
        result.add({'name': name, 'path': foundPath});
      }
    }
    return result;
  }

  Future<Set<String>> getLocalImageNames() async {
    final dbImgs = await getDbImages();
    return dbImgs.map((e) => e['name']!).toSet();
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
          final ts = DateTime.now()
              .toIso8601String()
              .replaceAll(':', '-')
              .substring(0, 19);
          await src.copy(p.join(docsDir.path, 'backup_$ts.db'));
          break;
        }
      }
    } catch (_) {}
  }
}
