import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; // for debugPrint
import '../data/app_data.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS
// ─────────────────────────────────────────────────────────────────────────────
class _Clr {
  static const darker     = PdfColor(0.1, 0.1, 0.1);
  static const excelBrown = PdfColor(0.816, 0.753, 0.627);
}

class PdfGenerator {
  static pw.Font? _regular;
  static pw.Font? _bold;
  static pw.Font? _extraBold;
  static pw.MemoryImage? _cachedLogo;

  static Future<void> _loadFonts() async {
    if (_regular != null) return; // Cache hit
    _regular   = pw.Font.helvetica();
    _bold      = pw.Font.helveticaBold();
    _extraBold = pw.Font.timesBold();
  }

  static Future<pw.MemoryImage?> _loadLogo() async {
    if (_cachedLogo != null) return _cachedLogo; // Cache hit
    try {
      final imgBytes = (await rootBundle.load('assets/logo_master_inverted.png')).buffer.asUint8List();
      _cachedLogo = pw.MemoryImage(imgBytes);
      return _cachedLogo;
    } catch (e) { return null; }
  }

  static String _pf(num v) => NumberFormat('#,##0.00').format(v);

  static Future<void> _saveFile(List<int> bytes, String suggestedName, String title) async {
    try {
      final String? result = await FilePicker.platform.saveFile(
        dialogTitle: title,
        fileName: suggestedName,
        type: FileType.custom,
        allowedExtensions: ['pdf', 'xlsx'],
      );
      if (result != null) {
        final path = result.contains('.') ? result : '$result.${suggestedName.split('.').last}';
        await File(path).writeAsBytes(bytes);
      }
    } catch (e) {
      debugPrint("Error saving file: $e");
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // EXPORTS
  // ══════════════════════════════════════════════════════════════════════════════

  static Future<pw.Document> generateDocumentForPreview(Map<String, dynamic> tx, {String? preparedBy}) async {
    await _loadFonts();
    await Future.delayed(Duration.zero); // UI Pulse
    pw.MemoryImage? logo = await _loadLogo();
    final pdf = pw.Document();
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => _buildReceiptBody(tx, logo, preparedBy: preparedBy),
    ));
    return pdf;
  }

  static Future<void> printReceipt(Map<String, dynamic> tx, {String? businessName, String? preparedBy}) async {
    final pdf = await generateDocumentForPreview(tx, preparedBy: preparedBy);
    await _saveFile(await pdf.save(), 'SR_${tx['id']}.pdf', 'Save Sales Receipt');
  }

  static Future<void> exportTableToPdf(List<Map<String, dynamic>> transactions, {bool isShop = false, String reportType = 'daily', DateTime? date}) async {
    if (transactions.isEmpty) return;
    await _loadFonts();
    pw.MemoryImage? logo = await _loadLogo();
    final pdf = pw.Document();

    final now = date ?? DateTime.now();
    String reportTitle = isShop ? 'SHOP SALES AUDIT REPORT' : 'BEANS WHOLESALE PERFORMANCE REPORT';
    if (reportType == 'monthly') reportTitle = isShop ? 'SHOP MONTHLY SALES REVENUE REPORT' : 'BEANS WHOLESALE PERFORMANCE REPORT';
    if (reportType == 'products') reportTitle = 'PRODUCT SALES PERFORMANCE ANALYTICS';
    
    List<String> headers = [];
    List<List<String>> dataRows = [];
    Map<int, pw.TableColumnWidth> colWidths = {};

    if (reportType == 'products') {
      headers = ['Rank', 'Product Name', 'Quantity Sold', 'Revenue Amount'];
      colWidths = {
        0: const pw.FixedColumnWidth(40),
        1: const pw.FlexColumnWidth(2),
        2: const pw.FixedColumnWidth(80),
        3: const pw.FixedColumnWidth(100),
      };

      Map<String, Map<String, dynamic>> products = {};
      for (final tx in transactions) {
        final items = (tx['items'] as List? ?? []);
        for (final i in items) {
          final name = i['name']?.toString() ?? 'Unknown';
          final qty = (i['qty'] as num?)?.toDouble() ?? 0.0;
          final price = (i['price'] as num?)?.toDouble() ?? 0.0;
          
          final p = products.putIfAbsent(name, () => {'qty': 0.0, 'rev': 0.0});
          p['qty'] += qty;
          p['rev'] += (qty * price);
        }
      }
      
      final sortedKeys = products.keys.toList()..sort((a,b) => products[b]!['rev'].compareTo(products[a]!['rev']));
      for (var i = 0; i < sortedKeys.length; i++) {
        final k = sortedKeys[i];
        dataRows.add([
          '#${i+1}',
          k,
          AppData.fmt(products[k]!['qty'] as double),
          'P ${_pf(products[k]!['rev'] as double)}'
        ]);
        if (i % 20 == 0) await Future.delayed(Duration.zero); // UI Thread Yield
      }
    } else if (reportType == 'monthly') {
      headers = ['Date Range', 'Selected Month', 'Total Orders', 'Revenue Total'];
      colWidths = {
        0: const pw.FlexColumnWidth(1),
        1: const pw.FlexColumnWidth(1.2),
        2: const pw.FixedColumnWidth(100),
        3: const pw.FixedColumnWidth(120),
      };

      Map<String, Map<String, dynamic>> days = {};
      for (final tx in transactions) {
        final raw = tx['date'] ?? tx['timestamp'];
        final dt = (raw is DateTime) ? raw : (DateTime.tryParse(raw?.toString() ?? '') ?? now);
        final key = DateFormat('yyyy-MM-dd').format(dt);
        
        final d = days.putIfAbsent(key, () => {'orders': 0, 'rev': 0.0, 'date': dt});
        d['orders'] += 1;
        d['rev'] += (tx['total_amount'] ?? tx['amount'] ?? 0.0) as num;
      }
      
      // Ensure all days from 1st to today are included
      final lastDay = now.day;
      for (int i = 1; i <= lastDay; i++) {
        final dDate = DateTime(now.year, now.month, i);
        final key = DateFormat('yyyy-MM-dd').format(dDate);
        if (!days.containsKey(key)) {
          days[key] = {'orders': 0, 'rev': 0.0, 'date': dDate};
        }
      }
      
      final sortedDays = days.keys.toList()..sort();
      for (final d in sortedDays) {
        dataRows.add([
          DateFormat('MMM dd, yyyy').format(days[d]!['date'] as DateTime),
          DateFormat('EEEE').format(days[d]!['date'] as DateTime),
          days[d]!['orders'].toString(),
          'P ${_pf((days[d]!['rev'] as num).toDouble())}'
        ]);
      }
      await Future.delayed(Duration.zero);
    } else {
      headers = isShop 
          ? ['Ref ID', 'Date Time', 'User', 'Mode', 'Amount']
          : ['SR NO.', 'Date', 'Customers Name', 'Address', 'Contact'];
      
      if (!isShop) {
        final products = AppData.beansProducts;
        for (var p in products) {
          headers.add(p['name'].toString().toUpperCase());
          headers.add('UNIT COST');
        }
        headers.addAll(['DELIVERY', 'TOTAL', 'MODE', 'REF NO.']);

        colWidths = {
          0: const pw.FixedColumnWidth(65), // SR NO
          1: const pw.FixedColumnWidth(45), // Date
          2: const pw.FixedColumnWidth(110), // Customer
          3: const pw.FixedColumnWidth(100), // Address
          4: const pw.FixedColumnWidth(80), // Contact
        };
        for (var i = 0; i < products.length; i++) {
          colWidths[5 + (i * 2)] = const pw.FixedColumnWidth(65);
          colWidths[5 + (i * 2) + 1] = const pw.FixedColumnWidth(65);
        }
        final base = 5 + (products.length * 2);
        colWidths[base] = const pw.FixedColumnWidth(60);
        colWidths[base + 1] = const pw.FixedColumnWidth(70);
        colWidths[base + 2] = const pw.FixedColumnWidth(60);
        colWidths[base + 3] = const pw.FixedColumnWidth(80);
      } else {
        colWidths = {
          0: const pw.FixedColumnWidth(85),
          1: const pw.FlexColumnWidth(1.2),
          2: const pw.FlexColumnWidth(1),
          3: const pw.FixedColumnWidth(50),
          4: const pw.FixedColumnWidth(70),
        };
      }

      for (var r = 0; r < transactions.length; r++) {
        final t = transactions[r];
        final raw = t['date'] ?? t['timestamp'];
        final dt = (raw is DateTime) ? raw : (DateTime.tryParse(raw?.toString() ?? '') ?? now);
        final dateStr = DateFormat(isShop ? 'MMM d, h:mm a' : 'MM/dd/yyyy').format(dt);
        
        if (isShop) {
          dataRows.add([
            t['id']?.toString() ?? t['reference_number']?.toString() ?? '',
            dateStr,
            t['user_name']?.toString() ?? '',
            t['payment_mode']?.toString() ?? 'Cash',
            'P ${_pf((t['amount'] as num).toDouble())}',
          ]);
        } else {
          final items = (t['items'] as List? ?? []);
          final List<String> row = [
            t['sr_number'] ?? t['id'] ?? '',
            dateStr,
            t['customer_name'] ?? 'General',
            t['address'] ?? 'N/A',
            t['contact'] ?? 'N/A',
          ];
          
          final products = AppData.beansProducts;
          for (var p in products) {
            final pName = p['name'].toString().toLowerCase();
            final sold = items.where((i) => i['name'].toString().toLowerCase() == pName).toList();
            final qty = sold.isEmpty ? 0 : sold.fold(0, (sum, i) => sum + (i['qty'] as num).toInt());
            final cost = sold.isEmpty ? 0.0 : (sold.first['price'] as num).toDouble();
            row.add(qty > 0 ? '$qty' : '-');
            row.add(qty > 0 ? 'P ${_pf(cost)}' : '-');
          }
          
          row.addAll([
             'P ${_pf((t['delivery_fee'] ?? 0.0).toDouble())}',
             'P ${_pf((t['total_amount'] ?? t['amount'] as num).toDouble())}',
             t['payment_mode'] ?? 'Cash',
             t['reference_number'] ?? 'N/A',
          ]);
          dataRows.add(row);
        }
        if (r % 20 == 0) await Future.delayed(Duration.zero); // Periodic breathing during large loops
      }
    }

    pdf.addPage(pw.MultiPage(
      pageFormat: (isShop && reportType != 'monthly') ? PdfPageFormat.a4 : PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(32),
      header: (ctx) => _buildLetterhead(logo),
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 10),
        child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
      ),
      build: (ctx) => [
        pw.SizedBox(height: 20),
        pw.Center(child: pw.Text(reportTitle, style: pw.TextStyle(font: _extraBold, fontSize: 18, color: PdfColors.blueGrey900))),
        pw.SizedBox(height: 10),
        pw.Center(child: pw.Text('${reportType.toUpperCase()} PERIOD: ${DateFormat(reportType == 'daily' ? 'MMMM dd, yyyy' : 'MMMM yyyy').format(now)}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700))),
        pw.SizedBox(height: 24),
        
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          columnWidths: colWidths,
          children: [
            pw.TableRow(
              children: List.generate(headers.length, (hIdx) {
                final h = headers[hIdx];
                final isProductCol = !isShop && hIdx >= 5 && hIdx < (5 + (AppData.beansProducts.length * 2));
                PdfColor bg = PdfColors.blueGrey900;
                
                if (isProductCol) {
                  final pIdx = (hIdx - 5) ~/ 2;
                  final pName = AppData.beansProducts[pIdx]['name'].toString();
                  if (hIdx % 2 == 0) {
                    // Main product column color
                    if (pName.contains('SAMPLE 2')) {
                      bg = PdfColors.orange400;
                    } else if (pName.contains('SAMPLE 1')) {
                      bg = PdfColors.green600;
                    } else if (pName.contains('SAMPLE 3')) {
                      bg = PdfColors.red800;
                    } else {
                      bg = PdfColors.cyan600;
                    }
                  } else {
                    bg = PdfColors.orange50;
                    if (pName.contains('SAMPLE 1')) {
                      bg = PdfColors.green50;
                    } else if (pName.contains('SAMPLE 3')) {
                      bg = PdfColors.red50;
                    } else if (pName.contains('SAMPLE 2')) {
                      bg = PdfColors.orange50;
                    }
                  }
                }

                return pw.Container(
                  color: bg,
                  padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                  alignment: pw.Alignment.center,
                  child: pw.Text(h, 
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(font: _bold, fontSize: 8.5, color: bg.luminance > 0.5 ? PdfColors.brown900 : PdfColors.white)),
                );
              }),
            ),
            ...List.generate(dataRows.length, (index) => pw.TableRow(
              decoration: pw.BoxDecoration(color: index % 2 == 1 ? PdfColors.grey50 : PdfColors.white),
              children: List.generate(dataRows[index].length, (vIdx) {
                final v = dataRows[index][vIdx];
                return pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                  alignment: pw.Alignment.center,
                  child: pw.Text(v, style: const pw.TextStyle(fontSize: 8.5)),
                );
              }),
            )),
          ],
        ),
      ],
    ));



    try {
      final bytes = await pdf.save();
      if (bytes.isEmpty) {
        debugPrint("Error: Document bytes are empty. Generation aborted.");
        return;
      }
      final String suggestedName = '${isShop ? 'Shop' : 'Beans'}_${reportType.toUpperCase()}_${DateFormat('yyyyMMdd').format(now)}.pdf';
      await _saveFile(bytes, suggestedName, 'Save PDF Report');
    } catch (e) {
      debugPrint("Full Document Save Fault: $e");
    }
  }

  static Future<void> bulkPrint(List<Map<String, dynamic>> transactions, {String? preparedBy}) async {
    if (transactions.isEmpty) return;
    await _loadFonts();
    pw.MemoryImage? logo = await _loadLogo();
    final pdf = pw.Document();
    for (final tx in transactions) {
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => _buildReceiptBody(tx, logo, preparedBy: preparedBy),
      ));
    }
    await _saveFile(await pdf.save(), 'BULK_RECEIPTS_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf', 'Save Bulk Receipts');
  }

  static Future<void> exportInventoryReport({
    required String business,
    required DateTime date,
    required List<Map<String, dynamic>> ingredients,
    required bool isMonthly,
  }) async {
    await _loadFonts();
    final pdf = pw.Document();
    final isShop = business == 'shop';
    final dateStr = DateFormat('MMMM dd, yyyy').format(date).toUpperCase();
    final logo = await _loadLogo();

    final int chunkSize = isMonthly ? 5 : ingredients.length;
    final chunks = <List<Map<String, dynamic>>>[];
    for (var i = 0; i < ingredients.length; i += chunkSize) {
      chunks.add(ingredients.sublist(i, i + chunkSize > ingredients.length ? ingredients.length : i + chunkSize));
    }

    for (var pIndex = 0; pIndex < chunks.length; pIndex++) {
      final currentChunk = chunks[pIndex];
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _buildLetterhead(logo),
            pw.Divider(thickness: 0.5),
            pw.SizedBox(height: 5),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.blueGrey800,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Text(
                    isMonthly ? 'MONTHLY STOCK SUMMARY RECORD' : 'DAILY INVENTORY AUDIT RECORD',
                    style: pw.TextStyle(font: _bold, fontSize: 11, color: PdfColors.white),
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(dateStr, style: pw.TextStyle(font: _bold, fontSize: 12, color: PdfColors.blueGrey900)),
                    pw.Text('System Sync: ${DateFormat('hh:mm a').format(DateTime.now())}', 
                      style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                    pw.Text('Part ${pIndex + 1} of ${chunks.length}', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            isMonthly ? _buildMonthlyTable(isShop, currentChunk, date) : _buildDailyTable(isShop, currentChunk),
            pw.Spacer(),
            pw.Divider(color: PdfColors.grey300),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('Certified Accounting Copy • Innovative Cuppa Inventory System v2.0', style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey400)),
              pw.Text('Page ${pIndex + 1} of ${chunks.length}', style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey400)),
            ]),
          ],
        ),
      ));
    }

    final prefix = isMonthly ? 'MonthlyInv' : 'DailyInv';
    await _saveFile(await pdf.save(), '${prefix}_${business.toUpperCase()}_${DateFormat('yyyyMMdd').format(date)}.pdf', 'Save Inventory Report');
  }

  static pw.Widget _buildDailyTable(bool isShop, List<Map<String, dynamic>> ingredients) {
    final nameKey = isShop ? 'name' : 'product_name';
    final totalIn = AppData.getStockAddTotal(isShop);
    final totalOut = AppData.getStockOutTotal(isShop);
    
    return pw.Stack(
      children: [
        // Side Accent Bar for premium look
        pw.Positioned(
          left: -24, top: -10, bottom: -10,
          child: pw.Container(width: 5, color: PdfColors.blueGrey800),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // Quick Summary Stats Row
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _summaryStat('TOTAL STOCK-IN', AppData.fmt(totalIn), PdfColors.green700),
                _summaryStat('TOTAL STOCK-OUT', AppData.fmt(totalOut), PdfColors.red700),
                _summaryStat('AUDIT SAMPLE', '${ingredients.length} items', PdfColors.blueGrey700),
              ],
            ),
            pw.SizedBox(height: 20),
            
            // Modern Clean Table
            pw.Table(
              columnWidths: {
                0: const pw.FlexColumnWidth(5),
                1: const pw.FlexColumnWidth(1.2),
                2: const pw.FlexColumnWidth(1.2),
                3: const pw.FlexColumnWidth(1.2),
                4: const pw.FlexColumnWidth(1.5),
              },
              children: [
                // Header Row
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.blueGrey900,
                    borderRadius: pw.BorderRadius.vertical(top: pw.Radius.circular(6)),
                  ),
                  children: [
                    _thModern('PRODUCT / INGREDIENT NAME', align: pw.Alignment.centerLeft),
                    _thModern('BEG.'),
                    _thModern('ADD'),
                    _thModern('OUT'),
                    _thModern('ENDING'),
                  ],
                ),
                // Data Rows
                ...List.generate(ingredients.length, (index) {
                  final ing = ingredients[index];
                  final isLast = index == ingredients.length - 1;
                  final isAlt = index % 2 == 1;
                  final name = ing[nameKey] as String;
                  final daily = AppData.getIngredientDaily(ing, isShop) ?? {
                    'beg': (ing[isShop ? 'stock' : 'balance_qty'] ?? 0.0) as double,
                    'add': 0.0, 'out': 0.0,
                    'end': (ing[isShop ? 'stock' : 'balance_qty'] ?? 0.0) as double,
                  };
                  
                  return pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: isAlt ? PdfColors.grey50 : PdfColors.white,
                      border: pw.Border(
                        bottom: isLast ? const pw.BorderSide(color: PdfColors.blueGrey900, width: 1) : const pw.BorderSide(color: PdfColors.grey200, width: 0.5),
                        left: const pw.BorderSide(color: PdfColors.grey200, width: 0.5),
                        right: const pw.BorderSide(color: PdfColors.grey200, width: 0.5),
                      ),
                    ),
                    children: [
                      _tdModern(name, isBold: true, align: pw.Alignment.centerLeft),
                      _tdModern(AppData.formatStock(daily['beg'] as double, daily['unit'] ?? ''), color: PdfColors.blueGrey600),
                      _tdModern(AppData.formatStock(daily['add'] as double, daily['unit'] ?? ''), color: PdfColors.green700),
                      _tdModern(AppData.formatStock(daily['out'] as double, daily['unit'] ?? ''), color: PdfColors.red700),
                      _tdModern(AppData.formatStock(daily['end'] as double, daily['unit'] ?? ''), isBold: true, color: PdfColors.blueGrey900),
                    ],
                  );
                }),
              ],
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _summaryStat(String label, String value, PdfColor color) {
    return pw.Container(
      width: 160,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: PdfColors.grey200),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
          pw.SizedBox(height: 4),
          pw.Text(value, style: pw.TextStyle(font: _bold, fontSize: 14, color: color)),
        ],
      ),
    );
  }

  static pw.Widget _thModern(String text, {pw.Alignment align = pw.Alignment.center}) => pw.Container(
    height: 24, alignment: align, padding: const pw.EdgeInsets.symmetric(horizontal: 10),
    child: pw.Text(text, style: pw.TextStyle(font: _bold, fontSize: 8, color: PdfColors.white)),
  );

  static pw.Widget _tdModern(String text, {bool isBold = false, pw.Alignment align = pw.Alignment.center, PdfColor? color}) => pw.Container(
    height: 28, alignment: align, padding: const pw.EdgeInsets.symmetric(horizontal: 10),
    child: pw.Text(text, style: pw.TextStyle(font: isBold ? _bold : _regular, fontSize: 9, color: color ?? PdfColors.black)),
  );


  static pw.Widget _buildMonthlyTable(bool isShop, List<Map<String, dynamic>> ingredients, DateTime date) {
    const double dateWidth = 40.0;
    final columnWidths = <int, pw.TableColumnWidth>{
      0: const pw.FixedColumnWidth(dateWidth),
    };
    for (var i = 1; i <= ingredients.length * 4; i++) {
        columnWidths[i] = const pw.FlexColumnWidth(1);
    }
    
    final nameKey = isShop ? 'name' : 'product_name';
    final daysInMonth = DateTime(date.year, date.month + 1, 0).day;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          alignment: pw.Alignment.centerLeft,
          child: pw.Text('DAILY INVENTORY ACCOUNTING RECORD (${DateFormat('MMMM yyyy').format(date).toUpperCase()})', style: pw.TextStyle(font: _bold, fontSize: 6.5)),
        ),
        // Unified Branded Header Row
        pw.Row(
          children: [
            pw.Container(
              width: dateWidth, height: 12, 
              alignment: pw.Alignment.center,
              decoration: const pw.BoxDecoration(
                color: PdfColors.grey300, 
                border: pw.Border(
                  left: pw.BorderSide(color: PdfColors.grey400, width: 0.2),
                  top: pw.BorderSide(color: PdfColors.grey400, width: 0.2),
                  bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.2),
                ),
              ),
              child: pw.Text('DATE', style: pw.TextStyle(font: _bold, fontSize: 5)),
            ),
            ...List.generate(ingredients.length, (pIdx) {
              final name = ingredients[pIdx][nameKey] as String;
              final color = _getIngColor(name);
              return pw.Expanded(
                flex: 4, 
                child: pw.Container(
                  height: 12, 
                  alignment: pw.Alignment.center,
                  decoration: pw.BoxDecoration(
                    color: color,
                    border: pw.Border.all(color: PdfColors.grey400, width: 0.2),
                  ),
                  child: pw.Text(name, 
                    style: pw.TextStyle(font: _bold, fontSize: 5, color: PdfColors.white),
                    maxLines: 1, 
                    overflow: pw.TextOverflow.clip),
                ),
              );
            }),
          ],
        ),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.2),
          columnWidths: columnWidths,
          children: [
            // Sub-metrics Header
            pw.TableRow(
              children: [
                pw.Container(color: PdfColors.grey200, height: 10),
                ...List.generate(ingredients.length, (_) => [
                  _thInvGrid('BEG.', PdfColors.grey100),
                  _thInvGrid('ADD', PdfColors.grey100),
                  _thInvGrid('OUT', PdfColors.grey100),
                  _thInvGrid('END', PdfColors.grey100),
                ]).expand((e) => e),
              ],
            ),
            // Data Rows (Days of Month)
            ...List.generate(daysInMonth, (index) {
              final currentDay = DateTime(date.year, date.month, index + 1);
              final dayStr = DateFormat('MMM d').format(currentDay);
              
              return pw.TableRow(
                children: [
                  _tdInvGrid(dayStr, isBold: true, bg: PdfColors.grey200),
                  ...List.generate(ingredients.length, (pIdx) {
                    final daily = AppData.getIngredientDaily(ingredients[pIdx], isShop, date: currentDay);
                    
                    if (daily == null) {
                      return [ _tdInvGrid('0'), _tdInvGrid('0'), _tdInvGrid('0'), _tdInvGrid('0', isBold: true) ];
                    }
                    
                    return [
                      _tdInvGrid(AppData.formatStock(daily['beg'] as double, daily['unit'] ?? '')),
                      _tdInvGrid(AppData.formatStock(daily['add'] as double, daily['unit'] ?? '')),
                      _tdInvGrid(AppData.formatStock(daily['out'] as double, daily['unit'] ?? '')),
                      _tdInvGrid(AppData.formatStock(daily['end'] as double, daily['unit'] ?? ''), isBold: true),
                    ];
                  }).expand((e) => e),
                ],
              );
            }),
          ],
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // SHARED COMPONENTS
  // ══════════════════════════════════════════════════════════════════════════════

  static pw.Widget _buildLetterhead(pw.MemoryImage? logo) {
    return pw.Column(
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            if (logo != null) pw.Container(width: 35, height: 35, child: pw.Image(logo, fit: pw.BoxFit.contain)),
            pw.SizedBox(width: 12),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('INNOVATIVE CUPPA COFFEE ROASTERY SERVICES', style: pw.TextStyle(font: _bold, fontSize: 13, color: PdfColors.blueGrey900, letterSpacing: 0.5)),
                pw.Text('1ST FLOOR JARAULA BLDG.. JV SERIÑA ST. CARMEN, CAGAYAN DE ORO CITY', style: const pw.TextStyle(fontSize: 7, color: PdfColors.blueGrey700)),
                pw.Text('Telephone number: (088) 8587324 / 0915-2700-658 / 0933-985-1948', style: const pw.TextStyle(fontSize: 7, color: PdfColors.blueGrey700)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Container(height: 1, color: PdfColors.grey200),
      ],
    );
  }

  static PdfColor _getIngColor(String name) {
    if (name.contains('ESPRESSO')) return PdfColor.fromInt(0xFF795548);
    if (name.contains('WHOLE MILK')) return PdfColor.fromInt(0xFF64B5F6);
    if (name.contains('OAT MILK')) return PdfColor.fromInt(0xFF81C784);
    if (name.contains('VANILLA')) return PdfColor.fromInt(0xFFFFB74D);
    if (name.contains('CARAMEL')) return PdfColor.fromInt(0xFFD4AF37);
    if (name.contains('WHIPPED')) return PdfColors.grey400;
    return PdfColors.grey700;
  }

  static pw.Widget _thInvGrid(String text, PdfColor bg, {bool isMain = false}) => pw.Container(
    height: 14, alignment: pw.Alignment.center, color: bg,
    child: pw.Text(text, style: pw.TextStyle(font: _bold, fontSize: isMain ? 7 : 6)),
  );

  static pw.Widget _tdInvGrid(String text, {bool isBold = false, PdfColor? bg, double height = 10}) => pw.Container(
    height: height, alignment: pw.Alignment.center, color: bg,
    child: pw.Text(text, style: pw.TextStyle(font: isBold ? _bold : _regular, fontSize: 6.5)),
  );

  static pw.Widget _buildReceiptBody(Map<String, dynamic> tx, pw.MemoryImage? logo, {String? preparedBy}) {
    final rawDate = tx['date'] ?? tx['generated_at'] ?? tx['timestamp'];
    final date = (rawDate is DateTime) ? rawDate : (DateTime.tryParse(rawDate?.toString() ?? '') ?? DateTime.now());
    final items = (tx['items'] as List<dynamic>? ?? []);
    final id = tx['sr_number']?.toString() ?? tx['id']?.toString() ?? 'N/A';
    
    // 🛡️ Pre-calculate grand total with high-precision fallbacks
    final total = (tx['total_amount'] ?? tx['amount'] ?? items.fold(0.0, (sum, i) => sum + (((i['qty'] ?? 0) as num).toDouble() * ((i['price'] ?? 0) as num).toDouble()))) as num;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _buildLetterhead(logo),
        pw.SizedBox(height: 10),
        pw.Divider(thickness: 1, color: PdfColors.grey300),
        pw.SizedBox(height: 10),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('RECEIPT NO: $id', style: pw.TextStyle(font: _bold, fontSize: 9)),
            pw.Text('DATE: ${DateFormat('MMMM dd, yyyy').format(date)}', style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Center(child: pw.Text('SALES RECEIPT', style: pw.TextStyle(font: _extraBold, fontSize: 24, letterSpacing: 2))),
        pw.SizedBox(height: 16),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              _infoRow('Customer:', tx['customer_name']?.toString() ?? 'General Client'),
              _infoRow('Contact:', tx['contact']?.toString() ?? '#N/A'),
              _infoRow('Address:', tx['address']?.toString() ?? '#N/A'),
            ]),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              _infoRow('Payment Mode:', tx['payment_mode']?.toString() ?? 'N/A'),
            ]),
          ],
        ),
        pw.SizedBox(height: 20),
        pw.Table(
          border: pw.TableBorder.all(color: _Clr.darker, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(3),
            1: const pw.FixedColumnWidth(60),
            2: const pw.FixedColumnWidth(60),
            3: const pw.FixedColumnWidth(80),
            4: const pw.FixedColumnWidth(100),
          },
          children: [
            pw.TableRow(decoration: const pw.BoxDecoration(color: _Clr.excelBrown), children: [
              _th('Particulars'), _th('Qty.', center: true), _th('Unit', center: true), _th('Unit Cost', center: true), _th('Total', center: true),
            ]),
            ...items.map((item) {
              final qty = item['qty'] is num ? (item['qty'] as num).toDouble() : 0.0;
              final price = item['price'] is num ? (item['price'] as num).toDouble() : 0.0;
              return pw.TableRow(children: [
                _td(item['name']?.toString() ?? 'Unknown'),
                _td(AppData.fmt(qty), center: true),
                _td(AppData.isShop(tx['id']?.toString() ?? '') ? 'units' : 'pcs', center: true),
                _td(_pf(price), center: true),
                _td(_pf(qty * price), center: true),
              ]);
            }),
            pw.TableRow(children: [
              _td('', border: false), _td('', border: false), _td('', border: false),
              pw.Container(padding: const pw.EdgeInsets.all(6), alignment: pw.Alignment.centerRight, child: pw.Text('TOTAL', style: pw.TextStyle(font: _bold, fontSize: 10))),
              _td(_pf(total.toDouble()), center: true, bold: true),
            ]),
          ],
        ),
        pw.SizedBox(height: 40),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Prepared by:', style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 20),
            pw.Container(width: 140, height: 0.5, color: _Clr.darker),
            pw.Text(preparedBy ?? 'Authorized Representative', style: pw.TextStyle(font: _bold, fontSize: 11)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Receive By:', style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 20),
            pw.Container(width: 140, height: 0.5, color: _Clr.darker),
            pw.Text(tx['receiver_name']?.toString() ?? 'Famela Sumania', style: pw.TextStyle(font: _bold, fontSize: 11)),
          ]),
        ]),
      ],
    );
  }

  static pw.Widget _infoRow(String label, String value) => pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
    pw.SizedBox(width: 70, child: pw.Text(label, style: pw.TextStyle(font: _bold, fontSize: 8))),
    pw.Text(value, style: const pw.TextStyle(fontSize: 8)),
  ]);

  static pw.Widget _th(String text, {bool center = false}) => pw.Container(
    padding: const pw.EdgeInsets.all(6), alignment: center ? pw.Alignment.center : pw.Alignment.centerLeft,
    child: pw.Text(text, style: pw.TextStyle(font: _bold, fontSize: 9)),
  );

  static pw.Widget _td(String text, {bool center = false, bool bold = false, bool border = true}) => pw.Container(
    padding: const pw.EdgeInsets.all(6), alignment: center ? pw.Alignment.center : pw.Alignment.centerLeft,
    child: pw.Text(text, style: pw.TextStyle(font: bold ? _bold : _regular, fontSize: 9)),
  );
}
