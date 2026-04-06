import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import '../data/app_data.dart';

class PersistenceService {
  static const String _fileName = 'app_state.json';

  static Future<String> get _localPath async {
    final directory = await getApplicationSupportDirectory();
    return directory.path;
  }

  static Future<File> get _localFile async {
    final path = await _localPath;
    return File('$path/$_fileName');
  }

  /// Saves app state using a background isolate for heavy JSON processing to prevent UI hangs.
  static Future<void> saveState() async {
    try {
      final file = await _localFile;
      
      final Map<String, dynamic> state = {
        'shopIngredients': _prepareForSave(AppData.shopIngredients),
        'beansInventory': _prepareForSave(AppData.beansInventory),
        'shopReports': _prepareForSave(AppData.shopReports),
        'beansTransactions': _prepareForSave(AppData.beansTransactions),
        'accounts': _prepareForSave(AppData.accounts),
        'rolePermissions': AppData.rolePermissions,
        'srCounter': AppData.getSrCounter(),
        'srPrefix': AppData.getSrPrefix(),
      };

      // Offload heavy JSON stringification to a background thread to keep UI fluid
      final jsonString = await compute(jsonEncode, state);
      await file.writeAsString(jsonString);
      
      debugPrint('State saved to ${file.path}');
    } catch (e) {
      debugPrint('Error saving state: $e');
    }
  }

  static dynamic _prepareForSave(dynamic data) {
    if (data is DateTime) return data.toIso8601String();
    if (data is List) return data.map((e) => _prepareForSave(e)).toList();
    if (data is Map) {
      return data.map((k, v) => MapEntry(k.toString(), _prepareForSave(v)));
    }
    return data;
  }

  /// Loads app state using a background isolate for heavy JSON parsing.
  static Future<void> loadState() async {
    try {
      final file = await _localFile;
      if (!await file.exists()) return;

      final contents = await file.readAsString();
      
      // Offload heavy JSON parsing to a background isolate
      final decoded = await compute(jsonDecode, contents);
      final state = _processLoaded(decoded) as Map<String, dynamic>;

      if (state['shopIngredients'] != null) {
        AppData.shopIngredients = List<Map<String, dynamic>>.from(state['shopIngredients']);
      }
      if (state['beansInventory'] != null) {
        AppData.beansInventory = List<Map<String, dynamic>>.from(state['beansInventory']);
      }
      if (state['shopReports'] != null) {
        AppData.shopReports = List<Map<String, dynamic>>.from(state['shopReports']);
      }
      if (state['beansTransactions'] != null) {
        AppData.beansTransactions = List<Map<String, dynamic>>.from(state['beansTransactions']);
      }
      if (state['accounts'] != null) {
        AppData.accounts = List<Map<String, dynamic>>.from(state['accounts']);
      }
      if (state['srCounter'] != null) {
        AppData.setSrCounter(state['srCounter']);
      }
      if (state['srPrefix'] != null) {
        AppData.setSrPrefix(state['srPrefix']);
      }
      if (state['rolePermissions'] != null) {
        AppData.rolePermissions.clear();
        (state['rolePermissions'] as Map<String, dynamic>).forEach((k, v) {
          AppData.rolePermissions[k] = List<String>.from(v);
        });
      }

      debugPrint('State loaded from ${file.path}');
    } catch (e) {
      debugPrint('Error loading state: $e');
    }
  }

  static dynamic _processLoaded(dynamic data) {
    if (data is String) {
      if (data.length >= 19 && data.contains('T')) {
        return DateTime.tryParse(data) ?? data;
      }
      return data;
    }
    if (data is List) return data.map((e) => _processLoaded(e)).toList();
    if (data is Map) {
      final sanitized = <String, dynamic>{};
      data.forEach((k, v) {
        String key = k.toString();
        // Sanitize old keys coming from local file
        if (key == 'outToday') key = 'out_today';
        if (key == 'addedToday') key = 'added_today';
        sanitized[key] = _processLoaded(v);
      });
      return sanitized;
    }
    return data;
  }
}
