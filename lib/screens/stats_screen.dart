import 'package:flutter/material.dart';
import '../models/beneficiary.dart';

class StatsScreen extends StatefulWidget {
  final List<Beneficiary> allBeneficiaries;
  const StatsScreen({super.key, required this.allBeneficiaries});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  late List<Beneficiary> _data;
  final _mainRows = <List<dynamic>>[];
  final _detailRows = <List<dynamic>>[];
  int _quota = 0, _done = 0, _e = 0, _g = 0, _w = 0, _s = 0;
  final _status = {'في طور الانجاز': 0, 'على مستوى الاعمدة': 0, 'منتهية غير مشغولة': 0, 'منتهية ومشغولة': 0};

  @override
  void initState() {
    super.initState();
    _data = widget.allBeneficiaries;
    _calc();
  }

  void _calc() {
    _mainRows.clear(); _detailRows.clear();
    _quota = _data.length;
    _done = _data.where((b) => b.done == 1).length;
    _status.updateAll((k, v) => 0); _e = _g = _w = _s = 0;
    
    final programs = _data.map((b) => b.program ?? 'عام').toSet().toList();
    for (var p in programs) {
      final pData = _data.where((b) => (b.program ?? 'عام') == p).toList();
      final pDone = pData.where((b) => b.done == 1).toList();
      final st = {
        'في طور الانجاز': pDone.where((b) => b.status == 'في طور الانجاز').length,
        'على مستوى الاعمدة': pDone.where((b) => b.status == 'على مستوى الاعمدة').length,
        'منتهية غير مشغولة': pDone.where((b) => b.status == 'منتهية غير مشغولة').length,
        'منتهية ومشغولة': pDone.where((b) => b.status == 'منتهية ومشغولة').length,
      };
      final eSum = pDone.fold(0, (s, b) => s + b.electricity);
      final gSum = pDone.fold(0, (s, b) => s + b.gas);
      final wSum = pDone.fold(0, (s, b) => s + b.water);
      final sSum = pDone.fold(0, (s, b) => s + b.sewage);
      st.forEach((k, v) => _status[k] = (_status[k] ?? 0) + v);
      _e += eSum; _g += gSum; _w += wSum; _s += sSum;
      _mainRows.add([p, pData.length, '${pDone.length} (${pData.isEmpty ? 0 : (pDone.length / pData.length * 100).round()}%)', st['في طور الانجاز'], st['على مستوى الاعمدة'], st['منتهية غير مشغولة'], st['منتهية ومشغولة'], eSum, gSum, wSum, sSum]);
      
      final occ = pDone.where((b) => b.status == 'منتهية ومشغولة').toList();
      if (occ.isNotEmpty) {
        _detailRows.add([p, occ.length, occ.fold(0, (s, b) => s + b.electricity), occ.fold(0, (s, b) => s + b.gas), occ.fold(0, (s, b) => s + b.water), occ.fold(0, (s, b) => s + b.sewage)]);
      }
    }
    _mainRows.add(['الإجمالي', _quota, '$_done (${_quota == 0 ? 0 : (_done / _quota * 100).round()}%)', _status['في طور الانجاز']!, _status['على مستوى الاعمدة']!, _status['منتهية غير مشغولة']!, _status['منتهية ومشغولة']!, _e, _g, _w, _s]);
    if (_status['منتهية ومشغولة']! > 0) {
      final allDone = _data.where((b) => b.done == 1 && b.status == 'منتهية ومشغولة').toList();
      _detailRows.add(['الإجمالي', allDone.length, allDone.fold(0, (s, b) => s + b.electricity), allDone.fold(0, (s, b) => s + b.gas), allDone.fold(0, (s, b) => s + b.water), allDone.fold(0, (s, b) => s + b.sewage)]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('📈 التقرير الإحصائي')),
      body: SingleChildScrollView(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFFF0F9FF), borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('الملخص العام', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Text('إجمالي المستفيدين: $_quota'), Text('المنجز: $_done (${_quota == 0 ? 0 : (_done / _quota * 100).round()}%)')])),
        const SizedBox(height: 16),
        Card(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Padding(padding: const EdgeInsets.all(8), child: DataTable(columns: const [DataColumn(label: Text('البرنامج')), DataColumn(label: Text('الحصة')), DataColumn(label: Text('منجزة')), DataColumn(label: Text('كهرباء')), DataColumn(label: Text('غاز')), DataColumn(label: Text('مياه')), DataColumn(label: Text('تطهير'))], rows: _mainRows.map((r) => DataRow(color: r[0] == 'الإجمالي' ? MaterialStateProperty.all(const Color(0xFFE0F2FE)) : null, cells: [DataCell(Text(r[0].toString())), DataCell(Text(r[1].toString())), DataCell(Text(r[2].toString())), DataCell(Text(r[7].toString())), DataCell(Text(r[8].toString())), DataCell(Text(r[9].toString())), DataCell(Text(r[10].toString()))])).toList())))),
        if (_detailRows.isNotEmpty) Card(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Padding(padding: const EdgeInsets.all(8), child: DataTable(columns: const [DataColumn(label: Text('البرنامج')), DataColumn(label: Text('منتهية مشغولة')), DataColumn(label: Text('كهرباء')), DataColumn(label: Text('غاز')), DataColumn(label: Text('مياه')), DataColumn(label: Text('تطهير'))], rows: _detailRows.map((r) => DataRow(color: r[0] == 'الإجمالي' ? MaterialStateProperty.all(const Color(0xFFE0F2FE)) : null, cells: [DataCell(Text(r[0].toString())), DataCell(Text(r[1].toString())), DataCell(Text(r[2].toString())), DataCell(Text(r[3].toString())), DataCell(Text(r[4].toString())), DataCell(Text(r[5].toString()))])).toList())))),
      ])),
    );
  }
}
