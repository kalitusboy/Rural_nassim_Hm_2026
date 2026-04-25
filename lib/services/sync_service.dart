import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'database_service.dart';

/// خدمة المزامنة — المنطق الأساسي فقط، بدون واجهة
/// القاعدة الذهبية: done=1 لا يُمحى أبداً
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final _db = DatabaseService();

  // ─────────────────────────────────────────────
  // مفتاح التعرف على السجل (نفس الشخص على أجهزة مختلفة)
  // ─────────────────────────────────────────────
  static String _key(Map<String, dynamic> r) {
    final fn = (r['first_name'] ?? '').toString().trim().toLowerCase();
    final ln = (r['last_name'] ?? '').toString().trim().toLowerCase();
    final bd = (r['birth_date'] ?? '').toString().trim();
    final ad = (r['address'] ?? '').toString().trim().toLowerCase();
    return '$fn|$ln|$bd|$ad';
  }

  // ─────────────────────────────────────────────
  // قاعدة حل التعارض
  // ─────────────────────────────────────────────
  static Map<String, dynamic> _resolve(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    // done=1 يفوز دائماً — لا شيء يكتب فوقه
    final done =
        ((local['done'] as int? ?? 0) == 1 || (remote['done'] as int? ?? 0) == 1)
            ? 1
            : 0;

    // الأحدث updated_at يفوز للحقول الأخرى
    final localTs = local['updated_at'] as int? ?? 0;
    final remoteTs = remote['updated_at'] as int? ?? 0;
    final winner = remoteTs > localTs ? remote : local;

    return {
      ...winner,
      'done': done,
      'id': local['id'], // احتفظ بالـ id المحلي
    };
  }

  // ─────────────────────────────────────────────
  // دمج قائمة سجلات واردة في قاعدة البيانات المحلية
  // ─────────────────────────────────────────────
  Future<Map<String, int>> mergeRecords(
      List<Map<String, dynamic>> incoming) async {
    final db = await _db.database;
    int added = 0;
    int updated = 0;

    // بناء خريطة السجلات المحلية
    final localList = await db.query('beneficiaries');
    final Map<String, Map<String, dynamic>> localMap = {};
    for (final r in localList) {
      localMap[_key(r)] = Map<String, dynamic>.from(r);
    }

    final docsDir = await getApplicationDocumentsDirectory();

    for (final remote in incoming) {
      final k = _key(remote);

      if (!localMap.containsKey(k)) {
        // سجل جديد — أضفه
        final toInsert = Map<String, dynamic>.from(remote)..remove('id');
        // صحّح مسار الصورة ليكون محلياً
        if (toInsert['image_file_name'] != null) {
          toInsert['image_path'] =
              p.join(docsDir.path, toInsert['image_file_name']);
        }
        await db.insert('beneficiaries', toInsert);
        added++;
      } else {
        // سجل موجود — حلّ التعارض
        final merged = _resolve(localMap[k]!, remote);
        // صحّح مسار الصورة
        if (merged['image_file_name'] != null) {
          merged['image_path'] =
              p.join(docsDir.path, merged['image_file_name']);
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

  // ─────────────────────────────────────────────
  // استرجاع جميع السجلات كـ Map
  // ─────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getAllRecords() async {
    final db = await _db.database;
    return db.query('beneficiaries');
  }

  // ─────────────────────────────────────────────
  // نسخة احتياطية تلقائية قبل أي مزامنة
  // ─────────────────────────────────────────────
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

  // ─────────────────────────────────────────────
  // إدارة ملفات الصور
  // ─────────────────────────────────────────────
  Future<Directory> getImagesDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    // الصور تُحفظ مباشرة في مجلد الوثائق (كما هو الحال في التطبيق الحالي)
    return docsDir;
  }

  Future<List<String>> getLocalImageFilenames() async {
    final dir = await getImagesDir();
    if (!await dir.exists()) return [];
    final files = await dir.list().toList();
    return files
        .whereType<File>()
        .map((f) => p.basename(f.path))
        .where((name) =>
            name.endsWith('.jpg') ||
            name.endsWith('.jpeg') ||
            name.endsWith('.png'))
        .toList();
  }
}
