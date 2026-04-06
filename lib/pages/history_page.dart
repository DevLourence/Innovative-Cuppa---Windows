import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/app_data.dart';
import '../utils/pdf_generator.dart';

class HistoryPage extends StatefulWidget {
  final String business;
  final Map<String, dynamic> user;
  const HistoryPage({super.key, required this.business, required this.user});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  bool get isShop => widget.business == 'shop';
  Color get accent => isShop ? const Color(0xFFC8822A) : const Color(0xFF4A7C59);
  
  String _filterType = 'ALL'; // ALL, SOLD, RESTOCK, OUT
  
  List<Map<String, dynamic>> get _transactions {
    List<Map<String, dynamic>> raw = [];
    
    if (isShop) {
      // 🛡️ UNIFIED FEED: Merge Sales reports with external Inventory movements (Restocks/Deductions)
      final reports = AppData.shopReports;
      // Filter inventory logs: only include those NOT related to a sale (Type 'sold') to avoid duplicates
      final movements = AppData.shopInventory.where((m) => 
        (m['action_type'] ?? m['type']) != 'sold'
      ).toList();
      raw = [...reports, ...movements];
    } else {
      raw = AppData.beansTransactions;
    }

    // Sort by Date Descending
    raw.sort((a, b) {
      final da = DateTime.tryParse((a['date'] ?? a['timestamp'] ?? a['generated_at'])?.toString() ?? '') ?? DateTime(2000);
      final db = DateTime.tryParse((b['date'] ?? b['timestamp'] ?? b['generated_at'])?.toString() ?? '') ?? DateTime(2000);
      return db.compareTo(da);
    });

    if (_filterType == 'ALL') return raw;
    return raw.where((t) {
      final type = (t['action_type'] ?? t['type'] ?? 'sold').toString().toLowerCase();
      if (_filterType == 'SOLD') return type == 'sold';
      if (_filterType == 'RESTOCK') return type == 'restock' || type == 'in';
      if (_filterType == 'OUT') return type == 'out' || type == 'deduct';
      return true;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    AppData.syncNotifier.addListener(_refresh);
  }

  @override
  void dispose() {
    AppData.syncNotifier.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF5F3F0),
      padding: const EdgeInsets.all(32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Header
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('History', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF1C1008), letterSpacing: -0.5)),
            const SizedBox(height: 3),
            Text('All recorded transactions and inventory activity', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
          ]),
          Row(children: [
            _headerBtn(Icons.filter_list_rounded, _filterType == 'ALL' ? 'Filter' : _filterType, _showFilterDialog),
            const SizedBox(width: 8),
            _headerBtn(Icons.download_rounded, 'Export', _exportData),
          ]),
        ]),

        const SizedBox(height: 24),

        // Table container
        Expanded(
          child: Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 10, offset: const Offset(0, 4))]),
            child: Column(children: [
              // Header row
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFFF0EDE8))),
                ),
                child: Row(children: [
                  Expanded(flex: 2, child: _th('Date')),
                  Expanded(flex: 6, child: _th('Activity')),
                  const SizedBox(width: 48),
                ]),
              ),
              Expanded(
                child: _transactions.isEmpty
                    ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey[200]),
                        const SizedBox(height: 12),
                        Text('No transactions yet', style: TextStyle(fontSize: 14, color: Colors.grey[400])),
                      ]))
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _transactions.length,
                        separatorBuilder: (_, _) => const Divider(color: Color(0xFFF5F3F0), height: 1),
                        itemBuilder: (ctx, i) => _buildRow(_transactions[i]),
                      ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildRow(Map<String, dynamic> tx) {
    final rawDate = tx['timestamp'] ?? tx['date'] ?? tx['generated_at'];
    final date = rawDate is DateTime ? rawDate : DateTime.tryParse(rawDate?.toString() ?? '') ?? DateTime.now();
    final type = (tx['action_type'] ?? tx['type'] ?? 'sold').toString().toLowerCase();
    String activityText; Color typeColor; IconData typeIcon;

    if (type == 'sold') {
      final items = tx['items'] as List<dynamic>? ?? [];
      final count = items.fold(0, (s, i) => s + (i['qty'] is num ? (i['qty'] as num).toInt() : int.tryParse(i['qty']?.toString() ?? '0') ?? 0));
      final names = items.take(2).map((i) => i['name'] ?? i['item'] ?? 'Item').join(', ');
      final amount = tx['amount'] is num ? (tx['amount'] as num).toDouble() : double.tryParse(tx['amount']?.toString() ?? '0.0') ?? 0.0;
      activityText = 'Sold $count items ($names${items.length > 2 ? '…' : ''}) · ₱${amount.toStringAsFixed(2)}';
      typeColor = accent; typeIcon = Icons.shopping_bag_outlined;
    } else {
      // 🛡️ INVENTORY LOG PROTECTION: Handle manual movements
      final isAdd = type == 'restock' || type == 'in';
      // Lookup name if missing from master JSON block (Beans/Wholesale) or specific columns
      final items = tx['items'] as List<dynamic>? ?? [];
      String? itemName = tx['itemName'] ?? tx['item_name'];
      
      final rawQ = tx['qty'] ?? tx['change_qty'] ?? 0.0;
      double itemQty = (rawQ is num ? rawQ.toDouble() : double.tryParse(rawQ.toString()) ?? 0.0).abs();
      
      if (itemName == null && items.isNotEmpty) {
        itemName = items.first['name'] ?? items.first['item'];
        if (itemQty == 0) itemQty = ((items.first['qty'] as num?)?.toDouble() ?? 0.0).abs();
      }
      
      String? unit = tx['unit'];
      if (itemName == null && tx['target_ingredient_id'] != null) {
        final id = tx['target_ingredient_id'].toString();
        final match = AppData.shopIngredients.firstWhere((i) => i['id'].toString() == id, orElse: () => {});
        if (match.isNotEmpty) {
           itemName = match['name'];
           unit = match['unit'];
        }
      }
      
      itemName ??= 'Generic Product';
      activityText = '${isAdd ? 'Restocked' : 'Manual Deduction'}: ${AppData.fmt(itemQty)}${unit ?? ''} of $itemName';
      typeColor = isAdd ? Colors.green.shade600 : Colors.orange.shade600; 
      typeIcon = isAdd ? Icons.add_circle_outline_rounded : Icons.remove_circle_outline_rounded;
    }

    return InkWell(
      onTap: () => _showDetails(tx),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(children: [
          Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(DateFormat('MMM d').format(date), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1C1008))),
            Text(DateFormat('h:mm a').format(date), style: TextStyle(fontSize: 11, color: Colors.grey[400])),
          ])),
          Expanded(flex: 6, child: Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: typeColor.withAlpha(12), shape: BoxShape.circle),
              child: Icon(typeIcon, color: typeColor, size: 14),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(activityText, style: const TextStyle(fontSize: 13, color: Color(0xFF1C1008)), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 1),
              Text('By ${tx['user_name'] ?? 'Unknown'}', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
            ])),
          ])),
          SizedBox(width: 48, child: Icon(Icons.chevron_right_rounded, color: Colors.grey[300], size: 18)),
        ]),
      ),
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Filter History', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _filterTile('ALL Activity', 'ALL', Icons.history_rounded),
            _filterTile('Sales Only', 'SOLD', Icons.shopping_bag_outlined),
            _filterTile('Restocks Only', 'RESTOCK', Icons.add_circle_outline_rounded),
            _filterTile('Stock-Outs Only', 'OUT', Icons.remove_circle_outline_rounded),
          ],
        ),
      ),
    );
  }

  Widget _filterTile(String label, String value, IconData icon) {
    final active = _filterType == value;
    return ListTile(
      leading: Icon(icon, color: active ? accent : Colors.grey[400], size: 20),
      title: Text(label, style: TextStyle(fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? accent : const Color(0xFF1C1008))),
      selected: active,
      trailing: active ? Icon(Icons.check_circle_rounded, color: accent, size: 20) : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onTap: () {
        setState(() => _filterType = value);
        Navigator.pop(context);
      },
    );
  }

  void _exportData() {
    PdfGenerator.exportTableToPdf(_transactions, isShop: isShop);
  }

  void _showDetails(Map<String, dynamic> tx) {
    final rawDate = tx['timestamp'] ?? tx['date'] ?? tx['generated_at'];
    final date = rawDate is DateTime ? rawDate : DateTime.tryParse(rawDate?.toString() ?? '') ?? DateTime.now();
    final type = (tx['action_type'] ?? tx['type'] ?? 'sold').toString().toLowerCase();
    final items = (tx['items'] as List<dynamic>? ?? []).toList();

    // 🛡️ RESOLVE INVENTORY METADATA
    final isAdd = type == 'restock' || type == 'in';
    final rawQty = tx['qty'] ?? tx['change_qty'] ?? 0.0;
    final q = (rawQty is num ? rawQty.toDouble() : double.tryParse(rawQty.toString()) ?? 0.0).abs();
    
    String? itemName = tx['itemName'] ?? tx['item_name'];
    String? unit = tx['unit'];
    if (itemName == null && tx['target_ingredient_id'] != null) {
      final id = tx['target_ingredient_id'].toString();
      final match = AppData.shopIngredients.firstWhere((i) => i['id'].toString() == id, orElse: () => {});
      if (match.isNotEmpty) {
          itemName = match['name'];
          unit = match['unit'];
      }
    }
    itemName ??= 'Material';

    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: EdgeInsets.zero,
      content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Dialog header
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 16, 0),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(type == 'sold' ? 'Transaction ${tx['id']}' : 'Stock Record',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1C1008))),
              Text(DateFormat('MMM d, yyyy • h:mm a').format(date), style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            ])),
            IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => Navigator.pop(ctx)),
          ]),
        ),
        const SizedBox(height: 16),
        const Divider(height: 1, color: Color(0xFFF0EDE8)),

        // Body
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ITEMS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.grey[400], letterSpacing: 1.2)),
            const SizedBox(height: 12),
            if (type == 'sold')
              ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xFFF5F3F0), borderRadius: BorderRadius.circular(6)),
                    child: Text('×${item['qty']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1C1008))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item['name'] ?? 'Item', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    if (item['size'] != null) Text(item['size'], style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                  ])),
                  Text('₱${((item['price'] ?? 0) * (item['qty'] ?? 0)).toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ]),
              ))
            else 
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isAdd ? Colors.green : Colors.orange).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('${isAdd ? '+' : '-'}${AppData.fmt(q)}',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: isAdd ? Colors.green.shade600 : Colors.orange.shade600)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(itemName!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    if (unit != null) Text(unit, style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                  ],
                )),
              ]),
          ]),
        ),

        if (type == 'sold') ...[
          const Divider(height: 1, color: Color(0xFFF0EDE8)),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Total', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[600])),
              Text('₱ ${(tx['amount'] is num ? (tx['amount'] as num).toDouble() : 0.0).toStringAsFixed(2)}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: accent)),
            ]),
          ),
        ],

        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(width: double.infinity, height: 40, child: OutlinedButton.icon(
            onPressed: () => PdfGenerator.exportTableToPdf([tx], isShop: isShop),
            icon: Icon(Icons.print_outlined, size: 16, color: accent),
            label: Text('Print Receipt', style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: accent.withAlpha(60)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          )),
        ),
      ])),
    ));
  }

  Widget _headerBtn(IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFF0EDE8)),
          ),
          child: Row(children: [
            Icon(icon, size: 15, color: accent),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF1C1008), fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  Widget _th(String title) => Text(title.toUpperCase(),
    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.grey[400], letterSpacing: 1));
}
