import 'package:flutter/material.dart';
import '../data/app_data.dart';
import '../services/supabase_service.dart';
import '../utils/pdf_generator.dart';

class SalesPage extends StatefulWidget {
  final String business;
  final Map<String, dynamic> user;
  const SalesPage({super.key, required this.business, required this.user});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  bool get isShop => widget.business == 'shop';
  Color get accent => isShop ? const Color(0xFFC8822A) : const Color(0xFF4A7C59);

  final Map<Map<String, dynamic>, int> _cart = {};
  String _searchQuery = '';
  String _selectedCategory = 'All';
  late List<Map<String, dynamic>> _allProducts;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    AppData.syncNotifier.addListener(_loadProducts);
  }

  @override
  void didUpdateWidget(SalesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.business != widget.business) {
      _loadProducts();
      _clearCart(); // Optional: clears cart to prevent cross-business mixtures
    }
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFF0EDE8))),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: accent),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF1C1008))),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    AppData.syncNotifier.removeListener(_loadProducts);
    super.dispose();
  }

  void _loadProducts() {
    if (!mounted) return;
    setState(() {
      _allProducts = isShop ? AppData.shopProducts : AppData.beansProducts;
      _isLoading = false;
    });
  }

  List<Map<String, dynamic>> get _filteredProducts {
    return _allProducts.where((p) {
      final nameStr = p['name']?.toString() ?? '';
      final nameLower = nameStr.toLowerCase();
      final queryLower = _searchQuery.toLowerCase();
      final nameMatch = nameLower.contains(queryLower);
      final catMatch = _selectedCategory == 'All' || p['category'] == _selectedCategory;
      return nameMatch && catMatch;
    }).toList();
  }

  List<String> get _categories {
    final cats = _allProducts.map((p) => p['category']?.toString() ?? 'General').toSet().toList();
    cats.sort();
    return ['All', ...cats];
  }

  double get _cartTotal {
    double total = 0;
    _cart.forEach((product, qty) {
      final price = product.containsKey('selectedSize') 
          ? (product['selectedSize']['price'] as num).toDouble() 
          : (product['price'] as num).toDouble();
      total += price * qty;
    });
    return total;
  }

  void _addToCart(Map<String, dynamic> product) {
    setState(() {
      final existingKey = _cart.keys.firstWhere(
        (k) => k['id'] == product['id'] && k['selectedSize']?['name'] == product['selectedSize']?['name'],
        orElse: () => {},
      );

      if (existingKey.isNotEmpty) {
        _cart[existingKey] = _cart[existingKey]! + 1;
      } else {
        _cart[Map<String, dynamic>.from(product)] = 1;
      }
    });
  }

  void _removeFromCart(Map<String, dynamic> product) {
    setState(() {
      if (_cart[product]! > 1) {
        _cart[product] = _cart[product]! - 1;
      } else {
        _cart.remove(product);
      }
    });
  }

  void _clearCart() {
    setState(() {
      _cart.clear();
    });
  }

  void _selectSize(Map<String, dynamic> product) {
    final List<dynamic> sizes = product['sizes'] ?? [];
    if (sizes.isEmpty) {
      // Check stock for non-size product just in case
      final shortages = AppData.checkStockShortage(isShop, [{...product, 'qty': 1}]);
      if (shortages.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Item sold out: ${shortages.join(", ")}'), backgroundColor: Colors.red));
        return;
      }
      _addToCart(product);
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Select Size: ${product['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontFamily: 'Outfit')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: sizes.map((s) {
            // 🛡️ RE-SYNC: Combined Stock + Recipe check
            final ings = (s['ingredients'] as List? ?? []);
            final shortages = AppData.checkStockShortage(isShop, [{...product, 'qty': 1, 'size': s['name']}]);
            
            final noRecipe = isShop && ings.isEmpty;
            final isSizeOut = shortages.isNotEmpty || noRecipe;
            final reason = noRecipe ? 'NO RECIPE' : 'SOLD OUT';
            
            return ListTile(
              enabled: !isSizeOut,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              title: Text(s['name'], style: TextStyle(fontWeight: FontWeight.bold, color: isSizeOut ? Colors.grey : Colors.black87)),
              subtitle: Text(isSizeOut ? reason : '₱ ${s['price']}', style: TextStyle(color: isSizeOut ? Colors.red[300] : accent, fontWeight: FontWeight.bold)),
              trailing: Icon(isSizeOut ? Icons.block_rounded : Icons.add_circle_outline_rounded, color: isSizeOut ? Colors.grey[300] : accent),
              onTap: isSizeOut ? null : () {
                final pWithSize = Map<String, dynamic>.from(product);
                pWithSize['selectedSize'] = s;
                _addToCart(pWithSize);
                Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  String _pf(num v) => v.toStringAsFixed(2);

  void _checkout() async {
    if (_cart.isEmpty) return;

    String? customerName;
    String? receiverName;
    String? address;
    String? contact;
    String paymentMode = 'Cash';
    double deliveryFee = 0.0;
    String? referenceNumber;

    if (isShop) {
      final selectedResult = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => _UnifiedPaymentDialog(accent: accent),
      );
      if (selectedResult == null) return;
      paymentMode = selectedResult['mode'];
      referenceNumber = selectedResult['ref']?.isEmpty == true ? 'N/A' : selectedResult['ref'];
    } else {
      final info = await _showWholesaleDialog();
      if (info == null) return;
      customerName = info['name']?.isEmpty == true ? 'General Client' : info['name'];
      receiverName = info['receiver']?.isEmpty == true ? 'Famela Sumania' : info['receiver'];
      address = info['address'];
      contact = info['contact'];
      paymentMode = info['pay'] ?? 'Cash';
      deliveryFee = info['delivery'] ?? 0.0;
      referenceNumber = info['ref'];
    }

    final saleItems = _cart.entries.map((e) {
      final p = e.key;
      return {
        'id': p['id']?.toString() ?? 'N/A',
        'name': p['name'].toString(),
        'size': p.containsKey('selectedSize') ? p['selectedSize']['name'] : null,
        'qty': e.value,
        'price': p.containsKey('selectedSize') ? (p['selectedSize']['price'] as num).toDouble() : (p['price'] as num).toDouble(),
      };
    }).toList();

    // ── Pre-checkout Stock Validation ───────────────────────────────────────
    final shortages = AppData.checkStockShortage(isShop, saleItems);
    if (shortages.isNotEmpty) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 12),
            Text('Stock Shortage', style: TextStyle(fontWeight: FontWeight.w900, fontFamily: 'Outfit')),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('The following items do not have enough stock:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ...shortages.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $s', style: const TextStyle(fontSize: 13, color: Colors.red)),
              )),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ADJUST ORDER')),
          ],
        ),
      );
      return;
    }

    // 🛡️ Automated SR Sequence Handshake
    final nextSr = isShop ? '' : AppData.getAndIncrementSr();

    // 🚀 High-Speed Background Sync: Don't block the UI while syncing to Supabase
    AppData.recordSale(
      isShop, _cartTotal, items: saleItems, 
      userId: widget.user['id'].toString(), userName: widget.user['name'] ?? 'Unknown',
      customerName: customerName, receiverName: receiverName,
      address: address, contact: contact, paymentMode: paymentMode,
      deliveryFee: deliveryFee, referenceNumber: referenceNumber,
      srNumber: nextSr,
    );

    if (!mounted) return;
    _showSuccessDialog();
    _clearCart(); // Clear cart instantly for next order
  }

  Future<Map<String, dynamic>?> _showWholesaleDialog() {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        final nameCtrl = TextEditingController();
        final addrCtrl = TextEditingController();
        final contCtrl = TextEditingController();
        final deliCtrl = TextEditingController(text: '0');
        final refCtrl  = TextEditingController();
        String selPay = 'Cash';
        return StatefulBuilder(
          builder: (context, setDlg) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            title: const Text('Wholesale SR Data', style: TextStyle(fontWeight: FontWeight.w900, fontFamily: 'Outfit')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // SR Number is now automated - High-Precision Roastery Sync
                  _field(nameCtrl, 'Customer Name', Icons.business_rounded),
                  _field(addrCtrl, 'Address', Icons.location_on_rounded),
                  _field(contCtrl, 'Contact', Icons.phone_rounded),
                  Row(
                    children: [
                      Expanded(child: _field(deliCtrl, 'Delivery Fee', Icons.delivery_dining_rounded, isNum: true)),
                      if (selPay != 'Cash' && selPay != 'Comp') ...[
                        const SizedBox(width: 12),
                        Expanded(child: _field(refCtrl, 'Ref #', Icons.confirmation_number_rounded)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 24),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'Cash', label: Text('Cash')),
                      ButtonSegment(value: 'G-Cash', label: Text('G-Cash')),
                      ButtonSegment(value: 'Bank', label: Text('Bank')),
                      ButtonSegment(value: 'Comp', label: Text('Comp')),
                    ],
                    selected: {selPay},
                    onSelectionChanged: (Set<String> n) => setDlg(() => selPay = n.first),
                    style: SegmentedButton.styleFrom(selectedBackgroundColor: accent, selectedForegroundColor: Colors.white, visualDensity: VisualDensity.compact),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, {
                  'name': nameCtrl.text, 'receiver': 'Famela Sumania', 'address': addrCtrl.text,
                  'contact': contCtrl.text, 'delivery': double.tryParse(deliCtrl.text) ?? 0.0,
                  'ref': refCtrl.text, 'pay': selPay
                }),
                style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('CONFIRM'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _field(TextEditingController c, String l, IconData i, {bool isNum = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: isNum ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: l, prefixIcon: Icon(i, size: 20, color: accent), filled: true, fillColor: const Color(0xFFF5F3F0),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        // 🛡️ Auto-Dismiss Timer for High-Frequency Stores
        Future.delayed(const Duration(milliseconds: 2500), () {
          if (ctx.mounted) Navigator.maybePop(ctx);
        });

        return Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            constraints: const BoxConstraints(maxWidth: 380),
            child: Material(
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              elevation: 40,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 100, width: double.infinity,
                    decoration: BoxDecoration(color: Colors.green.withAlpha(20), borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
                    child: const Center(child: Icon(Icons.check_circle_rounded, color: Color(0xFF2ECC71), size: 48)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
                    child: Column(
                      children: [
                        const Text('Sale Confirmed', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, fontFamily: 'Outfit')),
                        const SizedBox(height: 4),
                        Text('Order has been processed.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => Navigator.pop(ctx),
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF5F3F0), foregroundColor: Colors.black, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                                child: const Text('OK'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  final tx = (isShop ? AppData.shopReports : AppData.beansTransactions).first;
                                  PdfGenerator.printReceipt(tx, businessName: isShop?'Shop':'Beans', preparedBy: widget.user['name']);
                                },
                                icon: const Icon(Icons.print_rounded, size: 16),
                                label: const Text('PRINT'),
                                style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, elevation: 2, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F3F0),
      body: Row(
        children: [
          // Main Body
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                _buildFilterBar(),
                Expanded(
                  child: _filteredProducts.isEmpty
                    ? _buildEmptyState()
                    : GridView.builder(
                        padding: const EdgeInsets.all(32),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisSpacing: 24, crossAxisSpacing: 24, childAspectRatio: 0.75),
                        itemCount: _filteredProducts.length,
                        itemBuilder: (ctx, i) => _buildProductCard(_filteredProducts[i]),
                      ),
                ),
              ],
            ),
          ),
          // Sidebar
          _buildSidebar(),
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
                const Text('Point of Sale', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, fontFamily: 'Outfit', color: Color(0xFF1C1008))),
                Text(isShop ? 'Innovative Cuppa Coffee Shop' : 'Innovative Beans Business', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: accent)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _actionBtn(Icons.sync_rounded, 'Refresh', () async {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Roastery Sync Initiated... 🛡️📊'), duration: Duration(milliseconds: 800)));
            await SupabaseService.pullFromCloud();
            if (mounted) {
              _loadProducts();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Resilient Cloud Sync Complete 🛡️⚓'), backgroundColor: Colors.green));
            }
          }),
          const SizedBox(width: 24),
          Flexible(
            child: Container(
              height: 54,
              constraints: const BoxConstraints(maxWidth: 340),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withAlpha(3), blurRadius: 10, offset: const Offset(0, 4))]),
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(hintText: 'Lookup items...', prefixIcon: Icon(Icons.search_rounded, color: accent), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(40, 32, 40, 0),
      child: SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: _categories.map((cat) {
            final sel = _selectedCategory == cat;
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ChoiceChip(
                label: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(cat)),
                selected: sel,
                onSelected: (v) => setState(() => _selectedCategory = cat),
                selectedColor: accent,
                labelStyle: TextStyle(color: sel ? Colors.white : Colors.black87, fontWeight: sel ? FontWeight.w800 : FontWeight.w600, fontSize: 13),
                showCheckmark: false,
                elevation: sel ? 4 : 0,
                shadowColor: accent.withAlpha(50),
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: sel ? accent : const Color(0xFFEEECE8))),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 60, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('No products found matching filters', style: TextStyle(color: Colors.grey[400], fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> p) {
    bool isSoldOut = false;
    String soldOutReason = 'SOLD OUT';
    
    // Check stock for the item (at qty 1)
    if (isShop) {
      if (p['has_sizes'] == true) {
        final sizes = (p['sizes'] as List? ?? []);
        bool anyAvailable = false;
        bool anyRecipe = false;
        for (var s in sizes) {
          final ings = (s['ingredients'] as List? ?? []);
          if (ings.isNotEmpty) {
            anyRecipe = true;
            final shortages = AppData.checkStockShortage(isShop, [{...p, 'qty': 1, 'size': s['name']}]);
            if (shortages.isEmpty) { anyAvailable = true; break; }
          }
        }
        if (!anyRecipe) {
          isSoldOut = true;
          soldOutReason = 'NO RECIPE';
        } else {
          isSoldOut = !anyAvailable;
        }
      } else {
        final ings = (p['ingredients'] as List? ?? []);
        final rawSizes = (p['sizes'] as List? ?? []);
        
        bool hasRecipe = ings.isNotEmpty || (rawSizes.isNotEmpty && (rawSizes.first['ingredients'] as List? ?? []).isNotEmpty);
        
        if (!hasRecipe) {
          isSoldOut = true;
          soldOutReason = 'NO RECIPE';
        } else {
          final shortages = AppData.checkStockShortage(isShop, [{...p, 'qty': 1}]);
          isSoldOut = shortages.isNotEmpty;
        }
      }
    } else {
      final shortages = AppData.checkStockShortage(isShop, [{...p, 'qty': 1}]);
      isSoldOut = shortages.isNotEmpty;
    }

    return Opacity(
      opacity: isSoldOut ? 0.6 : 1.0,
      child: Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 24, offset: const Offset(0, 12)),
            BoxShadow(color: accent.withAlpha(5), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isSoldOut ? null : (() => (isShop && p['has_sizes'] == true) ? _selectSize(p) : _addToCart(p)),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Image Area
                  Expanded(
                    flex: 12,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: accent.withAlpha(5),
                          ),
                          child: (p['image_url'] != null && p['image_url'].toString().isNotEmpty)
                              ? Image.network(
                                  p['image_url'].toString(),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Center(child: Icon(isShop ? Icons.local_cafe_rounded : Icons.grain_rounded, size: 48, color: accent.withAlpha(40))),
                                  loadingBuilder: (_, child, prog) => prog == null ? child : Center(child: CircularProgressIndicator(color: accent, strokeWidth: 2)),
                                )
                              : Center(child: Icon(isShop ? Icons.local_cafe_rounded : Icons.grain_rounded, size: 48, color: accent.withAlpha(40))),
                        ),
                        // Top Gradient for better text readability if we add any
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
                        // Category Pill
                        Positioned(
                          top: 12, left: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: Colors.white.withAlpha(200), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white.withAlpha(200))),
                            child: Text(p['category']?.toString().toUpperCase() ?? 'GENERAL', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: accent, letterSpacing: 0.8)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Content Area
                  Expanded(
                    flex: 12,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p['name'] ?? 'Untitled Item', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, fontFamily: 'Outfit', color: Color(0xFF1C1008), height: 1.1), maxLines: 2, overflow: TextOverflow.ellipsis),
                          if (!isShop && (p['net_weight']?.toString().isNotEmpty ?? false))
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                                child: Text('${p['net_weight']}${p['net_unit'] ?? ''}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: accent)),
                              ),
                            ),
                          const Spacer(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p['has_sizes'] == true ? 'Multiple' : '₱${p['price']}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: accent, fontFamily: 'Outfit')),
                                  if (p['has_sizes'] == true) Text('Available Sizes', style: TextStyle(fontSize: 9, color: Colors.grey[400], fontWeight: FontWeight.w600)),
                                ],
                              ),
                              if (!isSoldOut)
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: accent,
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [BoxShadow(color: accent.withAlpha(60), blurRadius: 10, offset: const Offset(0, 4))],
                                  ),
                                  child: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              // Sold Out Overlay
              if (isSoldOut)
                Positioned.fill(
                  child: Container(
                    color: Colors.white.withAlpha(150),
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(color: Colors.red[600], borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.red.withAlpha(40), blurRadius: 10, offset: const Offset(0, 4))]),
                      child: Text(soldOutReason, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1.5)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 400,
      decoration: BoxDecoration(color: Colors.white, border: const Border(left: BorderSide(color: Color(0xFFF0EDE8))), boxShadow: [BoxShadow(color: Colors.black.withAlpha(4), blurRadius: 40, offset: const Offset(-10, 0))]),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 48, 32, 24),
            child: Row(
              children: [
                Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: accent.withAlpha(15), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.shopping_bag_rounded, color: accent, size: 24)),
                const SizedBox(width: 16),
                const Text('Current Order', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, fontFamily: 'Outfit')),
                const Spacer(),
                if (_cart.isNotEmpty) TextButton(onPressed: _clearCart, child: Text('Clear All', style: TextStyle(color: Colors.red[400], fontWeight: FontWeight.w800))),
              ],
            ),
          ),
          Expanded(
            child: _cart.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shopping_cart_outlined, size: 60, color: Colors.grey[200]),
                        const SizedBox(height: 16),
                        Text('Your basket is empty', style: TextStyle(color: Colors.grey[300], fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: _cart.length,
                    separatorBuilder: (ctx, i) => const SizedBox(height: 12),
                    itemBuilder: (ctx, i) => _buildCartItem(_cart.keys.elementAt(i), _cart.values.elementAt(i)),
                  ),
          ),
          _buildSummarySection(),
        ],
      ),
    );
  }

  Widget _buildSummarySection() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: Colors.white, border: const Border(top: BorderSide(color: Color(0xFFF0EDE8))), boxShadow: [BoxShadow(color: Colors.black.withAlpha(2), blurRadius: 20, offset: const Offset(0, -10))]),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Grand Total', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.grey)),
              Text('₱ ${_pf(_cartTotal)}', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: accent, fontFamily: 'Outfit', letterSpacing: -1)),
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity, height: 68,
            child: ElevatedButton(
              onPressed: _cart.isEmpty ? null : _checkout,
              style: ElevatedButton.styleFrom(
                backgroundColor: accent, foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFF5F3F0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 8, shadowColor: accent.withAlpha(100),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('GO TO CHECKOUT', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5)),
                  const SizedBox(width: 12),
                  const Icon(Icons.arrow_forward_rounded, size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartItem(Map<String, dynamic> p, int q) {
    final price = p.containsKey('selectedSize') ? p['selectedSize']['price'] : p['price'];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFF9F8F6), borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p['name'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (p.containsKey('selectedSize')) 
                  Text(p['selectedSize']['name'], style: TextStyle(fontSize: 12, color: accent, fontWeight: FontWeight.bold))
                else if (!isShop && (p['net_weight']?.toString().isNotEmpty ?? false))
                  Text('${p['net_weight']}${p['net_unit'] ?? ''}', style: TextStyle(fontSize: 12, color: accent, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('₱ $price each', style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Row(
            children: [
              _cartAction(Icons.remove_rounded, Colors.grey, () => _removeFromCart(p)),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('$q', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
              _cartAction(Icons.add_rounded, accent, () => _addToCart(p)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cartAction(IconData i, Color c, VoidCallback t) {
    return InkWell(
      onTap: t,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFEEECE8))),
        child: Icon(i, size: 16, color: c),
      ),
    );
  }
}

class _UnifiedPaymentDialog extends StatefulWidget {
  final Color accent;
  const _UnifiedPaymentDialog({required this.accent});

  @override
  State<_UnifiedPaymentDialog> createState() => _UnifiedPaymentDialogState();
}

class _UnifiedPaymentDialogState extends State<_UnifiedPaymentDialog> {
  String selectedMode = 'Cash';
  final refCtrl = TextEditingController();

  Widget _btn(String mode, IconData ic, Color c) {
    bool sel = selectedMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => selectedMode = mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: sel ? c.withAlpha(20) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: sel ? c : const Color(0xFFF0EDE8), width: 2),
            boxShadow: sel ? [BoxShadow(color: c.withAlpha(30), blurRadius: 10, offset: const Offset(0, 4))] : [],
          ),
          child: Column(
            children: [
              Icon(ic, color: sel ? c : Colors.grey[400], size: 28),
              const SizedBox(height: 8),
              Text(mode, style: TextStyle(fontWeight: FontWeight.w900, color: sel ? c : Colors.grey[600], fontSize: 13, letterSpacing: 0.5)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        constraints: const BoxConstraints(maxWidth: 420),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          elevation: 60,
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Quick Checkout', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, fontFamily: 'Outfit')),
                const SizedBox(height: 8),
                Text('Select payment and confirm', style: TextStyle(color: Colors.grey[500], fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 32),
                Row(
                  children: [
                    _btn('Cash', Icons.payments_rounded, const Color(0xFF2ECC71)),
                    const SizedBox(width: 12),
                    _btn('GCash', Icons.account_balance_wallet_rounded, const Color(0xFF007BFF)),
                    const SizedBox(width: 12),
                    _btn('Maya', Icons.wallet_rounded, const Color(0xFF00C853)),
                  ],
                ),
                if (selectedMode != 'Cash') ...[
                  const SizedBox(height: 24),
                  TextField(
                    controller: refCtrl,
                    autofocus: true,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1),
                    decoration: InputDecoration(
                      hintText: 'Reference Number',
                      filled: true,
                      fillColor: const Color(0xFFF9F8F6),
                      prefixIcon: Icon(Icons.confirmation_number_rounded, color: widget.accent, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, {'mode': selectedMode, 'ref': refCtrl.text}),
                    style: ElevatedButton.styleFrom(backgroundColor: widget.accent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 8, shadowColor: widget.accent.withAlpha(100)),
                    child: const Text('FINALIZE ORDER', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w800))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
