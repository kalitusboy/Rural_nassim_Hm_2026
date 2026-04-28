import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// بيانات المحضر
class ReportData {
  final String wilaya;
  final String daira;
  final String baladia;
  final String program;
  final String place;
  final String date;
  final String reportNumber;
  final int quota;
  final int inProgress;
  final int pillars;
  final int finishedNotOccupied;
  final int finishedOccupied;
  final int elecOcc;
  final int gasOcc;
  final int waterOcc;
  final int sewOcc;
  final int fullyConnected;

  const ReportData({
    required this.wilaya,
    required this.daira,
    required this.baladia,
    required this.program,
    required this.place,
    required this.date,
    required this.reportNumber,
    required this.quota,
    required this.inProgress,
    required this.pillars,
    required this.finishedNotOccupied,
    required this.finishedOccupied,
    required this.elecOcc,
    required this.gasOcc,
    required this.waterOcc,
    required this.sewOcc,
    required this.fullyConnected,
  });
}

/// خدمة إنشاء المحاضر بصيغة Word (.docx)
class ReportService {
  static final ReportService _i = ReportService._();
  factory ReportService() => _i;
  ReportService._();

  // ──────────────────────────────────────────────
  // إنشاء ملف DOCX وحفظه
  // ──────────────────────────────────────────────
  Future<String> generateDocx(ReportData d) async {
    final archive = Archive();

    // دالة مساعدة تحسب الحجم الصحيح تلقائياً
    void addXml(String path, String content) {
      final bytes = _utf8(content);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    // ① [Content_Types].xml
    addXml('[Content_Types].xml', _contentTypes());

    // ② _rels/.rels
    addXml('_rels/.rels', _rootRels());

    // ③ word/document.xml (المحتوى الرئيسي)
    addXml('word/document.xml', _buildDocument(d));

    // ④ word/_rels/document.xml.rels
    addXml('word/_rels/document.xml.rels', _documentRels());

    // ⑤ word/styles.xml
    addXml('word/styles.xml', _styles());

    // ⑥ word/settings.xml
    addXml('word/settings.xml', _settings());

    // حفظ الملف
    final bytes = ZipEncoder().encode(archive)!;
    final dl = Directory('/storage/emulated/0/Download/محاضر_الإحصاء');
    if (!await dl.exists()) await dl.create(recursive: true);

    final safeProg = d.program
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(' ', '_');
    final fname = 'محضر_${safeProg}_${d.reportNumber.replaceAll('/', '-')}.docx';
    final file = File(p.join(dl.path, fname));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  // ──────────────────────────────────────────────
  // تصدير صور برنامج كـ ZIP
  // ──────────────────────────────────────────────
  Future<String> exportPhotosZip(
      String program, List<Map<String, String>> images) async {
    final archive = Archive();
    int count = 0;

    for (final img in images) {
      final path = img['path'] ?? '';
      final name = img['name'] ?? '';
      if (path.isEmpty || name.isEmpty) continue;
      final file = File(path);
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
      count++;
    }

    if (count == 0) throw Exception('لا توجد صور للتصدير');

    final zipBytes = ZipEncoder().encode(archive)!;
    final dl = Directory('/storage/emulated/0/Download/محاضر_الإحصاء');
    if (!await dl.exists()) await dl.create(recursive: true);

    final safeProg = program
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(' ', '_');
    final fname = 'صور_${safeProg}_$count.zip';
    final file = File(p.join(dl.path, fname));
    await file.writeAsBytes(zipBytes);
    return file.path;
  }

  // ──────────────────────────────────────────────
  // بناء document.xml — قلب المحضر
  // ──────────────────────────────────────────────
  String _buildDocument(ReportData d) {
    final rows = StringBuffer();

    // دالة مساعدة لصف جدول
    void addRow(String label, String value, {bool bold = false}) {
      rows.write('''
<w:tr>
  <w:tc>
    <w:tcPr><w:tcW w:w="4500" w:type="dxa"/>
      <w:shd w:val="clear" w:color="auto" w:fill="E8F0FE"/>
    </w:tcPr>
    <w:p><w:pPr><w:jc w:val="right"/></w:pPr>
      <w:r><w:rPr><w:b/><w:rtl/></w:rPr><w:t xml:space="preserve">$label</w:t></w:r>
    </w:p>
  </w:tc>
  <w:tc>
    <w:tcPr><w:tcW w:w="4500" w:type="dxa"/></w:tcPr>
    <w:p><w:pPr><w:jc w:val="center"/></w:pPr>
      <w:r><w:rPr>${bold ? '<w:b/>' : ''}<w:rtl/></w:rPr>
        <w:t xml:space="preserve">[ ${_x(value)} ]</w:t>
      </w:r>
    </w:p>
  </w:tc>
</w:tr>''');
    }

    addRow('سكنات في طور الإنجاز (أشغال كبرى)', d.inProgress.toString());
    addRow('سكنات على مستوى الأعمدة', d.pillars.toString());
    addRow('سكنات منتهية غير مشغولة', d.finishedNotOccupied.toString());
    addRow('سكنات منتهية ومشغولة', d.finishedOccupied.toString(), bold: true);

    final netRows = StringBuffer();
    void addNet(String label, String val) {
      netRows.write('''
<w:tr>
  <w:tc>
    <w:tcPr><w:tcW w:w="4500" w:type="dxa"/>
      <w:shd w:val="clear" w:color="auto" w:fill="E8F5E9"/>
    </w:tcPr>
    <w:p><w:pPr><w:jc w:val="right"/></w:pPr>
      <w:r><w:rPr><w:b/><w:rtl/></w:rPr><w:t xml:space="preserve">$label</w:t></w:r>
    </w:p>
  </w:tc>
  <w:tc>
    <w:tcPr><w:tcW w:w="4500" w:type="dxa"/></w:tcPr>
    <w:p><w:pPr><w:jc w:val="center"/></w:pPr>
      <w:r><w:rPr><w:rtl/></w:rPr><w:t xml:space="preserve">[ $val ]</w:t></w:r>
    </w:p>
  </w:tc>
</w:tr>''');
    }

    addNet('مربوطة بشبكة الكهرباء', d.elecOcc.toString());
    addNet('مربوطة بشبكة الغاز', d.gasOcc.toString());
    addNet('مربوطة بشبكة المياه', d.waterOcc.toString());
    addNet('مربوطة بشبكة التطهير', d.sewOcc.toString());
    addNet('مربوطة بكافة الشبكات', d.fullyConnected.toString());

    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:wpc="http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas"
  xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
  xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml"
  xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<w:body>

<!-- ═══════════════════════════════ الترويسة ═══════════════════════════════ -->
<w:p>
  <w:pPr><w:jc w:val="center"/><w:spacing w:before="0" w:after="80"/></w:pPr>
  <w:r><w:rPr><w:b/><w:sz w:val="28"/><w:rtl/></w:rPr>
    <w:t>الجمهورية الجزائرية الديمقراطية الشعبية</w:t>
  </w:r>
</w:p>

<w:p>
  <w:pPr><w:jc w:val="center"/><w:spacing w:before="0" w:after="80"/></w:pPr>
  <w:r><w:rPr><w:b/><w:sz w:val="24"/><w:rtl/></w:rPr>
    <w:t xml:space="preserve">ولاية: ${_x(d.wilaya)}          دائرة: ${_x(d.daira)}          بلدية: ${_x(d.baladia)}</w:t>
  </w:r>
</w:p>

<!-- فاصل -->
<w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" w:color="1A237E"/></w:pBdr></w:pPr></w:p>

<!-- ═══════════════════════════════ العنوان ════════════════════════════════ -->
<w:p>
  <w:pPr><w:jc w:val="center"/><w:spacing w:before="120" w:after="80"/></w:pPr>
  <w:r><w:rPr><w:b/><w:sz w:val="32"/><w:color w:val="1A237E"/><w:rtl/></w:rPr>
    <w:t>محضر معاينة ميدانية وإحصاء السكن الريفي</w:t>
  </w:r>
</w:p>

<w:p>
  <w:pPr><w:jc w:val="center"/><w:spacing w:before="0" w:after="120"/></w:pPr>
  <w:r><w:rPr><w:b/><w:sz w:val="24"/><w:color w:val="B71C1C"/><w:rtl/></w:rPr>
    <w:t xml:space="preserve">رقم: ${_x(d.reportNumber)}/2026</w:t>
  </w:r>
</w:p>

<!-- ════════════════════════ ديباجة اللجنة ════════════════════════════════ -->
<w:p>
  <w:pPr><w:jc w:val="both"/><w:spacing w:before="80" w:after="80"/></w:pPr>
  <w:r><w:rPr><w:sz w:val="22"/><w:rtl/></w:rPr>
    <w:t xml:space="preserve">في يوم ${_x(d.date)}، قامت اللجنة المكلفة بإحصاء ومتابعة السكن الريفي، والمشكلة من:</w:t>
  </w:r>
</w:p>

<w:p><w:pPr><w:jc w:val="right"/><w:ind w:right="720"/></w:pPr>
  <w:r><w:rPr><w:sz w:val="22"/><w:rtl/></w:rPr>
    <w:t>السيدة: رئيسة فرع السكن للدائرة</w:t>
  </w:r>
</w:p>
<w:p><w:pPr><w:jc w:val="right"/><w:ind w:right="720"/></w:pPr>
  <w:r><w:rPr><w:sz w:val="22"/><w:rtl/></w:rPr>
    <w:t>السيد: المكلف بالبناء الريفي على مستوى الدائرة</w:t>
  </w:r>
</w:p>
<w:p><w:pPr><w:jc w:val="right"/><w:ind w:right="720"/></w:pPr>
  <w:r><w:rPr><w:sz w:val="22"/><w:rtl/></w:rPr>
    <w:t>السيد: المكلف بالبناء الريفي على مستوى البلدية</w:t>
  </w:r>
</w:p>

<w:p>
  <w:pPr><w:jc w:val="both"/><w:spacing w:before="80" w:after="160"/></w:pPr>
  <w:r><w:rPr><w:sz w:val="22"/><w:rtl/></w:rPr>
    <w:t xml:space="preserve">بتنفيذ معاينة ميدانية وإحصاء شامل للسكنات الريفية ضمن برنامج: </w:t>
  </w:r>
  <w:r><w:rPr><w:b/><w:sz w:val="22"/><w:color w:val="1A237E"/><w:rtl/></w:rPr>
    <w:t>${_x(d.program)}</w:t>
  </w:r>
  <w:r><w:rPr><w:sz w:val="22"/><w:rtl/></w:rPr>
    <w:t>.</w:t>
  </w:r>
</w:p>

<w:p>
  <w:pPr><w:jc w:val="both"/><w:spacing w:before="0" w:after="160"/></w:pPr>
  <w:r><w:rPr><w:sz w:val="22"/><w:rtl/></w:rPr>
    <w:t>بعد إتمام عملية المعاينة والجرد الدقيق، خلصت اللجنة إلى ما يلي:</w:t>
  </w:r>
</w:p>

<!-- ════════════════════════ أولاً ════════════════════════════════════════ -->
<w:p>
  <w:pPr><w:jc w:val="right"/><w:spacing w:before="120" w:after="80"/></w:pPr>
  <w:r><w:rPr><w:b/><w:sz w:val="26"/><w:color w:val="1A237E"/><w:rtl/></w:rPr>
    <w:t>أولاً: معلومات البرنامج</w:t>
  </w:r>
</w:p>

<w:tbl>
  <w:tblPr>
    <w:tblW w:w="9000" w:type="dxa"/>
    <w:jc w:val="center"/>
    <w:tblBorders>
      <w:top w:val="single" w:sz="4" w:color="CCCCCC"/>
      <w:left w:val="single" w:sz="4" w:color="CCCCCC"/>
      <w:bottom w:val="single" w:sz="4" w:color="CCCCCC"/>
      <w:right w:val="single" w:sz="4" w:color="CCCCCC"/>
      <w:insideH w:val="single" w:sz="4" w:color="CCCCCC"/>
      <w:insideV w:val="single" w:sz="4" w:color="CCCCCC"/>
    </w:tblBorders>
    <w:tblCellMar>
      <w:top w:w="80" w:type="dxa"/>
      <w:left w:w="120" w:type="dxa"/>
      <w:bottom w:w="80" w:type="dxa"/>
      <w:right w:w="120" w:type="dxa"/>
    </w:tblCellMar>
  </w:tblPr>
  <w:tblGrid>
    <w:gridCol w:w="4500"/>
    <w:gridCol w:w="4500"/>
  </w:tblGrid>
  <w:tr>
    <w:tc>
      <w:tcPr><w:tcW w:w="4500" w:type="dxa"/>
        <w:shd w:val="clear" w:color="auto" w:fill="1A237E"/>
      </w:tcPr>
      <w:p><w:pPr><w:jc w:val="center"/></w:pPr>
        <w:r><w:rPr><w:b/><w:color w:val="FFFFFF"/><w:rtl/></w:rPr>
          <w:t>البيان</w:t></w:r>
      </w:p>
    </w:tc>
    <w:tc>
      <w:tcPr><w:tcW w:w="4500" w:type="dxa"/>
        <w:shd w:val="clear" w:color="auto" w:fill="1A237E"/>
      </w:tcPr>
      <w:p><w:pPr><w:jc w:val="center"/></w:pPr>
        <w:r><w:rPr><w:b/><w:color w:val="FFFFFF"/><w:rtl/></w:rPr>
          <w:t>القيمة</w:t></w:r>
      </w:p>
    </w:tc>
  </w:tr>
  <w:tr>
    <w:tc>
      <w:tcPr><w:tcW w:w="4500" w:type="dxa"/>
        <w:shd w:val="clear" w:color="auto" w:fill="E8F0FE"/>
      </w:tcPr>
      <w:p><w:pPr><w:jc w:val="right"/></w:pPr>
        <w:r><w:rPr><w:b/><w:rtl/></w:rPr><w:t>تسمية البرنامج</w:t></w:r>
      </w:p>
    </w:tc>
    <w:tc>
      <w:tcPr><w:tcW w:w="4500" w:type="dxa"/></w:tcPr>
      <w:p><w:pPr><w:jc w:val="center"/></w:pPr>
        <w:r><w:rPr><w:b/><w:rtl/></w:rPr>
          <w:t>${_x(d.program)}</w:t></w:r>
      </w:p>
    </w:tc>
  </w:tr>
  <w:tr>
    <w:tc>
      <w:tcPr><w:tcW w:w="4500" w:type="dxa"/>
        <w:shd w:val="clear" w:color="auto" w:fill="E8F0FE"/>
      </w:tcPr>
      <w:p><w:pPr><w:jc w:val="right"/></w:pPr>
        <w:r><w:rPr><w:b/><w:rtl/></w:rPr><w:t>حصة البلدية</w:t></w:r>
      </w:p>
    </w:tc>
    <w:tc>
      <w:tcPr><w:tcW w:w="4500" w:type="dxa"/></w:tcPr>
      <w:p><w:pPr><w:jc w:val="center"/></w:pPr>
        <w:r><w:rPr><w:b/><w:color w:val="1A237E"/><w:rtl/></w:rPr>
          <w:t xml:space="preserve">[ ${d.quota} ] سكن ريفي</w:t></w:r>
      </w:p>
    </w:tc>
  </w:tr>
</w:tbl>

<!-- ════════════════════════ ثانياً ═══════════════════════════════════════ -->
<w:p>
  <w:pPr><w:jc w:val="right"/><w:spacing w:before="200" w:after="80"/></w:pPr>
  <w:r><w:rPr><w:b/><w:sz w:val="26"/><w:color w:val="1A237E"/><w:rtl/></w:rPr>
    <w:t>ثانياً: الحالة الفيزيائية للسكنات</w:t>
  </w:r>
</w:p>

<w:tbl>
  <w:tblPr>
    <w:tblW w:w="9000" w:type="dxa"/>
    <w:jc w:val="center"/>
    <w:tblBorders>
      <w:top w:val="single" w:sz="4" w:color="CCCCCC"/>
      <w:left w:val="single" w:sz="4" w:color="CCCCCC"/>
      <w:bottom w:val="single" w:sz="4" w:color="CCCCCC"/>
      <w:right w:val="single" w:sz="4" w:color="CCCCCC"/>
      <w:insideH w:val="single" w:sz="4" w:color="CCCCCC"/>
      <w:insideV w:val="single" w:sz="4" w:color="CCCCCC"/>
    </w:tblBorders>
    <w:tblCellMar>
      <w:top w:w="80" w:type="dxa"/>
      <w:left w:w="120" w:type="dxa"/>
      <w:bottom w:w="80" w:type="dxa"/>
      <w:right w:w="120" w:type="dxa"/>
    </w:tblCellMar>
  </w:tblPr>
  <w:tblGrid>
    <w:gridCol w:w="4500"/>
    <w:gridCol w:w="4500"/>
  </w:tblGrid>
  ${rows.toString()}
</w:tbl>

<!-- ════════════════════════ ثالثاً ══════════════════════════════════════ -->
<w:p>
  <w:pPr><w:jc w:val="right"/><w:spacing w:before="200" w:after="80"/></w:pPr>
  <w:r><w:rPr><w:b/><w:sz w:val="26"/><w:color w:val="1A237E"/><w:rtl/></w:rPr>
    <w:t>ثالثاً: وضعية الربط بالشبكات العمومية</w:t>
  </w:r>
</w:p>
<w:p>
  <w:pPr><w:jc w:val="right"/><w:spacing w:before="0" w:after="80"/></w:pPr>
  <w:r><w:rPr><w:i/><w:sz w:val="20"/><w:color w:val="555555"/><w:rtl/></w:rPr>
    <w:t xml:space="preserve">(السكنات المنتهية والمشغولة فقط — من أصل [ ${d.finishedOccupied} ] سكن)</w:t>
  </w:r>
</w:p>

<w:tbl>
  <w:tblPr>
    <w:tblW w:w="9000" w:type="dxa"/>
    <w:jc w:val="center"/>
    <w:tblBorders>
      <w:top w:val="single" w:sz="4" w:color="CCCCCC"/>
      <w:left w:val="single" w:sz="4" w:color="CCCCCC"/>
      <w:bottom w:val="single" w:sz="4" w:color="CCCCCC"/>
      <w:right w:val="single" w:sz="4" w:color="CCCCCC"/>
      <w:insideH w:val="single" w:sz="4" w:color="CCCCCC"/>
      <w:insideV w:val="single" w:sz="4" w:color="CCCCCC"/>
    </w:tblBorders>
    <w:tblCellMar>
      <w:top w:w="80" w:type="dxa"/>
      <w:left w:w="120" w:type="dxa"/>
      <w:bottom w:w="80" w:type="dxa"/>
      <w:right w:w="120" w:type="dxa"/>
    </w:tblCellMar>
  </w:tblPr>
  <w:tblGrid>
    <w:gridCol w:w="4500"/>
    <w:gridCol w:w="4500"/>
  </w:tblGrid>
  ${netRows.toString()}
</w:tbl>

<!-- ════════════════════════ رابعاً ══════════════════════════════════════ -->
<w:p>
  <w:pPr><w:jc w:val="right"/><w:spacing w:before="200" w:after="80"/></w:pPr>
  <w:r><w:rPr><w:b/><w:sz w:val="26"/><w:color w:val="1A237E"/><w:rtl/></w:rPr>
    <w:t>رابعاً: المرفقات</w:t>
  </w:r>
</w:p>
<w:p>
  <w:pPr><w:jc w:val="both"/><w:spacing w:before="0" w:after="80"/></w:pPr>
  <w:r><w:rPr><w:sz w:val="22"/><w:rtl/></w:rPr>
    <w:t>جميع المرفقات مدمجة ضمن قرص مضغوط (CD) وتشمل:</w:t>
  </w:r>
</w:p>
<w:p>
  <w:pPr><w:jc w:val="right"/><w:ind w:right="720"/><w:spacing w:before="0" w:after="60"/></w:pPr>
  <w:r><w:rPr><w:sz w:val="22"/><w:rtl/></w:rPr>
    <w:t>• جدول بياني تفصيلي يحتوي على القائمة الاسمية للمستفيدين، الحالة الفيزيائية لكل سكن، ووضعية الربط بالشبكات.</w:t>
  </w:r>
</w:p>
<w:p>
  <w:pPr><w:jc w:val="right"/><w:ind w:right="720"/><w:spacing w:before="0" w:after="160"/></w:pPr>
  <w:r><w:rPr><w:sz w:val="22"/><w:rtl/></w:rPr>
    <w:t>• صور توثق وضعية البنايات لكل سكن.</w:t>
  </w:r>
</w:p>

<!-- فاصل -->
<w:p><w:pPr><w:spacing w:before="120" w:after="0"/>
  <w:pBdr><w:top w:val="single" w:sz="6" w:space="1" w:color="1A237E"/></w:pBdr>
</w:pPr></w:p>

<!-- ════════════════════════ التوقيعات ══════════════════════════════════ -->
<w:p>
  <w:pPr><w:jc w:val="both"/><w:spacing w:before="120" w:after="80"/></w:pPr>
  <w:r><w:rPr><w:sz w:val="22"/><w:rtl/></w:rPr>
    <w:t xml:space="preserve">حرر هذا المحضر في ${_x(d.place)} بتاريخ ${_x(d.date)}.</w:t>
  </w:r>
</w:p>

<w:p>
  <w:pPr><w:jc w:val="center"/><w:spacing w:before="120" w:after="80"/></w:pPr>
  <w:r><w:rPr><w:b/><w:sz w:val="24"/><w:color w:val="1A237E"/><w:rtl/></w:rPr>
    <w:t>إمضاءات أعضاء اللجنة</w:t>
  </w:r>
</w:p>

<!-- جدول التوقيعات -->
<w:tbl>
  <w:tblPr>
    <w:tblW w:w="9000" w:type="dxa"/>
    <w:jc w:val="center"/>
    <w:tblBorders>
      <w:top w:val="none"/><w:left w:val="none"/>
      <w:bottom w:val="none"/><w:right w:val="none"/>
      <w:insideH w:val="none"/><w:insideV w:val="none"/>
    </w:tblBorders>
  </w:tblPr>
  <w:tblGrid>
    <w:gridCol w:w="3000"/>
    <w:gridCol w:w="3000"/>
    <w:gridCol w:w="3000"/>
  </w:tblGrid>
  <w:tr>
    <w:tc><w:tcPr><w:tcW w:w="3000" w:type="dxa"/></w:tcPr>
      <w:p><w:pPr><w:jc w:val="center"/></w:pPr>
        <w:r><w:rPr><w:b/><w:sz w:val="20"/><w:rtl/></w:rPr>
          <w:t>رئيسة فرع السكن – الدائرة</w:t></w:r>
      </w:p>
    </w:tc>
    <w:tc><w:tcPr><w:tcW w:w="3000" w:type="dxa"/></w:tcPr>
      <w:p><w:pPr><w:jc w:val="center"/></w:pPr>
        <w:r><w:rPr><w:b/><w:sz w:val="20"/><w:rtl/></w:rPr>
          <w:t>المكلف بالبناء الريفي – الدائرة</w:t></w:r>
      </w:p>
    </w:tc>
    <w:tc><w:tcPr><w:tcW w:w="3000" w:type="dxa"/></w:tcPr>
      <w:p><w:pPr><w:jc w:val="center"/></w:pPr>
        <w:r><w:rPr><w:b/><w:sz w:val="20"/><w:rtl/></w:rPr>
          <w:t>المكلف بالبناء الريفي – البلدية</w:t></w:r>
      </w:p>
    </w:tc>
  </w:tr>
  ${_signatureRows()}
</w:tbl>

<w:sectPr>
  <w:pgSz w:w="11906" w:h="16838"/>
  <w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134"/>
  <w:bidi/>
</w:sectPr>
</w:body>
</w:document>''';
  }

  // صفوف التوقيعات (9 صفوف فارغة)
  String _signatureRows() {
    final sb = StringBuffer();
    final labels = ['الاسم واللقب:', 'التوقيع:', ''];
    for (int i = 0; i < 9; i++) {
      final lbl = i < labels.length ? labels[i] : '';
      sb.write('''
<w:tr>
  <w:trPr><w:trHeight w:val="600"/></w:trPr>
  <w:tc><w:tcPr><w:tcW w:w="3000" w:type="dxa"/></w:tcPr>
    <w:p><w:pPr><w:jc w:val="center"/></w:pPr>
      <w:r><w:rPr><w:sz w:val="20"/><w:rtl/></w:rPr>
        <w:t xml:space="preserve">${_x(lbl)}  …………………………………</w:t>
      </w:r>
    </w:p>
  </w:tc>
  <w:tc><w:tcPr><w:tcW w:w="3000" w:type="dxa"/></w:tcPr>
    <w:p><w:pPr><w:jc w:val="center"/></w:pPr>
      <w:r><w:rPr><w:sz w:val="20"/><w:rtl/></w:rPr>
        <w:t xml:space="preserve">${_x(lbl)}  …………………………………</w:t>
      </w:r>
    </w:p>
  </w:tc>
  <w:tc><w:tcPr><w:tcW w:w="3000" w:type="dxa"/></w:tcPr>
    <w:p><w:pPr><w:jc w:val="center"/></w:pPr>
      <w:r><w:rPr><w:sz w:val="20"/><w:rtl/></w:rPr>
        <w:t xml:space="preserve">${_x(lbl)}  …………………………………</w:t>
      </w:r>
    </w:p>
  </w:tc>
</w:tr>''');
    }
    return sb.toString();
  }

  // ── ملفات DOCX الداعمة ──────────────────────
  String _contentTypes() => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml"
    ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml"
    ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
  <Override PartName="/word/settings.xml"
    ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>
</Types>''';

  String _rootRels() => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1"
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
    Target="word/document.xml"/>
</Relationships>''';

  String _documentRels() => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1"
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles"
    Target="styles.xml"/>
  <Relationship Id="rId2"
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings"
    Target="settings.xml"/>
</Relationships>''';

  String _styles() => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:docDefaults>
    <w:rPrDefault><w:rPr>
      <w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/>
      <w:sz w:val="22"/><w:szCs w:val="22"/>
      <w:lang w:val="ar-DZ" w:bidi="ar-DZ"/>
    </w:rPr></w:rPrDefault>
    <w:pPrDefault><w:pPr>
      <w:bidi/><w:jc w:val="right"/>
    </w:pPr></w:pPrDefault>
  </w:docDefaults>
</w:styles>''';

  String _settings() => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:bidi/>
  <w:defaultTabStop w:val="720"/>
</w:settings>''';

  // ── مساعدات ─────────────────────────────────
  List<int> _utf8(String s) => utf8.encode(s);

  /// تهريب XML
  String _x(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
