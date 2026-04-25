
import 'dart:io'; // <-- أضف هذا
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart'; // <-- أضف هذا
import 'package:open_file/open_file.dart';
// تأكد من صحة المسارات التالية في مشروعك
import '../models/beneficiary.dart';
import '../services/excel_service.dart';
import '../services/database_service.dart';

class StatsScreen extends StatefulWidget {
  final List<Beneficiary>? allBeneficiaries;
  const StatsScreen({super.key, this.allBeneficiaries});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final ExcelService _excelService = ExcelService();
  final DatabaseService _dbService = DatabaseService();

  List<Beneficiary> _data = [];
  bool _isLoading = true;

  final List<List<dynamic>> _mainRows = [];
  final List<String> _mainHeaders = [
    'البرنامج', 'الحصة', 'محصاة', 'نسبة الإنجاز %',
    'في طور الانجاز', 'على مستوى الاعمدة', 'منتهية غير مشغولة', 'منتهية ومشغولة',
    'كهرباء (كل الحالات)', 'غاز (كل الحالات)', 'مياه (كل الحالات)', 'تطهير (كل الحالات)'
  ];

  final List<List<dynamic>> _detailRows = [];
  final List<String> _detailHeaders = [
    'البرنامج', 'عدد المنتهية المشغولة', 'كهرباء', 'غاز', 'مياه', 'تطهير'
  ];

  int _grandQuota = 0;
  int _grandDone = 0;
  final Map<String, int> _grandStatus = {
    "في طور الانجاز": 0,
    "على مستوى الاعمدة": 0,
    "منتهية غير مشغولة": 0,
    "منتهية ومشغولة": 0,
  };
  int _grandE = 0, _grandG = 0, _grandW = 0, _grandS = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    if (widget.allBeneficiaries != null && widget.allBeneficiaries!.isNotEmpty) {
      _data = widget.allBeneficiaries!;
    } else {
      _data = await _dbService.getAllBeneficiaries();
    }
    _calculateStats();
    setState(() => _isLoading = false);
  }

  String _normalizeProgram(String? program) {
    return (program ?? 'عام').trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _safeText(dynamic value) {
    return (value ?? '').toString().trim();
  }

  void _calculateStats() {
    final programs = _data
        .map((b) => _normalizeProgram(b.program))
        .where((p) => p.isNotEmpty)
        .toSet()
        .toList();

    _mainRows.clear();
    _detailRows.clear();

    _grandQuota = _data.length;
    _grandDone = _data.where((b) => b.done == 1).length;

    _grandStatus.updateAll((key, value) => 0);
    _grandE = _grandG = _grandW = _grandS = 0;

    // إضافة صف لكل برنامج حتى لو لم تكن فيه حالات محصاة
    for (var program in programs) {
      final programData = _data.where((b) => _normalizeProgram(b.program) == program).toList();
      final programDone = programData.where((b) => b.done == 1).toList();

      final quota = programData.length;
      final done = programDone.length;
      final progress = quota > 0 ? (done / quota * 100).round() : 0;

      final statusCounts = {
        "في طور الانجاز": programDone.where((b) => _safeText(b.status) == "في طور الانجاز").length,
        "على مستوى الاعمدة": programDone.where((b) => _safeText(b.status) == "على مستوى الاعمدة").length,
        "منتهية غير مشغولة": programDone.where((b) => _safeText(b.status) == "منتهية غير مشغولة").length,
        "منتهية ومشغولة": programDone.where((b) => _safeText(b.status) == "منتهية ومشغولة").length,
      };

      final eSum = programDone.fold(0, (sum, b) => sum + b.electricity);
      final gSum = programDone.fold(0, (sum, b) => sum + b.gas);
      final wSum = programDone.fold(0, (sum, b) => sum + b.water);
      final sSum = programDone.fold(0, (sum, b) => sum + b.sewage);

      statusCounts.forEach((k, v) => _grandStatus[k] = (_grandStatus[k] ?? 0) + v);
      _grandE += eSum;
      _grandG += gSum;
      _grandW += wSum;
      _grandS += sSum;

      _mainRows.add([
        program,
        quota,
        done,
        '$progress%',
        statusCounts["في طور الانجاز"]!,
        statusCounts["على مستوى الاعمدة"]!,
        statusCounts["منتهية غير مشغولة"]!,
        statusCounts["منتهية ومشغولة"]!,
        eSum,
        gSum,
        wSum,
        sSum,
      ]);

      final occupied = programDone.where((b) => _safeText(b.status) == "منتهية ومشغولة").toList();
      if (occupied.isNotEmpty) {
        final occE = occupied.fold(0, (sum, b) => sum + b.electricity);
        final occG = occupied.fold(0, (sum, b) => sum + b.gas);
        final occW = occupied.fold(0, (sum, b) => sum + b.water);
        final occS = occupied.fold(0, (sum, b) => sum + b.sewage);
        _detailRows.add([program, occupied.length, occE, occG, occW, occS]);
      }
    }

    // صف الإجمالي الرئيسي
    final totalProgress = _grandQuota > 0 ? (_grandDone / _grandQuota * 100).round() : 0;
    _mainRows.add([
      'الإجمالي',
      _grandQuota,
      _grandDone,
      '$totalProgress%',
      _grandStatus["في طور الانجاز"]!,
      _grandStatus["على مستوى الاعمدة"]!,
      _grandStatus["منتهية غير مشغولة"]!,
      _grandStatus["منتهية ومشغولة"]!,
      _grandE,
      _grandG,
      _grandW,
      _grandS,
    ]);

    // إجمالي الجدول التفصيلي
    final totalOcc = _grandStatus["منتهية ومشغولة"] ?? 0;
     if (totalOcc > 0) {
      final allDone = _data.where((b) => b.done == 1).toList();
      final occupiedAll = allDone.where((b) => _safeText(b.status) == "منتهية ومشغولة").toList();
      final totalOccE = occupiedAll.fold(0, (sum, b) => sum + b.electricity);
      final totalOccG = occupiedAll.fold(0, (sum, b) => sum + b.gas);
      final totalOccW = occupiedAll.fold(0, (sum, b) => sum + b.water);
      final totalOccS = occupiedAll.fold(0, (sum, b) => sum + b.sewage);
      _detailRows.add(['الإجمالي', totalOcc, totalOccE, totalOccG, totalOccW, totalOccS]);
    }
  }
  
 // استبدل الدالة _exportStatistics بالنسخة التالية
Future<void> _exportStatistics() async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final fileName =
        'تقرير_إحصائي_${DateTime.now().millisecondsSinceEpoch}.xlsx';

    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/$fileName';

    final exportedPath = await _excelService.exportStatisticsToFile(
      filePath: filePath,
      mainHeaders: _mainHeaders,
      mainRows: _mainRows,
      detailHeaders: _detailHeaders,
      detailRows: _detailRows,
      openAfterSave: false,
    );

    if (!mounted) return;

    Navigator.of(context, rootNavigator: true).pop();

    if (exportedPath != null) {
      await OpenFile.open(exportedPath);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ تم تصدير التقرير: $fileName'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      throw Exception('فشل إنشاء الملف');
    }
  } catch (e) {
    if (!mounted) return;

    Navigator.of(context, rootNavigator: true).pop();

    debugPrint('Export error: $e');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('❌ خطأ: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final totalProgress = _grandQuota > 0 ? (_grandDone / _grandQuota * 100).round() : 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          '📊 التقرير الإحصائي المفصل',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 20),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFEFF6FF), Color(0xFFF8FAFC)],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // بطاقة الملخص العام
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE0F2FE), Color(0xFFF0F9FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.summarize, color: const Color(0xFF0D47A1), size: 28),
                        const SizedBox(width: 12),
                        const Text(
                          'الملخص العام',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0D47A1),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildSummaryItem('إجمالي المستفيدين', '$_grandQuota', Icons.people, const Color(0xFF0D47A1)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildSummaryItem('المحصاة', '$_grandDone ($totalProgress%)', Icons.check_circle, const Color(0xFF2E7D32)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // عنوان الجدول الرئيسي
              _buildSectionTitle('📋 الإحصائيات العامة', Icons.table_chart),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 6)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _buildMainTable(),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // الجدول التفصيلي
              if (_detailRows.isNotEmpty) ...[
                _buildSectionTitle('🔌 تحليل الربط بالشبكات (المنازل المنتهية والمشغولة)', Icons.network_check),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 6)),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _buildDetailTable(),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 28),

              // الأزرار
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _exportStatistics,
                      icon: const Icon(Icons.file_download, size: 20),
                      label: const Text('تصدير التقرير (Excel)', style: TextStyle(fontSize: 14, fontFamily: 'Cairo')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE67E22),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, size: 20),
                      label: const Text('العودة للقائمة', style: TextStyle(fontSize: 14, fontFamily: 'Cairo')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF64748B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Color(0xFF475569))),
                const SizedBox(height: 4),
                Text(value, style: TextStyle(fontFamily: 'Cairo', fontSize: 18, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF0D47A1), size: 24),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(fontFamily: 'Cairo', fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
        ),
      ],
    );
  }

  // استخدام DataTable بدلاً من Table لتجنب أخطاء colSpan
  Widget _buildMainTable() {
    if (_mainRows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text('لا توجد بيانات إحصائية متاحة', style: TextStyle(fontFamily: 'Cairo', fontSize: 16)),
        ),
      );
    }

    return DataTable(
      columnSpacing: 12,
      horizontalMargin: 12,
      headingRowHeight: 48,
      dataRowMinHeight: 42,
      border: TableBorder.all(color: const Color(0xFFE2E8F0), width: 0.5),
      headingRowColor: MaterialStateProperty.all(const Color(0xFFF1F5F9)),
      headingTextStyle: const TextStyle(
        fontFamily: 'Cairo',
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: Color(0xFF0D47A1),
      ),
      dataTextStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Color(0xFF1E293B)),
      columns: _mainHeaders.map((h) => DataColumn(label: Text(h, textAlign: TextAlign.center))).toList(),
      rows: _mainRows.map((row) {
        final isTotal = row[0] == 'الإجمالي';
        return DataRow(
          color: isTotal ? MaterialStateProperty.all(const Color(0xFFE0F2FE)) : null,
          cells: [
            DataCell(Text(row[0].toString(), style: TextStyle(fontWeight: isTotal ? FontWeight.bold : FontWeight.normal))),
            DataCell(Text(row[1].toString())),
            DataCell(Text(row[2].toString())),
            DataCell(Text(row[3].toString())),
            DataCell(Text(row[4].toString())),
            DataCell(Text(row[5].toString())),
            DataCell(Text(row[6].toString())),
            DataCell(Text(row[7].toString())),
            DataCell(Text(row[8].toString())),
            DataCell(Text(row[9].toString())),
            DataCell(Text(row[10].toString())),
            DataCell(Text(row[11].toString())),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildDetailTable() {
    if (_detailRows.isEmpty) return const SizedBox.shrink();

    return DataTable(
      columnSpacing: 16,
      horizontalMargin: 12,
      headingRowHeight: 48,
      dataRowMinHeight: 42,
      border: TableBorder.all(color: const Color(0xFFE2E8F0), width: 0.5),
      headingRowColor: MaterialStateProperty.all(const Color(0xFFF1F5F9)),
      headingTextStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1)),
      dataTextStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
      columns: _detailHeaders.map((h) => DataColumn(label: Text(h, textAlign: TextAlign.center))).toList(),
      rows: _detailRows.map((row) {
        final isTotal = row[0] == 'الإجمالي';
        return DataRow(
          color: isTotal ? MaterialStateProperty.all(const Color(0xFFE0F2FE)) : null,
          cells: row.map((cell) => DataCell(Text(cell.toString(), style: TextStyle(fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)))).toList(),
        );
      }).toList(),
    );
  }
}
