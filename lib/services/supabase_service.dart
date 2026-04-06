import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/app_data.dart';

class SupabaseService {
  static Future<void> init() async {
    // Already handled in main.dart via Supabase.initialize
  }

  static Future<bool> pullFromCloud({bool pushFirst = false}) async {
    try {
      final client = Supabase.instance.client;
      debugPrint('Supabase: Initiating Resilient 10-Table Sync Pulse...');

      Future<List<Map<String, dynamic>>> safeGet(String table, {String? orderCol, bool desc = true}) async {
        try {
          // 🛡️ RE-SYNC: Use dynamic to allow chaining Filter and Transform builders
          dynamic query = client.from(table).select();
          if (orderCol != null) query = query.order(orderCol, ascending: !desc);
          final res = await query;
          return _p(res);
        } catch (e) {
          debugPrint('Supabase: Table Sync Bypass ($table) -> $e');
          return [];
        }
      }

      if (pushFirst) {
        debugPrint('Supabase: Performing Safety Push Handshake...');
        for (var item in AppData.beansInventory) { await client.from('beans_inventory').upsert(item); }
        for (var item in AppData.shopIngredients) { await client.from('shop_ingredients').upsert(item); }
      }

      // Individual Resilient Fetches
      final accounts = await safeGet('accounts');
      final sp = await safeGet('shop_products');
      final bp = await safeGet('beans_products');
      final si = await safeGet('shop_ingredients');
      final bi = await safeGet('beans_inventory');
      final sr = await safeGet('shop_reports', orderCol: 'created_at');
      final bt = await safeGet('beans_transactions', orderCol: 'date');
      final bsd = await safeGet('beans_sr_data');
      final invMove = await safeGet('shop_inventory');
      final st = await safeGet('shop_transactions', orderCol: 'created_at');

      // Populate local state safely
      if (accounts.isNotEmpty) { AppData.accounts.clear(); AppData.accounts.addAll(accounts); }
      if (sp.isNotEmpty) { AppData.shopProducts.clear(); AppData.shopProducts.addAll(sp); }
      if (bp.isNotEmpty) { AppData.beansProducts.clear(); AppData.beansProducts.addAll(bp); }
      if (si.isNotEmpty) { AppData.shopIngredients.clear(); AppData.shopIngredients.addAll(si); }
      if (bi.isNotEmpty) { AppData.beansInventory.clear(); AppData.beansInventory.addAll(bi); }
      if (sr.isNotEmpty) { AppData.shopOverall.clear(); AppData.shopOverall.addAll(sr); }
      if (bt.isNotEmpty) { AppData.beansTransactions.clear(); AppData.beansTransactions.addAll(bt); }
      if (bsd.isNotEmpty) { AppData.beansSrData.clear(); AppData.beansSrData.addAll(bsd); }
      if (invMove.isNotEmpty) { AppData.shopInventory.clear(); AppData.shopInventory.addAll(invMove); }
      if (st.isNotEmpty) { AppData.shopReports.clear(); AppData.shopReports.addAll(st); }

      debugPrint('Supabase: 10-Table Resilient Sync COMPLETED.');
      return true;
    } catch (e) {
      debugPrint('Supabase: Global Sync Failure -> $e');
      return false;
    } finally {
      AppData.syncNotifier.value++; 
    }
  }

  /// Helper to convert Supabase raw results into useful Dart maps (parsing dates etc)
  static List<Map<String, dynamic>> _p(dynamic raw) {
    if (raw == null) return [];
    final list = List<Map<String, dynamic>>.from(raw);
    for (var item in list) {
      // Common date columns to parse globally
      for (final key in ['date', 'order_date', 'created_at', 'timestamp', 'generated_at']) {
        if (item.containsKey(key) && item[key] != null && item[key] is String) {
          item[key] = DateTime.tryParse(item[key]);
        }
      }
    }
    return list;
  }

  /// Authentication helper: Fetch a single user account by username
  static Future<Map<String, dynamic>?> authenticate(String username) async {
    try {
      final res = await Supabase.instance.client
          .from('accounts')
          .select()
          .eq('username', username)
          .maybeSingle();

      if (res == null) debugPrint('Supabase Auth: No user found for "$username" (Check RLS policies)');
      return res;
    } catch (e) {
      debugPrint('Supabase Auth Error: $e');
      return null;
    }
  }

  /// Generic insert for any table (useful for auto-generated IDs)
  static Future<void> insert(String table, Map<String, dynamic> data) async {
    try {
      final preparedData = _prep(data);
      debugPrint('Supabase: Attempting insert into $table -> $preparedData');
      await Supabase.instance.client.from(table).insert(preparedData);
      
      // 🛡️ RE-SYNC: Pull latest state to ensure local AppData parity
      await pullFromCloud();
      
      // Force UI notify in case pullFromCloud logic was already identical
      AppData.syncNotifier.value++;
    } catch (e) {
      debugPrint('Supabase: Insert Error ($table): $e');
      rethrow;
    }
  }

  /// Generic update for any table with an ID/Key
  static Future<void> update(String table, Map<String, dynamic> data, dynamic id, {String column = 'id'}) async {
    try {
      final preparedData = _prep(data);
      await Supabase.instance.client.from(table).update(preparedData).eq(column, id);
      await pullFromCloud();
    } catch (e) {
      debugPrint('Update Error ($table): $e');
      rethrow;
    }
  }

  /// Generic upsert for any table
  static Future<void> upsert(String table, Map<String, dynamic> data) async {
    try {
      final preparedData = _prep(data);
      String? conflictTarget;
      if (table == 'beans_inventory') conflictTarget = 'product_name';
      if (table == 'shop_ingredients') conflictTarget = 'name';
      if (table == 'shop_inventory') conflictTarget = 'name';

      if (conflictTarget != null) {
        await Supabase.instance.client.from(table).upsert(preparedData, onConflict: conflictTarget);
      } else {
        await Supabase.instance.client.from(table).upsert(preparedData);
      }
      await pullFromCloud();
    } catch (e) {
      debugPrint('Upsert Error ($table): $e');
      rethrow;
    }
  }

  static dynamic _prep(dynamic data) {
    if (data is DateTime) return data.toIso8601String();
    if (data is List) return data.map((e) => _prep(e)).toList();
    if (data is Map) {
      return data.map((k, v) => MapEntry(k.toString(), _prep(v)));
    }
    return data;
  }

  /// Generic delete for any table
  static Future<void> delete(String table, dynamic id, {String column = 'id'}) async {
    try {
      await Supabase.instance.client.from(table).delete().eq(column, id);
      await pullFromCloud();
    } catch (e) {
      debugPrint('Delete Error ($table): $e');
    }
  }

  /// CRITICAL: Wipes all operational data from the cloud (EXCLUDING ACCOUNTS for safety)
  static Future<void> clearAllCloudData() async {
    try {
      final client = Supabase.instance.client;
      final tables = [
        'shop_products', 'beans_products', 
        'shop_ingredients', 'beans_inventory', 
        'shop_reports', 'beans_transactions',
        'beans_sr_data', 'shop_inventory',
        'shop_transactions'
      ];

      for (var t in tables) {
        await client.from(t).delete().not('id', 'is', null);
      }
      debugPrint('Supabase: Global Wipe Successful');
    } catch (e) {
      debugPrint('Supabase Global Wipe Error: $e');
      rethrow;
    }
  }

  /// RESTORE SYNC: Pushes all current AppData to the cloud (used after local restore)
  static Future<void> pushAllLocalToCloud() async {
    try {
      // 1. CLEAR CLOUD FIRST TO PREVENT PK CONFLICTS
      await clearAllCloudData();
      
      final client = Supabase.instance.client;
      
      // Helper to sanitize data for Supabase (handle IDs and Date formats)
      List<Map<String, dynamic>> clean(List<Map<String, dynamic>> list, {bool keepId = false}) {
        return list.map((m) {
          final copy = Map<String, dynamic>.from(m);
          if (!keepId) copy.remove('id'); // Remove only if we want cloud to autogen (UUID)
          
          // Sanitize nested dates and complex types
          copy.forEach((key, value) {
            if (value is DateTime) {
              copy[key] = value.toIso8601String();
            } else if (value is List) {
              // Deep clone items list to be safe
              copy[key] = value.map((v) => v is Map ? Map<String, dynamic>.from(v) : v).toList();
            }
          });
          return copy;
        }).toList();
      }

      // 2. BATCH INSERT EVERYTHING
      // We keep IDs for transaction tables as they often use custom String PKs (e.g. TX-..., SR-...)
      if (AppData.shopProducts.isNotEmpty) await client.from('shop_products').insert(clean(AppData.shopProducts));
      if (AppData.beansProducts.isNotEmpty) await client.from('beans_products').insert(clean(AppData.beansProducts));
      if (AppData.shopIngredients.isNotEmpty) await client.from('shop_ingredients').insert(clean(AppData.shopIngredients));
      if (AppData.beansInventory.isNotEmpty) await client.from('beans_inventory').insert(clean(AppData.beansInventory));
      if (AppData.beansTransactions.isNotEmpty) await client.from('beans_transactions').insert(clean(AppData.beansTransactions, keepId: true));
      if (AppData.beansSrData.isNotEmpty) await client.from('beans_sr_data').insert(clean(AppData.beansSrData));
      if (AppData.shopInventory.isNotEmpty) await client.from('shop_inventory').insert(clean(AppData.shopInventory));
      
      // 3. SPECIAL DUAL-PUSH FOR SHOP HISTORY & OVERALL REPORTS
      if (AppData.shopReports.isNotEmpty) {
          // A. Push to shop_transactions (Pure History) - KEEP custom TX- IDs
          await client.from('shop_transactions').insert(clean(AppData.shopReports, keepId: true));

          // B. Push to shop_reports (Overall Metadata) - REMOVE ID to allow cloud UUID gen
          final wrapped = AppData.shopReports.map((tx) {
            final rawDate = tx['date'];
            final now = rawDate is DateTime ? rawDate : DateTime.tryParse(rawDate?.toString() ?? '') ?? DateTime.now();
            return {
              'report_type': tx['type'] == 'sold' ? 'sale' : 'inventory_move',
              'target_date': now.toIso8601String().split('T')[0],
              'summary_data': tx,
            };
          }).toList();
          await client.from('shop_reports').insert(wrapped);
      }

      debugPrint('Supabase: Global Cloud Restore Successful');
    } catch (e) {
      debugPrint('Supabase Restore Error: $e');
      rethrow;
    }
  }

  /// Upload a product icon image to Supabase Storage.
  /// [business] is either 'shop' or 'beans' — determines the subfolder.
  /// Returns the public URL on success, or null on failure.
  static Future<String?> uploadProductImage(String business, Uint8List bytes, String fileName) async {
    try {
      final folder = business == 'shop' ? 'shop/icon' : 'beans/icon';
      final safeName = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
      final path = '$folder/$safeName';

      // Explicitly hint content type for Supabase Storage
      final extension = fileName.split('.').last.toLowerCase();
      final contentType = (extension == 'png') ? 'image/png' : (extension == 'webp' ? 'image/webp' : 'image/jpeg');

      debugPrint('Supabase Storage: Attempting upload to bucket "Product" at path "$path" as "$contentType"...');
      await Supabase.instance.client.storage.from('Product').uploadBinary(path, bytes,
          fileOptions: FileOptions(upsert: true, contentType: contentType));

      final publicUrl = Supabase.instance.client.storage.from('Product').getPublicUrl(path);
      debugPrint('Supabase Storage: Upload success! URL: $publicUrl');
      return publicUrl;
    } catch (e) {
      debugPrint('Supabase Storage Upload Error: $e');
      rethrow;
    }
  }

  /// Delete a product icon from storage by its public URL.
  static Future<void> deleteProductImage(String publicUrl) async {
    try {
      debugPrint('Supabase Storage: Attempting deletion for URL -> $publicUrl');
      
      // Robust path extraction: everything after the bucket name "Product/"
      final marker = '/Product/';
      final bucketIdx = publicUrl.indexOf(marker);
      if (bucketIdx == -1) {
         debugPrint('Supabase Storage: Deletion aborted - URL does not contain bucket marker ($marker)');
         return;
      }
      
      final path = publicUrl.substring(bucketIdx + marker.length);
      // Remove any query parameters (like ?t=...)
      final cleanPath = path.contains('?') ? path.split('?').first : path;
      
      debugPrint('Supabase Storage: Extracted path for deletion -> $cleanPath');
      final List<FileObject> removed = await Supabase.instance.client.storage.from('Product').remove([cleanPath]);
      
      if (removed.isNotEmpty) {
        debugPrint('Supabase Storage: Deletion SUCCESS for $cleanPath');
      } else {
        debugPrint('Supabase Storage: No file found or deletion failed for $cleanPath');
      }
    } catch (e) {
      debugPrint('Supabase Storage Delete Error: $e');
    }
  }
}
