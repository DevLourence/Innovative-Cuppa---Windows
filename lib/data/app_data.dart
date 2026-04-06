import 'dart:async';
import 'package:flutter/material.dart';
import '../services/persistence_service.dart';
import '../services/supabase_service.dart';

class AppData {
  static final ValueNotifier<bool> darkModeNotifier = ValueNotifier<bool>(false);
  
  /// Page Access Permissions by Role
  static final Map<String, List<String>> rolePermissions = {
    'admin': ['sales', 'products', 'inventory', 'reports', 'accounts', 'history'],
    'manager': ['sales', 'products', 'inventory', 'reports', 'history'],
    'cashier': ['sales', 'history'],
    'barista': ['sales', 'products', 'inventory'],
  };

  /// Reactive low-stock counts: [shopCount, beansCount]
  static final ValueNotifier<List<int>> lowStockNotifier = ValueNotifier<List<int>>([0, 0]);
  
  /// Global sync status
  static final ValueNotifier<int> syncNotifier = ValueNotifier<int>(0);

  static bool isShop(String id) => id.startsWith('TR-');

  /// 🛡️ ADAPTIVE CONVERSION: Formats stock with sub-unit intelligence (kg -> g, L -> ml)
  /// Automatically scales down for micro-measurements and strips .0 for whole numbers.
  static String formatStock(double qty, String unit) {
    String u = unit;
    double v = qty;
    
    final uLower = unit.toLowerCase();
    
    // Scale down logic for small measurements
    if (uLower == 'kg' && qty < 1.0 && qty > 0) {
      v = qty * 1000;
      u = 'g';
    } else if (uLower == 'l' && qty < 1.0 && qty > 0) {
      v = qty * 1000;
      u = 'ml';
    } else if (uLower == 'lb' && qty < 1.0 && qty > 0) {
      v = qty * 16;
      u = 'oz';
    } else if (uLower == 'gal' && qty < 1.0 && qty > 0) {
      v = qty * 3.78541;
      u = 'L';
      if (v < 1.0) { v *= 1000; u = 'ml'; }
    }
    
    // 🛡️ Enhanced Precision: Use fmt logic to show up to 3 decimal places but strip trailing .0
    String fmtStr = v.toStringAsFixed(3);
    if (fmtStr.contains('.')) {
      while (fmtStr.endsWith('0')) { fmtStr = fmtStr.substring(0, fmtStr.length - 1); }
      if (fmtStr.endsWith('.')) { fmtStr = fmtStr.substring(0, fmtStr.length - 1); }
    }

    return '$fmtStr $u';
  }

  static double getLowStockThreshold(String ingName, bool isShop) {
    double maxReq = 0.1; // Baseline
    final products = isShop ? shopProducts : beansProducts;
    final ingredients = isShop ? shopIngredients : beansInventory;
    final nameK = isShop ? 'name' : 'product_name';
    final invMatches = ingredients.where((i) => i[nameK] == ingName);
    if (invMatches.isEmpty) {
      return 0.3;
    }
    final invUnit = invMatches.first['unit']?.toString().toLowerCase() ?? '';

    for (var p in products) {
      final List variants = (p['sizes'] as List? ?? []);
      final List standardIngs = (p['ingredients'] as List? ?? []);
      
      List<List> allRecipeGroups = [standardIngs];
      for (var v in variants) {
        allRecipeGroups.add(v['ingredients'] as List? ?? []);
      }

      for (var group in allRecipeGroups) {
        for (var ing in group) {
           if (ing['item'] == ingName || ing['name'] == ingName) {
              final qty = (ing['qty'] as num?)?.toDouble() ?? 0.0;
              final rUnit = ing['unit']?.toString().toLowerCase() ?? '';
              
              double multiplier = 1.0;
              if (rUnit == 'g' && invUnit == 'kg') {
                multiplier = 0.001;
              } else if (rUnit == 'ml' && invUnit == 'l') {
                multiplier = 0.001;
              } else if (rUnit == 'kg' && invUnit == 'g') {
                multiplier = 1000.0;
              } else if (rUnit == 'l' && invUnit == 'ml') {
                multiplier = 1000.0;
              }

              if (qty * multiplier > maxReq) {
                maxReq = qty * multiplier;
              }
           }
        }
      }
    }
    return maxReq * 3; // 🚀 Target: 3 Orders
  }

  static void _refreshLowStockCount(bool isShopStatus) {
    final shopLow = shopIngredients.where((i) {
      final val = (i['stock'] as num?)?.toDouble() ?? (double.tryParse(i['stock']?.toString() ?? '0') ?? 0.0);
      final initial = (i['initial_qty'] as num?)?.toDouble() ?? val;
      return initial > 0 && val <= initial * 0.2;
    }).length;

    final beansLow = beansInventory.where((i) {
      final val = (i['balance_qty'] as num?)?.toDouble() ?? (double.tryParse(i['balance_qty']?.toString() ?? '0') ?? 0.0);
      final initial = (i['initial_qty'] as num?)?.toDouble() ?? val;
      return initial > 0 && val <= initial * 0.2;
    }).length;

    lowStockNotifier.value = [shopLow, beansLow];
  }
  
  // ── Database Table Containers ───────────────────────────────────────────
  
  static List<Map<String, dynamic>> accounts = [];
  
  static List<Map<String, dynamic>> beansProducts = [];
  static List<Map<String, dynamic>> beansSrData = [];
  static List<Map<String, dynamic>> beansTransactions = [];
  static List<Map<String, dynamic>> beansInventory = []; // Maps to beans stock

  static List<Map<String, dynamic>> shopProducts = [];
  static List<Map<String, dynamic>> shopIngredients = [];
  static List<Map<String, dynamic>> shopInventory = []; // Maps to movement logs
  static List<Map<String, dynamic>> shopReports = []; // Raw sales entries (from shop_transactions)
  static List<Map<String, dynamic>> shopOverall = []; // Overall report metadata (from shop_reports)

  // ── Logic ──────────────────────────────────────────────────────────────
  
  static final Map<String, double> _cachedTotals = {};
  
  static void _invalidateCache() {
    _cachedTotals.clear();
  }

  static Future<void> ensureInventorySync(String userName) async {
    bool hasChanges = false;
    // 🛡️ SYNC SHOP INGREDIENTS
    for (var p in shopProducts) {
      if (p['ingredients'] != null && p['ingredients'] is List) {
        final ingList = p['ingredients'] as List;
        for (var i in ingList) {
          final name = i['name'] as String;
          final exists = shopIngredients.any((si) => si['name'] == name);
          if (!exists) {
            hasChanges = true;
            debugPrint('Auto-Sync: Initializing missing shop ingredient -> $name');
            await updateStock(true, name, 0, true, userName, isInitializing: true, skipPersistence: true);
          }
        }
      }
    }

    // 🛡️ SYNC BEANS INVENTORY
    for (var p in beansProducts) {
      final name = p['name'] as String;
      final exists = beansInventory.any((i) => i['product_name'] == name);
      if (!exists) {
        hasChanges = true;
        debugPrint('Auto-Sync: Initializing missing beans product -> $name');
        
        // 🛡️ High-Precision Unit Capture: Pull professional units from product metadata
        final unit = p['net_unit']?.toString() ?? 'g';
        final initQty = (p['net_weight'] as num?)?.toDouble() ?? 0.0;
        
        await updateStock(false, name, 0, true, userName, isInitializing: true, skipPersistence: true, unitOverride: unit);
        // Force refresh the new item with its initial weight if possible
        final newItemIdx = beansInventory.indexWhere((i) => i['product_name'] == name);
        if (newItemIdx != -1) {
          beansInventory[newItemIdx]['initial_qty'] = initQty;
          beansInventory[newItemIdx]['balance_qty'] = initQty;
        }
      }
    }

    if (hasChanges) {
      await PersistenceService.saveState();
    }
  }

  static Future<void> init() async {
    final cloud = await SupabaseService.pullFromCloud();
    
    // 🛡️ SAFETY FALLBACK: If cloud is unreachable OR specifically empty (e.g. migration)
    // merge with the local disk state so we don't lose restocks.
    if (!cloud || (beansInventory.isEmpty && shopIngredients.isEmpty)) {
      debugPrint('AppData: No cloud data found, performing High-Precision Disk Recovery...');
      await PersistenceService.loadState();
    }
    
    _refreshLowStockCount(true);
    _normalizeShopUnits(); // 🛡️ Proactively correct "units" to professional roastery units

    // 🛡️ HIGH-FREQUENCY BACKGROUND AUTO-SYNC: Pulse cloud parity every 1 minute for a real-time roastery command center
    Timer.periodic(const Duration(minutes: 1), (t) async {
       debugPrint('AppData: High-Precision 60-Second Auto-Sync Pulse...');
       await SupabaseService.pullFromCloud();
    });
  }

  static Future<void> _normalizeShopUnits() async {
    bool hasChanges = false;
    for (var ing in shopIngredients) {
      if (ing['unit'] == 'units' || ing['unit'] == null) {
        final name = (ing['name'] ?? '').toString().toLowerCase();
        String? newUnit;
        
        if (name.contains('matcha')) {
          newUnit = 'g';
        } else if (name.contains('milk')) {
          newUnit = 'L';
        } else if (name.contains('sweetener')) {
          newUnit = 'L';
        } else if (name.contains('cups') || name.contains('lids')) {
          newUnit = 'sets';
        }
        
        if (newUnit != null) {
          debugPrint('Smart-Normalizer: Standardizing ${ing['name']} -> $newUnit');
          ing['unit'] = newUnit;
          hasChanges = true;
          // Proactively push the correction to cloud
          await SupabaseService.upsert('shop_ingredients', ing);
        }
      }
    }
    if (hasChanges) {
      syncNotifier.value++;
      PersistenceService.saveState();
    }
  }

  static int _srCounter = 5000;
  static String _srPrefix = 'SR-';

  static int getSrCounter() => _srCounter;
  static void setSrCounter(int val) => _srCounter = val;
  
  static String getSrPrefix() => _srPrefix;
  static void setSrPrefix(String prefix) => _srPrefix = prefix;

  static String getAndIncrementSr() {
    final res = '$_srPrefix$_srCounter';
    _srCounter++;
    PersistenceService.saveState();
    return res;
  }
  
  static Future<void> recordSale(bool isShop, double amount, {
    required List<Map<String, dynamic>> items,
    required String userId,
    required String userName,
    String? customerName,
    String? receiverName,
    String? address,
    String? contact,
    String paymentMode = 'Cash',
    double deliveryFee = 0.0,
    String? referenceNumber,
    String? srNumber,
  }) async {
    final list = isShop ? shopReports : beansTransactions;
    final prefix = isShop ? 'TX-' : _srPrefix;
    final now = DateTime.now();
    
    // 🛡️ SR Number is now automated - High-Precision Roastery Sync
    final id = isShop
        ? '$prefix${now.millisecondsSinceEpoch}'
        : (srNumber?.isNotEmpty == true ? srNumber! : '$prefix${_srCounter++}');

    final txData = {
      'id': id,
      'sr_number': isShop ? id : (srNumber ?? id), // Dedicate sequence field
      'date': now,
      'amount': amount,
      'items': items,
      'user_name': userName,
      'payment_mode': paymentMode,
      'reference_number': referenceNumber ?? 'N/A',
      'type': 'sold',
    };

    // 🛡️ Filtered version for general movement ledger (beans_transactions) to prevent 'column not found' errors
    // We only attach customer data to the dedicated SR audit table
    final extendedTxData = {
      ...txData,
      if (!isShop) 'customer_name': customerName ?? 'General Client',
      if (!isShop) 'receiver_name': receiverName ?? 'Famela Sumania',
      if (!isShop) 'address': address ?? 'N/A',
      if (!isShop) 'contact': contact ?? 'N/A',
    };

    list.insert(0, extendedTxData);
    
    // 🛡️ UNIVERSAL SALES LOGGING (Register every sale to Audit Movement tables)
    final movementTable = isShop ? 'shop_transactions' : 'beans_transactions';
    await SupabaseService.upsert(movementTable, isShop ? extendedTxData : txData);

    // 🛡️ Beans Business Specific: Log to professional SR Data table for audit with FULL wholesale metadata
    if (!isShop) {
      await SupabaseService.insert('beans_sr_data', {
        'sr_number': id,
        'customer_name': customerName ?? 'General Client',
        'receiver_name': receiverName ?? 'Famela Sumania',
        'address': address ?? 'N/A',
        'contact': contact ?? 'N/A',
        'total_amount': amount,
        'delivery_fee': deliveryFee,
        'payment_mode': paymentMode,
        'reference_number': referenceNumber,
        'prepared_by': userName,
        'user_id': userId,
        'items': items,
        'meta_data': extendedTxData,
      });
    }

    if (isShop) {
      // 2. Report Entry (Overall Metadata for custom reporting engine)
      final reportData = {
        'report_type': 'sale',
        'target_date': now.toIso8601String().split('T')[0],
        'summary_data': txData,
      };
      await SupabaseService.insert('shop_reports', reportData);
      _refreshLowStockCount(true);
    } else {
      // 🛡️ Beans Business Deduction: Products map directly to inventory items
      for (final soldItem in items) {
        final name = soldItem['name'] ?? 'Unknown';
        final qty = (soldItem['qty'] as num?)?.toDouble() ?? 0.0;
        
        // 🚀 Deduct from master beans inventory (this also handles cloud sync/logging)
        await updateStock(false, name, qty, false, userName);
      }
      _refreshLowStockCount(false);
    }

    // ── Auto-deduct ingredients ──────────────────────────────────────────────
    final ingredients = isShop ? shopIngredients : beansInventory;
    final products = isShop ? shopProducts : beansProducts;

    for (final soldItem in items) {
      final soldName = soldItem['name']?.toString() ?? '';
      final soldQty  = (soldItem['qty'] as num?)?.toDouble() ?? 1.0;
      final soldSize = soldItem['size']?.toString();

      // Find the product definition
      final productMatches = products.where((p) => p['name'] == soldName);
      if (productMatches.isEmpty) continue;
      final product = productMatches.first;

      // Get ingredient list for this product (size-aware)
      List<dynamic> ingList = [];
      if (product['has_sizes'] == true && soldSize != null) {
        final sizeMatches = (product['sizes'] as List).where((s) {
          final sName = s['name']?.toString().toLowerCase().replaceAll(' ', '') ?? '';
          final target = soldSize.toLowerCase().replaceAll(' ', '');
          return sName == target;
        });
        if (sizeMatches.isNotEmpty) {
          ingList = sizeMatches.first['ingredients'] ?? [];
        }
      } else {
        // 🛡️ High-Performance Fallback: Check top-level 'ingredients' OR first entry of 'sizes'
        final rawSizes = product['sizes'] as List?;
        ingList = (product['ingredients'] as List?) ?? 
                  ((rawSizes != null && rawSizes.isNotEmpty) ? (rawSizes.first['ingredients'] as List?) ?? [] : []);
      }

      // Deduct each ingredient
      for (final ing in ingList) {
        final ingName = ing['item']?.toString() ?? '';
        final ingQty  = (ing['qty'] as num?)?.toDouble() ?? 0.0;
        final ingUnit = ing['unit']?.toString() ?? ''; // Unit from recipe

        final nameKey = isShop ? 'name' : 'product_name';
        final stockKey = isShop ? 'stock' : 'balance_qty';

        final ingMatches = ingredients.where((i) => i[nameKey] == ingName);
        if (ingMatches.isEmpty) continue;
        final ingItem = ingMatches.first;
        final invUnit = ingItem['unit']?.toString() ?? ''; // Unit in inventory

        // Conversion logic
        double multiplier = 1.0;
        String rU = ingUnit.toLowerCase().trim();
        String iU = invUnit.toLowerCase().trim();

        // Normalize synonyms
        if (rU == 'liter' || rU == 'litre') rU = 'l';
        if (iU == 'liter' || iU == 'litre') iU = 'l';
        if (rU == 'kilogram') rU = 'kg';
        if (iU == 'kilogram') iU = 'kg';
        if (rU == 'gram') rU = 'g';
        if (iU == 'gram') iU = 'g';
        if (rU == 'ounce') rU = 'oz';
        if (iU == 'ounce') iU = 'oz';

        if (rU != iU) {
          // Weight (g, kg, oz, lb)
          if (rU == 'g' && iU == 'kg') { multiplier = 0.001; }
          else if (rU == 'kg' && iU == 'g') { multiplier = 1000.0; }
          else if (rU == 'oz' && iU == 'g') { multiplier = 28.3495; }
          else if (rU == 'g' && iU == 'oz') { multiplier = 0.035274; }
          else if (rU == 'oz' && iU == 'kg') { multiplier = 0.0283495; }
          else if (rU == 'kg' && iU == 'oz') { multiplier = 35.274; }
          else if (rU == 'lb' && iU == 'kg') { multiplier = 0.453592; }
          else if (rU == 'kg' && iU == 'lb') { multiplier = 2.20462; }
          else if (rU == 'lb' && iU == 'g') { multiplier = 453.592; }
          else if (rU == 'g' && iU == 'lb') { multiplier = 0.00220462; }

          // Volume (ml, l, oz, gal, tsp, tbsp)
          else if (rU == 'ml' && iU == 'l') { multiplier = 0.001; }
          else if (rU == 'l' && iU == 'ml') { multiplier = 1000.0; }
          else if (rU == 'oz' && iU == 'ml') { multiplier = 29.5735; }
          else if (rU == 'ml' && iU == 'oz') { multiplier = 0.033814; }
          else if (rU == 'oz' && iU == 'l') { multiplier = 0.0295735; }
          else if (rU == 'l' && iU == 'oz') { multiplier = 33.814; }
          else if (rU == 'gal' && iU == 'l') { multiplier = 3.78541; }
          else if (rU == 'l' && iU == 'gal') { multiplier = 0.264172; }
          else if (rU == 'tsp' && iU == 'ml') { multiplier = 4.92892; }
          else if (rU == 'tbsp' && iU == 'ml') { multiplier = 14.7868; }
          else if (rU == 'tsp' && iU == 'g') { multiplier = 5.0; } // Estimate for dry tsp
          else if (rU == 'tbsp' && iU == 'g') { multiplier = 15.0; } // Estimate for dry tbsp
        }

        final totalDeduct = (ingQty * multiplier) * soldQty;

        final currentStock = (ingItem[stockKey] as num).toDouble();
        ingItem[stockKey] = ((currentStock - totalDeduct).clamp(0.0, double.infinity)).toDouble();
        
        // 🚀 INSTANT RESPONSE: Notify UI that local memory has been updated!
        AppData.syncNotifier.value++;

        // PERSIST to cloud (Background)
        final table = isShop ? 'shop_ingredients' : 'beans_inventory';
        SupabaseService.upsert(table, ingItem);

        // 🛡️ EXTRA: Log dedicated movement records for full inventory monitoring
        final now = DateTime.now();
        if (isShop) {
           final targetId = ingItem['id'] ?? ingItem['uuid'];
           if (targetId != null) {
              final movement = {
                'target_ingredient_id': targetId,
                'itemName': ingName, // 🛡️ RELIABILITY: Ensure name is attached for instant UI matching
                'change_qty': -totalDeduct,
                'action_type': 'sold', // Distinguished as auto-deducted during sale
                'performed_by': txData['user_name'] ?? 'System',
                'timestamp': now.toIso8601String(),
              };
              
              // 🚀 LOCAL INJECTION: Add to memory instantly
              shopInventory.add(movement);
              AppData.syncNotifier.value++;

              SupabaseService.insert('shop_inventory', movement);
           }
        } else {
          final movementLog = {
            'id': 'SOD-${now.millisecondsSinceEpoch}-${ingName.hashCode}',
            'date': now,
            'amount': 0.0,
            'itemName': ingName,
            'qty': totalDeduct,
            'items': [{'name': ingName, 'qty': totalDeduct}],
            'user_name': txData['user_name'],
            'type': 'sold', // Distinguished as auto-deducted during sale
            'reference_number': id, // Link to the SR number
          };
          
          // 🚀 LOCAL INJECTION: Add to memory instantly for Beans too
          beansTransactions.add(movementLog);
          AppData.syncNotifier.value++;

          // Push to movement table in background for the audit trail
          SupabaseService.insert('beans_transactions', movementLog);
        }
      }
    }

    _invalidateCache();
    // Refresh low stock notifier so sidebar badge updates reactively
    _refreshLowStockCount(isShop);
    PersistenceService.saveState();
  }

  static Future<void> updateTransactionMetadata(bool isShop, String id, {
    String? customerName,
    String? address,
    String? contact,
  }) async {
    final list = isShop ? shopReports : beansTransactions;
    final index = list.indexWhere((t) => t['id'] == id);
    
    if (index != -1) {
      final tx = list[index];
      if (customerName != null) tx['customer_name'] = customerName;
      if (address != null) tx['address'] = address;
      if (contact != null) tx['contact'] = contact;

      final table = isShop ? 'shop_transactions' : 'beans_transactions';
      await SupabaseService.update(table, tx, id);

      if (!isShop) {
        // Also update the dedicated SR audit table
        await SupabaseService.update('beans_sr_data', {
          'customer_name': tx['customer_name'],
          'address': tx['address'],
          'contact': tx['contact'],
          'meta_data': tx,
        }, id, column: 'sr_number');
      }
      
      syncNotifier.value++;
      PersistenceService.saveState();
    }
  }

  static Future<void> updateStock(bool isShop, String name, double qty, bool isAdd, String userName, {DateTime? customDate, bool isInitializing = false, bool skipPersistence = false, String? unitOverride}) async {
    final list = isShop ? shopIngredients : beansInventory;
    final txList = isShop ? shopInventory : beansTransactions;

    final itemKey = isShop ? 'name' : 'product_name';
    final stockKey = isShop ? 'stock' : 'balance_qty';
    
    // 🛡️ High-Precision Unit Fallback
    final defaultUnit = isShop ? 'units' : 'pcs';

    final itemMatches = list.where((e) => e[itemKey] == name);
    
    Map<String, dynamic> item;
    if (itemMatches.isEmpty) {
      if (!isInitializing && !isAdd) return; // Can't deduct from non-existent item
      
      // Initialize new item record - strictly preserving world-class precision
      item = {
        itemKey: name,
        stockKey: 0.0,
        'unit': unitOverride ?? defaultUnit,
      };
      list.add(item);
    } else {
      item = itemMatches.first;
    }

    if (itemMatches.isNotEmpty || isInitializing || isAdd) {
      final unit = item['unit'] ?? defaultUnit; // Strictly use the record's professional unit
      
      final now = DateTime.now();
      final effectiveDate = customDate ?? now;

      if (isAdd) {
        item[stockKey] = ((item[stockKey] as num?)?.toDouble() ?? 0.0) + qty;
      } else {
        item[stockKey] = ((item[stockKey] as num?)?.toDouble() ?? 0.0) - qty;
      }

      final stockTx = {
        'id': (isAdd ? 'ST-' : 'SO-') + now.millisecondsSinceEpoch.toString(),
        'date': effectiveDate,
        'amount': 0.0,
        'items': [{'name': name, 'qty': qty}],
        'user_name': userName,
        'type': isAdd ? 'restock' : 'out',
      };

      txList.insert(0, stockTx);
      
      // 3. Cloud & Disk Persistence (High-Priority Committal)
      if (!skipPersistence) {
        debugPrint('AppData: Committing $name balance change to cloud ($qty $unit)...');
        final futures = <Future>[];
        // Final update to the ingredient/product current balance record
        futures.add(SupabaseService.upsert(isShop ? 'shop_ingredients' : 'beans_inventory', item));
        
        if (isShop) {
           // 🛡️ SCHEMA-PERFECT MAPPING with high-precision ID validation
           final targetId = item['id'] ?? item['uuid']; // Safely resolve the ingredient's cloud ID
           
           if (targetId != null) {
             futures.add(SupabaseService.insert('shop_inventory', {
                'target_ingredient_id': targetId,
                'change_qty': isAdd ? qty : -qty,
                'action_type': isAdd ? 'restock' : 'out',
                'performed_by': userName,
                'timestamp': now.toIso8601String(),
             }));
           } else {
             debugPrint('AppData: Warning - Skipping cloud log for $name (Ingredient ID is missing)');
           }
        } else {
           // Standard Beans movement log record
           futures.add(SupabaseService.upsert('beans_transactions', stockTx));
        }
        
        await Future.wait(futures).then((_) {
          debugPrint('AppData: Cloud Committal SUCCESS for $name');
        }).catchError((e) {
          debugPrint('AppData: Cloud Committal ERROR: $e');
        });
        
        _refreshLowStockCount(isShop);
        await PersistenceService.saveState();
        syncNotifier.value++; // Instant UI feedback
      }
    }
  }

  static double getSalesTotal(bool isShop, {bool monthly = false, bool allTime = false}) {
    final cacheKey = '${isShop ? 'shop' : 'beans'}_${monthly ? 'mo' : (allTime ? 'all' : 'day')}';
    if (_cachedTotals.containsKey(cacheKey)) return _cachedTotals[cacheKey]!;

    final list = isShop ? shopReports : beansTransactions;
    final now = DateTime.now();
    
    double calculate(List<Map<String, dynamic>> items) {
      return items.fold(0.0, (sum, s) {
        final amt = s['amount'];
        final val = amt is num ? amt.toDouble() : double.tryParse(amt?.toString() ?? '0') ?? 0.0;
        return sum + val;
      });
    }

    double result = 0.0;
    if (allTime) {
      result = calculate(list.where((s) {
        final isSold = s['type'] == 'sold' || (s['amount'] != null && (s['amount'] as num) > 0);
        return isSold;
      }).toList());
    } else if (monthly) {
      result = calculate(list.where((s) {
        final raw = s['date'] ?? s['generated_at'];
        final d = (raw is DateTime ? raw : DateTime.tryParse(raw?.toString() ?? '') ?? now).toLocal();
        final isSold = s['type'] == 'sold' || (s['amount'] != null && (s['amount'] as num) > 0);
        return isSold && d.month == now.month && d.year == now.year;
      }).toList());
    } else {
      result = calculate(list.where((s) {
        final raw = s['date'] ?? s['generated_at'];
        final d = (raw is DateTime ? raw : DateTime.tryParse(raw?.toString() ?? '') ?? now).toLocal();
        final isSold = s['type'] == 'sold' || (s['amount'] != null && (s['amount'] as num) > 0);
        return isSold && DateUtils.isSameDay(d, now);
      }).toList());
    }
    
    _cachedTotals[cacheKey] = result;
    return result;
  }
  
  static List<Map<String, dynamic>> getTopSellingItems(bool isShop, {int limit = 3}) {
    final transactions = (isShop ? shopReports : beansTransactions)
        .where((t) {
          final isSold = t['type'] == 'sold' || (t['amount'] != null && (t['amount'] as num) > 0);
          return isSold && t['items'] != null;
        })
        .toList();
    
    final Map<String, int> counts = {};
    for (var tx in transactions) {
      final itemList = tx['items'] as List;
      for (var item in itemList) {
        final name = item['name'] as String;
        final qty = (item['qty'] as num).toInt();
        counts[name] = (counts[name] ?? 0) + qty;
      }
    }

    final sortedNames = counts.keys.toList()..sort((a,b) => counts[b]!.compareTo(counts[a]!));
    final topNames = sortedNames.take(limit).toList();
    final totalSold = counts.values.fold(0, (a, b) => a + b);
    
    return topNames.map((name) => {
      'name': name,
      'count': counts[name],
      'percent': totalSold > 0 ? (counts[name]! / totalSold) : 0.0,
    }).toList();
  }
  
  static double getStockAddTotal(bool isShop) {
    double total = 0;
    final now = DateTime.now();
    final movements = isShop ? shopInventory : beansTransactions;
    
    for (var tx in movements) {
      final raw = tx['date'];
      final date = raw is DateTime ? raw : DateTime.tryParse(raw?.toString() ?? '') ?? now;
      if (DateUtils.isSameDay(date, now)) {
        final type = tx['type']?.toString().toLowerCase() ?? '';
        if (type == 'restock' || type == 'in') {
          total += (tx['qty'] as num?)?.toDouble() ?? 0.0;
        }
      }
    }
    return total;
  }

  static double getStockOutTotal(bool isShop) {
    double total = 0;
    final now = DateTime.now();
    final movements = isShop ? [...shopReports, ...shopInventory] : beansTransactions;

    for (var tx in movements) {
      final raw = tx['date'];
      final date = raw is DateTime ? raw : DateTime.tryParse(raw?.toString() ?? '') ?? now;
      if (DateUtils.isSameDay(date, now)) {
        final type = tx['type']?.toString().toLowerCase() ?? '';
        if (type == 'out' || type == 'deduct' || type == 'sold') {
          // Precision sum based on target item name if needed, but here we want the GLOBAL total for the badge
          total += (tx['qty'] as num?)?.toDouble() ?? 0.0;
        }
      }
    }
    return total;
  }
  
  static double getTotalStock(bool isShop) {
    final list = isShop ? shopIngredients : beansInventory;
    final stockKey = isShop ? 'stock' : 'balance_qty';
    return list.fold(0.0, (sum, i) {
      final raw = i[stockKey];
      final val = raw is num ? raw.toDouble() : (double.tryParse(raw?.toString() ?? '0') ?? 0.0);
      return sum + val;
    });
  }

  static List<Map<String, dynamic>> getLowStockItems(bool isShop) {
    final list = isShop ? shopIngredients : beansInventory;
    final stockKey = isShop ? 'stock' : 'balance_qty';
    return list.where((item) {
      final raw = item[stockKey];
      final val = raw is num ? raw.toDouble() : (double.tryParse(raw?.toString() ?? '0') ?? 0.0);
      final init = (item['initial_qty'] as num?)?.toDouble() ?? 1.0;
      return val <= (init * 0.20);
    }).toList();
  }

  static Map<String, dynamic>? getIngredientDaily(Map<String, dynamic> item, bool isShop, {DateTime? date}) {
    final name = item[isShop ? 'name' : 'product_name'] ?? 'Unknown';
    final stockKey = isShop ? 'stock' : 'balance_qty';
    final targetDay = DateTime(date?.year ?? DateTime.now().year, date?.month ?? DateTime.now().month, date?.day ?? DateTime.now().day);
    
    double dayAdd = 0;
    double dayOut = 0;
    double futureDelta = 0;
    
    final now = DateTime.now();
    
    // 🛡️ De-duplicated Log Source: Prevention of overlaps between reports and movement tables
    final Set<String> processedTxIds = {};
    final reports = (isShop ? shopReports : beansTransactions);
    final movements = (isShop ? shopInventory : beansTransactions);
    final allLogs = [...reports, ...movements];

    for (final tx in allLogs) {
      final txId = tx['id']?.toString() ?? '${tx['date']}_${tx['amount']}';
      if (processedTxIds.contains(txId)) continue;
      processedTxIds.add(txId);

      final raw = tx['date'] ?? tx['timestamp'] ?? tx['generated_at'];
      final txDate = raw is DateTime ? raw : DateTime.tryParse(raw?.toString() ?? '') ?? now;
      final txDay = DateTime(txDate.year, txDate.month, txDate.day);

      final type = (tx['type'] ?? tx['action_type'] ?? 'sold').toString().toLowerCase();
      final items = (tx['items'] as List<dynamic>? ?? []);

      // 🛡️ Precision Item Match: Use a single source of truth for tx quantity logic
      double txQty = 0;
      final targetId = tx['target_ingredient_id']?.toString();
      final myId = (item['id'] ?? item['uuid'])?.toString();

      if (isShop && targetId != null && targetId == myId) {
        txQty = (tx['change_qty'] as num?)?.toDouble() ?? 0.0;
      } else if (tx['itemName'] == name) {
        txQty = (tx['qty'] as num?)?.toDouble() ?? 0.0;
      } else {
        for (var i in items) {
          if (i['name'] == name) txQty += (i['qty'] as num?)?.toDouble() ?? 0.0;
        }
      }

      txQty = txQty.abs(); // Absolute magnitude for delta logic
      if (txQty == 0) continue;

      if (txDay.isAfter(targetDay)) {
        // Transactions strictly AFTER our target – these must be stripped from current stock to find target end-balance
        if (type == 'restock' || type == 'in') {
          futureDelta += txQty;
        } else if (type == 'out' || type == 'deduct' || type == 'sold') {
          futureDelta -= txQty;
        }
      } else if (txDay.isAtSameMomentAs(targetDay)) {
        // Transactions EXACTLY on this day – these form the columns for the day
        if (type == 'restock' || type == 'in') {
          dayAdd += txQty;
        } else if (type == 'out' || type == 'deduct' || type == 'sold') {
          dayOut += txQty;
        }
      }
    }

    final currentBalance = (item[stockKey] as num?)?.toDouble() ?? 0.0;
    final endBalance = currentBalance - futureDelta;
    final begBalance = endBalance - dayAdd + dayOut;

    final init = (item['initial_qty'] as num?)?.toDouble() ?? 1.0;
    final isLow = endBalance <= (init * 0.20);

    return {
      'name': name,
      'unit': item['unit'] ?? (isShop ? 'units' : 'pcs'),
      'beg': begBalance.clamp(0.0, double.infinity),
      'add': dayAdd,
      'out': dayOut,
      'end': endBalance.clamp(0.0, double.infinity),
      'status': isLow ? 'low' : 'ok',
    };
  }

  static String fmt(num v) {
    String s = v.toDouble().toStringAsFixed(3);
    if (s.contains('.')) {
      while (s.endsWith('0')) { s = s.substring(0, s.length - 1); }
      if (s.endsWith('.')) { s = s.substring(0, s.length - 1); }
    }
    return s;
  }

  /// Check if the total required ingredients/products are available in inventory for the current cart.
  /// Returns a list of strings describing any shortages found (empty if all OK).
  static List<String> checkStockShortage(bool isShop, List<Map<String, dynamic>> items) {
    final shortages = <String>[];
    final ingredients = isShop ? shopIngredients : beansInventory;
    final products = isShop ? shopProducts : beansProducts;
    final nameKey = isShop ? 'name' : 'product_name';
    final stockKey = isShop ? 'stock' : 'balance_qty';
    
    // Group totals required by inventory product name to handle shared ingredients
    final totalsRequired = <String, double>{};

    for (final soldItem in items) {
      final soldName = soldItem['name']?.toString() ?? '';
      final soldQty  = (soldItem['qty'] as num?)?.toDouble() ?? 1.0;
      final soldSize = soldItem['size']?.toString();

      final productMatches = products.where((p) => p['name'] == soldName);
      if (productMatches.isEmpty) continue;
      final product = productMatches.first;

      List<dynamic> ingList = [];
      if (product['has_sizes'] == true && soldSize != null) {
        final sizeMatches = (product['sizes'] as List).where((s) {
          final sName = s['name']?.toString().toLowerCase().replaceAll(' ', '') ?? '';
          final target = soldSize.toLowerCase().replaceAll(' ', '');
          return sName == target;
        });
        if (sizeMatches.isNotEmpty) ingList = sizeMatches.first['ingredients'] ?? [];
      } else {
        final rawSizes = product['sizes'] as List?;
        ingList = (product['ingredients'] as List?) ?? 
                  ((rawSizes != null && rawSizes.isNotEmpty) ? (rawSizes.first['ingredients'] as List?) ?? [] : []);
      }

      for (final ing in ingList) {
        final ingName = ing['item']?.toString() ?? '';
        final ingQty  = (ing['qty'] as num?)?.toDouble() ?? 0.0;
        final ingUnit = ing['unit']?.toString() ?? '';

        final invMatch = ingredients.where((i) => i[nameKey] == ingName);
        if (invMatch.isEmpty) continue;
        final invItem = invMatch.first;
        final invUnit = invItem['unit']?.toString() ?? '';

        double multiplier = 1.0;
        String rU = ingUnit.toLowerCase().trim();
        String iU = invUnit.toLowerCase().trim();
        
        // Normalize synonyms
        if (rU == 'liter' || rU == 'litre') rU = 'l';
        if (iU == 'liter' || iU == 'litre') iU = 'l';
        if (rU == 'kilogram') rU = 'kg';
        if (iU == 'kilogram') iU = 'kg';
        if (rU == 'gram') rU = 'g';
        if (iU == 'gram') iU = 'g';
        if (rU == 'ounce') rU = 'oz';
        if (iU == 'ounce') iU = 'oz';

        if (rU != iU) {
          // Weight (g, kg, oz, lb)
          if (rU == 'g' && iU == 'kg') { multiplier = 0.001; }
          else if (rU == 'kg' && iU == 'g') { multiplier = 1000.0; }
          else if (rU == 'oz' && iU == 'g') { multiplier = 28.3495; }
          else if (rU == 'g' && iU == 'oz') { multiplier = 0.035274; }
          else if (rU == 'oz' && iU == 'kg') { multiplier = 0.0283495; }
          else if (rU == 'kg' && iU == 'oz') { multiplier = 35.274; }
          else if (rU == 'lb' && iU == 'kg') { multiplier = 0.453592; }
          else if (rU == 'kg' && iU == 'lb') { multiplier = 2.20462; }

          // Volume (ml, l, oz, gal, tsp, tbsp)
          else if (rU == 'ml' && iU == 'l') { multiplier = 0.001; }
          else if (rU == 'l' && iU == 'ml') { multiplier = 1000.0; }
          else if (rU == 'oz' && iU == 'ml') { multiplier = 29.5735; }
          else if (rU == 'ml' && iU == 'oz') { multiplier = 0.033814; }
          else if (rU == 'oz' && iU == 'l') { multiplier = 0.0295735; }
          else if (rU == 'l' && iU == 'oz') { multiplier = 33.814; }
          else if (rU == 'gal' && iU == 'l') { multiplier = 3.78541; }
          else if (rU == 'l' && iU == 'gal') { multiplier = 0.264172; }
          else if (rU == 'tsp' && iU == 'ml') { multiplier = 4.92892; }
          else if (rU == 'tbsp' && iU == 'ml') { multiplier = 14.7868; }
          else if (rU == 'tsp' && iU == 'g') { multiplier = 5.0; } 
          else if (rU == 'tbsp' && iU == 'g') { multiplier = 15.0; } 
        }

        final needed = (ingQty * multiplier) * soldQty;
        totalsRequired[ingName] = (totalsRequired[ingName] ?? 0.0) + needed;
      }
    }

    // Check each requirement against balance
    for (final entry in totalsRequired.entries) {
      final ingName = entry.key;
      final needed = entry.value;

      final invMatch = ingredients.where((i) => i[nameKey] == ingName);
      if (invMatch.isNotEmpty) {
        final balance = (invMatch.first[stockKey] as num).toDouble();
        if (balance < (needed - 0.0001)) { 
          final unit = invMatch.first['unit'] ?? 'units';
          shortages.add('$ingName: Short ${fmt(needed - balance)}$unit');
        }
      }
    }

    return shortages;
  }
}
