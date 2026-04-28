import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/beneficiary.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  static Database? _database;
  static const String _tableName = 'beneficiaries';
  static const int _dbVersion = 1;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'ihsa_2026.db');
    return openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) async {
        await db.rawQuery('PRAGMA journal_mode=WAL');
        await db.rawQuery('PRAGMA synchronous=NORMAL');
        await db.rawQuery('PRAGMA cache_size=-32000'); // 32MB cache
        await db.rawQuery('PRAGMA temp_store=MEMORY');
      },
      onCreate: _onCreate,
      onOpen: (db) async => await _createIndexes(db),
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableName(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        first_name TEXT NOT NULL,
        last_name TEXT NOT NULL,
        full_name TEXT,
        birth_date TEXT,
        birth_place TEXT,
        address TEXT,
        program TEXT DEFAULT 'عام',
        done INTEGER DEFAULT 0,
        electricity INTEGER DEFAULT 0,
        gas INTEGER DEFAULT 0,
        water INTEGER DEFAULT 0,
        sewage INTEGER DEFAULT 0,
        status TEXT DEFAULT 'في طور الانجاز',
        image_path TEXT,
        image_file_name TEXT,
        created_at INTEGER,
        updated_at INTEGER
      )
    ''');
    await _createIndexes(db);
  }

  Future<void> _createIndexes(Database db) async {
    final indexes = [
      'CREATE INDEX IF NOT EXISTS idx_done ON $_tableName(done)',
      'CREATE INDEX IF NOT EXISTS idx_program ON $_tableName(program)',
      'CREATE INDEX IF NOT EXISTS idx_status ON $_tableName(status)',
      'CREATE INDEX IF NOT EXISTS idx_address ON $_tableName(address)',
      'CREATE INDEX IF NOT EXISTS idx_done_status ON $_tableName(done, status)',
      'CREATE INDEX IF NOT EXISTS idx_done_program ON $_tableName(done, program)',
      'CREATE INDEX IF NOT EXISTS idx_image ON $_tableName(image_file_name)',
      'CREATE INDEX IF NOT EXISTS idx_first_name ON $_tableName(first_name COLLATE NOCASE)',
      'CREATE INDEX IF NOT EXISTS idx_last_name ON $_tableName(last_name COLLATE NOCASE)',
      'CREATE INDEX IF NOT EXISTS idx_full_name ON $_tableName(full_name COLLATE NOCASE)',
      'CREATE INDEX IF NOT EXISTS idx_done_address ON $_tableName(done, address)',
      'CREATE INDEX IF NOT EXISTS idx_done_updated_at ON $_tableName(done, updated_at DESC)',
      'CREATE INDEX IF NOT EXISTS idx_lookup_identity ON $_tableName(first_name, last_name, birth_date, address)',
    ];
    for (final sql in indexes) {
      await db.execute(sql);
    }
  }

  // ─────────────────────────────────────────────
  // CRUD
  // ─────────────────────────────────────────────

  Future<List<Beneficiary>> getAllBeneficiaries() async {
    final db = await database;
    final maps = await db.query(_tableName, orderBy: 'id DESC');
    return maps.map(Beneficiary.fromMap).toList();
  }

  Future<List<Beneficiary>> getPendingBeneficiaries() async =>
      searchBeneficiaries(doneValue: 0, limit: 1000000);

  Future<List<Beneficiary>> getCompletedBeneficiaries() async =>
      searchBeneficiaries(doneValue: 1, limit: 1000000);

  Future<List<String>> getDistinctAddresses() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT DISTINCT address FROM $_tableName
      WHERE address IS NOT NULL AND TRIM(address) <> ''
      ORDER BY address COLLATE NOCASE ASC
    ''');
    return result
        .map((r) => (r['address'] ?? '').toString().trim())
        .where((v) => v.isNotEmpty)
        .toList();
  }

  Future<List<Beneficiary>> searchBeneficiaries({
    required int doneValue,
    String query = '',
    String? address,
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await database;
    final trimmedQuery = query.trim();
    final whereClauses = <String>['done = ?'];
    final whereArgs = <Object?>[doneValue];

    if (address != null && address.trim().isNotEmpty) {
      whereClauses.add('address = ?');
      whereArgs.add(address.trim());
    }

    if (trimmedQuery.isNotEmpty) {
      final likePattern = '${trimmedQuery.replaceAll('%', '')}%';
      whereClauses.add('''(
        first_name LIKE ? COLLATE NOCASE OR
        last_name  LIKE ? COLLATE NOCASE OR
        full_name  LIKE ? COLLATE NOCASE OR
        address    LIKE ? COLLATE NOCASE OR
        program    LIKE ? COLLATE NOCASE
      )''');
      whereArgs.addAll(List.filled(5, likePattern));
    }

    final maps = await db.query(
      _tableName,
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs,
      orderBy: doneValue == 1 ? 'updated_at DESC, id DESC' : 'id DESC',
      limit: limit,
      offset: offset,
    );
    return maps.map(Beneficiary.fromMap).toList();
  }

  Future<Beneficiary?> getBeneficiary(int id) async {
    final db = await database;
    final maps = await db.query(_tableName, where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Beneficiary.fromMap(maps.first);
  }

  Future<int> insertBeneficiary(Beneficiary beneficiary) async {
    final db = await database;
    final map = beneficiary.toMap();
    final now = DateTime.now().millisecondsSinceEpoch;
    map['created_at'] = now;
    map['updated_at'] = now;
    map.remove('id');
    return db.insert(_tableName, map);
  }

  Future<void> insertBeneficiaries(List<Beneficiary> beneficiaries) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final b in beneficiaries) {
      final map = b.toMap();
      map['created_at'] = now;
      map['updated_at'] = now;
      map.remove('id');
      batch.insert(_tableName, map);
    }
    await batch.commit(noResult: true);
  }

  Future<int> updateBeneficiary(Beneficiary beneficiary) async {
    final db = await database;
    final map = beneficiary.toMap();
    map['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    return db.update(_tableName, map, where: 'id = ?', whereArgs: [beneficiary.id]);
  }

  Future<int> deleteBeneficiary(int id) async {
    final db = await database;
    final b = await getBeneficiary(id);
    if (b?.imagePath != null) {
      try { await File(b!.imagePath!).delete(); } catch (_) {}
    }
    return db.delete(_tableName, where: 'id = ?', whereArgs: [id]);
  }

  Future<Beneficiary?> findBeneficiaryByKey(
      String firstName, String lastName, String? birthDate, String? address) async {
    final db = await database;
    final maps = await db.query(_tableName,
        where: 'first_name = ? AND last_name = ? AND birth_date = ? AND address = ?',
        whereArgs: [firstName, lastName, birthDate ?? '', address ?? ''],
        limit: 1);
    if (maps.isEmpty) return null;
    return Beneficiary.fromMap(maps.first);
  }

  Future<void> updateBeneficiaryFromMap(int id, Map<String, dynamic> newData) async {
    final db = await database;
    newData.remove('created_at');
    newData['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    await db.update(_tableName, newData, where: 'id = ?', whereArgs: [id]);
  }

  // ─────────────────────────────────────────────
  // STATISTICS — كلها في SQL، لا تحميل في الذاكرة
  // ─────────────────────────────────────────────

  /// إحصاء سريع للشاشة الرئيسية (لوحة التحكم)
  Future<Map<String, dynamic>> getDashboardStats() async {
    final db = await database;
    final row = (await db.rawQuery('''
      SELECT
        COUNT(*)                                          AS total,
        SUM(CASE WHEN done=1 THEN 1 ELSE 0 END)          AS done,
        SUM(CASE WHEN done=0 THEN 1 ELSE 0 END)          AS pending,
        SUM(CASE WHEN done=1 AND image_file_name IS NOT NULL
                 AND image_file_name != '' THEN 1 ELSE 0 END) AS with_image,
        SUM(CASE WHEN done=1 AND (image_file_name IS NULL
                 OR image_file_name='') THEN 1 ELSE 0 END)    AS without_image,
        SUM(CASE WHEN done=1 AND status='منتهية ومشغولة' THEN 1 ELSE 0 END) AS occupied
      FROM $_tableName
    ''')).first;

    return {
      'total':        (row['total']        as int? ?? 0),
      'done':         (row['done']         as int? ?? 0),
      'pending':      (row['pending']      as int? ?? 0),
      'with_image':   (row['with_image']   as int? ?? 0),
      'without_image':(row['without_image'] as int? ?? 0),
      'occupied':     (row['occupied']     as int? ?? 0),
    };
  }

  /// إحصائيات متقدمة كاملة بلا تحميل سجلات
  Future<Map<String, dynamic>> getAdvancedStats() async {
    final db = await database;

    // ① إجمالي عام
    final totals = (await db.rawQuery('''
      SELECT
        COUNT(*)                                                    AS total,
        SUM(CASE WHEN done=1 THEN 1 ELSE 0 END)                    AS done,
        SUM(CASE WHEN done=1 AND image_file_name IS NOT NULL
                 AND image_file_name != '' THEN 1 ELSE 0 END)      AS with_image,
        SUM(CASE WHEN done=1 AND (image_file_name IS NULL
                 OR image_file_name='') THEN 1 ELSE 0 END)         AS without_image,
        SUM(CASE WHEN done=1 AND electricity=1 THEN 1 ELSE 0 END)  AS elec,
        SUM(CASE WHEN done=1 AND gas=1 THEN 1 ELSE 0 END)          AS gas,
        SUM(CASE WHEN done=1 AND water=1 THEN 1 ELSE 0 END)        AS water,
        SUM(CASE WHEN done=1 AND sewage=1 THEN 1 ELSE 0 END)       AS sewage
      FROM $_tableName
    ''')).first;

    // ② حسب البرنامج
    final byProgram = await db.rawQuery('''
      SELECT
        program,
        COUNT(*)                                                               AS total,
        SUM(CASE WHEN done=1 THEN 1 ELSE 0 END)                               AS done,
        SUM(CASE WHEN done=1 AND status='في طور الانجاز'    THEN 1 ELSE 0 END) AS s1,
        SUM(CASE WHEN done=1 AND status='على مستوى الاعمدة' THEN 1 ELSE 0 END) AS s2,
        SUM(CASE WHEN done=1 AND status='منتهية غير مشغولة' THEN 1 ELSE 0 END) AS s3,
        SUM(CASE WHEN done=1 AND status='منتهية ومشغولة'    THEN 1 ELSE 0 END) AS s4,
        SUM(CASE WHEN done=1 AND electricity=1 THEN 1 ELSE 0 END)              AS elec,
        SUM(CASE WHEN done=1 AND gas=1         THEN 1 ELSE 0 END)              AS gas,
        SUM(CASE WHEN done=1 AND water=1       THEN 1 ELSE 0 END)              AS water,
        SUM(CASE WHEN done=1 AND sewage=1      THEN 1 ELSE 0 END)              AS sewage,
        SUM(CASE WHEN done=1 AND image_file_name IS NOT NULL
                 AND image_file_name != '' THEN 1 ELSE 0 END)                  AS with_image,
        MIN(created_at)                                                        AS first_added
      FROM $_tableName
      WHERE program IS NOT NULL
      GROUP BY program
      ORDER BY first_added ASC
    ''');

    // ③ حسب الحالة الفيزيائية (للمحصاة فقط)
    final byStatus = await db.rawQuery('''
      SELECT
        status,
        COUNT(*)                                                              AS total,
        SUM(CASE WHEN electricity=1 THEN 1 ELSE 0 END)                       AS elec,
        SUM(CASE WHEN gas=1         THEN 1 ELSE 0 END)                       AS gas,
        SUM(CASE WHEN water=1       THEN 1 ELSE 0 END)                       AS water,
        SUM(CASE WHEN sewage=1      THEN 1 ELSE 0 END)                       AS sewage,
        SUM(CASE WHEN electricity=1 AND gas=0 AND water=0 AND sewage=0
                 THEN 1 ELSE 0 END)                                           AS elec_only,
        SUM(CASE WHEN electricity=0 AND gas=1 AND water=0 AND sewage=0
                 THEN 1 ELSE 0 END)                                           AS gas_only,
        SUM(CASE WHEN electricity=0 AND gas=0 AND water=1 AND sewage=0
                 THEN 1 ELSE 0 END)                                           AS water_only,
        SUM(CASE WHEN electricity=0 AND gas=0 AND water=0 AND sewage=1
                 THEN 1 ELSE 0 END)                                           AS sewage_only,
        SUM(CASE WHEN electricity=1 AND gas=1 AND water=0 AND sewage=0
                 THEN 1 ELSE 0 END)                                           AS elec_gas,
        SUM(CASE WHEN electricity=1 AND gas=1 AND water=1 AND sewage=1
                 THEN 1 ELSE 0 END)                                           AS all_four,
        SUM(CASE WHEN electricity=0 AND gas=0 AND water=0 AND sewage=0
                 THEN 1 ELSE 0 END)                                           AS none,
        SUM(CASE WHEN image_file_name IS NOT NULL AND image_file_name != ''
                 THEN 1 ELSE 0 END)                                           AS with_image
      FROM $_tableName
      WHERE done=1
      GROUP BY status
      ORDER BY CASE status
        WHEN 'منتهية ومشغولة'    THEN 1
        WHEN 'منتهية غير مشغولة' THEN 2
        WHEN 'على مستوى الاعمدة' THEN 3
        ELSE 4 END
    ''');

    // ④ إحصاء الصور حسب الحالة
    final imageByStatus = await db.rawQuery('''
      SELECT
        status,
        SUM(CASE WHEN image_file_name IS NOT NULL AND image_file_name != ''
                 THEN 1 ELSE 0 END) AS with_image,
        SUM(CASE WHEN image_file_name IS NULL OR image_file_name=''
                 THEN 1 ELSE 0 END) AS without_image
      FROM $_tableName
      WHERE done=1
      GROUP BY status
    ''');

    return {
      'totals': totals,
      'byProgram': byProgram,
      'byStatus': byStatus,
      'imageByStatus': imageByStatus,
    };
  }

  // ─────────────────────────────────────────────
  // Export / Import
  // ─────────────────────────────────────────────

  Future<String> exportToJson() async {
    final beneficiaries = await getAllBeneficiaries();
    return jsonEncode({
      'version': '1.0',
      'exportDate': DateTime.now().toIso8601String(),
      'beneficiaries': beneficiaries.map((b) => b.toMap()).toList(),
    });
  }

  Future<void> importFromJson(String jsonString) async {
    final data = jsonDecode(jsonString);
    final list = (data['beneficiaries'] as List)
        .map((item) => Beneficiary.fromMap(Map<String, dynamic>.from(item)))
        .toList();
    await insertBeneficiaries(list);
  }

  Future<Map<String, int>> mergeFromJsonFiles(List<File> jsonFiles) async {
    int imported = 0, duplicates = 0;
    final existing = await getAllBeneficiaries();
    final existingKeys = existing
        .map((b) => '${b.firstName}|${b.lastName}|${b.birthDate}|${b.address}')
        .toSet();

    for (final file in jsonFiles) {
      try {
        final data = jsonDecode(await file.readAsString());
        final list = data['beneficiaries'] as List? ?? [];
        for (final item in list) {
          final b = Beneficiary.fromMap(Map<String, dynamic>.from(item));
          final key = '${b.firstName}|${b.lastName}|${b.birthDate}|${b.address}';
          if (!existingKeys.contains(key)) {
            await insertBeneficiary(b);
            existingKeys.add(key);
            imported++;
          } else {
            duplicates++;
          }
        }
      } catch (_) {}
    }
    return {'imported': imported, 'duplicates': duplicates};
  }

  Future<Map<String, dynamic>> getStatistics() async {
    final db = await database;
    final totalResult = await db.rawQuery('SELECT COUNT(*) as total FROM $_tableName');
    final completedResult = await db.rawQuery('SELECT COUNT(*) as total FROM $_tableName WHERE done = 1');
    final total = totalResult.first['total'] as int;
    final completed = completedResult.first['total'] as int;
    final programStats = await db.rawQuery('''
      SELECT program, COUNT(*) as total,
        SUM(CASE WHEN done=1 THEN 1 ELSE 0 END) as done_count,
        SUM(CASE WHEN done=1 AND status="في طور الانجاز"    THEN 1 ELSE 0 END) as status_1,
        SUM(CASE WHEN done=1 AND status="على مستوى الاعمدة" THEN 1 ELSE 0 END) as status_2,
        SUM(CASE WHEN done=1 AND status="منتهية غير مشغولة" THEN 1 ELSE 0 END) as status_3,
        SUM(CASE WHEN done=1 AND status="منتهية ومشغولة"    THEN 1 ELSE 0 END) as status_4,
        SUM(CASE WHEN done=1 THEN electricity ELSE 0 END) as elec_sum,
        SUM(CASE WHEN done=1 THEN gas         ELSE 0 END) as gas_sum,
        SUM(CASE WHEN done=1 THEN water       ELSE 0 END) as water_sum,
        SUM(CASE WHEN done=1 THEN sewage      ELSE 0 END) as sew_sum
      FROM $_tableName WHERE program IS NOT NULL
      GROUP BY program ORDER BY program
    ''');
    final occupiedStats = await db.rawQuery('''
      SELECT program, COUNT(*) as occupied_count,
        SUM(electricity) as elec_sum, SUM(gas) as gas_sum,
        SUM(water) as water_sum, SUM(sewage) as sew_sum
      FROM $_tableName WHERE done=1 AND status="منتهية ومشغولة"
      GROUP BY program ORDER BY program
    ''');
    return {
      'total': total, 'completed': completed,
      'progress': total > 0 ? (completed / total * 100).round() : 0,
      'programStats': programStats, 'occupiedStats': occupiedStats,
    };
  }

  // ─────────────────────────────────────────────
  // إحصائيات المحضر — بيانات تفصيلية لبرنامج واحد
  // ─────────────────────────────────────────────
  Future<Map<String, dynamic>> getReportStats(String program) async {
    final db = await database;
    final general = (await db.rawQuery('''
      SELECT
        COUNT(*)                                                                AS quota,
        SUM(CASE WHEN done=1 THEN 1 ELSE 0 END)                                AS done,
        SUM(CASE WHEN done=1 AND status='في طور الانجاز'    THEN 1 ELSE 0 END) AS in_progress,
        SUM(CASE WHEN done=1 AND status='على مستوى الاعمدة' THEN 1 ELSE 0 END) AS pillars,
        SUM(CASE WHEN done=1 AND status='منتهية غير مشغولة' THEN 1 ELSE 0 END) AS finished_not_occupied,
        SUM(CASE WHEN done=1 AND status='منتهية ومشغولة'    THEN 1 ELSE 0 END) AS finished_occupied
      FROM $_tableName WHERE program = ?
    ''', [program])).first;
    final networks = (await db.rawQuery('''
      SELECT
        SUM(CASE WHEN electricity=1 THEN 1 ELSE 0 END) AS elec_occ,
        SUM(CASE WHEN gas=1         THEN 1 ELSE 0 END) AS gas_occ,
        SUM(CASE WHEN water=1       THEN 1 ELSE 0 END) AS water_occ,
        SUM(CASE WHEN sewage=1      THEN 1 ELSE 0 END) AS sew_occ,
        SUM(CASE WHEN electricity=1 AND gas=1 AND water=1 AND sewage=1
                 THEN 1 ELSE 0 END)                    AS fully_connected
      FROM $_tableName
      WHERE program = ? AND done=1 AND status='منتهية ومشغولة'
    ''', [program])).first;
    return {...general, ...networks};
  }

  Future<List<Map<String, String>>> getProgramImages(String program) async {
    final db = await database;
    final rows = await db.query(_tableName,
        columns: ['image_file_name', 'image_path', 'first_name', 'last_name'],
        where: "program = ? AND done=1 AND image_file_name IS NOT NULL AND image_file_name != ''",
        whereArgs: [program]);
    return rows.map((r) => {
      'name':       (r['image_file_name'] ?? '').toString(),
      'path':       (r['image_path']      ?? '').toString(),
      'first_name': (r['first_name']      ?? '').toString(),
      'last_name':  (r['last_name']       ?? '').toString(),
    }).toList();
  }

  Future<List<String>> getPrograms() async {
    final db = await database;
    final rows = await db.rawQuery(
        "SELECT program, MIN(created_at) AS first_added FROM $_tableName WHERE program IS NOT NULL AND program != '' GROUP BY program ORDER BY first_added ASC");
    return rows.map((r) => r['program'].toString()).toList();
  }
}
