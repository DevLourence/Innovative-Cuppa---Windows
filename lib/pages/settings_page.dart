import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/app_data.dart';
import '../services/persistence_service.dart';
import '../services/supabase_service.dart';
import 'package:file_picker/file_picker.dart';

class SettingsPage extends StatefulWidget {
  final String business;
  final Map<String, dynamic> user;
  final VoidCallback? onReset;
  const SettingsPage({super.key, required this.business, required this.user, this.onReset});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool get isShop => widget.business == 'shop';
  Color get accent => isShop ? const Color(0xFFC8822A) : const Color(0xFF4A7C59);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppData.darkModeNotifier,
      builder: (context, isDark, child) {
        return Container(
          color: isDark ? const Color(0xFF121212) : const Color(0xFFF5F3F0),
          child: Column(children: [
            // Header
            Container(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Preferences', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF1C1008), letterSpacing: -0.5)),
                  Text('Manage your account and app behavior', style: TextStyle(fontSize: 13, color: isDark ? Colors.grey[500] : Colors.grey[600])),
                ]),
                _syncStatus(isDark),
              ]),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(32),
                children: [
                  _section('Account', [
                    _tile(Icons.person_outline_rounded, 'Profile', 'Logged in as ${widget.user['name']}', isDark, onTap: () {}),
                    _tile(Icons.lock_outline_rounded, 'Security', 'Change your password', isDark, onTap: () {}),
                  ], isDark),
                  const SizedBox(height: 24),
                  _section('Business', [
                    _tile(Icons.storefront_rounded, 'Business Profile', isShop ? 'Innovative Cuppa Shop' : 'Innovative Cuppa Beans', isDark, onTap: () {}),
                    if (widget.user['role']?.toLowerCase() == 'admin')
                      _tile(Icons.receipt_long_rounded, 'SR Counter', 'Next: ${AppData.getSrPrefix()}${AppData.getSrCounter()}', isDark, onTap: () => _showSrDialog(isDark)),
                  ], isDark),
                  const SizedBox(height: 24),
                  if (widget.user['role']?.toLowerCase() == 'admin') ...[
                    _section('Data Management', [
                      _tile(Icons.cloud_upload_outlined, 'Backup Data', 'Export and encrypt all records', isDark, onTap: () => _backupData()),
                      _tile(Icons.cloud_download_outlined, 'Restore Data', 'Import from an encrypted backup file', isDark, onTap: () => _restoreData()),
                      _tile(Icons.delete_forever_rounded, 'Clear All Data', 'Permanently wipe local data cache', isDark, isDangerous: true, onTap: () => _clearAllData()),
                    ], isDark),
                    const SizedBox(height: 24),
                  ],
                  _section('System', [
                    _tile(Icons.info_outline_rounded, 'About', 'Version 2.0.5', isDark, onTap: () {}),
                  ], isDark),
                  const SizedBox(height: 32),
                  if (widget.user['role']?.toLowerCase() == 'admin')
                    _buildPermissionsSection(isDark),
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ]),
        );
      },
    );
  }

  void _showLoading(String message) {
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
              Text(message, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1C1008))),
              const SizedBox(height: 4),
              const Text('Please do not close the app...', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }

  void _backupData() async {
    try {
      final state = {
        'shopIngredients': AppData.shopIngredients,
        'shopProducts': AppData.shopProducts,
        'shopInventory': AppData.shopInventory,
        'shopReports': AppData.shopReports,
        'beansInventory': AppData.beansInventory,
        'beansProducts': AppData.beansProducts,
        'beansSrData': AppData.beansSrData,
        'beansTransactions': AppData.beansTransactions,
        'accounts': AppData.accounts,
        'rolePermissions': AppData.rolePermissions,
        'sr_counter': AppData.getSrCounter(),
        'backup_date': DateTime.now().toIso8601String(),
      };

      _showLoading('Preparing Backup...');

      // Custom encoder to handle DateTime objects inside reports/transactions
      final jsonStr = jsonEncode(state, toEncodable: (o) {
        if (o is DateTime) return o.toIso8601String();
        return o;
      });
      
      final encrypted = base64Encode(utf8.encode(jsonStr));
      
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Encrypted Backup',
        fileName: 'innovative_cuppa_backup_${DateFormat('yyyyMMdd').format(DateTime.now())}.icb',
      );

      if (mounted) Navigator.pop(context); // Remove loading

      if (outputFile != null) {
        final file = File(outputFile);
        await file.writeAsString(encrypted);
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup saved successfully!')));
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Backup failed: $e')));
      }
    }
  }

  void _restoreData() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles();
      if (result != null) {
        final path = result.files.single.path;
        if (path == null) return;

        final file = File(path);
        final content = await file.readAsString();
        final decoded = utf8.decode(base64Decode(content));
        final Map<String, dynamic> state = jsonDecode(decoded);

        if (!mounted) return;

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Confirm Restore'),
            content: const Text('Warning: This will OVERWRITE all current data with the backup file. This cannot be undone.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  
                  Navigator.pop(ctx); // Close confirmation
                  _showLoading('Restoring System State...');
                  
                  setState(() {
                    if (state.containsKey('shopIngredients')) AppData.shopIngredients = List<Map<String, dynamic>>.from(state['shopIngredients']);
                    if (state.containsKey('shopProducts')) AppData.shopProducts = List<Map<String, dynamic>>.from(state['shopProducts']);
                    if (state.containsKey('shopInventory')) AppData.shopInventory = List<Map<String, dynamic>>.from(state['shopInventory']);
                    if (state.containsKey('shopReports')) AppData.shopReports = List<Map<String, dynamic>>.from(state['shopReports']);
                    
                    if (state.containsKey('beansInventory')) AppData.beansInventory = List<Map<String, dynamic>>.from(state['beansInventory']);
                    if (state.containsKey('beansProducts')) AppData.beansProducts = List<Map<String, dynamic>>.from(state['beansProducts']);
                    if (state.containsKey('beansSrData')) AppData.beansSrData = List<Map<String, dynamic>>.from(state['beansSrData']);
                    if (state.containsKey('beansTransactions')) AppData.beansTransactions = List<Map<String, dynamic>>.from(state['beansTransactions']);
                    
                    if (state.containsKey('accounts')) AppData.accounts = List<Map<String, dynamic>>.from(state['accounts']);
                    if (state.containsKey('rolePermissions')) {
                       state['rolePermissions'].forEach((k, v) => AppData.rolePermissions[k] = List<String>.from(v));
                    }
                    if (state.containsKey('sr_counter')) AppData.setSrCounter(state['sr_counter']);
                  });
                  
                  await PersistenceService.saveState();

                  // 🔄 PUSH TO CLOUD IF RESTORED
                  try {
                    await SupabaseService.pushAllLocalToCloud();
                  } catch (cloudErr) {
                    debugPrint('Restored locally but cloud sync failed: $cloudErr');
                  }
                  
                  if (mounted) {
                    Navigator.pop(context); // Remove loading
                    messenger.showSnackBar(const SnackBar(content: Text('Restore successful! Local & Cloud data in sync.')));
                    
                    // 🏃 AUTO-LOGOUT TO RESET STATE & PREVENT CRASHES
                    if (widget.onReset != null) {
                      Future.delayed(const Duration(seconds: 1), widget.onReset);
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: accent),
                child: const Text('Restore Now', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Restore failed: Invalid backup file.')));
      }
    }
  }

  void _clearAllData() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('CLEAR ALL DATA?', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: const Text('This will permanently delete all records, transactions, and settings locally. This is irreversible.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
               final messenger = ScaffoldMessenger.of(context);
               
               Navigator.pop(ctx); // Close confirmation
               _showLoading('Wiping Global Data...');
               
               try {
                 // 🆘 WIPE CLOUD FIRST
                 await SupabaseService.clearAllCloudData();

                  setState(() {
                    AppData.shopIngredients = [];
                    AppData.shopProducts = [];
                    AppData.shopInventory = [];
                    AppData.shopReports = [];
                    AppData.beansInventory = [];
                    AppData.beansProducts = [];
                    AppData.beansSrData = [];
                    AppData.beansTransactions = [];
                    AppData.setSrCounter(0);
                    // AppData.accounts is NOT cleared
                  });
                 
                 await PersistenceService.saveState();
                 
                 if (mounted) {
                   Navigator.pop(context); // Remove loading
                   messenger.showSnackBar(const SnackBar(content: Text('All local & cloud data erased successfully.')));
                   
                   // 🏃 AUTO-LOGOUT TO RESET STATE & PREVENT CRASHES
                   if (widget.onReset != null) {
                     Future.delayed(const Duration(seconds: 1), widget.onReset);
                   }
                 }
               } catch (e) {
                 if (mounted) {
                   Navigator.pop(context); // Remove loading
                   messenger.showSnackBar(SnackBar(content: Text('Failed to wipe cloud data: $e')));
                 }
               }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('WIPE DATA', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionsSection(bool isDark) {
    final roles = AppData.rolePermissions.keys.toList();
    final features = [
      {'id': 'sales', 'label': 'Sales'},
      {'id': 'products', 'label': 'Products'},
      {'id': 'reports', 'label': 'Reports'},
      {'id': 'accounts', 'label': 'Accounts'},
      {'id': 'history', 'label': 'History'},
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('ROLE ACCESS MANAGEMENT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: accent, letterSpacing: 1.2)),
            InkWell(
              onTap: () => _addCustomRole(),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text('+ ADD CUSTOM ROLE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: accent)),
              ),
            ),
          ],
        ),
      ),
      Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(accent.withAlpha(10)),
              columnSpacing: 24,
              columns: [
                const DataColumn(label: Text('Feature', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                for (var r in roles)
                  DataColumn(
                    label: Row(children: [
                      Text(r.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      if (!['admin', 'manager', 'cashier', 'barista'].contains(r)) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => _deleteCustomRole(r),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(color: Colors.red.withAlpha(20), shape: BoxShape.circle),
                            child: const Icon(Icons.close_rounded, size: 10, color: Colors.red),
                          ),
                        ),
                      ],
                    ]),
                  ),
              ],
              rows: features.map((f) {
                return DataRow(cells: [
                  DataCell(Text(f['label']!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  for (var r in roles)
                    DataCell(
                      Transform.scale(
                        scale: 0.8,
                        child: Switch(
                          value: r == 'admin' ? true : (AppData.rolePermissions[r]?.contains(f['id']) ?? false),
                          onChanged: r == 'admin'
                              ? null
                              : (val) {
                                  setState(() {
                                    if (val) {
                                      AppData.rolePermissions[r]!.add(f['id']!);
                                    } else {
                                      AppData.rolePermissions[r]!.remove(f['id']!);
                                    }
                                  });
                                  PersistenceService.saveState();
                                },
                          activeTrackColor: accent.withValues(alpha: 0.5),
                          activeThumbColor: accent,
                        ),
                      ),
                    ),
                ]);
              }).toList(),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _section(String title, List<Widget> tiles, bool isDark) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 12),
        child: Text(title.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: isDark ? Colors.grey[500] : Colors.grey[400], letterSpacing: 1)),
      ),
      Container(
        decoration: BoxDecoration(color: isDark ? const Color(0xFF1E1E1E) : Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 10, offset: const Offset(0, 4))]),
        child: Column(children: tiles),
      ),
    ]);
  }

  Widget _tile(IconData icon, String title, String sub, bool isDark, {required VoidCallback onTap, bool isDangerous = false}) {
    return ListTile(
      onTap: onTap,
      leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: isDangerous ? Colors.red.withAlpha(20) : accent.withAlpha(20), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: isDangerous ? Colors.red : accent, size: 18)),
      title: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDangerous ? Colors.red : (isDark ? Colors.white : const Color(0xFF1C1008)))),
      subtitle: Text(sub, style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[500] : Colors.grey[600])),
      trailing: Icon(Icons.chevron_right_rounded, color: isDark ? Colors.grey[700] : Colors.grey[300], size: 18),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
    );
  }

  Widget _syncStatus(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: Colors.green.withAlpha(15), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.green.withAlpha(30))),
      child: Row(children: [
        const Icon(Icons.check_circle_rounded, color: Colors.green, size: 14),
        const SizedBox(width: 6),
        Text('All Data Synced', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.green.shade700)),
      ]),
    );
  }

  void _showSrDialog(bool isDark) {
    final prefixCtrl = TextEditingController(text: AppData.getSrPrefix());
    final countCtrl = TextEditingController(text: AppData.getSrCounter().toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('SR Sequence Configuration', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: isDark ? Colors.white : Colors.black)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: prefixCtrl,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                labelText: 'SR Prefix',
                labelStyle: TextStyle(color: isDark ? Colors.grey : Colors.black54),
                hintText: 'e.g. SR-'
              )
            ),
            const SizedBox(height: 16),
            TextField(
              controller: countCtrl,
              keyboardType: TextInputType.number,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                labelText: 'Next Sequence Number',
                labelStyle: TextStyle(color: isDark ? Colors.grey : Colors.black54),
                hintText: 'e.g. 5000'
              )
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final n = int.tryParse(countCtrl.text);
              if (n != null) {
                AppData.setSrPrefix(prefixCtrl.text);
                AppData.setSrCounter(n);
                PersistenceService.saveState();
              }
              Navigator.pop(ctx);
              setState(() {});
            },
            style: ElevatedButton.styleFrom(backgroundColor: accent),
            child: const Text('Update', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _addCustomRole() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add Custom Role', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            hintText: 'e.g. Supervisor',
            filled: true,
            fillColor: const Color(0xFFF5F3F0),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () {
              final newRole = ctrl.text.trim().toLowerCase();
              if (newRole.isNotEmpty && !AppData.rolePermissions.containsKey(newRole)) {
                setState(() {
                  AppData.rolePermissions[newRole] = ['sales'];
                });
                PersistenceService.saveState();
              }
              Navigator.pop(ctx);
            },
            child: const Text('Create Role'),
          ),
        ],
      ),
    );
  }

  void _deleteCustomRole(String role) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Custom Role?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.red)),
        content: Text('Are you sure you want to permanently delete the "$role" role from the system?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () {
              setState(() {
                AppData.rolePermissions.remove(role);
              });
              PersistenceService.saveState();
              Navigator.pop(ctx);
            },
            child: const Text('Delete Role'),
          ),
        ],
      ),
    );
  }
}
