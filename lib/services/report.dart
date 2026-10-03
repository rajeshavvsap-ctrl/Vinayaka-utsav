import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models.dart';
import 'db.dart';

final _rs = NumberFormat.currency(locale: 'en_IN', symbol: 'Rs. ', decimalDigits: 0);
String _m(num v) => _rs.format(v);

final _maroon = PdfColor.fromHex('#7A1F1F');
final _cream = PdfColor.fromHex('#FFF7EC');
final _line = PdfColor.fromHex('#E6CFB3');
final _muted = PdfColor.fromHex('#7A5A50');

typedef _Row = Map<String, dynamic>;

class _Data {
  _Data(this.activities, this.signups, this.expenses, this.contributions);
  final List<_Row> activities;
  final List<_Row> signups;
  final List<_Row> expenses;
  final List<_Row> contributions;

  num get spent => expenses.fold<num>(0, (s, e) => s + toNum(e['amount']));
  num get verified => _sumWhere('verified');
  num get pending => _sumWhere('pending');
  num _sumWhere(String status) => contributions
      .where((c) => c['status'] == status)
      .fold<num>(0, (s, c) => s + toNum(c['amount']));
}

Future<_Data> _load({String? day}) async {
  Future<List<_Row>> q(CollectionReference<_Row> c) async {
    final Query<_Row> query = day == null ? c : c.where('date', isEqualTo: day);
    final snap = await query.get();
    return snap.docs.map((d) => d.data()).toList();
  }

  final results = await Future.wait([
    q(Db.activities),
    q(Db.poojaSignups),
    q(Db.expenses),
    q(Db.contributions),
  ]);
  int byDate(_Row a, _Row b) => '${a['date']}'.compareTo('${b['date']}');
  return _Data(
    results[0]..sort((a, b) => '${a['date']} ${a['time']}'.compareTo('${b['date']} ${b['time']}')),
    results[1]..sort((a, b) => '${a['date']} ${a['slot']} ${a['name']}'.compareTo('${b['date']} ${b['slot']} ${b['name']}')),
    results[2]..sort(byDate),
    results[3]..sort(byDate),
  );
}

Future<pw.ThemeData> _theme() async {
  try {
    final base = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();
    final telugu = await PdfGoogleFonts.notoSansTeluguRegular();
    return pw.ThemeData.withFont(base: base, bold: bold, fontFallback: [telugu]);
  } catch (_) {
    // Offline: fall back to the built-in font.
    return pw.ThemeData.base();
  }
}

pw.Widget _header(Festival f, String title) => pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      margin: const pw.EdgeInsets.only(bottom: 12),
      decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _maroon, width: 2))),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(f.title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _maroon)),
            pw.Text(title, style: const pw.TextStyle(fontSize: 12)),
          ]),
          pw.Text('Generated ${DateFormat('d MMM yyyy, h:mm a').format(DateTime.now())}',
              style: pw.TextStyle(fontSize: 9, color: _muted)),
        ],
      ),
    );

pw.Widget _footer(pw.Context ctx) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: pw.TextStyle(fontSize: 9, color: _muted)),
    );

pw.Widget _section(String title) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 16, bottom: 6),
      child: pw.Text(title, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _maroon)),
    );

pw.Widget _summary(List<List<String>> items) => pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(color: _cream, border: pw.Border.all(color: _line)),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          for (final it in items)
            pw.Column(children: [
              pw.Text(it[0], style: pw.TextStyle(fontSize: 9, color: _muted)),
              pw.Text(it[1], style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            ]),
        ],
      ),
    );

/// Table with an optional bold total row; numeric columns right-aligned.
pw.Widget _table(List<String> headers, List<List<String>> rows,
    {Set<int> right = const {}, List<String>? total}) {
  if (rows.isEmpty) {
    return pw.Text('No entries.', style: pw.TextStyle(color: _muted, fontSize: 10));
  }
  final data = [...rows, if (total != null) total];
  return pw.TableHelper.fromTextArray(
    headers: headers,
    data: data,
    border: pw.TableBorder.all(color: _line, width: 0.5),
    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
    headerDecoration: pw.BoxDecoration(color: _maroon),
    cellStyle: const pw.TextStyle(fontSize: 9),
    cellAlignments: {for (final i in right) i: pw.Alignment.centerRight},
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    oddRowDecoration: pw.BoxDecoration(color: _cream),
  );
}

String _day(Festival f, String key) {
  final n = f.dayNumber(key);
  return n == null ? shortDay(key) : 'Day $n · ${shortDay(key)}';
}

List<String> _expenseRow(Festival f, _Row e, {bool withDate = true}) => [
      if (withDate) _day(f, '${e['date']}'),
      '${e['item']}',
      '${e['category']}',
      '${e['paidBy']}',
      '${e['mode'] ?? ''}',
      '${(e['proofId'] ?? '').toString().isNotEmpty ? 'Yes' : '-'}',
      _m(toNum(e['amount'])),
    ];

List<String> _contribRow(Festival f, _Row c, {bool withDate = true}) => [
      if (withDate) _day(f, '${c['date']}'),
      '${c['name']}',
      '${c['mode']}',
      '${c['txnRef'] ?? ''}',
      '${c['status']}',
      _m(toNum(c['amount'])),
    ];

Future<void> _share(pw.Document doc, String filename) async {
  await Printing.sharePdf(bytes: await doc.save(), filename: filename);
}

/// Everything recorded for one festival day.
Future<void> shareDayReport(Festival f, String day) async {
  final d = await _load(day: day);
  final doc = pw.Document(theme: await _theme(), title: '${f.title} ${_day(f, day)}');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    header: (_) => _header(f, '${_day(f, day)} report · ${prettyDay(day)}'),
    footer: _footer,
    build: (_) => [
      _summary([
        ['Contributions (verified)', _m(d.verified)],
        ['Pending verification', _m(d.pending)],
        ['Expenses', _m(d.spent)],
        ['Net for the day', _m(d.verified - d.spent)],
      ]),
      _section('Expenses (${d.expenses.length})'),
      _table(
        ['Item', 'Category', 'Paid by', 'Mode', 'Bill', 'Amount'],
        [for (final e in d.expenses) _expenseRow(f, e, withDate: false)],
        right: {5},
        total: ['Total', '', '', '', '', _m(d.spent)],
      ),
      _section('Contributions (${d.contributions.length})'),
      _table(
        ['Name', 'Mode', 'Txn ref', 'Status', 'Amount'],
        [for (final c in d.contributions) _contribRow(f, c, withDate: false)],
        right: {4},
        total: ['Verified total', '', '', '', _m(d.verified)],
      ),
      _section('Pooja Seva (${d.signups.length})'),
      _table(['Slot', 'Name', 'Note'],
          [for (final s in d.signups) ['${s['slot']}', '${s['name']}', '${s['note'] ?? ''}']]),
      _section('Activities (${d.activities.length})'),
      _table(['Time', 'Activity', 'Place', 'Coordinator'], [
        for (final a in d.activities)
          [prettyTime('${a['time']}'), '${a['title']}', '${a['place'] ?? ''}', '${a['coordinator'] ?? ''}']
      ]),
    ],
  ));
  await _share(doc, 'Day-${f.dayNumber(day) ?? ''}-$day-report.pdf');
}

/// Final accounts for the whole festival.
Future<void> shareFinalReport(Festival f) async {
  final d = await _load();

  // Expenses by category.
  final byCat = <String, num>{};
  for (final e in d.expenses) {
    final c = '${e['category']}';
    byCat[c] = (byCat[c] ?? 0) + toNum(e['amount']);
  }
  final catRows = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

  // Day-wise totals (festival days, plus any other dates that have entries).
  final days = <String>{...f.dayKeys, for (final e in d.expenses) '${e['date']}', for (final c in d.contributions) '${c['date']}'}
      .toList()
    ..sort();
  num sumOn(List<_Row> rows, String day, {String? status}) => rows
      .where((r) => r['date'] == day && (status == null || r['status'] == status))
      .fold<num>(0, (s, r) => s + toNum(r['amount']));

  // Contributions by mode (verified only).
  final byMode = <String, num>{};
  for (final c in d.contributions.where((c) => c['status'] == 'verified')) {
    final m = '${c['mode']}';
    byMode[m] = (byMode[m] ?? 0) + toNum(c['amount']);
  }

  final doc = pw.Document(theme: await _theme(), title: '${f.title} final report');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    header: (_) => _header(
        f, 'Final report · ${shortDay(f.dayKeys.first)} – ${prettyDay(f.dayKeys.last)} (${f.days} days)'),
    footer: _footer,
    build: (_) => [
      _summary([
        ['Collected (verified)', _m(d.verified)],
        ['Pending verification', _m(d.pending)],
        ['Total expenses', _m(d.spent)],
        ['Balance', _m(d.verified - d.spent)],
      ]),
      _section('Day-wise summary'),
      _table(
        ['Day', 'Contributions (verified)', 'Expenses', 'Pooja names'],
        [
          for (final day in days)
            [
              _day(f, day),
              _m(sumOn(d.contributions, day, status: 'verified')),
              _m(sumOn(d.expenses, day)),
              '${d.signups.where((s) => s['date'] == day).length}',
            ]
        ],
        right: {1, 2, 3},
        total: ['Total', _m(d.verified), _m(d.spent), '${d.signups.length}'],
      ),
      _section('Expenses by category'),
      _table(
        ['Category', 'Amount', 'Share'],
        [
          for (final c in catRows)
            [c.key, _m(c.value), d.spent == 0 ? '-' : '${(c.value * 100 / d.spent).toStringAsFixed(1)}%']
        ],
        right: {1, 2},
        total: ['Total', _m(d.spent), '100%'],
      ),
      _section('Contributions by payment mode (verified)'),
      _table(
        ['Mode', 'Amount'],
        [for (final e in byMode.entries) [e.key, _m(e.value)]],
        right: {1},
        total: ['Total', _m(d.verified)],
      ),
      _section('All expenses (${d.expenses.length})'),
      _table(
        ['Day', 'Item', 'Category', 'Paid by', 'Mode', 'Bill', 'Amount'],
        [for (final e in d.expenses) _expenseRow(f, e)],
        right: {6},
        total: ['Total', '', '', '', '', '', _m(d.spent)],
      ),
      _section('All contributions (${d.contributions.length})'),
      _table(
        ['Day', 'Name', 'Mode', 'Txn ref', 'Status', 'Amount'],
        [for (final c in d.contributions) _contribRow(f, c)],
        right: {5},
        total: ['Verified total', '', '', '', '', _m(d.verified)],
      ),
      pw.SizedBox(height: 24),
      pw.Text('Prepared by the committee. Bills and payment screenshots are available in the app.',
          style: pw.TextStyle(fontSize: 9, color: _muted)),
    ],
  ));
  await _share(doc, '${f.title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')}-final-report.pdf');
}
