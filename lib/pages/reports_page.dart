import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/app_data.dart';
import '../utils/pdf_generator.dart';
import 'package:printing/printing.dart';

class ReportsPage extends StatefulWidget {
  final String business;
  final Map<String, dynamic> user;
  const ReportsPage({super.key, required this.business, required this.user});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  int _activeTab = 0;
  DateTime _selectedDate = DateTime.now();
  final ScrollController _horizontalScroll = ScrollController();
  final ScrollController _verticalScroll = ScrollController();

  List<Map<String, dynamic>> _displayTransactions = [];
  Map<String, dynamic>? _selectedTxForPreview;
  bool _isExporting = false;

  bool get _isShop => widget.business == 'shop';
  Color get _accent => _isShop ? const Color(0xFFC8822A) : const Color(0xFF4A7C59);
  Color get _accentLight => _isShop ? const Color(0xFFFDF3E7) : const Color(0xFFEAF4ED);
  Color get _accentDark => _isShop ? const Color(0xFF8B5E1E) : const Color(0xFF2E5039);

  @override
  void initState() {
    super.initState();
    _loadData();
    AppData.syncNotifier.addListener(_loadData);
  }

  @override
  void dispose() {
    AppData.syncNotifier.removeListener(_loadData);
    _horizontalScroll.dispose();
    _verticalScroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ReportsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.business != widget.business) {
      setState(() {
        _activeTab = 0;
        _selectedTxForPreview = null;
      });
      _loadData();
    }
  }

  void _loadData() {
    final now = DateTime.now();
    setState(() {
      final list = _isShop
          ? AppData.shopReports
          : ((_activeTab == 0 || _activeTab == 1) ? AppData.beansSrData : AppData.beansTransactions);

      _displayTransactions = list.where((t) {
        final rawDate = t['date'] ?? t['generated_at'] ?? t['timestamp'];
        DateTime d;
        if (rawDate is DateTime) {
          d = rawDate.toLocal();
        } else {
          d = (DateTime.tryParse(rawDate?.toString() ?? '') ?? now).toLocal();
        }
        if (_isShop && _activeTab == 1) {
          return d.year == _selectedDate.year && d.month == _selectedDate.month;
        }
        return d.year == _selectedDate.year && d.month == _selectedDate.month && d.day == _selectedDate.day;
      }).toList();

      _displayTransactions.sort((a, b) {
        final rawA = a['date'] ?? a['generated_at'] ?? a['timestamp'];
        final rawB = b['date'] ?? b['generated_at'] ?? b['timestamp'];
        final DateTime da = rawA is DateTime ? rawA.toLocal() : (DateTime.tryParse(rawA?.toString() ?? '') ?? now).toLocal();
        final DateTime db = rawB is DateTime ? rawB.toLocal() : (DateTime.tryParse(rawB?.toString() ?? '') ?? now).toLocal();
        if (!_isShop && _activeTab == 1) {
          final aP = a['isPrinted'] as bool? ?? false;
          final bP = b['isPrinted'] as bool? ?? false;
          if (aP != bP) return aP ? 1 : -1;
        }
        return db.compareTo(da);
      });

      if (_displayTransactions.isNotEmpty) {
        if (_selectedTxForPreview == null || !_displayTransactions.any((tx) => tx['id'] == _selectedTxForPreview!['id'])) {
          _selectedTxForPreview = _displayTransactions.first;
        }
      }
    });
  }

  void _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2101),
      initialDatePickerMode: _activeTab == 1 ? DatePickerMode.year : DatePickerMode.day,
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF4F6F9),
          body: Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: _activeTab == 1 && !_isShop
                    ? _buildSrSplitView(_accent)
                    : _buildMainLayout(),
              ),
            ],
          ),
        ),
        if (_isExporting) _buildExportOverlay(),
      ],
    );
  }

  // ─── TOP BAR ─────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    final tabs = _isShop
        ? ['Daily Reports', 'Monthly Insights', 'Product Sales']
        : ['SR Data', 'SR Print'];

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE8EAF0), width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Title
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 4, height: 20,
                          decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(2)),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _isShop ? 'Shop Analytics' : 'Beans Analytics',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF1A1D23), letterSpacing: -0.3),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 14),
                      child: Text(
                        DateFormat(_activeTab == 1 && _isShop ? 'MMMM yyyy' : 'EEEE, MMMM d, yyyy').format(_selectedDate),
                        style: const TextStyle(fontSize: 12, color: Color(0xFF8B8FA8)),
                      ),
                    ),
                  ],
                ),
              ),
              // Actions
              _topBarBtn(Icons.calendar_today_rounded, DateFormat('MMM dd').format(_selectedDate), _selectDate, outlined: true),
              const SizedBox(width: 10),
              _topBarBtn(Icons.picture_as_pdf_rounded, 'Export PDF', () async {
                setState(() => _isExporting = true);
                await Future.delayed(const Duration(milliseconds: 100));
                String type = 'daily';
                if (_activeTab == 1) type = 'monthly';
                if (_activeTab == 2) type = 'products';
                try {
                  await PdfGenerator.exportTableToPdf(_displayTransactions, isShop: _isShop, reportType: type, date: _selectedDate);
                } finally {
                  if (mounted) setState(() => _isExporting = false);
                }
              }),
            ],
          ),
          const SizedBox(height: 16),
          // Tabs
          Row(
            children: List.generate(tabs.length, (i) {
              final isActive = _activeTab == i;
              return GestureDetector(
                onTap: () { setState(() => _activeTab = i); _loadData(); },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: isActive ? _accentLight : Colors.transparent,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                    border: Border(bottom: BorderSide(color: isActive ? _accent : Colors.transparent, width: 2.5)),
                  ),
                  child: Text(
                    tabs[i],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      color: isActive ? _accentDark : const Color(0xFF8B8FA8),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _topBarBtn(IconData icon, String label, VoidCallback onTap, {bool outlined = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: outlined ? Colors.white : _accent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: outlined ? const Color(0xFFDDE1EE) : _accent),
          boxShadow: outlined ? [] : [BoxShadow(color: _accent.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: outlined ? const Color(0xFF5C6077) : Colors.white),
            const SizedBox(width: 7),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: outlined ? const Color(0xFF5C6077) : Colors.white)),
          ],
        ),
      ),
    );
  }

  // ─── MAIN LAYOUT ─────────────────────────────────────────────────────────────

  Widget _buildMainLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Header Chart (only for Beans SR Data tab)
        if (!_isShop && _activeTab == 0) _buildSidebar(),
        // Bottom Table Area
        Expanded(child: _buildTableArea()),
      ],
    );
  }

  // ─── SIDEBAR ────────────────────────────────────────────────────────────────

  Widget _buildSidebar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('WEEKLY SALES PERFORMANCE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF8B8FA8), letterSpacing: 1.5)),
          const SizedBox(height: 12),
          _buildMiniChart(),
        ],
      ),
    );
  }


  Widget _buildMiniChart() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    const dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final todayIdx = now.weekday - 1;

    final sales = List.generate(7, (i) {
      final day = DateTime(monday.year, monday.month, monday.day + i);
      return (_isShop ? AppData.shopReports : AppData.beansSrData).where((t) {
        final raw = t['date'] ?? t['generated_at'];
        final d = raw is DateTime ? raw : DateTime.tryParse(raw?.toString() ?? '') ?? DateTime(2000);
        return DateUtils.isSameDay(day, d);
      }).fold(0.0, (sum, t) => sum + ((t['amount'] ?? t['total_amount'] ?? 0.0) as num).toDouble());
    });

    final maxSale = sales.reduce((a, b) => a > b ? a : b);
    final weekTotal = sales.fold(0.0, (a, b) => a + b);

    return Container(
      height: 200,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EAF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Weekly Sales', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF1A1D23))),
                  Text(
                    '${DateFormat('MMM d').format(monday)} – ${DateFormat('MMM d').format(monday.add(const Duration(days: 6)))}',
                    style: const TextStyle(fontSize: 9, color: Color(0xFF8B8FA8)),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₱ ${NumberFormat('#,##0').format(weekTotal)}',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: _accent),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: _accentLight, borderRadius: BorderRadius.circular(10)),
                    child: Text('LIVE', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: _accentDark)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Bars
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final val = sales[i];
                final isToday = i == todayIdx;
                final isZero = val == 0;
                final heightRatio = maxSale == 0 ? 0.0 : val / maxSale;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (!isZero)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              '₱${NumberFormat.compact().format(val)}',
                              style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.w700, color: isToday ? _accentDark : const Color(0xFF5C6077)),
                            ),
                          ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 550),
                          curve: Curves.easeOutCubic,
                          height: isZero ? 3 : (68 * heightRatio).clamp(3.0, 68.0),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: isToday
                                  ? [_accent, _accentDark]
                                  : isZero
                                      ? [const Color(0xFFEEF0F5), const Color(0xFFEEF0F5)]
                                      : [_accent.withValues(alpha: 0.55), _accent.withValues(alpha: 0.28)],
                            ),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                            boxShadow: isToday
                                ? [BoxShadow(color: _accent.withValues(alpha: 0.35), blurRadius: 7, offset: const Offset(0, 2))]
                                : [],
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          dayLabels[i].substring(0, 2),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                            color: isToday ? _accent : const Color(0xFF8B8FA8),
                          ),
                        ),
                        SizedBox(
                          height: 5,
                          child: isToday
                              ? Center(child: Container(width: 4, height: 4, decoration: BoxDecoration(color: _accent, shape: BoxShape.circle)))
                              : null,
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }




  // ─── TABLE AREA ──────────────────────────────────────────────────────────────

  Widget _buildTableArea() {
    return Container(
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EAF0)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: _buildTabView(),
      ),
    );
  }

  Widget _buildTabView() {
    if (_isShop) {
      if (_activeTab == 0 || _activeTab == 1) return _buildStandardTable();
      return _buildProductSalesView();
    }
    if (_activeTab == 0) return _buildSrDataTable();
    if (_activeTab == 1) return _buildSrSplitView(_accent);
    return _buildInventoryGrid();
  }

  // ─── SR DATA TABLE ──────────────────────────────────────────────────────────

  Widget _buildSrDataTable() {
    final palette = [
      {'color': const Color(0xFFF97316), 'sub': const Color(0xFFFFF0E6)},
      {'color': const Color(0xFF16A34A), 'sub': const Color(0xFFE8F5ED)},
      {'color': const Color(0xFFDC2626), 'sub': const Color(0xFFFEF0F0)},
      {'color': const Color(0xFF2563EB), 'sub': const Color(0xFFEFF3FF)},
      {'color': const Color(0xFF7C3AED), 'sub': const Color(0xFFF3EEFF)},
      {'color': const Color(0xFF0891B2), 'sub': const Color(0xFFECFAFF)},
    ];

    final products = List.generate(AppData.beansProducts.length, (i) {
      final p = AppData.beansProducts[i];
      final c = palette[i % palette.length];
      return {'name': p['name'], 'color': c['color'], 'sub': c['sub']};
    });

    // Column widths (must match between header and data rows)
    const double wSr = 90.0;
    const double wDate = 80.0;
    const double wName = 150.0;
    const double wAddr = 150.0;
    const double wContact = 110.0;
    const double wQty = 90.0;
    const double wCost = 90.0;
    const double wDel = 90.0;
    const double wTotal = 110.0;
    const double wMode = 110.0;
    const double wRef = 120.0;
    const double wAction = 60.0;

    Widget headerCell(String label, double w, {Color bg = const Color(0xFF1E2330), Color textColor = Colors.white, TextAlign align = TextAlign.center}) {
      return Container(
        width: w,
        height: 44,
        alignment: align == TextAlign.center ? Alignment.center : Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: bg, border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 0.5))),
        child: Text(label, textAlign: align, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: textColor, letterSpacing: 0.2)),
      );
    }

    Widget dataCell(String val, double w, {bool bold = false, bool center = false, Color? bg, Color textColor = const Color(0xFF1A1D23)}) {
      return Container(
        width: w,
        height: 44,
        alignment: center ? Alignment.center : Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: bg ?? Colors.transparent,
          border: Border(right: BorderSide(color: const Color(0xFFEEF0F5), width: 0.5)),
        ),
        child: Text(val, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: textColor)),
      );
    }

    return Scrollbar(
      controller: _horizontalScroll,
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        controller: _horizontalScroll,
        child: SizedBox(
          width: wSr + wDate + wName + wAddr + wContact + (products.length * (wQty + wCost)) + wDel + wTotal + wMode + wRef + wAction,
          child: Column(
            children: [
              // Header
              Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF1E2330),
                  border: Border(bottom: BorderSide(color: Color(0xFF2D3348))),
                ),
                child: Row(children: [
                  headerCell('SR NO.', wSr),
                  headerCell('DATE', wDate),
                  headerCell('CUSTOMER', wName),
                  headerCell('ADDRESS', wAddr),
                  headerCell('CONTACT', wContact),
                  ...products.map((p) => Row(children: [
                    Container(
                      width: wQty, height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: (p['color'] as Color), border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.15)))),
                      child: Text((p['name'] as String).toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white)),
                    ),
                    Container(
                      width: wCost, height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: (p['sub'] as Color), border: Border(right: BorderSide(color: const Color(0xFFDDE1EE)))),
                      child: Text('UNIT COST', textAlign: TextAlign.center, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: (p['color'] as Color))),
                    ),
                  ])),
                  headerCell('DELIVERY', wDel),
                  headerCell('TOTAL', wTotal),
                  headerCell('MODE', wMode),
                  headerCell('REF NO.', wRef),
                  headerCell('', wAction),
                ]),
              ),
              // Body
              Expanded(
                child: _displayTransactions.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            Text('No records for ${DateFormat('MMM dd, yyyy').format(_selectedDate)}', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                          ],
                        ),
                      )
                    : Scrollbar(
                        controller: _verticalScroll,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _verticalScroll,
                          child: Column(
                            children: List.generate(_displayTransactions.length, (idx) {
                              final t = _displayTransactions[idx];
                              final items = t['items'] as List<dynamic>? ?? [];
                              final isEven = idx % 2 == 0;
                              final rawDate = t['date'] ?? t['generated_at'];
                              final dt = rawDate is DateTime ? rawDate : DateTime.tryParse(rawDate?.toString() ?? '') ?? DateTime.now();

                              return Container(
                                decoration: BoxDecoration(
                                  color: isEven ? Colors.white : const Color(0xFFF8F9FC),
                                  border: const Border(bottom: BorderSide(color: Color(0xFFEEF0F5))),
                                ),
                                child: Row(children: [
                                  dataCell(t['sr_number'] ?? t['id'] ?? '', wSr, bold: true, textColor: _accent),
                                  dataCell(DateFormat('MM/dd/yy').format(dt), wDate, center: true),
                                  dataCell(t['customer_name'] ?? 'General', wName, bold: true),
                                  dataCell(t['address'] ?? '—', wAddr),
                                  dataCell(t['contact'] ?? '—', wContact),
                                  ...products.map((p) {
                                    final pName = (p['name'] as String);
                                    final sold = items.where((i) => i['name'].toString().toLowerCase() == pName.toLowerCase()).toList();
                                    final qty = sold.isEmpty ? 0 : sold.fold(0, (sum, i) => sum + (i['qty'] as num).toInt());
                                    final cost = sold.isEmpty ? 0.0 : (sold.first['price'] as num).toDouble();
                                    return Row(children: [
                                      dataCell(qty > 0 ? '$qty' : '—', wQty, center: true, bg: qty > 0 ? (p['color'] as Color).withValues(alpha: 0.08) : null, textColor: qty > 0 ? (p['color'] as Color) : Colors.grey[400]!, bold: qty > 0),
                                      dataCell(qty > 0 ? '₱${NumberFormat('#,##0.00').format(cost)}' : '—', wCost, center: true, bg: qty > 0 ? (p['sub'] as Color) : null, textColor: qty > 0 ? (p['color'] as Color) : Colors.grey[400]!),
                                    ]);
                                  }),
                                  dataCell('₱${NumberFormat('#,##0.00').format((t['delivery_fee'] ?? 0).toDouble())}', wDel),
                                  dataCell('₱${NumberFormat('#,##0.00').format(((t['amount'] ?? t['total_amount'] ?? 0) as num).toDouble())}', wTotal, bold: true, textColor: const Color(0xFF16A34A)),
                                  dataCell(t['payment_mode'] ?? 'Cash', wMode, center: true),
                                  dataCell(t['reference_number'] ?? '—', wRef),
                                  Container(
                                    width: wAction, height: 44,
                                    alignment: Alignment.center,
                                    child: IconButton(
                                      icon: Icon(Icons.edit_note_rounded, size: 18, color: _accent),
                                      onPressed: () => _showEditMetadataDialog(t),
                                      tooltip: 'Edit metadata',
                                    ),
                                  ),
                                ]),
                              );
                            }),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── SR SPLIT VIEW ──────────────────────────────────────────────────────────

  Widget _buildSrSplitView(Color accent) {
    if (_displayTransactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.print_disabled_outlined, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('No records found for ${DateFormat('MMM dd').format(_selectedDate)}', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
          ],
        ),
      );
    }

    return Row(
      children: [
        // Invoice list
        Container(
          width: 320,
          decoration: BoxDecoration(
            color: const Color(0xFFF8F9FC),
            border: Border(right: BorderSide(color: const Color(0xFFE8EAF0))),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE8EAF0)))),
                child: Row(
                  children: [
                    Icon(Icons.list_alt_rounded, size: 16, color: accent),
                    const SizedBox(width: 8),
                    Text('${_displayTransactions.length} Invoices', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1A1D23))),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: _displayTransactions.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final t = _displayTransactions[index];
                    final isSelected = _selectedTxForPreview?['id'] == t['id'];
                    final isPrinted = t['isPrinted'] as bool? ?? false;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedTxForPreview = t),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isSelected ? accent.withValues(alpha: 0.08) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isSelected ? accent.withValues(alpha: 0.4) : const Color(0xFFE8EAF0), width: isSelected ? 1.5 : 1),
                          boxShadow: isSelected ? [BoxShadow(color: accent.withValues(alpha: 0.12), blurRadius: 8)] : [],
                        ),
                        child: Row(children: [
                          Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(color: isSelected ? accent.withValues(alpha: 0.15) : const Color(0xFFF0F2F8), borderRadius: BorderRadius.circular(10)),
                            child: Icon(isPrinted ? Icons.check_circle_rounded : Icons.receipt_outlined, size: 20, color: isPrinted ? Colors.green : (isSelected ? accent : Colors.grey[400]!)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(t['sr_number'] ?? t['id'] ?? 'N/A', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: isSelected ? accent : const Color(0xFF1A1D23))),
                            Text(t['customer_name'] ?? 'General', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                          ])),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text('₱${NumberFormat('#,##0').format((t['amount'] ?? t['total_amount'] ?? 0))}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: isSelected ? accent : const Color(0xFF1A1D23))),
                            if (!isPrinted)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.orange[200]!)),
                                child: Text('PENDING', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Colors.orange[700])),
                              ),
                          ]),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        // PDF Preview
        Expanded(
          child: _selectedTxForPreview == null
              ? const Center(child: Text('Select an invoice to preview.'))
              : PdfPreview(
                  build: (format) async {
                    final pdf = await PdfGenerator.generateDocumentForPreview(_selectedTxForPreview!, preparedBy: widget.user['name']);
                    return pdf.save();
                  },
                  loadingWidget: CircularProgressIndicator(color: accent),
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  canDebug: false,
                  allowPrinting: true,
                  allowSharing: false,
                  previewPageMargin: const EdgeInsets.all(32),
                  actions: [
                    PdfPreviewAction(
                      icon: Icon(Icons.picture_as_pdf_rounded, color: accent),
                      onPressed: (context, build, format) => PdfGenerator.printReceipt(_selectedTxForPreview!, preparedBy: widget.user['name']),
                    ),
                  ],
                  onPrinted: (context) {
                    setState(() {
                      _selectedTxForPreview?['isPrinted'] = true;
                      _loadData();
                    });
                  },
                ),
        ),
      ],
    );
  }

  // ─── EDIT METADATA DIALOG ────────────────────────────────────────────────────

  void _showEditMetadataDialog(Map<String, dynamic> tx) {
    final nameCtrl = TextEditingController(text: tx['customer_name'] ?? '');
    final addrCtrl = TextEditingController(text: tx['address'] ?? '');
    final contCtrl = TextEditingController(text: tx['contact'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.edit_note_rounded, color: _accent),
          const SizedBox(width: 10),
          Text('Edit Invoice ${tx['sr_number'] ?? tx['id']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dialogField(nameCtrl, 'Customer Name', Icons.person_rounded),
            const SizedBox(height: 12),
            _dialogField(addrCtrl, 'Address', Icons.location_on_rounded),
            const SizedBox(height: 12),
            _dialogField(contCtrl, 'Contact Number', Icons.phone_rounded),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: Colors.grey[600]))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () async {
              Navigator.pop(ctx);
              await AppData.updateTransactionMetadata(
                widget.business == 'shop', tx['id'],
                customerName: nameCtrl.text, address: addrCtrl.text, contact: contCtrl.text,
              );
            },
            child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _dialogField(TextEditingController ctrl, String label, IconData icon) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18, color: _accent),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE1EE))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE1EE))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _accent, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        filled: true, fillColor: const Color(0xFFF8F9FC),
      ),
    );
  }

  // ─── STANDARD SHOP TABLE ────────────────────────────────────────────────────

  Widget _buildStandardTable() {
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: const BoxDecoration(color: Color(0xFF1E2330), border: Border(bottom: BorderSide(color: Color(0xFF2D3348)))),
        child: Row(children: [
          for (final label in ['Ref ID', 'Date & Time', 'User', 'Mode', 'Amount', ''])
            Expanded(child: Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF8B8FA8), letterSpacing: 0.5))),
        ]),
      ),
      Expanded(
        child: _displayTransactions.isEmpty
            ? Center(child: Text('No records found.', style: TextStyle(color: Colors.grey[400])))
            : ListView.builder(
                itemCount: _displayTransactions.length,
                itemBuilder: (context, idx) {
                  final t = _displayTransactions[idx];
                  final rawDate = t['date'] ?? t['generated_at'] ?? t['timestamp'];
                  final d = rawDate is DateTime ? rawDate.toLocal() : (DateTime.tryParse(rawDate?.toString() ?? '') ?? DateTime.now()).toLocal();
                  final isEven = idx % 2 == 0;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: isEven ? Colors.white : const Color(0xFFF8F9FC),
                      border: const Border(bottom: BorderSide(color: Color(0xFFEEF0F5))),
                    ),
                    child: Row(children: [
                      Expanded(child: Text(t['id'] ?? 'N/A', style: TextStyle(fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.w600, color: _accent))),
                      Expanded(child: Text(DateFormat('MMM d, h:mm a').format(d), style: const TextStyle(fontSize: 12, color: Color(0xFF5C6077)))),
                      Expanded(child: Text(t['user_name'] ?? 'System', style: const TextStyle(fontSize: 12, color: Color(0xFF8B8FA8)))),
                      Expanded(child: Text(t['payment_mode'] ?? 'Cash', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF5C6077)))),
                      Expanded(child: Text('₱ ${NumberFormat('#,##0.00').format(((t['amount'] ?? 0) as num).toDouble())}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF16A34A)))),
                      Expanded(child: const Text('')),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }

  // ─── INVENTORY GRID ──────────────────────────────────────────────────────────

  Widget _buildInventoryGrid() {
    final list = _isShop ? AppData.shopIngredients : AppData.beansInventory;
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 14, mainAxisSpacing: 14, childAspectRatio: 2.4),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final item = list[index];
        final stock = (item['stock'] as num).toDouble();
        final isLow = stock < 10;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isLow ? Colors.red[200]! : const Color(0xFFE8EAF0)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)],
          ),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: isLow ? Colors.red[50] : _accentLight, borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.inventory_2_rounded, size: 20, color: isLow ? Colors.red : _accent),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(item['name'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1A1D23)), overflow: TextOverflow.ellipsis, maxLines: 1),
              Text(isLow ? 'LOW STOCK' : 'In Stock', style: TextStyle(fontSize: 10, color: isLow ? Colors.red : Colors.grey[500], fontWeight: FontWeight.w600)),
            ])),
            Text(stock.toStringAsFixed(0), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: isLow ? Colors.red : _accent)),
          ]),
        );
      },
    );
  }

  // ─── PRODUCT SALES VIEW ──────────────────────────────────────────────────────

  Widget _buildProductSalesView() {
    final Map<String, Map<String, dynamic>> stats = {};
    final now = DateTime.now();
    for (final tx in AppData.shopReports) {
      final rawDate = tx['date'] ?? tx['generated_at'];
      final date = rawDate is DateTime ? rawDate : DateTime.tryParse(rawDate?.toString() ?? '') ?? DateTime(2000);
      final isToday = date.day == now.day && date.month == now.month && date.year == now.year;
      final isMonth = date.month == now.month && date.year == now.year;
      final type = tx['type']?.toString();
      if (!isMonth || type != 'sold') continue;
      final items = tx['items'] as List<dynamic>? ?? [];
      for (final item in items) {
        final name = item['name']?.toString() ?? 'Unknown';
        final qty = ((item['qty'] ?? 0) as num).toInt();
        final price = ((item['price'] ?? 0.0) as num).toDouble();
        if (!stats.containsKey(name)) stats[name] = {'today': 0, 'month': 0, 'revenue': 0.0};
        if (isToday) stats[name]!['today'] += qty;
        stats[name]!['month'] += qty;
        stats[name]!['revenue'] += (qty * price);
      }
    }
    final sorted = stats.keys.toList()..sort((a, b) => stats[b]!['month'].compareTo(stats[a]!['month']));

    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: const BoxDecoration(color: Color(0xFF1E2330)),
        child: Row(children: [
          for (final l in ['Product Name', 'Sold Today', 'Sold This Month', 'Revenue'])
            Expanded(child: Text(l.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF8B8FA8), letterSpacing: 0.5))),
        ]),
      ),
      Expanded(child: ListView.builder(
        itemCount: sorted.length,
        itemBuilder: (context, idx) {
          final name = sorted[idx];
          final s = stats[name]!;
          final isEven = idx % 2 == 0;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            color: isEven ? Colors.white : const Color(0xFFF8F9FC),
            child: Row(children: [
              Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
              Expanded(child: Text('${s['today']} units', style: TextStyle(color: s['today'] > 0 ? Colors.green : Colors.grey, fontWeight: FontWeight.w600))),
              Expanded(child: Text('${s['month']} units', style: const TextStyle(fontWeight: FontWeight.w600))),
              Expanded(child: Text('₱ ${NumberFormat('#,##0.00').format(s['revenue'])}', style: TextStyle(color: _accent, fontWeight: FontWeight.w800))),
            ]),
          );
        },
      )),
    ]);
  }

  // ─── EXPORT OVERLAY ──────────────────────────────────────────────────────────

  Widget _buildExportOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.45),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 36),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 40, offset: const Offset(0, 10))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 48, height: 48, child: CircularProgressIndicator(color: _accent, strokeWidth: 3)),
              const SizedBox(height: 20),
              Text('Generating PDF Report...', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF1A1D23))),
              const SizedBox(height: 6),
              const Text('Please wait while we prepare your document.', style: TextStyle(fontSize: 12, color: Color(0xFF8B8FA8))),
            ],
          ),
        ),
      ),
    );
  }
}
