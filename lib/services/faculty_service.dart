import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/supabase/supabase_client.dart';
import '../models/attendance_row.dart';
import '../models/daily_test.dart';
import '../models/ranking.dart';
import '../models/test_attempt.dart';

class FacultyService {
  final _client = SupabaseService.client;

  /// Every one of the day's tests — up to 3 (one per category), however
  /// many admins have generated so far. Was `fetchTestForDate` returning
  /// a single row via `.maybeSingle()`, back when `test_date` alone was
  /// unique; now that a date can have one row per category (see
  /// supabase/schema.sql), this returns the whole list ordered so
  /// Aptitude/Technical/Communication show up in a stable, predictable
  /// order on the faculty QR screen.
  Future<List<DailyTest>> fetchTestsForDate(DateTime date) async {
    final dateStr = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final rows = await _client.from('daily_tests').select().eq('test_date', dateStr);
    final tests = (rows as List).map((r) => DailyTest.fromJson(r as Map<String, dynamic>)).toList();
    // Alphabetical-by-category from Postgres isn't the order a person
    // reads them in (Aptitude, Technical, Communication) — sort by the
    // enum's declared order instead so the QR screen is predictable.
    tests.sort((a, b) => a.category.index.compareTo(b.category.index));
    return tests;
  }

  /// Calls the `fetch_attendance` RPC (see supabase/functions.sql), which
  /// left-joins every student in the faculty's own department against
  /// `test_attempts` for this test — so students who never opened the
  /// test still show up (as "Pending"), not just ones who already have
  /// an attempts row. The RPC itself enforces the department scoping
  /// that RLS would otherwise apply to a plain table select.
  Future<List<AttendanceRow>> fetchAttendance(
    String dailyTestId, {
    int? year,
    String? section,
  }) async {
    final rows = await _client.rpc('fetch_attendance', params: {
      'p_daily_test_id': dailyTestId,
      if (year != null) 'p_year': year,
      if (section != null && section.isNotEmpty) 'p_section': section,
    });
    return (rows as List)
        .map((r) => AttendanceRow.fromRpcJson(r as Map<String, dynamic>, dailyTestId: dailyTestId))
        .toList();
  }

  /// Calls the `fetch_top_rankings` RPC (see supabase/functions.sql)
  /// rather than a plain client-side `rankings.select('*, students(...))'`
  /// — `students_select` (policies.sql) only lets a faculty caller read
  /// rows in their *own* department, but Overall/Year spans every
  /// department, and Department can now target any department (the
  /// faculty Ranking screen's department picker isn't limited to the
  /// caller's own). For any row outside the caller's department, that
  /// client-side embed was silently coming back `students: null` —
  /// RankingEntry.fromJson tolerates the null instead of crashing, so
  /// this shipped as a quiet bug: blank name/register number for anyone
  /// outside the viewing faculty's department, on exactly the tabs meant
  /// to show other departments.
  Future<List<RankingEntry>> fetchTop10(
    String dailyTestId, {
    String scope = 'overall', // overall | department | year
    String? departmentId,
    int? year,
  }) async {
    final rows = await _client.rpc('fetch_top_rankings', params: {
      'p_daily_test_id': dailyTestId,
      'p_scope': scope,
      if (departmentId != null) 'p_department_id': departmentId,
      if (year != null) 'p_year': year,
      'p_limit': 10,
    });
    return (rows as List)
        .map((r) => RankingEntry.fromRpcJson(r as Map<String, dynamic>, dailyTestId: dailyTestId))
        .toList();
  }

  Future<Uint8List> buildExcelReport(String testDateLabel, List<AttendanceRow> rows) async {
    final workbook = xls.Excel.createExcel();
    final sheet = workbook['Report'];
    sheet.appendRow([
      xls.TextCellValue('Register No'),
      xls.TextCellValue('Name'),
      xls.TextCellValue('Year'),
      xls.TextCellValue('Section'),
      xls.TextCellValue('Status'),
      xls.TextCellValue('Score'),
    ]);
    for (final r in rows) {
      sheet.appendRow([
        xls.TextCellValue(r.registerNumber),
        xls.TextCellValue(r.studentName),
        xls.IntCellValue(r.year),
        xls.TextCellValue(r.section ?? '-'),
        xls.TextCellValue(r.attempt.status.name),
        xls.IntCellValue(r.attempt.score ?? 0),
      ]);
    }
    final bytes = workbook.encode();
    return Uint8List.fromList(bytes ?? []);
  }

  // Brand palette mirrored from AppColors (faculty blue) — the pdf
  // package's widget tree is a separate render pipeline from Flutter's,
  // so these can't just reference AppColors directly and are redefined
  // here as PdfColor.
  static final _brand = PdfColor.fromHex('#2F6FED');
  static final _brandDark = PdfColor.fromHex('#1F4FC4');
  static final _brandLight = PdfColor.fromHex('#E9F0FE');
  static final _success = PdfColor.fromHex('#2E9E5B');
  static final _successLight = PdfColor.fromHex('#E3F6EA');
  static final _errorC = PdfColor.fromHex('#D64545');
  static final _errorLight = PdfColor.fromHex('#FCE9E9');
  static final _warning = PdfColor.fromHex('#E0A526');
  static final _warningLight = PdfColor.fromHex('#FBF1DD');
  static final _absent = PdfColor.fromHex('#9E9E9E');
  static final _absentLight = PdfColor.fromHex('#F0F0F0');
  static final _textPrimary = PdfColor.fromHex('#161821');
  static final _textSecondary = PdfColor.fromHex('#666D80');
  static final _borderColor = PdfColor.fromHex('#E7E9F1');
  static final _rowAlt = PdfColor.fromHex('#F7F8FC');

  static String _statusLabel(AttemptStatus status) => switch (status) {
        AttemptStatus.notStarted => 'Not started',
        AttemptStatus.inProgress => 'In progress',
        AttemptStatus.submitted => 'Submitted',
        AttemptStatus.absent => 'Absent',
      };

  static PdfColor _statusColor(AttemptStatus status) => switch (status) {
        AttemptStatus.submitted => _success,
        AttemptStatus.absent => _errorC,
        AttemptStatus.inProgress => _brand,
        AttemptStatus.notStarted => _absent,
      };

  static PdfColor _statusBg(AttemptStatus status) => switch (status) {
        AttemptStatus.submitted => _successLight,
        AttemptStatus.absent => _errorLight,
        AttemptStatus.inProgress => _brandLight,
        AttemptStatus.notStarted => _absentLight,
      };

  Future<Uint8List> buildPdfReport(String testDateLabel, List<AttendanceRow> rows) async {
    final submitted = rows.where((r) => r.attempt.status == AttemptStatus.submitted).toList();
    final absent = rows.where((r) => r.attempt.status == AttemptStatus.absent).length;
    final pending = rows.length - submitted.length - absent;
    final avgScore = submitted.isEmpty
        ? 0.0
        : submitted.map((r) => r.attempt.score ?? 0).reduce((a, b) => a + b) / submitted.length;

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 28),
        header: (context) {
          // Only repeat a slim running header on pages after the first —
          // the full banner below already does that job on page one.
          if (context.pageNumber == 1) return pw.SizedBox();
          return pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 8),
            margin: const pw.EdgeInsets.only(bottom: 12),
            decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _borderColor, width: 1))),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('AptiQR  |  Daily Aptitude Test Report', style: pw.TextStyle(fontSize: 9, color: _textSecondary)),
                pw.Text(testDateLabel, style: pw.TextStyle(fontSize: 9, color: _textSecondary)),
              ],
            ),
          );
        },
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: pw.TextStyle(fontSize: 8, color: _textSecondary),
          ),
        ),
        build: (context) => [
          // Title banner — solid brand-blue block instead of a plain black
          // text heading, so the report reads as belonging to the app
          // rather than a generic spreadsheet dump.
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(18),
            decoration: pw.BoxDecoration(color: _brand, borderRadius: pw.BorderRadius.circular(10)),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('APTIQR', style: pw.TextStyle(color: PdfColors.white, fontSize: 10, fontWeight: pw.FontWeight.bold, letterSpacing: 2)),
                    pw.SizedBox(height: 6),
                    pw.Text('Daily Aptitude Test Report', style: pw.TextStyle(color: PdfColors.white, fontSize: 19, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 3),
                    // Kept on its own Text (not concatenated with an em
                    // dash into the title above) — the base14 Helvetica
                    // font this package falls back to renders U+2014 as a
                    // missing-glyph box, which is what showed up as a
                    // literal "▢" in the old single-line title.
                    pw.Text(testDateLabel, style: pw.TextStyle(color: PdfColors.white, fontSize: 11)),
                  ],
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: pw.BoxDecoration(color: PdfColors.white, borderRadius: pw.BorderRadius.circular(20)),
                  child: pw.Text('${rows.length} student${rows.length == 1 ? '' : 's'}',
                      style: pw.TextStyle(color: _brandDark, fontSize: 10, fontWeight: pw.FontWeight.bold)),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 18),
          // Summary stat cards — the numbers a faculty member actually
          // scans for first (how many submitted/absent, and how the class
          // did), pulled up top instead of buried in a "count the rows"
          // table read.
          pw.Row(
            children: [
              _statCard('Submitted', '${submitted.length}', _success, _successLight),
              pw.SizedBox(width: 10),
              _statCard('Absent', '$absent', _errorC, _errorLight),
              pw.SizedBox(width: 10),
              _statCard('Pending', '$pending', _warning, _warningLight),
              pw.SizedBox(width: 10),
              _statCard('Avg. score', avgScore.toStringAsFixed(1), _brand, _brandLight),
            ],
          ),
          pw.SizedBox(height: 22),
          pw.Text('Student results', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _textPrimary)),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: _borderColor, width: 0.6),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.5),
              1: pw.FlexColumnWidth(2.3),
              2: pw.FlexColumnWidth(0.7),
              3: pw.FlexColumnWidth(0.9),
              4: pw.FlexColumnWidth(1.4),
              5: pw.FlexColumnWidth(0.9),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: _brand),
                children: ['Reg. No', 'Name', 'Year', 'Section', 'Status', 'Score']
                    .map((h) => pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                          child: pw.Text(h, style: pw.TextStyle(color: PdfColors.white, fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                        ))
                    .toList(),
              ),
              for (int i = 0; i < rows.length; i++)
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: i.isEven ? PdfColors.white : _rowAlt),
                  children: [
                    _cell(rows[i].registerNumber, _textPrimary),
                    _cell(rows[i].studentName, _textPrimary),
                    _cell('${rows[i].year}', _textSecondary),
                    _cell(rows[i].section ?? '-', _textSecondary),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      child: pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: pw.BoxDecoration(color: _statusBg(rows[i].attempt.status), borderRadius: pw.BorderRadius.circular(10)),
                        child: pw.Text(_statusLabel(rows[i].attempt.status),
                            style: pw.TextStyle(color: _statusColor(rows[i].attempt.status), fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                      ),
                    ),
                    _cell('${rows[i].attempt.score ?? 0}', _textPrimary, bold: true),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
    return doc.save();
  }

  static pw.Widget _statCard(String label, String value, PdfColor color, PdfColor bg) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 12),
        decoration: pw.BoxDecoration(color: bg, borderRadius: pw.BorderRadius.circular(8)),
        child: pw.Column(
          children: [
            pw.Text(value, style: pw.TextStyle(color: color, fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 2),
            pw.Text(label, style: pw.TextStyle(color: color, fontSize: 8)),
          ],
        ),
      ),
    );
  }

  static pw.Widget _cell(String text, PdfColor color, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(text, style: pw.TextStyle(color: color, fontSize: 9.5, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );
  }

  int countByStatus(List<AttendanceRow> rows, String status) {
    return rows.where((r) => r.attempt.status.name == status).length;
  }
}
