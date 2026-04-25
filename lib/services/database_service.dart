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
      // ✅ استخدم rawQuery بدلاً من execute لأوامر PRAGMA
      await db.rawQuery('PRAGMA journal_mode=WAL');
      await db.rawQuery('PRAGMA synchronous=NORMAL');
    },
     onCreate: _onCreate,
     onOpen: (db) async {
      await _createIndexes(db);
     },
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
    await db.execute('CREATE INDEX IF NOT EXISTS idx_done ON $_tableName(done)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_program ON $_tableName(program)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_address ON $_tableName(address)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_first_name ON $_tableName(first_name COLLATE NOCASE)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_last_name ON $_tableName(last_name COLLATE NOCASE)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_full_name ON $_tableName(full_name COLLATE NOCASE)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_done_address ON $_tableName(done, address)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_done_updated_at ON $_tableName(done, updated_at DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_lookup_identity ON $_tableName(first_name, last_name, birth_date, address)');
  }

  Future<List<Beneficiary>> getAllBeneficiaries() async {
    final db = await database;
    final maps = await db.query(_tableName, orderBy: 'id DESC');
    return maps.map(Beneficiary.fromMap).toList();
  }

  Future<List<Beneficiary>> getPendingBeneficiaries() async {
    return searchBeneficiaries(doneValue: 0, limit: 1000000);
  }

  Future<List<Beneficiary>> getCompletedBeneficiaries() async {
    return searchBeneficiaries(doneValue: 1, limit: 1000000);
  }

  Future<List<String>> getDistinctAddresses() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT DISTINCT address
      FROM $_tableName
      WHERE address IS NOT NULL AND TRIM(address) <> ''
      ORDER BY address COLLATE NOCASE ASC
    ''');

    return result
        .map((row) => (row['address'] ?? '').toString().trim())
        .where((value) => value.isNotEmpty)
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
      whereClauses.add('''
        (
          first_name LIKE ? COLLATE NOCASE OR
          last_name LIKE ? COLLATE NOCASE OR
          full_name LIKE ? COLLATE NOCASE OR
          address LIKE ? COLLATE NOCASE OR
          program LIKE ? COLLATE NOCASE
        )
      ''');
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
    final maps = await db.query(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
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

    for (final beneficiary in beneficiaries) {
      final map = beneficiary.toMap();
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
    return db.update(
      _tableName,
      map,
      where: 'id = ?',
      whereArgs: [beneficiary.id],
    );
  }

  Future<int> deleteBeneficiary(int id) async {
    final db = await database;
    final beneficiary = await getBeneficiary(id);
    if (beneficiary?.imagePath != null) {
      try {
        await File(beneficiary!.imagePath!).delete();
      } catch (_) {}
    }
    return db.delete(_tableName, where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, dynamic>> getStatistics() async {
    final db = await database;
    final totalResult = await db.rawQuery('SELECT COUNT(*) as total FROM $_tableName');
    final completedResult = await db.rawQuery('SELECT COUNT(*) as total FROM $_tableName WHERE done = 1');
    final total = totalResult.first['total'] as int;
    final completed = completedResult.first['total'] as int;

    final programStats = await db.rawQuery('''
      SELECT program, COUNT(*) as total,
        SUM(CASE WHEN done = 1 THEN 1 ELSE 0 END) as done_count,
        SUM(CASE WHEN done = 1 AND status = "في طور الانجاز" THEN 1 ELSE 0 END) as status_1,
        SUM(CASE WHEN done = 1 AND status = "على مستوى الاعمدة" THEN 1 ELSE 0 END) as status_2,
        SUM(CASE WHEN done = 1 AND status = "منتهية غير مشغولة" THEN 1 ELSE 0 END) as status_3,
        SUM(CASE WHEN done = 1 AND status = "منتهية ومشغولة" THEN 1 ELSE 0 END) as status_4,
        SUM(CASE WHEN done = 1 THEN electricity ELSE 0 END) as elec_sum,
        SUM(CASE WHEN done = 1 THEN gas ELSE 0 END) as gas_sum,
        SUM(CASE WHEN done = 1 THEN water ELSE 0 END) as water_sum,
        SUM(CASE WHEN done = 1 THEN sewage ELSE 0 END) as sew_sum
      FROM $_tableName
      WHERE program IS NOT NULL
      GROUP BY program
      ORDER BY program
    ''');

    final occupiedStats = await db.rawQuery('''
      SELECT program, COUNT(*) as occupied_count,
        SUM(electricity) as elec_sum,
        SUM(gas) as gas_sum,
        SUM(water) as water_sum,
        SUM(sewage) as sew_sum
      FROM $_tableName
      WHERE done = 1 AND status = "منتهية ومشغولة"
      GROUP BY program
      ORDER BY program
    ''');

    return {
      'total': total,
      'completed': completed,
      'progress': total > 0 ? (completed / total * 100).round() : 0,
      'programStats': programStats,
      'occupiedStats': occupiedStats,
    };
  }

  Future<String> exportToJson() async {
    final beneficiaries = await getAllBeneficiaries();
    final exportData = {
      'version': '1.0',
      'exportDate': DateTime.now().toIso8601String(),
      'beneficiaries': beneficiaries.map((b) => b.toMap()).toList(),
    };
    return jsonEncode(exportData);
  }

  Future<void> importFromJson(String jsonString) async {
    final data = jsonDecode(jsonString);
    final beneficiariesList = data['beneficiaries'] as List;
    final beneficiaries = beneficiariesList
        .map((item) => Beneficiary.fromMap(Map<String, dynamic>.from(item)))
        .toList();
    await insertBeneficiaries(beneficiaries);
  }

  Future<Map<String, int>> mergeFromJsonFiles(List<File> jsonFiles) async {
    int imported = 0;
    int duplicates = 0;
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

  Future<Beneficiary?> findBeneficiaryByKey(
    String firstName,
    String lastName,
    String? birthDate,
    String? address,
  ) async {
    final db = await database;
    final maps = await db.query(
      _tableName,
      where: 'first_name = ? AND last_name = ? AND birth_date = ? AND address = ?',
      whereArgs: [firstName, lastName, birthDate ?? '', address ?? ''],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Beneficiary.fromMap(maps.first);
  }

  Future<void> updateBeneficiaryFromMap(int id, Map<String, dynamic> newData) async {
    final db = await database;
    newData.remove('created_at');
    newData['updated_at'] = DateTime.now().millisecondsSinceEpoch;

    await db.update(
      _tableName,
      newData,
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
