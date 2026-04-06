import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/app_data.dart';
import '../services/supabase_service.dart';
import '../utils/pdf_generator.dart';

class InventoryPage extends StatefulWidget {
  final String business;
  final Map<String, dynamic> user;
  const InventoryPage({super.key, required this.business, required this.user});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _horizontalScroll = ScrollController();
  final ScrollController _verticalScroll = ScrollController();
  bool get isShop => widget.business == 'shop';
  Color get accent => isShop ? const Color(0xFFC8822A) : const Color(0xFF4A7C59);
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    AppData.syncNotifier.addListener(_onSync);
    _autoSync();
  }

  void _autoSync() async {
    await AppData.ensureInventorySync(widget.user['name'] ?? 'System');
    if (mounted) setState(() {});
  }

  void _onSync() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppData.syncNotifier.removeListener(_onSync);
    _tabController.dispose();
    _horizontalScroll.dispose();
    _verticalScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF5F3F0),
      child: Column(children: [
        // Header
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Stock Control', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: const Color(0xFF1C1008), letterSpacing: -0.5)),
                Text(isShop ? 'Real-time ingredient tracking' : 'Wholesale bean stock levels', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
              ]),
              Row(children: [
                _actionBtn(Icons.refresh_rounded, 'Sync Data', () async {
                  await SupabaseService.pullFromCloud(pushFirst: true);
                  if (mounted) setState(() {});
                }),
                const SizedBox(width: 12),
                _actionBtn(Icons.calendar_month_rounded, DateFormat('MMMM yyyy').format(_selectedDate), _selectDate),
                const SizedBox(width: 12),
                _actionBtn(Icons.picture_as_pdf_rounded, 'Export to PDF', _exportReport),
              ]),
            ]),
            const SizedBox(height: 24),
            TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: accent,
              unselectedLabelColor: Colors.grey[400],
              indicatorColor: accent,
              indicatorWeight: 3,
              labelPadding: const EdgeInsets.symmetric(horizontal: 24),
              dividerColor: Colors.transparent,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.2),
              tabs: const [
                Tab(text: 'Daily Breakdown'),
                Tab(text: 'Monthly Summary'),
              ],
            ),
          ]),
        ),

        // Content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildDailyView(),
              _buildMonthlyView(),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _buildDailyView() {
    final ingredients = isShop ? AppData.shopIngredients : AppData.beansInventory;
    final nameKey = isShop ? 'name' : 'product_name';
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(children: [
        // Cards
        Row(children: [
          _summaryCard('Inbound Today', '+${AppData.getStockAddTotal(isShop).toStringAsFixed(0)}', Colors.green, Icons.arrow_downward_rounded),
          const SizedBox(width: 24),
          _summaryCard('Outbound Today', '-${AppData.getStockOutTotal(isShop).toStringAsFixed(0)}', Colors.orange, Icons.arrow_upward_rounded),
          const SizedBox(width: 24),
          _summaryCard('Low Stock Items', AppData.getLowStockItems(isShop).length.toString(), Colors.red, Icons.warning_amber_rounded),
        ]),
        const SizedBox(height: 40),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Inventory Ledger', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1C1008))),
          ],
        ),
        const SizedBox(height: 24),

        // Table
        Container(
          width: double.infinity,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFF0EDE8))),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            _thRow(['Ingredient Name', 'Beginning', 'Restock (+)', 'Out (-)', 'Current Balance', 'Status', 'Action']),
            if (ingredients.isEmpty)
              _buildEmptyState('No inventory items found. Add products to begin.')
            else
              ...ingredients.map((ing) {
                final name = ing[nameKey] as String;
                final daily = AppData.getIngredientDaily(ing, isShop, date: _selectedDate);
                // Ensure we show zeros if the day hasn't been recorded yet
                final safeData = daily ?? {
                  'name': name,
                  'unit': ing['unit'] ?? (isShop ? 'units' : 'pcs'),
                  'beg': (ing[isShop ? 'stock' : 'balance_qty'] ?? 0.0) as double,
                  'add': 0.0, 'out': 0.0,
                  'end': (ing[isShop ? 'stock' : 'balance_qty'] ?? 0.0) as double,
                  'status': 'ok'
                };
                return _itemRow(safeData);
              }),
          ]),
        ),
      ]),
    );
  }

  Widget _summaryCard(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFF0EDE8))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey[500])),
            Icon(icon, size: 18, color: color),
          ]),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, fontFamily: 'Outfit')),
        ]),
      ),
    );
  }

  Widget _buildEmptyState(String msg) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80),
      child: Center(
        child: Column(children: [
          Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[200]),
          const SizedBox(height: 16),
          Text(msg, style: TextStyle(color: Colors.grey[400], fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
      ),
    );
  }

  // ── EXCEL STYLE MONTHLY ACCOUNTING RECORD ──────────────────────────────────
  Widget _buildMonthlyView() {
    final ingredients = isShop ? AppData.shopIngredients : AppData.beansInventory;

    final daysInMonth = DateTime(_selectedDate.year, _selectedDate.month + 1, 0).day;


    return Container(
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFEEECE8)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 20, offset: const Offset(0, 10))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Spreadsheet Sub-Header
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Color(0xFFDADCE0)))),
          child: Column(children: [
            Text('INNOVATIVE CUPPA COFFEE ROASTERY SERVICES', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
            Text('1ST FLOOR JARAULA BLDG.. JV SERIÑA ST. CARMEN, CAGAYAN DE ORO CITY', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Color(0xFF5F6368))),
            Text('DAILY ${isShop ? 'INGREDIENT' : 'INVENTORY'} (${DateFormat('MMMM').format(_selectedDate).toUpperCase()}) ACCOUNTING RECORD', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF5F6368))),
          ]),
        ),
        
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: Scrollbar(
              controller: _horizontalScroll,
              interactive: true,
              thickness: 10,
              radius: const Radius.circular(5),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: _horizontalScroll,
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  width: 60 + (ingredients.length * 240.0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Main Category Headers
                    Row(children: [
                      _exTh('DATE', 60, color: const Color(0xFFF8F9FA)),
                      ...ingredients.map((b) => _exMainTh(b[isShop ? 'name' : 'product_name'] as String, (b['color'] as Color?) ?? accent, 240)),
                    ]),
                    // Sub Headers (Beg, Add, Sold, End)
                    Row(children: [
                      _exTh('', 60, color: const Color(0xFFF8F9FA)),
                      ...List.generate(ingredients.length, (index) => Row(children: [
                        _exSubTh('BEG.', 60),
                        _exSubTh('ADD', 60),
                        _exSubTh('OUT', 60),
                        _exSubTh('END', 60),
                      ])),
                    ]),
                    // Data Rows (With Vertical Scrollbar)
                    Expanded(
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          scrollbarTheme: ScrollbarThemeData(
                            thumbColor: WidgetStateProperty.all(accent),
                          )
                        ),
                        child: Scrollbar(
                          controller: _verticalScroll,
                          interactive: true,
                          thickness: 8,
                          child: ListView.builder(
                            controller: _verticalScroll,
                            itemCount: daysInMonth,
                            padding: EdgeInsets.zero,
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemBuilder: (ctx, dIndex) {
                              final dayNum = dIndex + 1;
                              final monthName = DateFormat('MMM').format(_selectedDate);
                              final targetDate = DateTime(_selectedDate.year, _selectedDate.month, dayNum);

                              return Container(
                                height: 38,
                                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEECEC)))),
                                child: Row(children: [
                                  _exTd('$monthName $dayNum', 60, isCentered: true, color: const Color(0xFFF8F9FA)),
                                  ...List.generate(ingredients.length, (bIndex) {
                                    final item = ingredients[bIndex];
                                    final daily = AppData.getIngredientDaily(item[isShop ? 'name' : 'product_name'], isShop, date: targetDate);
                                    final unit = item['unit'] ?? (isShop ? 'units' : 'pcs');
                                    final itemColor = (item['color'] as Color?) ?? accent;

                                    return Row(children: [
                                      _exTd('${AppData.fmt(daily?['beg'] ?? (item[isShop ? 'stock' : 'balance_qty'] as num).toDouble())} $unit', 60, isCentered: true, color: itemColor.withValues(alpha: 0.05)),
                                      _exTd('+${AppData.fmt(daily?['add'] ?? 0)} $unit', 60, isCentered: true, color: itemColor.withValues(alpha: 0.1)),
                                      _exTd('-${AppData.fmt(daily?['out'] ?? 0)} $unit', 60, isCentered: true, color: itemColor.withValues(alpha: 0.15)),
                                      _exTd('${AppData.fmt(daily?['end'] ?? (item[isShop ? 'stock' : 'balance_qty'] as num).toDouble())} $unit', 60, isCentered: true, color: itemColor.withValues(alpha: 0.2), isBold: true),
                                    ]);
                                  }),
                                ]),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // ── EXCEL UI UTILS ─────────────────────────────────────────────────────────
  Widget _exMainTh(String label, Color color, double width) => Container(
    width: width, height: 40, alignment: Alignment.center,
    decoration: BoxDecoration(color: color, border: Border.all(color: const Color(0xFFDADCE0), width: 0.5)),
    child: Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5)),
  );

  Widget _exSubTh(String label, double width) => Container(
    width: width, height: 30, alignment: Alignment.center,
    decoration: BoxDecoration(color: const Color(0xFFE8EAED), border: Border.all(color: const Color(0xFFDADCE0), width: 0.5)),
    child: Text(label, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Color(0xFF5F6368))),
  );

  Widget _exTh(String label, double width, {Color? color}) => Container(
    width: width, height: 70, alignment: Alignment.center,
    decoration: BoxDecoration(color: color ?? Colors.white, border: Border.all(color: const Color(0xFFDADCE0), width: 0.5)),
    child: Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFF3C4043))),
  );

  Widget _exTd(String val, double width, {bool isCentered = false, bool isBold = false, Color? color}) => Container(
    width: width, height: 38, alignment: isCentered ? Alignment.center : Alignment.centerLeft,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(color: color, border: Border.all(color: const Color(0xFFEEECEC), width: 0.5)),
    child: Text(val, style: TextStyle(fontSize: 10, fontWeight: isBold ? FontWeight.w700 : FontWeight.w500, color: const Color(0xFF1C1008))),
  );


  Widget _buildMovementLog({String? filterName}) {
    // 🛡️ COMBINED SHOP LOGIC (Sales + Movements)
    final movements = isShop 
      ? [...AppData.shopReports, ...AppData.shopInventory]
      : AppData.beansTransactions;
    
    // Filter for legitimate inventory movements or sales that affected stock
    var log = movements.where((m) => 
      m['type'] == 'restock' || 
      m['type'] == 'out' || 
      m['type'] == 'in' || 
      m['type'] == 'deduct' || 
      (m['type'] == 'sold' && m['items'] != null)
    ).toList();
    
    if (filterName != null) {
      log = log.where((m) => 
        m['itemName'] == filterName || 
        (m['items'] != null && (m['items'] as List).any((i) => i['name'] == filterName))
      ).toList();
    }
    
    if (log.isEmpty) return _buildEmptyState('No movement logs found${filterName != null ? " for $filterName" : ""}.');

    return ListView.separated(
      shrinkWrap: filterName != null,
      physics: filterName != null ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
      padding: filterName != null ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      itemCount: log.length,
      separatorBuilder: (ctx, i) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) {
        final tx = log[i];
        final type = tx['type'] ?? 'out';
        final isAdd = type == 'restock' || type == 'in';
        final date = tx['date'] is DateTime ? tx['date'] as DateTime : DateTime.tryParse(tx['date']?.toString() ?? '') ?? DateTime.now();

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFF0EDE8))),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: (isAdd ? Colors.green : Colors.orange).withAlpha(15), shape: BoxShape.circle),
              child: Icon(isAdd ? Icons.add_rounded : Icons.remove_rounded, color: isAdd ? Colors.green : Colors.orange, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tx['itemName'] ?? (tx['items'] != null ? (tx['items'] as List).first['name'] : 'System Adjustment'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, fontFamily: 'Outfit')),
                Text('#${tx['id']} • ${DateFormat('MMM dd, hh:mm a').format(date)}', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${isAdd ? '+' : '-'}${tx['qty'] ?? 0.0}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: isAdd ? Colors.green : Colors.orange, fontFamily: 'Outfit')),
              Text(type.toString().toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.grey[400], letterSpacing: 0.5)),
            ]),
          ]),
        );
      },
    );
  }

  void _showProductFlow(String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFF9F8F6),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
        contentPadding: const EdgeInsets.all(32),
        title: Row(children: [
          Icon(Icons.timeline_rounded, color: accent, size: 28),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$name Flow History', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, fontFamily: 'Outfit')),
            Text('Historical movement for this product', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ])),
        ]),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: _buildMovementLog(filterName: name),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('CLOSE', style: TextStyle(color: accent, fontWeight: FontWeight.w900))),
        ],
      ),
    );
  }

  // ── STANDARD UI WIDGETS ───────────────────────────────────────────────────
  Widget _thRow(List<String> labels) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(color: Color(0xFFF9F8F6), borderRadius: BorderRadius.vertical(top: Radius.circular(14)), border: Border(bottom: BorderSide(color: Color(0xFFEEECE8)))),
      child: Row(children: labels.map((l) => Expanded(child: Text(l.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.grey[400], letterSpacing: 1)))).toList()),
    );
  }

  Widget _itemRow(Map<String, dynamic> data) {
    final isLow = data['status'] == 'low';
    final unit = data['unit'] ?? '';
    final name = data['name'] ?? 'Unknown';
    
    return InkWell(
      onTap: () => _showProductFlow(name),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF5F3F0)))),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1C1008))),
            Text(unit, style: TextStyle(fontSize: 10, color: Colors.grey[400], fontWeight: FontWeight.w600)),
          ])),
          Expanded(child: Text('${AppData.fmt(data['beg'])} $unit', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
          Expanded(child: Text('+${AppData.fmt(data['add'])} $unit', style: TextStyle(fontSize: 12, color: Colors.green[600], fontWeight: FontWeight.w700))),
          Expanded(child: Text('-${AppData.fmt(data['out'])} $unit', style: TextStyle(fontSize: 12, color: Colors.orange[700], fontWeight: FontWeight.w700))),
          Expanded(child: Text('${AppData.fmt(data['end'])} $unit', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF1C1008)))),
          Expanded(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: isLow ? Colors.red[50] : Colors.green[50], borderRadius: BorderRadius.circular(6), border: Border.all(color: isLow ? Colors.red[100]! : Colors.green[100]!)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 5, height: 5, decoration: BoxDecoration(color: isLow ? Colors.red : Colors.green, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(isLow ? 'REORDER' : 'HEALTHY', style: TextStyle(fontSize: 9, color: isLow ? Colors.red[700] : Colors.green[700], fontWeight: FontWeight.w900)),
            ]),
          )),
          // Action Buttons
          Expanded(child: Row(children: [
            _miniActionBtn(Icons.add_rounded, Colors.green, () => _showAdjustmentDialog(name, true)),
            const SizedBox(width: 8),
            _miniActionBtn(Icons.remove_rounded, Colors.orange, () => _showAdjustmentDialog(name, false)),
          ])),
        ]),
      ),
    );
  }

  Widget _miniActionBtn(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: color.withAlpha(20), borderRadius: BorderRadius.circular(6), border: Border.all(color: color.withAlpha(40))),
        child: Icon(icon, size: 14, color: color),
      ),
    );
  }

  void _showAdjustmentDialog(String name, bool isAdd) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(isAdd ? 'Manual Restock' : 'Manual Stock-Out', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: 'Enter quantity',
                filled: true,
                fillColor: const Color(0xFFF5F3F0),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(10)),
            child: GestureDetector(
              onTap: () async {
                final qty = double.tryParse(ctrl.text) ?? 0;
                if (qty > 0) {
                  await AppData.updateStock(isShop, name, qty, isAdd, widget.user['name'] ?? 'Admin');
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    setState(() {}); // 🔥 INSTANT DASHBOARD REFRESH
                  }
                }
              },
              child: const Text('Confirm', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }



  Widget _actionBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFEEECE8))),
        child: Row(children: [
          Icon(icon, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1C1008))),
        ]),
      ),
    );
  }

  void _selectDate() async {
    final d = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2025), lastDate: DateTime.now(), initialDatePickerMode: DatePickerMode.year);
    if (d != null) setState(() => _selectedDate = d);
  }

  void _exportReport() {
    final bool isMonthlyView = _tabController.index == 1;
    final allIngredients = isShop ? AppData.shopIngredients : AppData.beansInventory;
    final nameKey = isShop ? 'name' : 'product_name';
    List<String> selectedNames = allIngredients.map((e) => e[nameKey] as String).toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(isMonthlyView ? 'Monthly Export Selection' : 'Daily Export Selection', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w900, color: const Color(0xFF1C1008))),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Select products to include in the ${isMonthlyView ? 'Monthly Summary' : 'Daily Audit'}.', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(children: allIngredients.map((ing) {
                      final name = ing[nameKey] as String;
                      final isSelected = selectedNames.contains(name);
                      return CheckboxListTile(
                        value: isSelected,
                        title: Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        activeColor: accent,
                        dense: true,
                        onChanged: (v) {
                          setDialogState(() {
                            if (v!) {
                              selectedNames.add(name);
                            } else {
                              selectedNames.remove(name);
                            }
                          });
                        },
                      );
                    }).toList()),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w700))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, elevation: 0),
              onPressed: () {
                Navigator.pop(ctx);
                final filtered = allIngredients.where((e) => selectedNames.contains(e[nameKey])).toList();
                PdfGenerator.exportInventoryReport(
                  business: widget.business,
                  date: _selectedDate,
                  ingredients: filtered,
                  isMonthly: isMonthlyView,
                );
              },
              child: const Text('EXPORT SELECTED', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
