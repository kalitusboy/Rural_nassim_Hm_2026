
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/beneficiary.dart';
import '../services/excel_service.dart';
import '../services/database_service.dart';

class StatsScreen extends StatefulWidget {
  final List<Beneficiary>? allBeneficiaries; // اختياري الآن للتوافق

  const StatsScreen({super.key, this.allBeneficiaries});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final ExcelService _excelService = ExcelService();
  final DatabaseService _dbService = DatabaseService();

  List<Beneficiary> _data = [];
  bool _isLoading = true;

  late List<String> _programs;

  final List<List<dynamic>> _mainRows = [];
  final List<String> _mainHeaders = [
    'البرنامج', 'الحصة', 'منجزة', 'نسبة الإنجاز %',
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
      _data = await _dbService.getAllBeneficiaries(); // جلب من قاعدة البيانات
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
    _programs = _data
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

    for (var program in _programs) {
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
        program, quota, done, '$progress%',
        statusCounts["في طور الانجاز"]!,
        statusCounts["على مستوى الاعمدة"]!,
        statusCounts["منتهية غير مشغولة"]!,
        statusCounts["منتهية ومشغولة"]!,
        eSum, gSum, wSum, sSum,
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

    final totalProgress = _grandQuota > 0 ? (_grandDone / _grandQuota * 100).round() : 0;
    _mainRows.add([
      'الإجمالي', _grandQuota, _grandDone, '$totalProgress%',
      _grandStatus["في طور الانجاز"]!,
      _grandStatus["على مستوى الاعمدة"]!,
      _grandStatus["منتهية غير مشغولة"]!,
      _grandStatus["منتهية ومشغولة"]!,
      _grandE, _grandG, _grandW, _grandS,
    ]);

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

  Future<void> _exportStatistics() async {
    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: "حفظ التقرير الإحصائي",
      fileName: "تقرير_إحصائي_${DateTime.now().millisecondsSinceEpoch}.xlsx",
      allowedExtensions: ['xlsx'],
    );
    if (outputFile == null) return;
    try {
      await _excelService.exportStatisticsToFile(
        filePath: outputFile,
        mainHeaders: _mainHeaders,
        mainRows: _mainRows,
        detailHeaders: _detailHeaders,
        detailRows: _detailRows,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ تم التصدير بنجاح'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ فشل التصدير: $e'), backgroundColor: Colors.red),
        );
      }
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
                          child: _buildSummaryItem('المنجز', '$_grandDone ($totalProgress%)', Icons.check_circle, const Color(0xFF2E7D32)),
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

  // ====================== دوال الجداول باستخدام Table (مع colspan) ======================
  Widget _buildMainTable() {
    return Table(
      border: TableBorder.all(color: const Color(0xFFE2E8F0), width: 0.5),
      columnWidths: const {
        0: IntrinsicColumnWidth(),
        1: IntrinsicColumnWidth(),
        2: IntrinsicColumnWidth(),
        3: IntrinsicColumnWidth(),
        4: IntrinsicColumnWidth(),
        5: IntrinsicColumnWidth(),
        6: IntrinsicColumnWidth(),
        7: IntrinsicColumnWidth(),
        8: IntrinsicColumnWidth(),
        9: IntrinsicColumnWidth(),
        10: IntrinsicColumnWidth(),
        11: IntrinsicColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        // الصف الأول من العناوين (مع اندماج الأعمدة)
        TableRow(
          decoration: const BoxDecoration(color: Color(0xFFF1F5F9)),
          children: [
            _buildHeaderCell('البرنامج'),
            _buildHeaderCell('الحصة'),
            _buildHeaderCell('منجزة'),
            _buildHeaderCell('عدد البنايات حسب الحالة', colspan: 4),
            _buildHeaderCell('عدد الربط بالشبكات (كل الحالات)', colspan: 4),
          ],
        ),
        // الصف الثاني من العناوين (التفاصيل)
        TableRow(
          decoration: const BoxDecoration(color: Color(0xFFF1F5F9)),
          children: [
            _buildHeaderCell(''),
            _buildHeaderCell(''),
            _buildHeaderCell(''),
            _buildHeaderCell('في طور الانجاز'),
            _buildHeaderCell('على مستوى الاعمدة'),
            _buildHeaderCell('منتهية غير مشغولة'),
            _buildHeaderCell('منتهية ومشغولة'),
            _buildHeaderCell('كهرباء'),
            _buildHeaderCell('غاز'),
            _buildHeaderCell('مياه'),
            _buildHeaderCell('تطهير'),
          ],
        ),
        // صفوف البيانات
        ..._mainRows.map((row) {
          final isTotal = row[0] == 'الإجمالي';
          return TableRow(
            decoration: BoxDecoration(
              color: isTotal ? const Color(0xFFE0F2FE) : null,
            ),
            children: [
              _buildDataCell(row[0].toString(), isTotal: isTotal, isHeader: true),
              _buildDataCell(row[1].toString(), isTotal: isTotal),
              _buildDataCell('${row[2]} (${row[3]})', isTotal: isTotal),
              _buildDataCell(row[4].toString(), isTotal: isTotal),
              _buildDataCell(row[5].toString(), isTotal: isTotal),
              _buildDataCell(row[6].toString(), isTotal: isTotal),
              _buildDataCell(row[7].toString(), isTotal: isTotal),
              _buildDataCell(row[8].toString(), isTotal: isTotal),
              _buildDataCell(row[9].toString(), isTotal: isTotal),
              _buildDataCell(row[10].toString(), isTotal: isTotal),
              _buildDataCell(row[11].toString(), isTotal: isTotal),
            ],
          );
        }).toList(),
      ],
    );
  }

  Widget _buildDetailTable() {
    return Table(
      border: TableBorder.all(color: const Color(0xFFE2E8F0), width: 0.5),
      columnWidths: const {
        0: IntrinsicColumnWidth(),
        1: IntrinsicColumnWidth(),
        2: IntrinsicColumnWidth(),
        3: IntrinsicColumnWidth(),
        4: IntrinsicColumnWidth(),
        5: IntrinsicColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: const BoxDecoration(color: Color(0xFFF1F5F9)),
          children: [
            _buildHeaderCell('البرنامج'),
            _buildHeaderCell('عدد المنتهية المشغولة'),
            _buildHeaderCell('كهرباء'),
            _buildHeaderCell('غاز'),
            _buildHeaderCell('مياه'),
            _buildHeaderCell('تطهير'),
          ],
        ),
        ..._detailRows.map((row) {
          final isTotal = row[0] == 'الإجمالي';
          return TableRow(
            decoration: BoxDecoration(
              color: isTotal ? const Color(0xFFE0F2FE) : null,
            ),
            children: [
              _buildDataCell(row[0].toString(), isTotal: isTotal, isHeader: true),
              _buildDataCell(row[1].toString(), isTotal: isTotal),
              _buildDataCell(row[2].toString(), isTotal: isTotal),
              _buildDataCell(row[3].toString(), isTotal: isTotal),
              _buildDataCell(row[4].toString(), isTotal: isTotal),
              _buildDataCell(row[5].toString(), isTotal: isTotal),
            ],
          );
        }).toList(),
      ],
    );
  }

  Widget _buildHeaderCell(String text, {int colspan = 1}) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        alignment: Alignment.center,
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0D47A1),
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

   Widget _buildDataCell(String text, {bool isTotal = false, bool isHeader = false}) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        alignment: Alignment.center,
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 13,
            fontWeight: isTotal || isHeader ? FontWeight.bold : FontWeight.normal,
            color: isTotal ? const Color(0xFF0D47A1) : Colors.black,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
