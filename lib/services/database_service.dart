import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
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
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, 'ihsa_2026.db');
    return await openDatabase(path, version: _dbVersion, onCreate: _onCreate);
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
    await db.execute('CREATE INDEX idx_done ON $_tableName(done)');
    await db.execute('CREATE INDEX idx_program ON $_tableName(program)');
    await db.execute('CREATE INDEX idx_address ON $_tableName(address)');
  }

  Future<List<Beneficiary>> getAllBeneficiaries() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(_tableName, orderBy: 'id DESC');
    return maps.map((map) => Beneficiary.fromMap(map)).toList();
  }

  Future<List<Beneficiary>> getPendingBeneficiaries() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      where: 'done = ?',
      whereArgs: [0],
      orderBy: 'id DESC',
    );
    return maps.map((map) => Beneficiary.fromMap(map)).toList();
  }

  Future<List<Beneficiary>> getCompletedBeneficiaries() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      where: 'done = ?',
      whereArgs: [1],
      orderBy: 'updated_at DESC',
    );
    return maps.map((map) => Beneficiary.fromMap(map)).toList();
  }

  Future<Beneficiary?> getBeneficiary(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
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
    map['created_at'] = DateTime.now().millisecondsSinceEpoch;
    map['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    map.remove('id');
    return await db.insert(_tableName, map);
  }

  Future<void> insertBeneficiaries(List<Beneficiary> beneficiaries) async {
    final db = await database;
    final batch = db.batch();
    for (var beneficiary in beneficiaries) {
      final map = beneficiary.toMap();
      map['created_at'] = DateTime.now().millisecondsSinceEpoch;
      map['updated_at'] = DateTime.now().millisecondsSinceEpoch;
      map.remove('id');
      batch.insert(_tableName, map);
    }
    await batch.commit(noResult: true);
  }

  Future<int> updateBeneficiary(Beneficiary beneficiary) async {
    final db = await database;
    final map = beneficiary.toMap();
    map['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    return await db.update(
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
      try { await File(beneficiary!.imagePath!).delete(); } catch (_) {}
    }
    return await db.delete(_tableName, where: 'id = ?', whereArgs: [id]);
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
      FROM $_tableName WHERE program IS NOT NULL GROUP BY program ORDER BY program
    ''');
    final occupiedStats = await db.rawQuery('''
      SELECT program, COUNT(*) as occupied_count,
        SUM(electricity) as elec_sum, SUM(gas) as gas_sum,
        SUM(water) as water_sum, SUM(sewage) as sew_sum
      FROM $_tableName WHERE done = 1 AND status = "منتهية ومشغولة"
      GROUP BY program ORDER BY program
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
    final beneficiaries = beneficiariesList.map((item) => Beneficiary.fromMap(Map<String, dynamic>.from(item))).toList();
    await insertBeneficiaries(beneficiaries);
  }

  Future<Map<String, int>> mergeFromJsonFiles(List<File> jsonFiles) async {
    int imported = 0, duplicates = 0;
    final existing = await getAllBeneficiaries();
    final existingKeys = existing.map((b) => '${b.firstName}|${b.lastName}|${b.birthDate}|${b.address}').toSet();
    for (var file in jsonFiles) {
      try {
        final data = jsonDecode(await file.readAsString());
        final list = data['beneficiaries'] as List? ?? [];
        for (var item in list) {
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
}
