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
import 'sync_screen.dart'; // ← المزامنة

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  static const int _pageSize = 100;

  final _dbService = DatabaseService();
  final _excelService = ExcelService();
  final _exportService = ExportService();
  final _resultsController = StreamController<List<Beneficiary>>.broadcast();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  late TabController _tabController;

  List<String> _addresses = [];
  List<Beneficiary> _currentResults = [];
  String _search = '';
  String? _selectedAddress;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _currentOffset = 0;
  int _currentTab = 0;
  int _requestSequence = 0;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging || _currentTab == _tabController.index) return;
      setState(() => _currentTab = _tabController.index);
      _refreshList();
    });
    _scrollController.addListener(_onScroll);
    _initializeScreen();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    _tabController.dispose();
    _resultsController.close();
    super.dispose();
  }

  Future<void> _initializeScreen() async {
    await _refreshAddresses();
    await _refreshList();
  }

  Future<void> _refreshAddresses() async {
    final addresses = await _dbService.getDistinctAddresses();
    if (!mounted) return;

    setState(() {
      _addresses = addresses;
      if (_selectedAddress != null && !_addresses.contains(_selectedAddress)) {
        _selectedAddress = null;
      }
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loading || _loadingMore || !_hasMore) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 300) {
      _loadNextPage();
    }
  }

  Future<void> _refreshList() async {
    _searchDebounce?.cancel();
    _currentOffset = 0;
    _hasMore = true;
    _currentResults = [];
    _resultsController.add(const []);
    await _loadNextPage(reset: true);
  }

  Future<void> _loadNextPage({bool reset = false}) async {
    if ((_loading || _loadingMore) && !reset) return;
    if (!reset && !_hasMore) return;

    final requestId = ++_requestSequence;
    if (mounted) {
      setState(() {
        if (reset) {
          _loading = true;
        } else {
          _loadingMore = true;
        }
      });
    }

    try {
      final results = await _dbService.searchBeneficiaries(
        doneValue: _currentTab == 0 ? 0 : 1,
        query: _search,
        address: _selectedAddress,
        limit: _pageSize,
        offset: reset ? 0 : _currentOffset,
      );

      if (!mounted || requestId != _requestSequence) return;

      if (reset) {
        _currentResults = results;
      } else {
        _currentResults = [..._currentResults, ...results];
      }

      _currentOffset = _currentResults.length;
      _hasMore = results.length == _pageSize;
      _resultsController.add(List<Beneficiary>.unmodifiable(_currentResults));
    } catch (e) {
      if (mounted && requestId == _requestSequence) {
        _showSnack('❌ فشل تحميل البيانات: $e', false);
      }
    } finally {
      if (mounted && requestId == _requestSequence) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _reloadAfterDataChange() async {
    await _refreshAddresses();
    await _refreshList();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final normalized = value.trim();
      if (_search == normalized) return;
      setState(() => _search = normalized);
      _refreshList();
    });
  }

  Future<void> _importExcel() async {
    setState(() => _loading = true);
    try {
      final imported = await _excelService.importFromExcel();
      if (imported.isNotEmpty) {
        await _dbService.insertBeneficiaries(imported);
        _showSnack('✅ تم استيراد ${imported.length} مستفيد', true);
        await _reloadAfterDataChange();
      } else {
        _showSnack('⚠️ لم يتم استيراد أي بيانات، تأكد من تنسيق الأعمدة', false);
      }
    } catch (e) {
      _showSnack('❌ فشل الاستيراد: $e', false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _mergeDatabases() async {
    setState(() => _loading = true);
    try {
      final result = await _exportService.mergeDatabases();
      _showSnack(
        '✅ الدمج: ${result['imported']} جديد · ${result['updated']} محدث · ${result['skipped']} محصاة',
        true,
      );
      await _reloadAfterDataChange();
    } catch (e) {
      _showSnack('❌ فشل الدمج: $e', false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportResults() async {
    setState(() => _loading = true);
    try {
      final enumerated = await _dbService.getCompletedBeneficiaries();
      if (enumerated.isEmpty) {
        _showSnack('⚠️ لا توجد حالات محصاة للتصدير', false);
        return;
      }

      final filePath = await _excelService.exportToExcel(
        beneficiaries: enumerated,
        openAfterSave: true,
      );

      if (filePath != null) {
        _showSnack('✅ تم التصدير إلى: ${filePath.split('/').last}', true);
      }
    } catch (e) {
      _showSnack('❌ فشل التصدير: $e', false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnack(String msg, bool success) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: success ? Colors.green : Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showAbout() {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('ℹ️ حول البرنامج'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('📱 تطبيق إحصاء 2026'),
            Text('الإصدار: 2.1.0'),
            Text('المطور: حميتي نسيم - الحوضان'),
            Text('nas.hamiti89@gmail.com'),
            SizedBox(height: 8),
            Text('بحث سريع داخل SQLite مع فهارس، تحميل تدريجي، ومعالجة أكثر استقراراً للقوائم الكبيرة.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text(
          'إحصاء السكن الريفي 2026 | نسيم - الحوضان',
          style: TextStyle(fontSize: 15),
        ),
        // ← زر المزامنة — الإضافة الوحيدة على هذا الملف
        actions: [
          IconButton(
           icon: const Icon(Icons.sync, color: Colors.white),
           tooltip: 'المزامنة',
           onPressed: () async {
            await Navigator.push(
             context,
             MaterialPageRoute(builder: (_) => const SyncScreen()),
           );
           // بعد العودة من شاشة المزامنة، حدّث البيانات لرؤية المستجدات
            _reloadAfterDataChange();
           },
          ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '📋 غير المحصاة', icon: Icon(Icons.pending_actions)),
            Tab(text: '✅ المحصاة', icon: Icon(Icons.check_circle)),
          ],
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            child: Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _btn('📥 استيراد القائمة الأساسية', _importExcel, const Color(0xFF0D47A1)),
                      const SizedBox(width: 8),
                      _btn(
                        '📈 عرض الإحصائيات',
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const StatsScreen()),
                        ).then((_) => _refreshList()),
                        const Color(0xFFE67E22),
                      ),
                      const SizedBox(width: 8),
                      _btn('📤 تصدير JSON', () => _exportService.exportFullDatabase(), const Color(0xFF64748B)),
                      const SizedBox(width: 8),
                      _btn('🔄 دمج قواعد البيانات', _mergeDatabases, const Color(0xFF7C3AED)),
                      const SizedBox(width: 8),
                      _btn('📤 تصدير Excel', _exportResults, const Color(0xFF2E7D32)),
                      const SizedBox(width: 8),
                      _btn('🗜️ تصدير الصور ZIP', () => _exportService.exportImagesAsZip(), const Color(0xFF7C3AED)),
                      const SizedBox(width: 8),
                      _btn(
                        '👨‍💼 دمج بيانات الأعوان (مدير)',
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AdminMergeScreen()),
                        ),
                        const Color(0xFF9C27B0),
                      ),
                      const SizedBox(width: 8),
                      _btn(
                        '📊 إحصائيات متقدمة',
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AdvancedStatsScreen()),
                        ),
                        const Color(0xFF8E24AA),
                      ),
                      const SizedBox(width: 8),
                      _btn('ℹ️ حول البرنامج', _showAbout, const Color(0xFF6C757D)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: _selectedAddress,
                        hint: const Text('🔍 كل العناوين'),
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('كل العناوين')),
                          ..._addresses.map(
                            (address) => DropdownMenuItem<String?>(value: address, child: Text(address)),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() => _selectedAddress = value);
                          _refreshList();
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: '🔍 بحث سريع داخل القاعدة ببداية الاسم أو العنوان أو البرنامج...',
                      prefixIcon: Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                    onChanged: _onSearchChanged,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<List<Beneficiary>>(
              stream: _resultsController.stream,
              initialData: const [],
              builder: (context, snapshot) {
                final currentList = snapshot.data ?? const <Beneficiary>[];
                final isEmpty = currentList.isEmpty && !_loading;

                if (_loading && currentList.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline, size: 80, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text(
                          _currentTab == 0 ? 'لا توجد حالات غير محصاة' : 'لا توجد حالات محصاة',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Row(
                        children: [
                          Text(
                            'عدد النتائج المعروضة: ${currentList.length}',
                            style: const TextStyle(
                              color: Color(0xFF475569),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          if (_hasMore)
                            const Text(
                              'تحميل تدريجي',
                              style: TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: currentList.length + (_loadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= currentList.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }

                          final beneficiary = currentList[index];
                          return BeneficiaryCard(
                            beneficiary: beneficiary,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SurveyScreen(beneficiary: beneficiary),
                              ),
                            ).then((_) => _reloadAfterDataChange()),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _btn(String label, VoidCallback onTap, Color color) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}
