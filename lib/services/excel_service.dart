
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:open_file/open_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/beneficiary.dart';

class ExcelService {
  
  // ====================== الاستيراد من Excel ======================
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
      
      for (var i = 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        
        final fullName = _getCellValue(row, 0);
        final program = _getCellValue(row, 1);
        final address = _getCellValue(row, 2);
        final birthFull = _getCellValue(row, 3);
        final birthPlace = _getCellValue(row, 4);
        
        if (fullName.isEmpty) continue;
        
        final nameParts = _parseFullName(fullName);
        final birthDate = _extractBirthDate(birthFull);
        final finalBirthPlace = birthPlace.isNotEmpty ? birthPlace : _extractBirthPlace(birthFull);
        
        final beneficiary = Beneficiary(
          firstName: nameParts['first'] ?? '',
          lastName: nameParts['last'] ?? '',
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
        
        if (beneficiary.firstName.isNotEmpty || beneficiary.lastName.isNotEmpty) {
          beneficiaries.add(beneficiary);
        }
      }
    }
    
    return beneficiaries;
  }

  String _getCellValue(List<Data?> row, int index) {
    if (index >= row.length) return '';
    final cell = row[index];
    if (cell == null) return '';
    return cell.value.toString().trim();
  }

  Map<String, String> _parseFullName(String fullName) {
    fullName = fullName.trim();
    if (fullName.isEmpty) return {'first': '', 'last': ''};
    final parts = fullName.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return {'first': parts[0], 'last': ''};
    } else if (parts.length == 2) {
      return {'first': parts[0], 'last': parts[1]};
    } else {
      return {'first': parts[0], 'last': parts.sublist(1).join(' ')};
    }
  }

  String _extractBirthDate(String text) {
    if (text.isEmpty) return '';
    text = text.trim();
    
    final datePattern1 = RegExp(r'(\d{4})[/-](\d{1,2})[/-](\d{1,2})');
    final match1 = datePattern1.firstMatch(text);
    if (match1 != null) {
      return '${match1.group(1)}-${match1.group(2)?.padLeft(2, '0')}-${match1.group(3)?.padLeft(2, '0')}';
    }
    
    final datePattern2 = RegExp(r'(\d{1,2})[/-](\d{1,2})[/-](\d{4})');
    final match2 = datePattern2.firstMatch(text);
    if (match2 != null) {
      return '${match2.group(3)}-${match2.group(2)?.padLeft(2, '0')}-${match2.group(1)?.padLeft(2, '0')}';
    }
    
    final yearPattern = RegExp(r'عام\s*(\d{4})');
    final yearMatch = yearPattern.firstMatch(text);
    if (yearMatch != null) {
      return '${yearMatch.group(1)}-01-01';
    }
    
    final yearOnly = RegExp(r'^(\d{4})$');
    final yearOnlyMatch = yearOnly.firstMatch(text);
    if (yearOnlyMatch != null) {
      return '${yearOnlyMatch.group(1)}-01-01';
    }
    
    final anyDate = RegExp(r'(\d{1,2})[/-](\d{1,2})[/-](\d{4})|(\d{4})[/-](\d{1,2})[/-](\d{1,2})');
    final anyMatch = anyDate.firstMatch(text);
    if (anyMatch != null) {
      return anyMatch.group(0)!.replaceAll('/', '-');
    }
    
    return text.length > 50 ? text.substring(0, 50) : text;
  }

  String _extractBirthPlace(String text) {
    if (text.isEmpty) return '';
    String place = text;
    place = place.replaceAll(RegExp(r'\d{4}[/-]\d{1,2}[/-]\d{1,2}'), '');
    place = place.replaceAll(RegExp(r'\d{1,2}[/-]\d{1,2}[/-]\d{4}'), '');
    place = place.replaceAll(RegExp(r'عام\s*\d{4}'), '');
    place = place.replaceAll(RegExp(r'\d{4}'), '');
    place = place.trim();
    place = place.replaceAll(RegExp(r'^[,\s]+|[,\s]+$'), '');
    return place.isNotEmpty ? place : '';
  }

  // ====================== التصدير العادي (نتائج المستفيدين) ======================
  Future<String?> exportToExcel({
    required List<Beneficiary> beneficiaries,
    String? fileName,
    bool openAfterSave = true,
  }) async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['المستفيدين'];
      
      final headers = [
        'الإسم واللقب', 'البرنامج', 'العنوان', 'تاريخ الميلاد', 'مكان الميلاد',
        'كهرباء', 'غاز', 'مياه', 'تطهير', 'الحالة',
      ];
      
      for (var i = 0; i < headers.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
            .value = TextCellValue(headers[i]);
      }
      
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
      
      final directory = await getApplicationDocumentsDirectory();
      final name = fileName ?? 'تصدير_المستفيدين_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final filePath = '${directory.path}/$name';
      
      final file = File(filePath);
      await file.writeAsBytes(excel.encode()!);
      
      if (openAfterSave) {
        await OpenFile.open(filePath);
      }
      return filePath;
    } catch (e) {
      print('خطأ في تصدير Excel: $e');
      rethrow;
    }
  }

  // ====================== تصدير الإحصائيات (جدولين) ======================
  Future<String?> exportStatisticsToFile({
    required String filePath,
    required List<String> mainHeaders,
    required List<List<dynamic>> mainRows,
    required List<String> detailHeaders,
    required List<List<dynamic>> detailRows,
    bool openAfterSave = true,
  }) async {
    try {
      final excel = Excel.createExcel();

      // الورقة الأولى: الإحصائيات العامة
      final mainSheet = excel['الإحصائيات العامة'];
      _writeSheet(mainSheet, mainHeaders, mainRows);

      // الورقة الثانية: تفاصيل المنتهية والمشغولة
      final detailSheet = excel['تفاصيل المنتهية والمشغولة'];
      if (detailRows.isNotEmpty) {
        _writeSheet(detailSheet, detailHeaders, detailRows);
      } else {
        detailSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
            .value = TextCellValue('لا توجد بيانات');
      }

      final file = File(filePath);
      await file.writeAsBytes(excel.encode()!);
      
      if (openAfterSave) {
        await OpenFile.open(filePath);
      }
      return filePath;
    } catch (e) {
      print('خطأ في تصدير التقرير: $e');
      rethrow;
    }
  }

  void _writeSheet(Sheet sheet, List<String> headers, List<List<dynamic>> rows) {
    // كتابة الرأس
    for (int col = 0; col < headers.length; col++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0))
          .value = TextCellValue(headers[col]);
    }

    // كتابة الصفوف
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      final rowIndex = i + 1;
      for (int col = 0; col < row.length; col++) {
        final value = row[col];
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIndex));
        if (value == null) {
          cell.value = TextCellValue('');
        } else if (value is int) {
          cell.value = IntCellValue(value);
        } else {
          cell.value = TextCellValue(value.toString());
        }
      }
    }
  }
}
