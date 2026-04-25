import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import '../models/beneficiary.dart';

class AdvancedStatsScreen extends StatefulWidget {
  final List<Beneficiary> allBeneficiaries;
  const AdvancedStatsScreen({super.key, required this.allBeneficiaries});

  @override
  State<AdvancedStatsScreen> createState() => _AdvancedStatsScreenState();
}

class _AdvancedStatsScreenState extends State<AdvancedStatsScreen> {
  late List<Beneficiary> _completed; // المكتملين فقط
  late List<Beneficiary> _all;       // الكل (للحصة)

  // للإحصائيات حسب البرنامج
  late Map<String, Map<String, dynamic>> _programStats;

  // للإحصائيات السابقة (حسب الحالة الكلية)
  final Map<String, Map<String, int>> _advancedStats = {};
  final Map<String, int> _totalCountByStatus = {};

  @override
  void initState() {
    super.initState();
    _all = widget.allBeneficiaries;
    _completed = _all.where((b) => b.done == 1).toList();
    _calculateProgramStats();
    _calculateLegacyStats(); // الإحصائيات القديمة حسب الحالة
  }

  void _calculateProgramStats() {
    _programStats = {};

    // 1. تجميع جميع البرامج الفريدة
    final Set<String> programs = _all.map((b) => b.program ?? 'عام').toSet();

    for (var prog in programs) {
      final beneficiariesOfProg = _all.where((b) => (b.program ?? 'عام') == prog).toList();
      final completedOfProg = beneficiariesOfProg.where((b) => b.done == 1).toList();

      final totalQuota = beneficiariesOfProg.length;
      final totalDone = completedOfProg.length;

      // توزيع الحالات
      final statusCount = {
        'في طور الانجاز': 0,
        'على مستوى الاعمدة': 0,
        'منتهية غير مشغولة': 0,
        'منتهية ومشغولة': 0,
      };
      for (var b in completedOfProg) {
        statusCount[b.status] = (statusCount[b.status] ?? 0) + 1;
      }

      // تحليل الشبكات للحالة "منتهية ومشغولة"
      final occupied = completedOfProg.where((b) => b.status == 'منتهية ومشغولة').toList();
      int occElec = 0, occGas = 0, occWater = 0, occSewage = 0;
      for (var b in occupied) {
        if (b.electricity == 1) occElec++;
        if (b.gas == 1) occGas++;
        if (b.water == 1) occWater++;
        if (b.sewage == 1) occSewage++;
      }

      _programStats[prog] = {
        'totalQuota': totalQuota,
        'totalDone': totalDone,
        'statusCount': statusCount,
        'occupied': {
          'count': occupied.length,
          'electricity': occElec,
          'gas': occGas,
          'water': occWater,
          'sewage': occSewage,
        },
      };
    }
  }

  void _calculateLegacyStats() {
    // الكود القديم للإحصائيات حسب الحالة (بدون برنامج)...
    final statusList = ["في طور الانجاز", "على مستوى الاعمدة", "منتهية غير مشغولة", "منتهية ومشغولة"];
    for (var status in statusList) {
      _advancedStats[status] = {
        "electricity": 0,
        "gas": 0,
        "water": 0,
        "sewage": 0,
        "electricity_only": 0,
        "gas_only": 0,
        "water_only": 0,
        "sewage_only": 0,
        "electricity_gas": 0,
        "all_four": 0,
        "none": 0,
      };
      _totalCountByStatus[status] = 0;
    }

    for (var b in _completed) {
      final status = b.status;
      if (!_advancedStats.containsKey(status)) continue;
      _totalCountByStatus[status] = (_totalCountByStatus[status] ?? 0) + 1;
      final stats = _advancedStats[status]!;
      final hasE = b.electricity == 1;
      final hasG = b.gas == 1;
      final hasW = b.water == 1;
      final hasS = b.sewage == 1;

      if (hasE) stats["electricity"] = (stats["electricity"] ?? 0) + 1;
      if (hasG) stats["gas"] = (stats["gas"] ?? 0) + 1;
      if (hasW) stats["water"] = (stats["water"] ?? 0) + 1;
      if (hasS) stats["sewage"] = (stats["sewage"] ?? 0) + 1;

      int count = (hasE ? 1 : 0) + (hasG ? 1 : 0) + (hasW ? 1 : 0) + (hasS ? 1 : 0);
      if (count == 0) stats["none"] = (stats["none"] ?? 0) + 1;
      else if (count == 4) stats["all_four"] = (stats["all_four"] ?? 0) + 1;
      else {
        if (hasE && !hasG && !hasW && !hasS) stats["electricity_only"] = (stats["electricity_only"] ?? 0) + 1;
        if (!hasE && hasG && !hasW && !hasS) stats["gas_only"] = (stats["gas_only"] ?? 0) + 1;
        if (!hasE && !hasG && hasW && !hasS) stats["water_only"] = (stats["water_only"] ?? 0) + 1;
        if (!hasE && !hasG && !hasW && hasS) stats["sewage_only"] = (stats["sewage_only"] ?? 0) + 1;
        if (hasE && hasG && !hasW && !hasS) stats["electricity_gas"] = (stats["electricity_gas"] ?? 0) + 1;
      }
    }
  }

  Future<void> _exportToCSV() async {
    try {
      final csvContent = StringBuffer();

      // قسم البرامج
      csvContent.writeln('=== تقرير تفصيلي حسب البرنامج ===');
      csvContent.writeln('البرنامج,الحصة الكلية,المنجز,في طور الانجاز,على مستوى الاعمدة,منتهية غير مشغولة,منتهية ومشغولة');
      for (var entry in _programStats.entries) {
        final prog = entry.key;
        final data = entry.value;
        final status = data['statusCount'] as Map<String, int>;
        csvContent.writeln('$prog,${data['totalQuota']},${data['totalDone']},${status['في طور الانجاز']},${status['على مستوى الاعمدة']},${status['منتهية غير مشغولة']},${status['منتهية ومشغولة']}');
      }

      csvContent.writeln('\n=== تفاصيل الشبكات للحالة "منتهية ومشغولة" حسب البرنامج ===');
      csvContent.writeln('البرنامج,عدد المنتهية المشغولة,كهرباء,غاز,مياه,تطهير');
      for (var entry in _programStats.entries) {
        final prog = entry.key;
        final occ = entry.value['occupied'] as Map<String, int>;
        csvContent.writeln('$prog,${occ['count']},${occ['electricity']},${occ['gas']},${occ['water']},${occ['sewage']}');
      }

      // الإجماليات العامة
      int totalQuotaAll = 0, totalDoneAll = 0;
      int totalOccAll = 0, totalOccElec = 0, totalOccGas = 0, totalOccWater = 0, totalOccSew = 0;
      for (var data in _programStats.values) {
        totalQuotaAll += data['totalQuota'] as int;
        totalDoneAll += data['totalDone'] as int;
        final occ = data['occupied'] as Map<String, int>;
        totalOccAll += occ['count']!;
        totalOccElec += occ['electricity']!;
        totalOccGas += occ['gas']!;
        totalOccWater += occ['water']!;
        totalOccSew += occ['sewage']!;
      }
      csvContent.writeln('\n=== إجمالي عام ===');
      csvContent.writeln('إجمالي المستفيدين,$totalQuotaAll');
      csvContent.writeln('إجمالي المكتملين,$totalDoneAll');
      csvContent.writeln('إجمالي المنتهية المشغولة,$totalOccAll');
      csvContent.writeln('منهم كهرباء,$totalOccElec');
      csvContent.writeln('منهم غاز,$totalOccGas');
      csvContent.writeln('منهم مياه,$totalOccWater');
      csvContent.writeln('منهم تطهير,$totalOccSew');

      // أضف الإحصائيات القديمة أيضاً
      csvContent.writeln('\n=== إحصائيات عامة حسب الحالة (بدون تفصيل برنامج) ===');
      csvContent.writeln('الحالة,الحصة,كهرباء,غاز,مياه,تطهير,كهرباء فقط,غاز فقط,مياه فقط,تطهير فقط,كهرباء+غاز,جميع الخدمات,بدون خدمات');
      for (var entry in _advancedStats.entries) {
        final status = entry.key;
        final stats = entry.value;
        final total = _totalCountByStatus[status] ?? 0;
        csvContent.writeln('$status,$total,${stats["electricity"]},${stats["gas"]},${stats["water"]},${stats["sewage"]},${stats["electricity_only"]},${stats["gas_only"]},${stats["water_only"]},${stats["sewage_only"]},${stats["electricity_gas"]},${stats["all_four"]},${stats["none"]}');
      }

      final downloadDir = Directory('/storage/emulated/0/Download');
      if (!await downloadDir.exists()) await downloadDir.create(recursive: true);
      final fileName = 'تقرير_تفصيلي_متقدم_${DateTime.now().millisecondsSinceEpoch}.csv';
      final file = File('${downloadDir.path}/$fileName');
      await file.writeAsString(csvContent.toString());

      await OpenFile.open(file.path);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ تم التصدير إلى Download/$fileName'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ فشل التصدير: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final statuses = ["في طور الانجاز", "على مستوى الاعمدة", "منتهية غير مشغولة", "منتهية ومشغولة"];

    // إجماليات عامة للعرض
    int totalQuotaAll = 0, totalDoneAll = 0;
    int totalOccAll = 0, totalOccElec = 0, totalOccGas = 0, totalOccWater = 0, totalOccSew = 0;
    for (var data in _programStats.values) {
      totalQuotaAll += data['totalQuota'] as int;
      totalDoneAll += data['totalDone'] as int;
      final occ = data['occupied'] as Map<String, int>;
      totalOccAll += occ['count']!;
      totalOccElec += occ['electricity']!;
      totalOccGas += occ['gas']!;
      totalOccWater += occ['water']!;
      totalOccSew += occ['sewage']!;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('📊 تقرير تفصيلي متقدم', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _exportToCSV,
            tooltip: 'تصدير إلى CSV',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ========== إجماليات عامة ==========
            Card(
              color: const Color(0xFFE0F2FE),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('📊 إجمالي عام', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    Text('إجمالي المستفيدين (كل البرامج): $totalQuotaAll'),
                    Text('إجمالي المكتملين: $totalDoneAll'),
                    Text('إجمالي المنتهية والمشغولة: $totalOccAll'),
                    Text('منها كهرباء: $totalOccElec | غاز: $totalOccGas | مياه: $totalOccWater | تطهير: $totalOccSew'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ========== جدول ملخص حسب البرنامج ==========
            const Text('📋 ملخص حسب البرنامج (الحصة والحالات)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)]),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 20,
                    headingRowColor: MaterialStateProperty.all(const Color(0xFFF1F5F9)),
                    headingTextStyle: const TextStyle(fontWeight: FontWeight.bold),
                    columns: const [
                      DataColumn(label: Text('البرنامج')),
                      DataColumn(label: Text('الحصة الكلية')),
                      DataColumn(label: Text('المنجز')),
                      DataColumn(label: Text('في طور')),
                      DataColumn(label: Text('أعمدة')),
                      DataColumn(label: Text('غير مشغولة')),
                      DataColumn(label: Text('مشغولة')),
                    ],
                    rows: _programStats.entries.map((entry) {
                      final prog = entry.key;
                      final data = entry.value;
                      final status = data['statusCount'] as Map<String, int>;
                      return DataRow(cells: [
                        DataCell(Text(prog)),
                        DataCell(Text(data['totalQuota'].toString())),
                        DataCell(Text(data['totalDone'].toString())),
                        DataCell(Text(status['في طور الانجاز'].toString())),
                        DataCell(Text(status['على مستوى الاعمدة'].toString())),
                        DataCell(Text(status['منتهية غير مشغولة'].toString())),
                        DataCell(Text(status['منتهية ومشغولة'].toString())),
                      ]);
                    }).toList(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),

            // ========== جدول تفاصيل الشبكات للمشغولة ==========
            const Text('🔌 تفاصيل الشبكات للحالة "منتهية ومشغولة" حسب البرنامج', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)]),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 20,
                    headingRowColor: MaterialStateProperty.all(const Color(0xFFF1F5F9)),
                    headingTextStyle: const TextStyle(fontWeight: FontWeight.bold),
                    columns: const [
                      DataColumn(label: Text('البرنامج')),
                      DataColumn(label: Text('عدد المشغولة')),
                      DataColumn(label: Text('كهرباء')),
                      DataColumn(label: Text('غاز')),
                      DataColumn(label: Text('مياه')),
                      DataColumn(label: Text('تطهير')),
                    ],
                    rows: _programStats.entries.map((entry) {
                      final prog = entry.key;
                      final occ = entry.value['occupied'] as Map<String, int>;
                      return DataRow(cells: [
                        DataCell(Text(prog)),
                        DataCell(Text(occ['count'].toString())),
                        DataCell(Text(occ['electricity'].toString())),
                        DataCell(Text(occ['gas'].toString())),
                        DataCell(Text(occ['water'].toString())),
                        DataCell(Text(occ['sewage'].toString())),
                      ]);
                    }).toList(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),

            // ========== الإحصائيات القديمة (حسب الحالة الكلية) ==========
            const Text('📈 إحصائيات متقدمة (حسب الحالة الكلية)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)]),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('عدد المستفيدين المكتملين الذين يملكون الخدمة (بغض النظر عن باقي الخدمات)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 20,
                        headingRowColor: MaterialStateProperty.all(const Color(0xFFF1F5F9)),
                        headingTextStyle: const TextStyle(fontWeight: FontWeight.bold),
                        columns: const [
                          DataColumn(label: Text('الحالة')),
                          DataColumn(label: Text('الحصة')),
                          DataColumn(label: Text('كهرباء')),
                          DataColumn(label: Text('غاز')),
                          DataColumn(label: Text('مياه')),
                          DataColumn(label: Text('تطهير')),
                        ],
                        rows: statuses.map((status) {
                          final stats = _advancedStats[status] ?? {};
                          final total = _totalCountByStatus[status] ?? 0;
                          return DataRow(cells: [
                            DataCell(Text(status)),
                            DataCell(Text(total.toString())),
                            DataCell(Text(stats["electricity"]?.toString() ?? "0")),
                            DataCell(Text(stats["gas"]?.toString() ?? "0")),
                            DataCell(Text(stats["water"]?.toString() ?? "0")),
                            DataCell(Text(stats["sewage"]?.toString() ?? "0")),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)]),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('تحليل التركيبات (حسب الحالة الكلية)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 12,
                        headingRowColor: MaterialStateProperty.all(const Color(0xFFF1F5F9)),
                        headingTextStyle: const TextStyle(fontWeight: FontWeight.bold),
                        columns: const [
                          DataColumn(label: Text('الحالة')),
                          DataColumn(label: Text('الحصة')),
                          DataColumn(label: Text('كهرباء فقط')),
                          DataColumn(label: Text('غاز فقط')),
                          DataColumn(label: Text('مياه فقط')),
                          DataColumn(label: Text('تطهير فقط')),
                          DataColumn(label: Text('كهرباء+غاز')),
                          DataColumn(label: Text('جميع الخدمات')),
                          DataColumn(label: Text('بدون خدمات')),
                        ],
                        rows: statuses.map((status) {
                          final stats = _advancedStats[status] ?? {};
                          final total = _totalCountByStatus[status] ?? 0;
                          return DataRow(cells: [
                            DataCell(Text(status)),
                            DataCell(Text(total.toString())),
                            DataCell(Text(stats["electricity_only"]?.toString() ?? "0")),
                            DataCell(Text(stats["gas_only"]?.toString() ?? "0")),
                            DataCell(Text(stats["water_only"]?.toString() ?? "0")),
                            DataCell(Text(stats["sewage_only"]?.toString() ?? "0")),
                            DataCell(Text(stats["electricity_gas"]?.toString() ?? "0")),
                            DataCell(Text(stats["all_four"]?.toString() ?? "0")),
                            DataCell(Text(stats["none"]?.toString() ?? "0")),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: ElevatedButton.icon(
                onPressed: _exportToCSV,
                icon: const Icon(Icons.save_alt),
                label: const Text('تصدير التقرير الكامل إلى CSV'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00897B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}