
import 'package:flutter/material.dart';
import '../models/beneficiary.dart';
import '../services/database_service.dart';
import '../services/excel_service.dart';
import '../services/export_service.dart';
import '../widgets/beneficiary_card.dart';
import 'survey_screen.dart';
import 'stats_screen.dart';
import 'admin_merge_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final _dbService = DatabaseService();
  final _excelService = ExcelService();
  final _exportService = ExportService();

  List<Beneficiary> _allBeneficiaries = [];
  List<Beneficiary> _pending = [];
  List<Beneficiary> _completed = [];
  List<Beneficiary> _filteredPending = [];
  List<Beneficiary> _filteredCompleted = [];

  String _search = '';
  String? _selectedAddress;
  List<String> _addresses = [];
  bool _loading = false;
  late TabController _tabController;
  int _currentTab = 0; // 0: pending, 1: completed

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() => _currentTab = _tabController.index);
      _applyFilter();
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final all = await _dbService.getAllBeneficiaries();
    _allBeneficiaries = all;
    _pending = all.where((b) => b.done != 1).toList();
    _completed = all.where((b) => b.done == 1).toList();

    final addresses = <String>{};
    for (var b in _pending) {
      if (b.address != null && b.address!.isNotEmpty) addresses.add(b.address!);
    }
    for (var b in _completed) {
      if (b.address != null && b.address!.isNotEmpty) addresses.add(b.address!);
    }
    _addresses = addresses.toList()..sort();

    _applyFilter();
    setState(() => _loading = false);
  }

  void _applyFilter() {
    final sourceList = _currentTab == 0 ? _pending : _completed;
    var filtered = List<Beneficiary>.from(sourceList);

    if (_search.isNotEmpty) {
      final lowerSearch = _search.toLowerCase();
      filtered = filtered.where((b) {
        return b.displayName.toLowerCase().contains(lowerSearch) ||
            (b.address?.toLowerCase().contains(lowerSearch) ?? false) ||
            (b.program?.toLowerCase().contains(lowerSearch) ?? false);
      }).toList();
    }

    if (_selectedAddress != null && _selectedAddress!.isNotEmpty) {
      filtered = filtered.where((b) => b.address == _selectedAddress).toList();
    }

    setState(() {
      if (_currentTab == 0) {
        _filteredPending = filtered;
      } else {
        _filteredCompleted = filtered;
      }
    });
  }

  Future<void> _importExcel() async {
    setState(() => _loading = true);
    try {
      final imported = await _excelService.importFromExcel();
      if (imported.isNotEmpty) {
        await _dbService.insertBeneficiaries(imported);
        _showSnack('✅ تم استيراد ${imported.length} مستفيد', true);
        await _loadData();
      } else {
        _showSnack('⚠️ لم يتم استيراد أي بيانات (تأكد من تنسيق الأعمدة)', false);
      }
    } catch (e) {
      _showSnack('❌ فشل الاستيراد: $e', false);
    }
    setState(() => _loading = false);
  }

  Future<void> _mergeDatabases() async {
   setState(() => _loading = true);
   try {
     final result = await _exportService.mergeDatabases();
     _showSnack(
      '✅ الدمج: ${result['imported']} جديد · ${result['updated']} محدث · ${result['skipped']} مكتمل',
      true,
     );
     await _loadData();
   } catch (e) {
    _showSnack('❌ فشل الدمج: $e', false);
   }
   setState(() => _loading = false);
  }

  Future<void> _exportResults() async {
    setState(() => _loading = true);
    try {
      final completed = await _dbService.getCompletedBeneficiaries();
      if (completed.isEmpty) {
        _showSnack('⚠️ لا يوجد مستفيدين مكتملين للتصدير', false);
        setState(() => _loading = false);
        return;
      }
      final filePath = await _excelService.exportToExcel(
        beneficiaries: completed,
        openAfterSave: true,
      );
      if (filePath != null) {
        _showSnack('✅ تم التصدير إلى: ${filePath.split('/').last}', true);
      }
    } catch (e) {
      _showSnack('❌ فشل التصدير: $e', false);
    }
    setState(() => _loading = false);
  }

  void _showSnack(String msg, bool success) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? Colors.green : Colors.red,
      behavior: SnackBarBehavior.floating,
    ));
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
            Text('الإصدار: 2.0.0'),
            Text('المطور: حميتي نسيم - الحوضان'),
            Text('nas.hamiti89@gmail.com'),
            SizedBox(height: 8),
            Text('يتيح إدارة المستفيدين، الإحصائيات، وتصدير التقارير'),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('حسناً'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentList = _currentTab == 0 ? _filteredPending : _filteredCompleted;
    final isEmpty = currentList.isEmpty && !_loading;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('إحصاء السكن الريفي 2026 | نسيم - الحوضان', style: TextStyle(fontSize: 15)),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '📋 غير مكتملين', icon: Icon(Icons.pending_actions)),
            Tab(text: '✅ مكتملين', icon: Icon(Icons.check_circle)),
          ],
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
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
  _btn('📈 عرض الإحصائيات', () => Navigator.push(context, MaterialPageRoute(builder: (_) => StatsScreen())).then((_) => _loadData()), const Color(0xFFE67E22)),
  const SizedBox(width: 8),
  _btn('📤 تصدير JSON', () => _exportService.exportFullDatabase(), const Color(0xFF64748B)),
  const SizedBox(width: 8),
  _btn('🔄 دمج قواعد البيانات', _mergeDatabases, const Color(0xFF7C3AED)),
  const SizedBox(width: 8),
  _btn('📤 تصدير Excel', _exportResults, const Color(0xFF2E7D32)),
  const SizedBox(width: 8),
  _btn('🗜️ تصدير الصور ZIP', () => _exportService.exportImagesAsZip(), const Color(0xFF7C3AED)),
  const SizedBox(width: 8),
  _btn('👨‍💼 دمج بيانات الأعوان (مدير)', () {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminMergeScreen()));
  }, const Color(0xFF9C27B0)),
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
                            child: DropdownButton<String>(
                              value: _selectedAddress,
                              hint: const Text('🔍 كل العناوين'),
                              isExpanded: true,
                              items: [
                                const DropdownMenuItem(value: null, child: Text('كل العناوين')),
                                ..._addresses.map((a) => DropdownMenuItem(value: a, child: Text(a))),
                              ],
                              onChanged: (v) {
                                setState(() {
                                  _selectedAddress = v;
                                  _applyFilter();
                                });
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          decoration: const InputDecoration(
                            hintText: '🔍 ابحث بالاسم أو العنوان أو البرنامج...',
                            prefixIcon: Icon(Icons.search),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                          ),
                          onChanged: (v) {
                            setState(() {
                              _search = v;
                              _applyFilter();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.people_outline, size: 80, color: Colors.grey.shade300),
                              const SizedBox(height: 16),
                              Text(
                                _currentTab == 0 ? 'لا يوجد مستفيدين غير مكتملين' : 'لا يوجد مستفيدين مكتملين',
                                style: TextStyle(color: Colors.grey.shade500),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: currentList.length,
                          itemBuilder: (c, i) => BeneficiaryCard(
                            beneficiary: currentList[i],
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => SurveyScreen(beneficiary: currentList[i])),
                            ).then((_) => _loadData()),
                          ),
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
