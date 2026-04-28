import 'dart:async';
import 'package:flutter/material.dart';
import '../models/beneficiary.dart';
import '../services/database_service.dart';
import '../services/excel_service.dart';
import '../services/export_service.dart';
import '../widgets/beneficiary_card.dart';
import 'admin_merge_screen.dart';
import 'advanced_stats_screen.dart';
import 'stats_screen.dart';
import 'survey_screen.dart';
import 'sync_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  static const int _pageSize = 100;

  final _db           = DatabaseService();
  final _excelService = ExcelService();
  final _exportService= ExportService();
  final _stream       = StreamController<List<Beneficiary>>.broadcast();
  final _searchCtrl   = TextEditingController();
  final _scrollCtrl   = ScrollController();

  late TabController _tabs;

  List<String>       _addresses      = [];
  List<Beneficiary>  _results        = [];
  String             _search         = '';
  String?            _selectedAddr;
  bool               _loading        = false;
  bool               _loadingMore    = false;
  bool               _hasMore        = true;
  int                _offset         = 0;
  int                _tab            = 0;
  int                _reqSeq         = 0;
  Timer?             _debounce;

  // ─── إحصائيات الشريط ─────────────────────────
  Map<String, dynamic>? _dash;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (_tabs.indexIsChanging || _tab == _tabs.index) return;
        setState(() => _tab = _tabs.index);
        _reload();
      });
    _scrollCtrl.addListener(_onScroll);
    _init();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _tabs.dispose();
    _stream.close();
    super.dispose();
  }

  Future<void> _init() async {
    await _loadAddresses();
    await _reload();
    _loadDash();
  }

  Future<void> _loadDash() async {
    final d = await _db.getDashboardStats();
    if (mounted) setState(() => _dash = d);
  }

  Future<void> _loadAddresses() async {
    final a = await _db.getDistinctAddresses();
    if (!mounted) return;
    setState(() {
      _addresses = a;
      if (_selectedAddr != null && !a.contains(_selectedAddr)) {
        _selectedAddr = null;
      }
    });
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients || _loading || _loadingMore || !_hasMore) return;
    final p = _scrollCtrl.position;
    if (p.pixels >= p.maxScrollExtent - 300) _loadMore();
  }

  Future<void> _reload() async {
    _debounce?.cancel();
    _offset = 0;
    _hasMore = true;
    _results = [];
    _stream.add(const []);
    await _loadMore(reset: true);
    _loadDash();
  }

  Future<void> _loadMore({bool reset = false}) async {
    if ((_loading || _loadingMore) && !reset) return;
    if (!reset && !_hasMore) return;

    final id = ++_reqSeq;
    if (mounted) setState(() => reset ? _loading = true : _loadingMore = true);

    try {
      final res = await _db.searchBeneficiaries(
        doneValue: _tab == 0 ? 0 : 1,
        query: _search,
        address: _selectedAddr,
        limit: _pageSize,
        offset: reset ? 0 : _offset,
      );
      if (!mounted || id != _reqSeq) return;

      _results = reset ? res : [..._results, ...res];
      _offset  = _results.length;
      _hasMore = res.length == _pageSize;
      _stream.add(List.unmodifiable(_results));
    } catch (e) {
      if (mounted && id == _reqSeq) _snack('❌ $e', false);
    } finally {
      if (mounted && id == _reqSeq) {
        setState(() { _loading = false; _loadingMore = false; });
      }
    }
  }

  Future<void> _reloadAll() async {
    await _loadAddresses();
    await _reload();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final n = v.trim();
      if (_search == n) return;
      setState(() => _search = n);
      _reload();
    });
  }

  // ── الإجراءات ─────────────────────────────────
  Future<void> _importExcel() async {
    Navigator.pop(context);
    setState(() => _loading = true);
    try {
      final list = await _excelService.importFromExcel();
      if (list.isNotEmpty) {
        await _db.insertBeneficiaries(list);
        _snack('✅ تم استيراد ${list.length} مستفيد', true);
        await _reloadAll();
      } else {
        _snack('⚠️ لم يُستورد أي بيان، تأكد من تنسيق الأعمدة', false);
      }
    } catch (e) {
      _snack('❌ فشل الاستيراد: $e', false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _merge() async {
    Navigator.pop(context);
    setState(() => _loading = true);
    try {
      final r = await _exportService.mergeDatabases();
      _snack('✅ ${r['imported']} جديد · ${r['updated']} محدث · ${r['skipped']} محصاة', true);
      await _reloadAll();
    } catch (e) {
      _snack('❌ $e', false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportExcel() async {
    Navigator.pop(context);
    setState(() => _loading = true);
    try {
      final list = await _db.getCompletedBeneficiaries();
      if (list.isEmpty) { _snack('⚠️ لا توجد حالات محصاة', false); return; }
      final path = await _excelService.exportToExcel(beneficiaries: list, openAfterSave: true);
      if (path != null) _snack('✅ ${path.split('/').last}', true);
    } catch (e) {
      _snack('❌ $e', false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg, bool ok) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: ok ? Colors.green : Colors.red,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Drawer — قائمة الإجراءات ──────────────────
  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ترويسة الدرج
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              color: const Color(0xFF0D47A1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.home_work_outlined,
                      color: Colors.white, size: 32),
                  const SizedBox(height: 6),
                  const Text('إحصاء السكن الريفي',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                  Text('نسيم — الحوضان · 2026',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 11)),
                ],
              ),
            ),

            const SizedBox(height: 4),
            Expanded(
              child: ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: [

                _DrawerSection('📊 الإحصائيات'),
                _DrawerItem(Icons.bar_chart_outlined, 'عرض الإحصائيات',
                    Colors.orange, () {
                  Navigator.pop(context);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const StatsScreen()))
                      .then((_) => _reload());
                }),
                _DrawerItem(Icons.analytics_outlined, 'إحصائيات متقدمة',
                    Colors.purple, () {
                  Navigator.pop(context);
                  Navigator.push(context,
                      MaterialPageRoute(
                          builder: (_) => const AdvancedStatsScreen()));
                }),

                const Divider(height: 16),
                _DrawerSection('📁 البيانات'),
                _DrawerItem(Icons.download_outlined, 'استيراد القائمة الأساسية',
                    const Color(0xFF0D47A1), _importExcel),
                _DrawerItem(Icons.upload_file_outlined, 'تصدير Excel',
                    Colors.green.shade700, _exportExcel),
                _DrawerItem(Icons.merge_outlined, 'دمج قواعد البيانات',
                    Colors.deepPurple, _merge),
                _DrawerItem(Icons.share_outlined, 'تصدير JSON',
                    Colors.blueGrey, () {
                  Navigator.pop(context);
                  _exportService.exportFullDatabase();
                }),
                _DrawerItem(Icons.photo_library_outlined, 'تصدير الصور ZIP',
                    Colors.teal, () {
                  Navigator.pop(context);
                  _exportService.exportImagesAsZip();
                }),

                const Divider(height: 16),
                _DrawerSection('👨‍💼 المدير'),
                _DrawerItem(Icons.admin_panel_settings_outlined,
                    'دمج بيانات الأعوان', Colors.indigo, () {
                  Navigator.pop(context);
                  Navigator.push(context,
                      MaterialPageRoute(
                          builder: (_) => const AdminMergeScreen()));
                }),
                _DrawerItem(Icons.sync_outlined, 'مزامنة WiFi',
                    Colors.cyan.shade700, () {
                  Navigator.pop(context);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const SyncScreen()))
                      .then((_) => _reloadAll());
                }),

                const Divider(height: 16),
                _DrawerItem(Icons.info_outline, 'حول البرنامج',
                    Colors.grey, () {
                  Navigator.pop(context);
                  _showAbout();
                }),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  void _showAbout() {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('ℹ️ حول البرنامج'),
        content: const Column(mainAxisSize: MainAxisSize.min, children: [
          Text('📱 تطبيق إحصاء 2026'),
          Text('الإصدار: 2.2.0'),
          Text('المطور: حميتي نسيم — الحوضان'),
          Text('nas.hamiti89@gmail.com'),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('حسناً'))
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d       = _dash;
    final total   = d?['total']         as int? ?? 0;
    final done    = d?['done']          as int? ?? 0;
    final pending = d?['pending']       as int? ?? 0;
    final withImg = d?['with_image']    as int? ?? 0;
    final noImg   = d?['without_image'] as int? ?? 0;
    final pct     = total == 0 ? 0.0 : done / total;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      drawer: _buildDrawer(),
      appBar: AppBar(
        // ── عنوان مضغوط ──────────────────────────
        titleSpacing: 0,
        title: const Text('إحصاء 2026 — نسيم',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync, size: 20),
            tooltip: 'المزامنة',
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SyncScreen()));
              _reloadAll();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelStyle: const TextStyle(fontSize: 12),
          tabs: const [
            Tab(text: '📋 غير المحصاة', icon: Icon(Icons.pending_actions, size: 16)),
            Tab(text: '✅ المحصاة',      icon: Icon(Icons.check_circle,   size: 16)),
          ],
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
        ),
      ),

      body: Column(children: [

        // ══ شريط الأرقام المضغوط ══════════════════
        Container(
          color: const Color(0xFF0D47A1),
          padding: const EdgeInsets.fromLTRB(10, 5, 10, 6),
          child: Column(children: [
            Row(children: [
              _Tile('الكل',    total,   Colors.white),
              _Tile('محصاة',   done,    Colors.greenAccent),
              _Tile('متبقية',  pending, Colors.amber),
              _Tile('📷',      withImg, Colors.lightBlueAccent),
              _Tile('بلا 📷',  noImg,   Colors.redAccent),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Text('${(pct * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(color: Colors.white70, fontSize: 10)),
              const SizedBox(width: 6),
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: pct, minHeight: 5,
                  backgroundColor: Colors.white24,
                  valueColor:
                      const AlwaysStoppedAnimation(Colors.greenAccent),
                ),
              )),
              const SizedBox(width: 6),
              Text('$done/$total',
                  style: const TextStyle(color: Colors.white70, fontSize: 10)),
            ]),
          ]),
        ),

        // ══ شريط البحث والفلتر ════════════════════
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: Row(children: [
            // فلتر العنوان
            Expanded(
              flex: 2,
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _selectedAddr,
                    hint: const Text('كل العناوين',
                        style: TextStyle(fontSize: 12)),
                    isExpanded: true,
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('كل العناوين')),
                      ..._addresses.map((a) =>
                          DropdownMenuItem<String?>(
                              value: a, child: Text(a))),
                    ],
                    onChanged: (v) {
                      setState(() => _selectedAddr = v);
                      _reload();
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // حقل البحث
            Expanded(
              flex: 3,
              child: SizedBox(
                height: 40,
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'بحث بالاسم أو العنوان...',
                    hintStyle: const TextStyle(fontSize: 12),
                    prefixIcon:
                        const Icon(Icons.search, size: 18),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: Color(0xFFCBD5E1))),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: Color(0xFFCBD5E1))),
                  ),
                  onChanged: _onSearch,
                ),
              ),
            ),
          ]),
        ),

        // ══ القائمة ═══════════════════════════════
        Expanded(
          child: StreamBuilder<List<Beneficiary>>(
            stream: _stream.stream,
            initialData: const [],
            builder: (context, snap) {
              final list    = snap.data ?? const <Beneficiary>[];
              final isEmpty = list.isEmpty && !_loading;

              if (_loading && list.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              if (isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline,
                          size: 72, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text(
                        _tab == 0
                            ? 'لا توجد حالات غير محصاة'
                            : 'لا توجد حالات محصاة',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                );
              }

              return Column(children: [
                // عداد النتائج
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 3),
                  child: Row(children: [
                    Text('${list.length} نتيجة',
                        style: const TextStyle(
                            color: Color(0xFF475569),
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (_hasMore)
                      const Text('تحميل تدريجي',
                          style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 11)),
                  ]),
                ),
                // القائمة
                Expanded(
                  child: ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    itemCount: list.length + (_loadingMore ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i >= list.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                              child: CircularProgressIndicator()),
                        );
                      }
                      final b = list[i];
                      return BeneficiaryCard(
                        beneficiary: b,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  SurveyScreen(beneficiary: b)),
                        ).then((_) => _reloadAll()),
                      );
                    },
                  ),
                ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// بلاطة الشريط العلوي
// ─────────────────────────────────────────────
class _Tile extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _Tile(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(value.toString(),
              style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
          Text(label,
              style: const TextStyle(
                  color: Colors.white60, fontSize: 9)),
        ]),
      );
}

// ─────────────────────────────────────────────
// عنوان قسم في الـ Drawer
// ─────────────────────────────────────────────
Widget _DrawerSection(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      child: Text(title,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade500,
              letterSpacing: 0.5)),
    );

// ─────────────────────────────────────────────
// عنصر قائمة في الـ Drawer
// ─────────────────────────────────────────────
Widget _DrawerItem(
    IconData icon, String label, Color color, VoidCallback onTap) {
  return ListTile(
    dense: true,
    leading: Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, color: color, size: 18),
    ),
    title: Text(label, style: const TextStyle(fontSize: 13)),
    onTap: onTap,
    horizontalTitleGap: 10,
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
  );
}
