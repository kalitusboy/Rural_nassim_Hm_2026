
import 'package:flutter/material.dart';
import '../models/beneficiary.dart';
import '../services/excel_service.dart';

class StatsScreen extends StatefulWidget {
  final List<Beneficiary> allBeneficiaries;
  
  const StatsScreen({super.key, required this.allBeneficiaries});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final ExcelService _excelService = ExcelService();
  
  late List<Beneficiary> _data;
  late List<String> _programs;
  
  // بيانات الجدول الرئيسي
  final List<List<dynamic>> _mainRows = [];
  final List<String> _mainHeaders = [
    'البرنامج', 'الحصة', 'منجزة', 'نسبة الإنجاز %',
    'في طور الانجاز', 'على مستوى الاعمدة', 'منتهية غير مشغولة', 'منتهية ومشغولة',
    'كهرباء (كل الحالات)', 'غاز (كل الحالات)', 'مياه (كل الحالات)', 'تطهير (كل الحالات)'
  ];
  
  // بيانات الجدول التفصيلي
  final List<List<dynamic>> _detailRows = [];
  final List<String> _detailHeaders = [
    'البرنامج', 'عدد المنتهية المشغولة', 'كهرباء', 'غاز', 'مياه', 'تطهير'
  ];
  
  // الإحصائيات العامة
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
    _data = widget.allBeneficiaries;
    _calculateStats();
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
    
    _grandStatus["في طور الانجاز"] = 0;
    _grandStatus["على مستوى الاعمدة"] = 0;
    _grandStatus["منتهية غير مشغولة"] = 0;
    _grandStatus["منتهية ومشغولة"] = 0;
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
    final statsData = {
      'mainHeaders': _mainHeaders,
      'mainRows': _mainRows,
      'detailHeaders': _detailHeaders,
      'detailRows': _detailRows,
    };
    
    try {
      final filePath = await _excelService.exportStatisticsToExcel({
        'programStats': _programs.map((p) {
          final row = _mainRows.firstWhere((r) => r[0] == p, orElse: () => []);
          return {
            'program': p,
            'total': row.isNotEmpty ? row[1] : 0,
            'done': row.isNotEmpty ? row[2] : 0,
            'status1': row.isNotEmpty ? row[4] : 0,
            'status2': row.isNotEmpty ? row[5] : 0,
            'status3': row.isNotEmpty ? row[6] : 0,
            'status4': row.isNotEmpty ? row[7] : 0,
            'elec': row.isNotEmpty ? row[8] : 0,
            'gas': row.isNotEmpty ? row[9] : 0,
            'water': row.isNotEmpty ? row[10] : 0,
            'sew': row.isNotEmpty ? row[11] : 0,
          };
        }).toList(),
      });
      if (filePath != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم تصدير التقرير الإحصائي بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ فشل تصدير التقرير: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalProgress = _grandQuota > 0 ? (_grandDone / _grandQuota * 100).round() : 0;
    
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('📈 التقرير الإحصائي المفصل والمجمع'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // الملخص العام
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F9FF),
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.only(bottom: 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'الملخص العام',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 15,
                        color: Colors.black,
                      ),
                      children: [
                        const TextSpan(text: 'إجمالي المستفيدين: '),
                        TextSpan(
                          text: '$_grandQuota',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 15,
                        color: Colors.black,
                      ),
                      children: [
                        const TextSpan(text: 'المنجز: '),
                        TextSpan(
                          text: '$_grandDone ($totalProgress%)',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // الجدول الرئيسي
            const Text(
              '📋 الإحصائيات العامة',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _buildMainTable(),
                ),
              ),
            ),
            
            const SizedBox(height: 30),
            
            // الجدول التفصيلي
            if (_detailRows.isNotEmpty) ...[
              const Text(
                '🔌 تحليل الربط بالشبكات للمنازل المنتهية والمشغولة',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _buildDetailTable(),
                  ),
                ),
              ),
            ],
            
            const SizedBox(height: 24),
            
            // أزرار
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _exportStatistics,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE67E22),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '📊 تصدير التقرير الإحصائي (Excel)',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF94A3B8),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '🔙 العودة للقائمة',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainTable() {
    return Table(
      border: TableBorder.all(
        color: const Color(0xFFDDDDDD),
        width: 1,
      ),
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
        // الصف الأول من العناوين
        TableRow(
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
          ),
          children: [
            _buildHeaderCell('البرنامج'),
            _buildHeaderCell('الحصة'),
            _buildHeaderCell('منجزة'),
            _buildHeaderCell('عدد البنايات حسب الحالة'),
            _buildHeaderCell(''),
            _buildHeaderCell(''),
            _buildHeaderCell(''),
            _buildHeaderCell('عدد الربط بالشبكات (كل الحالات)'),
            _buildHeaderCell(''),
            _buildHeaderCell(''),
            _buildHeaderCell(''),
          ],
        ),
        // الصف الثاني من العناوين
        TableRow(
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
          ),
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
            decoration: isTotal
                ? const BoxDecoration(color: Color(0xFFE0F2FE))
                : null,
            children: [
              _buildDataCell(row[0].toString(), isHeader: true, isTotal: isTotal),
              _buildDataCell(row[1].toString(), isTotal: isTotal),
              _buildDataCell(row[2].toString() + (row[0] != 'الإجمالي' ? ' (${row[3]})' : ' (${row[3]})'), isTotal: isTotal),
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
        }),
      ],
    );
  }

  Widget _buildDetailTable() {
    return Table(
      border: TableBorder.all(
        color: const Color(0xFFDDDDDD),
        width: 1,
      ),
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
          decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
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
            decoration: isTotal
                ? const BoxDecoration(color: Color(0xFFE0F2FE))
                : null,
            children: [
              _buildDataCell(row[0].toString(), isHeader: true, isTotal: isTotal),
              _buildDataCell(row[1].toString(), isTotal: isTotal),
              _buildDataCell(row[2].toString(), isTotal: isTotal),
              _buildDataCell(row[3].toString(), isTotal: isTotal),
              _buildDataCell(row[4].toString(), isTotal: isTotal),
              _buildDataCell(row[5].toString(), isTotal: isTotal),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildHeaderCell(String text) {
    return TableCell(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        alignment: Alignment.center,
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0D47A1),
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildDataCell(String text, {bool isHeader = false, bool isTotal = false}) {
    return TableCell(
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
