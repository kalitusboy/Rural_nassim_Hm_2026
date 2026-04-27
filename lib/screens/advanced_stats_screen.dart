import 'dart:io';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import '../services/database_service.dart';

// ──────────────────────────────────────────────────────────────────────────────
// الثوابت المشتركة
// ──────────────────────────────────────────────────────────────────────────────
const _statusColors = {
  'منتهية ومشغولة':    Color(0xFF00897B),
  'منتهية غير مشغولة': Color(0xFF558B2F),
  'على مستوى الاعمدة': Color(0xFF1565C0),
  'في طور الانجاز':    Color(0xFFE65100),
};
const _kStatuses = [
  'منتهية ومشغولة',
  'منتهية غير مشغولة',
  'على مستوى الاعمدة',
  'في طور الانجاز',
];

// ──────────────────────────────────────────────────────────────────────────────
class AdvancedStatsScreen extends StatefulWidget {
  const AdvancedStatsScreen({super.key});

  @override
  State<AdvancedStatsScreen> createState() => _AdvancedStatsScreenState();
}

class _AdvancedStatsScreenState extends State<AdvancedStatsScreen>
    with SingleTickerProviderStateMixin {
  final _db = DatabaseService();
  late final TabController _tabs;
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _future = _db.getAdvancedStats();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _future = _db.getAdvancedStats());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('📊 الإحصائيات المتقدمة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
            tooltip: 'تحديث',
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () => _export(context),
            tooltip: 'تصدير CSV',
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.camera_alt, size: 18), text: 'الصور'),
            Tab(icon: Icon(Icons.bar_chart,   size: 18), text: 'البرامج'),
            Tab(icon: Icon(Icons.home,         size: 18), text: 'الحالة'),
            Tab(icon: Icon(Icons.bolt,         size: 18), text: 'الشبكات'),
          ],
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('خطأ: ${snap.error}'));
          }

          final data       = snap.data!;
          final totals     = data['totals']       as Map<String, dynamic>;
          final byProgram  = (data['byProgram']   as List).cast<Map<String, dynamic>>();
          final byStatus   = (data['byStatus']    as List).cast<Map<String, dynamic>>();
          final imgByStatus= (data['imageByStatus'] as List).cast<Map<String, dynamic>>();

          return TabBarView(
            controller: _tabs,
            children: [
              _ImageTab(totals: totals, imgByStatus: imgByStatus),
              _ProgramTab(byProgram: byProgram),
              _StatusTab(byStatus: byStatus),
              _NetworkTab(byStatus: byStatus, totals: totals),
            ],
          );
        },
      ),
    );
  }

  // ── تصدير CSV ──────────────────────────────────
  Future<void> _export(BuildContext ctx) async {
    try {
      final data      = await _future;
      final totals    = data['totals']    as Map<String, dynamic>;
      final byProgram = (data['byProgram'] as List).cast<Map<String, dynamic>>();
      final byStatus  = (data['byStatus']  as List).cast<Map<String, dynamic>>();
      final imgByStatus=(data['imageByStatus'] as List).cast<Map<String, dynamic>>();

      final csv = StringBuffer();
      csv.writeln('=== إحصائيات الصور ===');
      csv.writeln('الإجمالي المحصاة,مع صورة,بدون صورة,نسبة التصوير');
      final done = (totals['done'] as int? ?? 0);
      final wi   = (totals['with_image'] as int? ?? 0);
      final wo   = (totals['without_image'] as int? ?? 0);
      final pct  = done == 0 ? 0 : (wi / done * 100).toStringAsFixed(1);
      csv.writeln('$done,$wi,$wo,$pct%');

      csv.writeln('\n=== الصور حسب الحالة ===');
      csv.writeln('الحالة,مع صورة,بدون صورة');
      for (final r in imgByStatus) {
        csv.writeln('${r['status']},${r['with_image']},${r['without_image']}');
      }

      csv.writeln('\n=== الإجمالي العام ===');
      csv.writeln('إجمالي المستفيدين,${totals['total']}');
      csv.writeln('المحصاة,$done');
      csv.writeln('كهرباء,${totals['elec']}');
      csv.writeln('غاز,${totals['gas']}');
      csv.writeln('مياه,${totals['water']}');
      csv.writeln('تطهير,${totals['sewage']}');

      csv.writeln('\n=== حسب البرنامج ===');
      csv.writeln('البرنامج,الإجمالي,المحصاة,في طور,أعمدة,غير مشغولة,مشغولة,كهرباء,غاز,مياه,تطهير,مع صورة');
      for (final r in byProgram) {
        csv.writeln('${r['program']},${r['total']},${r['done']},${r['s1']},${r['s2']},${r['s3']},${r['s4']},${r['elec']},${r['gas']},${r['water']},${r['sewage']},${r['with_image']}');
      }

      csv.writeln('\n=== حسب الحالة الفيزيائية ===');
      csv.writeln('الحالة,الإجمالي,كهرباء,غاز,مياه,تطهير,كهرباء فقط,غاز فقط,مياه فقط,تطهير فقط,كهرباء+غاز,كل الشبكات,بلا شبكات,مع صورة');
      for (final r in byStatus) {
        csv.writeln('${r['status']},${r['total']},${r['elec']},${r['gas']},${r['water']},${r['sewage']},${r['elec_only']},${r['gas_only']},${r['water_only']},${r['sewage_only']},${r['elec_gas']},${r['all_four']},${r['none']},${r['with_image']}');
      }

      final dl = Directory('/storage/emulated/0/Download');
      if (!await dl.exists()) await dl.create(recursive: true);
      final ts   = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dl.path}/stats_$ts.csv');
      await file.writeAsString(csv.toString());
      await OpenFile.open(file.path);

      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text('✅ تم التصدير: stats_$ts.csv'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('❌ $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// تبويب الصور
// ══════════════════════════════════════════════════════════════════════════════
class _ImageTab extends StatelessWidget {
  final Map<String, dynamic> totals;
  final List<Map<String, dynamic>> imgByStatus;

  const _ImageTab({required this.totals, required this.imgByStatus});

  @override
  Widget build(BuildContext context) {
    final done = totals['done'] as int? ?? 0;
    final wi   = totals['with_image']    as int? ?? 0;
    final wo   = totals['without_image'] as int? ?? 0;
    final pct  = done == 0 ? 0.0 : wi / done;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        // ── بطاقة الملخص ──────────────────────────
        _SectionCard(
          color: const Color(0xFF4A148C),
          icon: Icons.camera_alt,
          title: 'تقدم التصوير',
          child: Column(children: [
            // دائرة النسبة
            SizedBox(
              height: 160,
              child: PieChart(PieChartData(
                sectionsSpace: 3,
                centerSpaceRadius: 48,
                sections: [
                  PieChartSectionData(
                    value: wi.toDouble(),
                    color: Colors.green.shade500,
                    title: '$wi\nصورة',
                    titleStyle: const TextStyle(
                        fontSize: 11, color: Colors.white,
                        fontWeight: FontWeight.bold),
                    radius: 50,
                  ),
                  if (wo > 0)
                    PieChartSectionData(
                      value: wo.toDouble(),
                      color: Colors.red.shade300,
                      title: '$wo\nبلا صورة',
                      titleStyle: const TextStyle(
                          fontSize: 11, color: Colors.white,
                          fontWeight: FontWeight.bold),
                      radius: 50,
                    ),
                ],
              )),
            ),
            const SizedBox(height: 8),
            // شريط تقدم
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 16,
                backgroundColor: Colors.red.shade100,
                valueColor: AlwaysStoppedAnimation(Colors.green.shade500),
              ),
            ),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('📷 $wi مُصوَّر',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700)),
              Text('${(pct * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18)),
              Text('❌ $wo بلا صورة',
                  style: TextStyle(color: Colors.red.shade600,
                      fontWeight: FontWeight.bold)),
            ]),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // تفصيل حسب الحالة
            ...imgByStatus.map((r) {
              final st     = r['status'] as String? ?? '';
              final withI  = r['with_image']    as int? ?? 0;
              final withO  = r['without_image'] as int? ?? 0;
              final tot    = withI + withO;
              final p      = tot == 0 ? 0.0 : withI / tot;
              final color  = _statusColors[st] ?? Colors.grey;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(width: 10, height: 10,
                          decoration: BoxDecoration(
                              color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Expanded(child: Text(st,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600))),
                      Text('$withI / $tot  (${(p * 100).toStringAsFixed(0)}%)',
                          style: TextStyle(
                              fontSize: 12, color: color,
                              fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: p, minHeight: 10,
                        backgroundColor: color.withOpacity(0.12),
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ]),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// تبويب البرامج
// ══════════════════════════════════════════════════════════════════════════════
class _ProgramTab extends StatelessWidget {
  final List<Map<String, dynamic>> byProgram;
  const _ProgramTab({required this.byProgram});

  static const _colors = [
    Color(0xFF0D47A1), Color(0xFF00897B), Color(0xFFE65100),
    Color(0xFF6A1B9A), Color(0xFF558B2F), Color(0xFF1565C0),
    Color(0xFFAD1457), Color(0xFF4E342E),
  ];

  @override
  Widget build(BuildContext context) {
    if (byProgram.isEmpty) {
      return const Center(child: Text('لا توجد بيانات'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [

        // ── مخطط أعمدة: المحصاة مقابل الإجمالي ──
        _SectionCard(
          color: const Color(0xFF0D47A1),
          icon: Icons.bar_chart,
          title: 'نسبة الإنجاز حسب البرنامج',
          child: SizedBox(
            height: 200,
            child: BarChart(BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: byProgram.fold<num>(0, (m, r) =>
                  (r['total'] as int? ?? 0) > m
                      ? (r['total'] as int? ?? 0)
                      : m).toDouble() * 1.15,
              barGroups: List.generate(byProgram.length, (i) {
                final r = byProgram[i];
                final total = (r['total'] as int? ?? 0).toDouble();
                final done  = (r['done']  as int? ?? 0).toDouble();
                final c = _colors[i % _colors.length];
                return BarChartGroupData(x: i, barRods: [
                  BarChartRodData(
                    toY: total, color: c.withOpacity(0.25),
                    width: 18, borderRadius: BorderRadius.circular(4)),
                  BarChartRodData(
                    toY: done, color: c, width: 18,
                    borderRadius: BorderRadius.circular(4)),
                ]);
              }),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true, reservedSize: 30,
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i >= byProgram.length) return const SizedBox();
                    final prog = (byProgram[i]['program'] as String? ?? '');
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(prog.length > 6 ? prog.substring(0, 6) : prog,
                          style: const TextStyle(fontSize: 9)),
                    );
                  },
                )),
                leftTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true, reservedSize: 35,
                  getTitlesWidget: (v, _) =>
                      Text(v.toInt().toString(),
                          style: const TextStyle(fontSize: 9)),
                )),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: 50,
                  getDrawingHorizontalLine: (_) =>
                      const FlLine(color: Colors.black12, strokeWidth: 0.5)),
              borderData: FlBorderData(show: false),
            )),
          ),
        ),

        const SizedBox(height: 16),

        // ── جدول تفصيلي ──────────────────────────
        _SectionCard(
          color: const Color(0xFF00897B),
          icon: Icons.table_chart,
          title: 'تفصيل حسب البرنامج',
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 16,
              headingRowColor: WidgetStateProperty.all(
                  const Color(0xFFF1F5F9)),
              headingTextStyle: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 12),
              dataTextStyle: const TextStyle(fontSize: 12),
              columns: const [
                DataColumn(label: Text('البرنامج')),
                DataColumn(label: Text('الإجمالي')),
                DataColumn(label: Text('المحصاة')),
                DataColumn(label: Text('النسبة')),
                DataColumn(label: Text('طور')),
                DataColumn(label: Text('أعمدة')),
                DataColumn(label: Text('غير مشغ')),
                DataColumn(label: Text('مشغولة')),
                DataColumn(label: Text('بصورة')),
              ],
              rows: List.generate(byProgram.length, (i) {
                final r     = byProgram[i];
                final total = r['total'] as int? ?? 0;
                final done  = r['done']  as int? ?? 0;
                final pct   = total == 0 ? '0%'
                    : '${(done / total * 100).toStringAsFixed(0)}%';
                final c = _colors[i % _colors.length];
                return DataRow(cells: [
                  DataCell(Row(children: [
                    Container(width: 8, height: 8,
                        decoration: BoxDecoration(
                            color: c, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(r['program'] as String? ?? ''),
                  ])),
                  DataCell(Text(total.toString())),
                  DataCell(Text(done.toString(),
                      style: TextStyle(
                          color: c, fontWeight: FontWeight.bold))),
                  DataCell(Text(pct)),
                  DataCell(Text((r['s1'] as int? ?? 0).toString())),
                  DataCell(Text((r['s2'] as int? ?? 0).toString())),
                  DataCell(Text((r['s3'] as int? ?? 0).toString())),
                  DataCell(Text((r['s4'] as int? ?? 0).toString(),
                      style: const TextStyle(
                          color: Color(0xFF00897B),
                          fontWeight: FontWeight.bold))),
                  DataCell(Text((r['with_image'] as int? ?? 0).toString())),
                ]);
              }),
            ),
          ),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// تبويب الحالة الفيزيائية
// ══════════════════════════════════════════════════════════════════════════════
class _StatusTab extends StatelessWidget {
  final List<Map<String, dynamic>> byStatus;
  const _StatusTab({required this.byStatus});

  @override
  Widget build(BuildContext context) {
    if (byStatus.isEmpty) {
      return const Center(child: Text('لا توجد بيانات محصاة'));
    }

    final total = byStatus.fold<int>(0, (s, r) => s + (r['total'] as int? ?? 0));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [

        // ── دائرة الحالات ─────────────────────────
        _SectionCard(
          color: const Color(0xFFE65100),
          icon: Icons.donut_large,
          title: 'توزيع المحصاة حسب الحالة',
          child: SizedBox(
            height: 200,
            child: Row(children: [
              Expanded(
                child: PieChart(PieChartData(
                  sectionsSpace: 3,
                  centerSpaceRadius: 40,
                  sections: byStatus.map((r) {
                    final st  = r['status'] as String? ?? '';
                    final val = (r['total'] as int? ?? 0).toDouble();
                    final c   = _statusColors[st] ?? Colors.grey;
                    final pct = total == 0 ? 0.0 : val / total * 100;
                    return PieChartSectionData(
                      value: val, color: c,
                      title: '${pct.toStringAsFixed(0)}%',
                      titleStyle: const TextStyle(
                          fontSize: 11, color: Colors.white,
                          fontWeight: FontWeight.bold),
                      radius: 55,
                    );
                  }).toList(),
                )),
              ),
              const SizedBox(width: 16),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: byStatus.map((r) {
                  final st  = r['status'] as String? ?? '';
                  final val = r['total'] as int? ?? 0;
                  final c   = _statusColors[st] ?? Colors.grey;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Container(width: 10, height: 10,
                          decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(st.length > 14 ? st.substring(0, 14) : st,
                          style: const TextStyle(fontSize: 11)),
                      const SizedBox(width: 4),
                      Text('($val)',
                          style: TextStyle(
                              fontSize: 11, color: c,
                              fontWeight: FontWeight.bold)),
                    ]),
                  );
                }).toList(),
              ),
            ]),
          ),
        ),

        const SizedBox(height: 16),

        // ── بطاقة لكل حالة ────────────────────────
        ...byStatus.map((r) {
          final st     = r['status'] as String? ?? '';
          final tot    = r['total']  as int? ?? 0;
          final c      = _statusColors[st] ?? Colors.grey;
          final wi     = r['with_image'] as int? ?? 0;
          final imgPct = tot == 0 ? 0.0 : wi / tot;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: c.withOpacity(0.3))),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border(right: BorderSide(color: c, width: 5)),
                ),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                            color: c, borderRadius: BorderRadius.circular(8)),
                        child: Text(st,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12,
                                fontWeight: FontWeight.bold)),
                      ),
                      const Spacer(),
                      Text('$tot',
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold,
                              color: c)),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: _StatPill('📷 بصورة', wi, Colors.green)),
                      Expanded(child: _StatPill('❌ بلا صورة',
                          tot - wi, Colors.red.shade400)),
                    ]),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: imgPct, minHeight: 8,
                        backgroundColor: Colors.red.shade100,
                        valueColor: AlwaysStoppedAnimation(Colors.green.shade500),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'تصوير ${(imgPct * 100).toStringAsFixed(1)}%',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// تبويب الشبكات
// ══════════════════════════════════════════════════════════════════════════════
class _NetworkTab extends StatelessWidget {
  final List<Map<String, dynamic>> byStatus;
  final Map<String, dynamic> totals;
  const _NetworkTab({required this.byStatus, required this.totals});

  @override
  Widget build(BuildContext context) {
    final totalDone = totals['done'] as int? ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [

        // ── إجمالي الشبكات ────────────────────────
        _SectionCard(
          color: Colors.amber.shade800,
          icon: Icons.bolt,
          title: 'إجمالي الشبكات للمحصاة',
          child: Column(children: [
            Row(children: [
              _NetworkGauge('كهرباء', totals['elec'] as int? ?? 0, totalDone, Icons.bolt, Colors.amber.shade700),
              _NetworkGauge('غاز', totals['gas'] as int? ?? 0, totalDone, Icons.local_fire_department, Colors.orange.shade700),
              _NetworkGauge('مياه', totals['water'] as int? ?? 0, totalDone, Icons.water_drop, Colors.blue.shade600),
              _NetworkGauge('تطهير', totals['sewage'] as int? ?? 0, totalDone, Icons.cleaning_services, Colors.teal.shade600),
            ]),
          ]),
        ),

        const SizedBox(height: 16),

        // ── تفصيل حسب الحالة ─────────────────────
        _SectionCard(
          color: Colors.teal.shade700,
          icon: Icons.table_chart,
          title: 'الشبكات حسب الحالة الفيزيائية',
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 14,
              headingRowColor: WidgetStateProperty.all(
                  const Color(0xFFF1F5F9)),
              headingTextStyle: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 11),
              dataTextStyle: const TextStyle(fontSize: 11),
              columns: const [
                DataColumn(label: Text('الحالة')),
                DataColumn(label: Text('الحصة')),
                DataColumn(label: Text('⚡ كهرباء')),
                DataColumn(label: Text('🔥 غاز')),
                DataColumn(label: Text('💧 مياه')),
                DataColumn(label: Text('🚿 تطهير')),
                DataColumn(label: Text('الكل')),
                DataColumn(label: Text('لا شيء')),
              ],
              rows: byStatus.map((r) {
                final st  = r['status'] as String? ?? '';
                final tot = r['total']  as int? ?? 0;
                final c   = _statusColors[st] ?? Colors.grey;
                return DataRow(cells: [
                  DataCell(Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: c.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(st.length > 12
                        ? st.substring(0, 12) : st,
                        style: TextStyle(color: c, fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  )),
                  DataCell(Text(tot.toString(),
                      style: const TextStyle(fontWeight: FontWeight.bold))),
                  DataCell(Text((r['elec']    as int? ?? 0).toString())),
                  DataCell(Text((r['gas']     as int? ?? 0).toString())),
                  DataCell(Text((r['water']   as int? ?? 0).toString())),
                  DataCell(Text((r['sewage']  as int? ?? 0).toString())),
                  DataCell(Text((r['all_four'] as int? ?? 0).toString(),
                      style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold))),
                  DataCell(Text((r['none']    as int? ?? 0).toString(),
                      style: const TextStyle(color: Colors.red))),
                ]);
              }).toList(),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // ── مخطط رادار مبسّط ──────────────────────
        _SectionCard(
          color: Colors.indigo.shade700,
          icon: Icons.radar,
          title: 'مقارنة الشبكات حسب الحالة',
          child: SizedBox(
            height: 220,
            child: BarChart(BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: byStatus.fold<num>(0, (m, r) {
                final mx = [
                  r['elec'] as int? ?? 0, r['gas'] as int? ?? 0,
                  r['water'] as int? ?? 0, r['sewage'] as int? ?? 0,
                ].reduce((a, b) => a > b ? a : b);
                return mx > m ? mx : m;
              }).toDouble() * 1.15,
              barGroups: List.generate(byStatus.length, (i) {
                final r = byStatus[i];
                final c = _statusColors[r['status'] as String? ?? '']
                    ?? Colors.grey;
                return BarChartGroupData(x: i, barRods: [
                  BarChartRodData(toY: (r['elec']   as int? ?? 0).toDouble(), color: Colors.amber.shade600,   width: 8, borderRadius: BorderRadius.circular(3)),
                  BarChartRodData(toY: (r['gas']    as int? ?? 0).toDouble(), color: Colors.orange.shade600,  width: 8, borderRadius: BorderRadius.circular(3)),
                  BarChartRodData(toY: (r['water']  as int? ?? 0).toDouble(), color: Colors.blue.shade500,    width: 8, borderRadius: BorderRadius.circular(3)),
                  BarChartRodData(toY: (r['sewage'] as int? ?? 0).toDouble(), color: Colors.teal.shade400,    width: 8, borderRadius: BorderRadius.circular(3)),
                ], barsSpace: 3);
              }),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true, reservedSize: 28,
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i >= byStatus.length) return const SizedBox();
                    final st = byStatus[i]['status'] as String? ?? '';
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        st.length > 8 ? st.substring(0, 8) : st,
                        style: const TextStyle(fontSize: 8),
                      ),
                    );
                  },
                )),
                leftTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true, reservedSize: 30,
                  getTitlesWidget: (v, _) => Text(
                      v.toInt().toString(),
                      style: const TextStyle(fontSize: 9)),
                )),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      const FlLine(color: Colors.black12, strokeWidth: 0.5)),
              borderData: FlBorderData(show: false),
            )),
          ),
        ),

        // مفتاح الألوان
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _Legend('كهرباء',  Colors.amber.shade600),
            const SizedBox(width: 12),
            _Legend('غاز',     Colors.orange.shade600),
            const SizedBox(width: 12),
            _Legend('مياه',    Colors.blue.shade500),
            const SizedBox(width: 12),
            _Legend('تطهير',   Colors.teal.shade400),
          ]),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Widgets مساعدة مشتركة
// ══════════════════════════════════════════════════════════════════════════════

class _SectionCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final Widget child;

  const _SectionCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16)),
          ),
          child: Row(children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
          ]),
        ),
        Padding(padding: const EdgeInsets.all(14), child: child),
      ]),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _StatPill(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(fontSize: 11, color: color)),
        const SizedBox(width: 4),
        Text(value.toString(),
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }
}

class _NetworkGauge extends StatelessWidget {
  final String label;
  final int value;
  final int total;
  final IconData icon;
  final Color color;
  const _NetworkGauge(this.label, this.value, this.total, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : value / total;
    return Expanded(
      child: Column(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(value.toString(),
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 10)),
        const SizedBox(height: 4),
        Text('${(pct * 100).toStringAsFixed(0)}%',
            style: TextStyle(fontSize: 10, color: color)),
        const SizedBox(height: 4),
        SizedBox(
          height: 50,
          child: PieChart(PieChartData(
            sections: [
              PieChartSectionData(
                  value: pct, color: color,
                  title: '', radius: 10),
              PieChartSectionData(
                  value: 1 - pct,
                  color: color.withOpacity(0.12),
                  title: '', radius: 10),
            ],
            centerSpaceRadius: 15,
            sectionsSpace: 1,
          )),
        ),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  final String label;
  final Color color;
  const _Legend(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(width: 10, height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 11)),
    ]);
  }
}
