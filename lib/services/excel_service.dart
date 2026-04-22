import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/beneficiary.dart';

class ExcelService {
  
  // استيراد من Excel - متوافق مع شكل ملف rural_depuis_2002.xlsx
  Future<List<Beneficiary>> importFromExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv'],
    );
    
    if (result == null || result.files.isEmpty) return [];
    
    final file = result.files.first;
    List<int> bytes;
    
    if (file.bytes != null) {
      bytes = file.bytes!;
    } else {
      bytes = await File(file.path!).readAsBytes();
    }
    
    final excel = Excel.decodeBytes(bytes);
    final beneficiaries = <Beneficiary>[];
    
    for (var table in excel.tables.keys) {
      final sheet = excel.tables[table];
      if (sheet == null) continue;
      
      // تخطي الصف الأول (العناوين) والبدء من الصف الثاني
      for (var i = 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        
        // استخراج البيانات من الأعمدة
        // العمود 0: الإسم واللقب
        // العمود 1: البرنامج
        // العمود 2: العنوان (في ملفك العمود الثالث هو العنوان)
        // العمود 3: تاريخ ومكان الميلاد (نص كامل)
        // العمود 4: مكان الميلاد (مكرر)
        
        final fullName = _getCellValue(row, 0);
        final program = _getCellValue(row, 1);
        final address = _getCellValue(row, 2);
        final birthFull = _getCellValue(row, 3); // تاريخ ومكان الميلاد معاً
        final birthPlace = _getCellValue(row, 4); // مكان الميلاد
        
        // تخطي الصفوف الفارغة
        if (fullName.isEmpty) continue;
        
        // تحليل الاسم الكامل إلى اسم أول ولقب
        final nameParts = _parseFullName(fullName);
        
        // تحليل تاريخ الميلاد من النص الكامل
        final birthDate = _extractBirthDate(birthFull);
        
        // إذا كان مكان الميلاد فارغاً، نستخدم العمود الرابع أو نستخرجه من النص
        String finalBirthPlace = birthPlace.isNotEmpty ? birthPlace : _extractBirthPlace(birthFull);
        
        final beneficiary = Beneficiary(
          firstName: nameParts.first,
          lastName: nameParts.last,
          name: fullName,
          birthDate: birthDate,
          birthPlace: finalBirthPlace,
          address: address.isNotEmpty ? address : null,
          program: program.isNotEmpty ? program : 'عام',
          done: 0,
          electricity: 0,
          gas: 0,
          water: 0,
          sewage: 0,
          status: 'في طور الانجاز',
        );
        
        // التأكد من وجود بيانات أساسية
        if (beneficiary.firstName.isNotEmpty || beneficiary.lastName.isNotEmpty) {
          beneficiaries.add(beneficiary);
        }
      }
    }
    
    return beneficiaries;
  }

  // الحصول على قيمة الخلية بأمان
  String _getCellValue(List<Data?> row, int index) {
    if (index >= row.length) return '';
    final cell = row[index];
    if (cell == null) return '';
    return cell.value.toString().trim();
  }

  // تحليل الاسم الكامل إلى اسم أول ولقب
  Map<String, String> _parseFullName(String fullName) {
    // تنظيف النص
    fullName = fullName.trim();
    
    // إذا كان الاسم فارغاً
    if (fullName.isEmpty) {
      return {'first': '', 'last': ''};
    }
    
    // تقسيم الاسم إلى أجزاء
    final parts = fullName.split(RegExp(r'\s+'));
    
    if (parts.length == 1) {
      return {'first': parts[0], 'last': ''};
    } else if (parts.length == 2) {
      return {'first': parts[0], 'last': parts[1]};
    } else {
      // إذا كان الاسم أكثر من كلمتين، الكلمة الأولى هي الاسم الأول والباقي لقب
      final firstName = parts[0];
      final lastName = parts.sublist(1).join(' ');
      return {'first': firstName, 'last': lastName};
    }
  }

  // استخراج تاريخ الميلاد من النص
  String _extractBirthDate(String text) {
    if (text.isEmpty) return '';
    
    // تنظيف النص
    text = text.trim();
    
    // البحث عن أنماط التاريخ
    // نمط: YYYY-MM-DD أو YYYY/MM/DD
    final datePattern1 = RegExp(r'(\d{4})[/-](\d{1,2})[/-](\d{1,2})');
    final match1 = datePattern1.firstMatch(text);
    if (match1 != null) {
      return '${match1.group(1)}-${match1.group(2)?.padLeft(2, '0')}-${match1.group(3)?.padLeft(2, '0')}';
    }
    
    // نمط: DD/MM/YYYY
    final datePattern2 = RegExp(r'(\d{1,2})[/-](\d{1,2})[/-](\d{4})');
    final match2 = datePattern2.firstMatch(text);
    if (match2 != null) {
      return '${match2.group(3)}-${match2.group(2)?.padLeft(2, '0')}-${match2.group(1)?.padLeft(2, '0')}';
    }
    
    // نمط: عام YYYY
    final yearPattern = RegExp(r'عام\s*(\d{4})');
    final yearMatch = yearPattern.firstMatch(text);
    if (yearMatch != null) {
      return '${yearMatch.group(1)}-01-01';
    }
    
    // نمط: YYYY فقط
    final yearOnly = RegExp(r'^(\d{4})$');
    final yearOnlyMatch = yearOnly.firstMatch(text);
    if (yearOnlyMatch != null) {
      return '${yearOnlyMatch.group(1)}-01-01';
    }
    
    // إذا كان النص يحتوي على تاريخ بأي صيغة
    final anyDate = RegExp(r'(\d{1,2})[/-](\d{1,2})[/-](\d{4})|(\d{4})[/-](\d{1,2})[/-](\d{1,2})');
    final anyMatch = anyDate.firstMatch(text);
    if (anyMatch != null) {
      return anyMatch.group(0)!.replaceAll('/', '-');
    }
    
    // إذا لم نجد تاريخ، نرجع النص كما هو
    return text.length > 50 ? text.substring(0, 50) : text;
  }

  // استخراج مكان الميلاد من النص
  String _extractBirthPlace(String text) {
    if (text.isEmpty) return '';
    
    // إزالة التاريخ من النص للحصول على المكان فقط
    String place = text;
    
    // إزالة أنماط التاريخ
    place = place.replaceAll(RegExp(r'\d{4}[/-]\d{1,2}[/-]\d{1,2}'), '');
    place = place.replaceAll(RegExp(r'\d{1,2}[/-]\d{1,2}[/-]\d{4}'), '');
    place = place.replaceAll(RegExp(r'عام\s*\d{4}'), '');
    place = place.replaceAll(RegExp(r'\d{4}'), '');
    
    // تنظيف النص المتبقي
    place = place.trim();
    
    // إزالة المسافات الزائدة والفواصل
    place = place.replaceAll(RegExp(r'^[,\s]+|[,\s]+$'), '');
    
    return place.isNotEmpty ? place : '';
  }

  // تصدير إلى Excel
  Future<String?> exportToExcel({
    required List<Beneficiary> beneficiaries,
    String? fileName,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['المستفيدين'];
    
    // إضافة العناوين
    final headers = [
      'الإسم واللقب',
      'البرنامج',
      'العنوان',
      'تاريخ الميلاد',
      'مكان الميلاد',
      'كهرباء',
      'غاز',
      'مياه',
      'تطهير',
      'الحالة',
    ];
    
    for (var i = 0; i < headers.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = TextCellValue(headers[i]);
    }
    
    // إضافة البيانات
    for (var i = 0; i < beneficiaries.length; i++) {
      final b = beneficiaries[i];
      final row = i + 1;
      
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = TextCellValue(b.displayName);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
          .value = TextCellValue(b.program ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
          .value = TextCellValue(b.address ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
          .value = TextCellValue(b.birthDate ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
          .value = TextCellValue(b.birthPlace ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row))
          .value = IntCellValue(b.electricity);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row))
          .value = IntCellValue(b.gas);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: row))
          .value = IntCellValue(b.water);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: row))
          .value = IntCellValue(b.sewage);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: row))
          .value = TextCellValue(b.status);
    }
    
    // حفظ الملف
    final directory = await getApplicationDocumentsDirectory();
    final name = fileName ?? 'تصدير_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    final filePath = '${directory.path}/$name';
    
    final file = File(filePath);
    await file.writeAsBytes(excel.encode()!);
    
    return filePath;
  }

  // تصدير الإحصائيات إلى Excel
  Future<String?> exportStatisticsToExcel(Map<String, dynamic> stats) async {
    final excel = Excel.createExcel();
    final sheet = excel['الإحصائيات'];
    
    final programStats = stats['programStats'] as List? ?? [];
    
    // العناوين
    final headers = ['البرنامج', 'الحصة', 'منجزة', 'نسبة الإنجاز', 'في طور', 'أعمدة', 'غير مشغولة', 'مشغولة', 'كهرباء', 'غاز', 'مياه', 'تطهير'];
    for (var i = 0; i < headers.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = TextCellValue(headers[i]);
    }
    
    // البيانات
    for (var i = 0; i < programStats.length; i++) {
      final p = programStats[i] as Map;
      final row = i + 1;
      
      final total = p['total'] as int? ?? 0;
      final done = p['done'] as int? ?? 0;
      final progress = total > 0 ? (done / total * 100).round() : 0;
      
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = TextCellValue(p['program']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
          .value = IntCellValue(total);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
          .value = IntCellValue(done);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
          .value = TextCellValue('$progress%');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
          .value = IntCellValue(p['status1'] as int? ?? 0);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row))
          .value = IntCellValue(p['status2'] as int? ?? 0);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row))
          .value = IntCellValue(p['status3'] as int? ?? 0);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: row))
          .value = IntCellValue(p['status4'] as int? ?? 0);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: row))
          .value = IntCellValue(p['elec'] as int? ?? 0);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: row))
          .value = IntCellValue(p['gas'] as int? ?? 0);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: row))
          .value = IntCellValue(p['water'] as int? ?? 0);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: row))
          .value = IntCellValue(p['sew'] as int? ?? 0);
    }
    
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/تقرير_إحصائي_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    
    final file = File(filePath);
    await file.writeAsBytes(excel.encode()!);
    
    return filePath;
  }
}
