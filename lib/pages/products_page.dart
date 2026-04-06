import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../data/app_data.dart';
import '../services/supabase_service.dart';
import '../utils/pdf_generator.dart';

class ProductsPage extends StatefulWidget {
  final String business;
  final Map<String, dynamic> user;
  const ProductsPage({super.key, required this.business, required this.user});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> with SingleTickerProviderStateMixin {
  bool get isShop => widget.business == 'shop';
  Color get accent => isShop ? const Color(0xFFC8822A) : const Color(0xFF4A7C59);
  bool get _isAdminOrManager => widget.user['role']?.toLowerCase() == 'admin' || widget.user['role']?.toLowerCase() == 'manager';

  late List<Map<String, dynamic>> _products;
  late List<Map<String, dynamic>> _ingredients;
  late TabController _tabController;
  final ScrollController _hScroll = ScrollController();
  final ScrollController _vScroll = ScrollController();
  DateTime _selectedDate = DateTime.now();

  final List<String> _shopProductCategories = ['Hot Coffee', 'Cold Coffee', 'Frappe', 'Pastry', 'Non-Coffee', 'Snacks'];
  final List<String> _beanProductCategories = ['House Blends', 'Premium', 'Single Origin', 'Blends', 'Local Origin', 'Imported', 'Decaf'];
  final List<String> _ingCategories = ['Powder', 'Dairy', 'Syrup', 'Fruit', 'Beans', 'Other'];
  final List<String> _unitOptions = ['kg', 'g', 'L', 'ml', 'pcs', 'set'];

  // 🛡️ SORTING STATE
  int  _ingSortCol = 0; // 0=Name, 1=Cat, 2=Stock, 3=Qty
  bool _ingSortAsc = true;
  int  _dailySortCol = 0; // 0=Name, 1=Beg, 2=Add, 3=Out, 4=Balance
  bool _dailySortAsc = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: isShop ? 4 : 3, vsync: this);
    _loadData();
    _autoSync();
    AppData.syncNotifier.addListener(_loadData);
  }

  @override
  void didUpdateWidget(ProductsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.business != widget.business) {
      _loadData();
    }
  }

  void _autoSync() async {
    await AppData.ensureInventorySync(widget.user['name'] ?? 'System');
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppData.syncNotifier.removeListener(_loadData);
    _tabController.dispose();
    _hScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  void _loadData() {
    if (!mounted) return;
    setState(() {
      _products = widget.business == 'shop' ? AppData.shopProducts : AppData.beansProducts;
      _ingredients = widget.business == 'shop' ? AppData.shopIngredients : AppData.beansInventory;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF5F3F0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildProductGrid(),
                if (isShop) _buildIngredientGrid(),
                _buildDailyView(),
                _buildMonthlyView(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(40, 48, 40, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Management', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, fontFamily: 'Outfit', color: Color(0xFF1C1008))),
                Text(isShop ? 'Menu, ingredients & stock control' : 'Product & inventory management', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: accent)),
              ],
            ),
          ),
          if (_tabController.index >= (isShop ? 2 : 1)) ...[
            _actionBtn(Icons.calendar_month_rounded, DateFormat('MMMM yyyy').format(_selectedDate), _selectDate),
            const SizedBox(width: 12),
            _actionBtn(Icons.picture_as_pdf_rounded, 'Export PDF', _exportReport),
            const SizedBox(width: 12),
          ],
          _actionBtn(Icons.sync_rounded, 'Refresh', () async {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Roastery Sync Initiated... 🛡️📊'), duration: Duration(milliseconds: 800)));
            await SupabaseService.pullFromCloud();
            if (mounted) {
              _loadData();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Resilient Cloud Sync Complete 🛡️⚓'), backgroundColor: Colors.green));
            }
          }),
          const SizedBox(width: 12),
          if (_isAdminOrManager && _tabController.index < (isShop ? 2 : 1))
            ElevatedButton.icon(
              onPressed: () => _tabController.index == 0 ? _showProductDialog() : _showIngredientDialog(),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: Text(_tabController.index == 0 ? 'ADD PRODUCT' : 'ADD MATERIAL', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)),
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                elevation: 8,
                shadowColor: accent.withAlpha(100),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(40, 32, 40, 0),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        labelColor: accent,
        unselectedLabelColor: Colors.grey[400],
        indicatorColor: accent,
        indicatorWeight: 4,
        dividerHeight: 0,
        labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, fontFamily: 'Outfit'),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, fontFamily: 'Outfit'),
        onTap: (_) => setState(() {}),
        tabs: [
          const Tab(text: 'Product Catalog'),
          if (isShop) const Tab(text: 'Materials'),
          const Tab(text: 'Daily Breakdown'),
          const Tab(text: 'Monthly Summary'),
        ],
      ),
    );
  }

  Widget _buildProductGrid() {
    if (_products.isEmpty) return _buildEmptyState('No products recorded yet.');
    return GridView.builder(
      padding: const EdgeInsets.all(32),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisSpacing: 24, crossAxisSpacing: 24, childAspectRatio: 0.75),
      itemCount: _products.length,
      itemBuilder: (ctx, i) => _buildProductCard(_products[i]),
    );
  }

  Widget _buildEmptyState(String msg) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 60, color: Colors.grey[200]),
          const SizedBox(height: 16),
          Text(msg, style: TextStyle(color: Colors.grey[300], fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> p) {
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(6), blurRadius: 20, offset: const Offset(0, 10)),
          BoxShadow(color: accent.withAlpha(4), blurRadius: 8, offset: const Offset(0, 4)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image Area
          Expanded(
            flex: 11,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  color: accent.withAlpha(5),
                  child: (p['image_url'] != null && p['image_url'].toString().isNotEmpty)
                      ? Image.network(
                          p['image_url'].toString(),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Center(child: Icon(isShop ? Icons.local_cafe_rounded : Icons.grain_rounded, size: 48, color: accent.withAlpha(40))),
                          loadingBuilder: (_, child, prog) => prog == null ? child : Center(child: CircularProgressIndicator(color: accent, strokeWidth: 2)),
                        )
                      : Center(child: Icon(isShop ? Icons.local_cafe_rounded : Icons.grain_rounded, size: 48, color: accent.withAlpha(40))),
                ),
                // Gradient Overlay
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [Colors.black.withAlpha(20), Colors.transparent, Colors.transparent],
                      ),
                    ),
                  ),
                ),
                // Admin Actions
                if (_isAdminOrManager)
                  Positioned(
                    top: 8, right: 8,
                    child: Container(
                      decoration: BoxDecoration(color: Colors.white.withAlpha(200), shape: BoxShape.circle),
                      child: PopupMenuButton(
                        icon: const Icon(Icons.more_horiz_rounded, color: Color(0xFF1C1008), size: 20),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        offset: const Offset(0, 40),
                        onSelected: (v) {
                          if (v == 'edit') _showProductDialog(p);
                          if (v == 'delete') _confirmDelete(p, true);
                        },
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_rounded, size: 16), SizedBox(width: 10), Text('Edit Product', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))])),
                          const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_rounded, size: 16, color: Colors.red), SizedBox(width: 10), Text('Delete', style: TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w600))])),
                        ],
                      ),
                    ),
                  ),
                // Category Tag
                Positioned(
                  top: 12, left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withAlpha(200), borderRadius: BorderRadius.circular(10)),
                    child: Text(p['category']?.toString().toUpperCase() ?? 'GENERAL', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: accent, letterSpacing: 0.8)),
                  ),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            flex: 9,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p['name'] ?? 'Untitled Item', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, fontFamily: 'Outfit', color: Color(0xFF1C1008), height: 1.1), maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (!isShop && (p['net_weight']?.toString().isNotEmpty ?? false))
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                        child: Text('${p['net_weight']}${p['net_unit'] ?? ''}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: accent)),
                      ),
                    ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(p['has_sizes'] == true ? 'Multiple' : '₱${p['price']}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: accent, fontFamily: 'Outfit')),
                      if (p['has_sizes'] == true) 
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(color: accent.withAlpha(15), borderRadius: BorderRadius.circular(6)),
                          child: Icon(Icons.layers_rounded, size: 12, color: accent),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIngredientGrid() {
    if (_ingredients.isEmpty) return _buildEmptyState('No inventory materials found.');
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        // Summary row
        Row(children: [
          _matStat('Total Items', _ingredients.length.toString(), Icons.inventory_2_rounded, accent),
          const SizedBox(width: 16),
          _matStat('Low Stock', AppData.getLowStockItems(isShop).length.toString(), Icons.warning_amber_rounded, Colors.red),
          const SizedBox(width: 16),
          _matStat('Categories', _ingredients.map((i) => i['category'] ?? 'Other').toSet().length.toString(), Icons.category_rounded, Colors.teal),
        ]),
        const SizedBox(height: 28),

        // Table
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFF0EDE8)),
            boxShadow: [BoxShadow(color: Colors.black.withAlpha(4), blurRadius: 20, offset: const Offset(0, 8))],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(color: Color(0xFFFAF9F6), border: Border(bottom: BorderSide(color: Color(0xFFF0EDE8)))),
              child: Row(children: [
                const SizedBox(width: 44),
                _colHeader('MATERIAL NAME', 0, flex: 3),
                _colHeader('CATEGORY', 1, flex: 2),
                _colHeader('STOCK %', 2, flex: 3),
                _colHeader('CURRENT QTY', 3, flex: 2),
                if (_isAdminOrManager) _colHeader('STOCK', -1, flex: 2), // -1 means non-sortable
                if (_isAdminOrManager) _colHeader('', -1, flex: 1),
              ]),
            ),
            // Rows
            ...(() {
              final sortedList = List<Map<String, dynamic>>.from(_ingredients);
              final nameK = isShop ? 'name' : 'product_name';
              final stockK = isShop ? 'stock' : 'balance_qty';
              
              sortedList.sort((a, b) {
                dynamic va, vb;
                switch (_ingSortCol) {
                  case 0: va = a[nameK]; vb = b[nameK]; break;
                  case 1: va = a['category']; vb = b['category']; break;
                  case 2: 
                    final valA = (a[stockK] as num?)?.toDouble() ?? 0.0;
                    final iniA = (a['initial_qty'] as num?)?.toDouble() ?? 1.0;
                    final valB = (b[stockK] as num?)?.toDouble() ?? 0.0;
                    final iniB = (b['initial_qty'] as num?)?.toDouble() ?? 1.0;
                    va = valA / (iniA > 0 ? iniA : 1.0);
                    vb = valB / (iniB > 0 ? iniB : 1.0);
                    break;
                  case 3: va = a[stockK]; vb = b[stockK]; break;
                  default: return 0;
                }
                int cmp = va.toString().toLowerCase().compareTo(vb.toString().toLowerCase());
                if (va is num && vb is num) cmp = va.compareTo(vb);
                return _ingSortAsc ? cmp : -cmp;
              });
              
              return List.generate(sortedList.length, (i) => _buildIngredientRow(sortedList[i], i));
            })(),
          ]),
        ),
      ],
    );
  }

  Widget _matStat(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFF0EDE8))),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withAlpha(15), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, fontFamily: 'Outfit')),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[400])),
          ]),
        ]),
      ),
    );
  }

  Widget _colHeader(String text, int colIdx, {int flex = 1}) {
    final bool isSortable = colIdx != -1;
    final bool isSelected = _ingSortCol == colIdx;
    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: isSortable ? () {
          setState(() {
            if (_ingSortCol == colIdx) {
              _ingSortAsc = !_ingSortAsc;
            } else {
              _ingSortCol = colIdx;
              _ingSortAsc = true;
            }
          });
        } : null,
        child: Row(
          children: [
            Text(text, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: isSelected ? accent : Colors.grey[400], letterSpacing: 1)),
            if (isSortable) ...[
              const SizedBox(width: 4),
              Icon(
                isSelected ? (_ingSortAsc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded) : Icons.unfold_more_rounded,
                size: 10,
                color: isSelected ? accent : Colors.grey[300],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIngredientRow(Map<String, dynamic> ing, int index) {
    final stock = (ing[isShop ? 'stock' : 'balance_qty'] as num?)?.toDouble() ?? 0.0;
    final unit = ing['unit'] ?? 'unit';
    final initialQty = (ing['initial_qty'] as num?)?.toDouble() ?? stock;
    final isLow = initialQty > 0 && stock <= initialQty * 0.2;
    final percent = initialQty > 0 ? (stock / initialQty).clamp(0.0, 1.0) : 1.0;
    final category = ing['category']?.toString() ?? 'Other';
    final name = ing['name'] ?? (isShop ? 'Material' : 'Bean Variant');
    final barColor = percent > 0.5 ? Colors.green : (percent > 0.2 ? Colors.orange : Colors.red);

    return Container(
      decoration: BoxDecoration(
        color: index.isEven ? Colors.white : const Color(0xFFFCFBFA),
        border: const Border(bottom: BorderSide(color: Color(0xFFF5F3F0))),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isAdminOrManager ? () => _showIngredientDialog(ing) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child: Row(children: [
              // Icon
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: accent.withAlpha(12), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.inventory_rounded, color: accent, size: 16),
              ),
              const SizedBox(width: 8),

              // Name
              Expanded(flex: 3, child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, fontFamily: 'Outfit'), overflow: TextOverflow.ellipsis)),

              // Category
              Expanded(flex: 2, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: accent.withAlpha(10), borderRadius: BorderRadius.circular(8)),
                child: Text(category, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: accent), overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
              )),

              // Stock bar
              Expanded(flex: 3, child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: percent,
                        minHeight: 6,
                        backgroundColor: const Color(0xFFF0EDE8),
                        color: barColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('${(percent * 100).toStringAsFixed(0)}% remaining', style: TextStyle(fontSize: 9, color: Colors.grey[400], fontWeight: FontWeight.w600)),
                  ],
                ),
              )),

              // Qty
              Expanded(flex: 2, child: Text(
                AppData.formatStock(stock, unit),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: isLow ? Colors.red : const Color(0xFF1C1008), fontFamily: 'Outfit'),
              )),



              // Stock adjustment
              if (_isAdminOrManager)
                Expanded(flex: 2, child: Row(children: [
                  _miniActionBtn(Icons.add_rounded, Colors.green, () => _showAdjustmentDialog(name, true)),
                  const SizedBox(width: 6),
                  _miniActionBtn(Icons.remove_rounded, Colors.orange, () => _showAdjustmentDialog(name, false)),
                ])),

              // Edit/Delete
              if (_isAdminOrManager)
                Expanded(flex: 1, child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  _matAction(Icons.edit_rounded, accent, () => _showIngredientDialog(ing)),
                  const SizedBox(width: 4),
                  _matAction(Icons.delete_outline_rounded, Colors.red, () => _confirmDelete(ing, false)),
                ])),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _matAction(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: color.withAlpha(10), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 15, color: color),
      ),
    );
  }

  void _showProductDialog([Map<String, dynamic>? product]) {
    final bool isEdit = product != null;
    final nameCtrl = TextEditingController(text: isEdit ? product['name'] : '');
    final priceCtrl = TextEditingController(text: isEdit ? product['price'].toString() : '');
    final weightCtrl = TextEditingController(text: isEdit ? (product['net_weight']?.toString() ?? '') : '');
    final initQtyCtrl = TextEditingController(text: '0'); // New: for beans inventory
    String selectedCat = isEdit ? product['category'] : (isShop ? _shopProductCategories.first : _beanProductCategories.first);
    bool isCustomCat = isEdit && !(isShop ? _shopProductCategories : _beanProductCategories).contains(selectedCat);
    final customCatCtrl = TextEditingController(text: isCustomCat ? selectedCat : '');
    if (isCustomCat) selectedCat = 'CUSTOM_NEW';

    // 🛡️ RE-SYNC: Initialize Recipe State (Hydrate from Top-Level OR Standard Variant)
    bool hasSizes = isEdit ? (product['has_sizes'] == true) : false;
    List<Map<String, dynamic>> rawSizes = isEdit ? List<Map<String, dynamic>>.from(product['sizes'] ?? []) : [];
    List<Map<String, dynamic>> sizes = rawSizes;
    String? imageUrl = isEdit ? product['image_url']?.toString() : null;
    Uint8List? pendingImageBytes; // bytes picked but not yet uploaded
    String? pendingImageName;
    bool isSaving = false;

    Future<void> pickImage(StateSetter setDs) async {
      final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      if (result != null && result.files.single.bytes != null) {
        setDs(() {
          pendingImageBytes = result.files.single.bytes;
          pendingImageName = result.files.single.name;
        });
      }
    }
    
    // Recovery Logic: If edit mode and no sizes, pull ingredients from the first variant (Standard) if top-level is empty
    List<Map<String, dynamic>> baseIngs = [];
    if (isEdit) {
       final topIngs = product['ingredients'] as List?;
       if (topIngs != null && topIngs.isNotEmpty) {
         baseIngs = List<Map<String, dynamic>>.from(topIngs);
       } else if (!hasSizes && rawSizes.isNotEmpty) {
         baseIngs = List<Map<String, dynamic>>.from(rawSizes.first['ingredients'] ?? []);
       }
    }

    final List<String> weightUnits = ['g', 'kg', 'lbs', 'oz', 'bags'];
    String selectedUnit = isEdit ? (product['net_unit']?.toString() ?? 'g') : 'g';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          contentPadding: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          content: Container(
            width: 600,
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  color: accent.withAlpha(10),
                  child: Row(
                    children: [
                      Icon(isEdit ? Icons.edit_note_rounded : Icons.add_business_rounded, color: accent, size: 32),
                      const SizedBox(width: 16),
                      Text(isEdit ? 'Refine Product' : 'Orchestrate Product', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, fontFamily: 'Outfit')),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(32),
                    children: [
                      // ── Image Picker ────────────────────────────────────
                      GestureDetector(
                        onTap: () => pickImage(setDialogState),
                        child: Container(
                          height: 140,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: accent.withAlpha(8),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: (imageUrl != null || pendingImageBytes != null) ? accent.withAlpha(60) : const Color(0xFFF0EDE8), width: 2, style: BorderStyle.solid),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: (pendingImageBytes != null)
                              // Show local preview for newly picked image
                              ? Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.memory(pendingImageBytes!, fit: BoxFit.cover),
                                    Positioned(
                                      bottom: 8, right: 8,
                                      child: GestureDetector(
                                        onTap: () => setDialogState(() { pendingImageBytes = null; pendingImageName = null; imageUrl = null; }),
                                        child: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.close_rounded, color: Colors.white, size: 14)),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 8, left: 8,
                                      child: GestureDetector(
                                        onTap: () => pickImage(setDialogState),
                                        child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.edit_rounded, color: Colors.white, size: 12), SizedBox(width: 4), Text('Change', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))])),
                                      ),
                                    ),
                                  ],
                                )
                              : (imageUrl != null && imageUrl!.isNotEmpty)
                              // Show existing network image
                              ? Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.network(imageUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
                                    Positioned(
                                      bottom: 8, right: 8,
                                      child: GestureDetector(
                                        onTap: () => setDialogState(() => imageUrl = null),
                                        child: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.close_rounded, color: Colors.white, size: 14)),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 8, left: 8,
                                      child: GestureDetector(
                                        onTap: () => pickImage(setDialogState),
                                        child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.edit_rounded, color: Colors.white, size: 12), SizedBox(width: 4), Text('Change', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))])),
                                      ),
                                    ),
                                  ],
                                )
                              : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  Icon(Icons.add_photo_alternate_rounded, size: 36, color: accent.withAlpha(80)),
                                  const SizedBox(height: 8),
                                  Text('Tap to upload product image', style: TextStyle(fontSize: 12, color: accent.withAlpha(120), fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  Text('JPG, PNG, WebP supported', style: TextStyle(fontSize: 10, color: Colors.grey[400])),
                                ]),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _dialogField(nameCtrl, 'Product Name', Icons.shopping_bag_rounded),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<String>(
                        initialValue: selectedCat,
                        items: [
                          ...(isShop ? _shopProductCategories : _beanProductCategories).map((c) => DropdownMenuItem(value: c, child: Text(c))),
                          const DropdownMenuItem(value: 'CUSTOM_NEW', child: Text('Other / New Category...', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))),
                        ],
                        onChanged: (v) => setDialogState(() => selectedCat = v!),
                        decoration: _dialogDeco('Category', Icons.category_rounded),
                      ),
                      if (selectedCat == 'CUSTOM_NEW') ...[
                        const SizedBox(height: 12),
                        _dialogField(customCatCtrl, 'Enter New Category Name', Icons.edit_calendar_rounded),
                      ],
                      const SizedBox(height: 32),
                      
                      // ── Switch Layout (Conditional for Shop) ──────────────────────────────
                      if (isShop) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: const Color(0xFFFAF9F6), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFF0EDE8))),
                          child: Row(
                            children: [
                              Icon(Icons.straighten_rounded, color: accent, size: 20),
                              const SizedBox(width: 12),
                              const Expanded(child: Text('Has Multiple Sizes', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
                              Switch(
                                value: hasSizes, 
                                activeThumbColor: accent,
                                onChanged: (v) => setDialogState(() => hasSizes = v),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],

                      if (!hasSizes) ...[
                        _dialogField(priceCtrl, 'Standard Price (₱)', Icons.payments_rounded, isNum: true),
                        const SizedBox(height: 32),
                        
                        if (isShop) ...[
                          _buildRecipeSection(setDialogState, baseIngs, 'Product Recipe'),
                        ] else ...[
                          Row(children: [
                             Expanded(flex: 3, child: _dialogField(weightCtrl, 'Net Weight Amount', Icons.scale_rounded, isNum: true)),
                             const SizedBox(width: 12),
                             Expanded(flex: 2, child: DropdownButtonFormField<String>(
                                 initialValue: selectedUnit,
                                 items: weightUnits.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                                 onChanged: (v) => setDialogState(() => selectedUnit = v!),
                                 decoration: _dialogDeco('Unit', Icons.tune_rounded),
                             )),
                          ]),
                          const SizedBox(height: 20),
                          _dialogField(initQtyCtrl, 'Initial Qty in Stock', Icons.inventory_2_rounded, isNum: true),
                        ],
                      ] else ...[
                        _buildSizesSection(setDialogState, sizes),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFF0EDE8)))),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.grey))),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: isSaving ? null : () async {
                             setDialogState(() => isSaving = true);
                             try {
                               // Upload pending image if any
                               if (pendingImageBytes != null && pendingImageName != null) {
                                 try {
                                   final oldImage = isEdit ? product['image_url'] : null;
                                   final uploaded = await SupabaseService.uploadProductImage(
                                     widget.business, pendingImageBytes!, pendingImageName!);
                                   if (uploaded != null) {
                                     imageUrl = uploaded;
                                     // 🛡️ BUCKET-MAINTENANCE: Automatically purge the OLD image from storage if replaced
                                     if (oldImage != null && oldImage.toString().isNotEmpty) {
                                        debugPrint('Storage Sanitizer: Purging old image path -> $oldImage');
                                        await SupabaseService.deleteProductImage(oldImage.toString());
                                     }
                                   }
                                 } catch (e) {
                                   if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Image Upload Failed: $e'), backgroundColor: Colors.red));
                                 }
                               }
                               final finalCat = selectedCat == 'CUSTOM_NEW' ? customCatCtrl.text.trim() : selectedCat;
                               if (finalCat.isEmpty) throw 'Please select or enter a category';

                               final data = isShop ? {
                                 'name': nameCtrl.text.trim(), 
                                 'price': hasSizes ? 0.0 : (double.tryParse(priceCtrl.text) ?? 0.0), 
                                 'category': finalCat,
                                 'has_sizes': hasSizes,
                                 'image_url': imageUrl ?? '',
                                 'sizes': hasSizes ? sizes : [{
                                    'name': 'Standard',
                                    'price': double.tryParse(priceCtrl.text) ?? 0.0,
                                    'ingredients': baseIngs
                                 }],
                               } : {
                                 'name': nameCtrl.text.trim(), 
                                 'price': double.tryParse(priceCtrl.text) ?? 0.0, 
                                 'category': finalCat,
                                 'image_url': imageUrl ?? '',
                                 'net_weight': weightCtrl.text.trim(),
                                 'net_unit': selectedUnit,
                                 'ingredients': isEdit ? product['ingredients'] : [], // Preserving historical JSON for wholesale
                               };
                               final table = isShop ? 'shop_products' : 'beans_products';
                               
                               if (isEdit) {
                                 await SupabaseService.update(table, data, product['id']);
                               } else {
                                 await SupabaseService.insert(table, data);
                                 if (!isShop) {
                                   final initQty = double.tryParse(initQtyCtrl.text) ?? 0.0;
                                   await AppData.updateStock(false, nameCtrl.text, initQty, true, widget.user['name'] ?? 'System', isInitializing: true);
                                 }
                               }
                               
                               _loadData();
                               if (ctx.mounted) Navigator.pop(ctx);
                             } catch (e) {
                               debugPrint('Product Save Error: $e');
                               if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Save Failed: $e'), backgroundColor: Colors.red));
                               }
                             } finally {
                               setDialogState(() => isSaving = false);
                             }
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: accent, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                        child: isSaving 
                           ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                           : const Text('SAVE PRODUCT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecipeSection(StateSetter setDialogState, List<Map<String, dynamic>> ings, String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, decoration: TextDecoration.underline)),
            TextButton.icon(
              onPressed: () => _showAddIngredientSubDialog(setDialogState, ings), 
              icon: const Icon(Icons.add_rounded, size: 16), 
              label: const Text('Add Material'),
              style: TextButton.styleFrom(foregroundColor: accent, textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (ings.isEmpty)
           Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12)), child: const Center(child: Text('No ingredients defined', style: TextStyle(color: Colors.grey, fontSize: 11))))
        else
          ...ings.asMap().entries.map((e) {
            final i = e.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFF0EDE8))),
              child: Row(
                children: [
                  Expanded(child: Text(i['item'] ?? i['name'] ?? 'Unknown Item', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                  Text('${i['qty'] ?? 0.0} ${i['unit'] ?? ''}', style: TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: 12)),
                  IconButton(onPressed: () => setDialogState(() => ings.removeAt(e.key)), icon: const Icon(Icons.close_rounded, size: 16, color: Colors.grey)),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildSizesSection(StateSetter setDialogState, List<Map<String, dynamic>> sizes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Defined Sizes', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, decoration: TextDecoration.underline)),
            TextButton.icon(
              onPressed: () => _showAddSizeSubDialog(setDialogState, sizes), 
              icon: const Icon(Icons.add_circle_outline_rounded, size: 16), 
              label: const Text('Add Variant'),
              style: TextButton.styleFrom(foregroundColor: accent, textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (sizes.isEmpty)
           const Center(child: Text('Add at least one size variant', style: TextStyle(color: Colors.grey, fontSize: 11)))
        else
          ...sizes.asMap().entries.map((e) {
            final s = e.value;
            final List<Map<String, dynamic>> sIngs = List<Map<String, dynamic>>.from(s['ingredients'] ?? []);
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFF0EDE8))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(s['name'].toString().toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13))),
                      Text('₱ ${s['price']}', style: TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: 14)),
                      IconButton(onPressed: () => setDialogState(() => sizes.removeAt(e.key)), icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.red)),
                    ],
                  ),
                  const Divider(),
                  _buildRecipeSection((f) { f(); s['ingredients'] = sIngs; setDialogState(() {}); }, sIngs, 'Variant Recipe'),
                ],
              ),
            );
          }),
      ],
    );
  }

  void _showAddSizeSubDialog(StateSetter parentSetState, List<Map<String, dynamic>> sizes) {
    final nameC = TextEditingController();
    final priceC = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Variant'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dialogField(nameC, 'Size Name (e.g. Large)', Icons.straighten_rounded),
            const SizedBox(height: 12),
            _dialogField(priceC, 'Price', Icons.payments_rounded, isNum: true),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          TextButton(onPressed: () {
            parentSetState(() => sizes.add({'name': nameC.text, 'price': double.tryParse(priceC.text) ?? 0.0, 'ingredients': []}));
            Navigator.pop(ctx);
          }, child: const Text('ADD')),
        ],
      ),
    );
  }

  void _showAddIngredientSubDialog(StateSetter parentSetState, List<Map<String, dynamic>> ings) {
    String? selectedIng;
    String? selectedUnit; 
    final qtyC = TextEditingController();
    final currentInventory = _ingredients; // 🛡️ RE-SYNC: Use correctly loaded inventory list

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, ss) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Ingredient Contribution', style: TextStyle(fontWeight: FontWeight.w900, fontFamily: 'Outfit')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                decoration: _dialogDeco('Select Material', Icons.inventory_rounded),
                items: currentInventory.map((i) => DropdownMenuItem(value: i['name'].toString(), child: Text('${i['name']} (${i['unit']})'))).toList(),
                onChanged: (v) {
                  ss(() {
                    selectedIng = v!;
                    final ingRef = currentInventory.firstWhere((i) => i['name'] == selectedIng);
                    selectedUnit = ingRef['unit']?.toString();
                  });
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                   Expanded(flex: 2, child: _dialogField(qtyC, 'Used Qty', Icons.numbers_rounded, isNum: true)),
                   const SizedBox(width: 8),
                   Expanded(
                     flex: 3,
                     child: DropdownButtonFormField<String>(
                       key: ValueKey(selectedUnit),
                       initialValue: selectedUnit,
                       items: _unitOptions.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                       onChanged: (v) => ss(() => selectedUnit = v!),
                       decoration: _dialogDeco('Recipe Unit', Icons.straighten_rounded),
                     ),
                   ),
                ],
              ),
              const SizedBox(height: 8),
              if (selectedIng != null) Text('Standard inventory unit for this item is: ${currentInventory.firstWhere((i) => i['name'] == selectedIng)['unit']}', style: TextStyle(fontSize: 10, color: Colors.grey[600], fontStyle: FontStyle.italic)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
            ElevatedButton(
              onPressed: () {
                if (selectedIng == null || selectedUnit == null) return;
                parentSetState(() => ings.add({
                  'item': selectedIng, 
                  'qty': double.tryParse(qtyC.text) ?? 0.0, 
                  'unit': selectedUnit
                }));
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(backgroundColor: accent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('ADD TO RECIPE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showIngredientDialog([Map<String, dynamic>? ing]) {
    final bool isEdit = ing != null;
    final nameCtrl = TextEditingController(text: isEdit ? (ing['name'] ?? '') : '');
    final specCtrl = TextEditingController(text: isEdit ? (ing['category'] ?? '') : '');
    final stockCtrl = TextEditingController(text: isEdit ? (ing[isShop ? 'stock' : 'balance_qty']?.toString() ?? '') : '');

    String? selectedCat = isEdit ? (_ingCategories.contains(ing['category']) ? ing['category'] : 'Other') : (isShop ? 'Powder' : 'Beans');
    String selectedUnit = isEdit ? (ing['unit'] ?? 'kg') : 'kg';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, ss) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          title: Text(isEdit ? 'Edit Stock' : 'Orchestrate Material', style: const TextStyle(fontWeight: FontWeight.w900, fontFamily: 'Outfit')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogField(nameCtrl, 'Item Name', Icons.inventory_rounded),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(selectedCat),
                initialValue: selectedCat,
                items: _ingCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => ss(() => selectedCat = v!),
                decoration: _dialogDeco('Material Category', Icons.category_rounded),
              ),
              if (selectedCat == 'Other') ...[
                const SizedBox(height: 12),
                _dialogField(specCtrl, 'Specify Category (e.g. Dairy, Packaging)', Icons.edit_note_rounded),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _dialogField(stockCtrl, 'Initial Qty', Icons.numbers_rounded, isNum: true)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(selectedUnit),
                      initialValue: selectedUnit,
                      items: _unitOptions.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                      onChanged: (v) => ss(() => selectedUnit = v!),
                      decoration: _dialogDeco('Unit', Icons.scale_rounded),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
            ElevatedButton(
              onPressed: () async {
                 final qty = double.tryParse(stockCtrl.text) ?? 0.0;
                 final data = {
                   'name': nameCtrl.text, 
                   'category': selectedCat == 'Other' ? specCtrl.text : (selectedCat ?? 'Other'),
                   isShop ? 'stock' : 'balance_qty': qty, 
                   'unit': selectedUnit,
                   if (!isEdit) 'initial_qty': qty,
                 };
                 final table = isShop ? 'shop_ingredients' : 'beans_inventory';
                 
                 try {
                   if (isEdit) {
                     await SupabaseService.update(table, data, ing['id']);
                   } else {
                     await SupabaseService.insert(table, data);
                   }
                   if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Inventory Catalog Refined Successfully! 🛡️⚓📦'), behavior: SnackBarBehavior.floating));
                 } catch (e) {
                   if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Sync Error: $e'), backgroundColor: Colors.red));
                 }
                 
                 _loadData();
                 if (ctx.mounted) Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(backgroundColor: accent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('SAVE MATERIAL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(Map<String, dynamic> item, bool isProduct) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Confirm Deletion', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to remove "${item['name']}"? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          TextButton(
            onPressed: () async {
               final table = isProduct ? (isShop ? 'shop_products' : 'beans_products') : (isShop ? 'shop_ingredients' : 'beans_inventory');
               
               // Cleanup Storage if image exists
               if (item['image_url'] != null && item['image_url'].toString().isNotEmpty) {
                 await SupabaseService.deleteProductImage(item['image_url'].toString());
               }

               await SupabaseService.delete(table, item['id']);
               _loadData();
               if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _dialogField(TextEditingController c, String l, IconData i, {bool isNum = false}) {
    return TextField(
      controller: c,
      keyboardType: isNum ? TextInputType.number : TextInputType.text,
      decoration: _dialogDeco(l, i),
    );
  }

  InputDecoration _dialogDeco(String l, IconData i) {
    return InputDecoration(
      labelText: l,
      prefixIcon: Icon(i, size: 20, color: accent),
      filled: true,
      fillColor: const Color(0xFFF5F3F0),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // INVENTORY FEATURES (merged from InventoryPage)
  // ══════════════════════════════════════════════════════════════════════════

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

  Widget _buildDailyView() {
    final ingredients = isShop ? AppData.shopIngredients : AppData.beansInventory;
    final nameKey = isShop ? 'name' : 'product_name';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(children: [
        const Row(children: [Text('Daily Inventory Records', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1C1008)))]),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFF0EDE8))),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            _thRow(['Ingredient Name', 'Beginning', 'Restock (+)', 'Out (-)', 'Current Balance']),
            if (ingredients.isEmpty)
              _invEmptyState('No inventory items found. Add products to begin.')
            else
              ...(() {
                final safeList = ingredients.map((ing) {
                  final name = ing[nameKey] as String;
                  final unit = ing['unit'] ?? (isShop ? 'units' : (ing['net_unit'] ?? 'g'));
                  final daily = AppData.getIngredientDaily(ing, isShop, date: _selectedDate);
                  final currentStock = (ing[isShop ? 'stock' : 'balance_qty'] as num?)?.toDouble() ?? 0.0;
                  final initialQty = (ing['initial_qty'] as num?)?.toDouble() ?? currentStock;
                  final isLow = initialQty > 0 && currentStock <= initialQty * 0.2;
                  
                  return daily ?? {
                    'name': name,
                    'unit': unit,
                    'beg': currentStock,
                    'add': 0.0, 'out': 0.0,
                    'end': currentStock,
                    'status': isLow ? 'low' : 'ok'
                  };
                }).toList();

                safeList.sort((a, b) {
                  dynamic va, vb;
                  switch (_dailySortCol) {
                    case 0: va = a['name']; vb = b['name']; break;
                    case 1: va = a['beg']; vb = b['beg']; break;
                    case 2: va = a['add']; vb = b['add']; break;
                    case 3: va = a['out']; vb = b['out']; break;
                    case 4: va = a['end']; vb = b['end']; break;
                    default: return 0;
                  }
                  int cmp = va.toString().toLowerCase().compareTo(vb.toString().toLowerCase());
                  if (va is num && vb is num) cmp = va.compareTo(vb);
                  return _dailySortAsc ? cmp : -cmp;
                });

                return safeList.map((data) => _itemRow(data));
              })(),
          ]),
        ),
      ]),
    );
  }



  Widget _invEmptyState(String msg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: const Color(0xFFF9F8F6), shape: BoxShape.circle, border: Border.all(color: const Color(0xFFEEECE8))),
              child: Icon(Icons.auto_graph_rounded, size: 48, color: accent.withValues(alpha: 0.2)),
            ),
            const SizedBox(height: 24),
            Text('No Data Found', style: TextStyle(color: const Color(0xFF1C1008), fontWeight: FontWeight.w900, fontSize: 18, fontFamily: 'Outfit')),
            const SizedBox(height: 8),
            Text(msg, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[500], fontWeight: FontWeight.w500, fontSize: 13, height: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyView() {
    final ingredients = isShop ? AppData.shopIngredients : AppData.beansInventory;
    final daysInMonth = DateTime(_selectedDate.year, _selectedDate.month + 1, 0).day;
    return Container(
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFEEECE8)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 20, offset: const Offset(0, 10))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Color(0xFFDADCE0)))),
          child: Column(children: [
            const Text('INNOVATIVE CUPPA COFFEE ROASTERY SERVICES', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
            const Text('1ST FLOOR JARAULA BLDG.. JV SERIÑA ST. CARMEN, CAGAYAN DE ORO CITY', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Color(0xFF5F6368))),
            Text('DAILY ${isShop ? 'INGREDIENT' : 'INVENTORY'} (${DateFormat('MMMM').format(_selectedDate).toUpperCase()}) ACCOUNTING RECORD', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF5F6368))),
          ]),
        ),
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: Scrollbar(
              controller: _hScroll,
              interactive: true,
              thickness: 10,
              radius: const Radius.circular(5),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: _hScroll,
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  width: 60 + (ingredients.length * 240.0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      _exTh('DATE', 60, color: const Color(0xFFF8F9FA)),
                      ...ingredients.map((b) => _exMainTh(b[isShop ? 'name' : 'product_name'] as String, (b['color'] as Color?) ?? accent, 240)),
                    ]),
                    Row(children: [
                      _exTh('', 60, color: const Color(0xFFF8F9FA)),
                      ...List.generate(ingredients.length, (index) => Row(children: [
                        _exSubTh('BEG.', 60), _exSubTh('ADD', 60), _exSubTh('OUT', 60), _exSubTh('END', 60),
                      ])),
                    ]),
                    Expanded(
                      child: Theme(
                        data: Theme.of(context).copyWith(scrollbarTheme: ScrollbarThemeData(thumbColor: WidgetStateProperty.all(accent))),
                        child: Scrollbar(
                          controller: _vScroll,
                          interactive: true,
                          thickness: 8,
                          child: ListView.builder(
                            controller: _vScroll,
                            itemCount: (() {
                               final now = DateTime.now();
                               if (_selectedDate.year == now.year && _selectedDate.month == now.month) {
                                  return now.day;
                               }
                               return daysInMonth;
                            })(),
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
                                    final daily = AppData.getIngredientDaily(item, isShop, date: targetDate);
                                    final unit = item['unit'] ?? (isShop ? 'units' : (item['net_unit'] ?? 'g'));
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

  // ── Table widgets ─────────────────────────────────────────────────────
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

  Widget _thRow(List<String> labels) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(color: Color(0xFFF9F8F6), borderRadius: BorderRadius.vertical(top: Radius.circular(14)), border: Border(bottom: BorderSide(color: Color(0xFFEEECE8)))),
      child: Row(
        children: List.generate(labels.length, (i) {
          final isSelected = _dailySortCol == i;
          return Expanded(
            child: InkWell(
              onTap: () {
                setState(() {
                  if (_dailySortCol == i) {
                    _dailySortAsc = !_dailySortAsc;
                  } else {
                    _dailySortCol = i;
                    _dailySortAsc = true;
                  }
                });
              },
              child: Row(
                children: [
                  Text(labels[i].toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: isSelected ? accent : Colors.grey[400], letterSpacing: 1)),
                  const SizedBox(width: 4),
                  Icon(isSelected ? (_dailySortAsc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded) : Icons.unfold_more_rounded, size: 10, color: isSelected ? accent : Colors.grey[300]),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _itemRow(Map<String, dynamic> data) {
    final unit = data['unit'] ?? '';
    final name = data['name'] ?? 'Unknown';
    final isLow = data['status'] == 'low';
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF5F3F0))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF1C1008), fontFamily: 'Outfit')),
                    if (isLow) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(4)),
                        child: Text('LOW', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.red[700])),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(unit.toUpperCase(), style: TextStyle(fontSize: 9, color: Colors.grey[400], fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              ],
            ),
          ),
          Expanded(child: Text(AppData.formatStock(data['beg']?.toDouble() ?? 0.0, unit), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF5F6368)))),
          Expanded(child: Text('+${AppData.formatStock(data['add']?.toDouble() ?? 0.0, unit)}', style: TextStyle(fontSize: 13, color: Colors.green[600], fontWeight: FontWeight.w800))),
          Expanded(child: Text('-${AppData.formatStock(data['out']?.toDouble() ?? 0.0, unit)}', style: TextStyle(fontSize: 13, color: Colors.orange[800], fontWeight: FontWeight.w800))),
          Expanded(child: Text(AppData.formatStock(data['end']?.toDouble() ?? 0.0, unit), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF1C1008)))),
        ],
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
            TextField(controller: ctrl, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(hintText: 'Enter quantity', filled: true, fillColor: const Color(0xFFF5F3F0), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final qty = double.tryParse(ctrl.text) ?? 0;
              if (qty > 0) {
                await AppData.updateStock(isShop, name, qty, isAdd, widget.user['name'] ?? 'Admin', customDate: _selectedDate);
                if (ctx.mounted) { Navigator.pop(ctx); setState(() {}); }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }


  void _exportReport() {
    final bool isMonthlyView = _tabController.index == (isShop ? 3 : 2);
    final allIngredients = isShop ? AppData.shopIngredients : AppData.beansInventory;
    final nameKey = isShop ? 'name' : 'product_name';
    List<String> selectedNames = allIngredients.map((e) => e[nameKey] as String).toList();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (innerCtx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(isMonthlyView ? 'Monthly Export Selection' : 'Daily Export Selection', style: const TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w900, color: Color(0xFF1C1008))),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Select products to include in the ${isMonthlyView ? 'Monthly Summary' : 'Daily Audit'}.', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              const SizedBox(height: 16),
              Flexible(child: SingleChildScrollView(child: Column(children: allIngredients.map((ing) {
                final name = ing[nameKey] as String;
                return CheckboxListTile(value: selectedNames.contains(name), title: Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)), activeColor: accent, dense: true,
                  onChanged: (v) => setDialogState(() { if (v!) { selectedNames.add(name); } else { selectedNames.remove(name); } }));
              }).toList()))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w700))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, elevation: 0),
              onPressed: () async {
                Navigator.pop(ctx);
                _showProcessing('Building Roastery Audit Report...');
                try {
                  final filtered = allIngredients.where((e) => selectedNames.contains(e[nameKey])).toList();
                  await PdfGenerator.exportInventoryReport(business: widget.business, date: _selectedDate, ingredients: filtered, isMonthly: isMonthlyView);
                } finally {
                  if (mounted) {
                    Navigator.of(context, rootNavigator: true).pop(); // Force pop the loading overlay from the root navigator
                  }
                }
              },
              child: const Text('EXPORT SELECTED', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  void _showProcessing(String msg) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: accent),
              const SizedBox(height: 24),
              Text(msg, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1C1008))),
              const SizedBox(height: 4),
              const Text('Building document, please wait...', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}
