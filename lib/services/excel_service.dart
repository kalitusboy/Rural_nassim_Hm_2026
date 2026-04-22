import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/beneficiary.dart';

class ExcelService {
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
      
      final headers = <String>[];
      for (var cell in sheet.rows.first) {
        headers.add(cell?.value?.toString() ?? '');
      }
      
      for (var i = 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        final rowData = <String, dynamic>{};
        for (var j = 0; j < headers.length && j < row.length; j++) {
          rowData[headers[j]] = row[j]?.value?.toString() ?? '';
        }
        final b = Beneficiary.fromExcelRow(rowData);
        if (b.firstName.isNotEmpty || b.lastName.isNotEmpty) {
          beneficiaries.add(b);
        }
      }
    }
    return beneficiaries;
  }

  Future<String?> exportToExcel({required List<Beneficiary> beneficiaries}) async {
    final excel = Excel.createExcel();
    final sheet = excel['المستفيدين'];
    final headers = ['الاسم الأول', 'اللقب', 'تاريخ الميلاد', 'مكان الميلاد', 'العنوان', 'البرنامج', 'كهرباء', 'غاز', 'مياه', 'تطهير', 'الحالة'];
    for (var i = 0; i < headers.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = TextCellValue(headers[i]);
    }
    for (var i = 0; i < beneficiaries.length; i++) {
      final b = beneficiaries[i];
      final row = i + 1;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue(b.firstName);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = TextCellValue(b.lastName);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value = TextCellValue(b.birthDate ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value = TextCellValue(b.birthPlace ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).value = TextCellValue(b.address ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row)).value = TextCellValue(b.program ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row)).value = IntCellValue(b.electricity);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: row)).value = IntCellValue(b.gas);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: row)).value = IntCellValue(b.water);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: row)).value = IntCellValue(b.sewage);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: row)).value = TextCellValue(b.status);
    }
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/تصدير_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    await File(filePath).writeAsBytes(excel.encode()!);
    return filePath;
  }
}
