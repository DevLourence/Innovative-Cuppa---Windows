import 'package:flutter/material.dart';
import '../data/app_data.dart';
import '../services/supabase_service.dart';
import '../services/persistence_service.dart';

class AccountsPage extends StatefulWidget {
  final String business;
  const AccountsPage({super.key, required this.business});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  Color get accent => widget.business == 'shop' ? const Color(0xFFC8822A) : const Color(0xFF4A7C59);
  final Color _bg = const Color(0xFFF5F3F0);
  final Color _dark = const Color(0xFF1C1008);

  void _showAccountDialog({Map<String, dynamic>? account}) {
    final bool isEdit = account != null;
    final nameCtrl = TextEditingController(text: isEdit ? account['name'] : '');
    final usernameCtrl = TextEditingController(text: isEdit ? account['username'] : '');
    final passwordCtrl = TextEditingController(text: isEdit ? account['password'] : '');
    String selectedRole = isEdit ? account['role'] : 'Barista';
    bool isActive = isEdit ? (account['is_active'] ?? true) : true;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isEdit ? 'Update Account' : 'Create New Account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _dark)),
          const SizedBox(height: 4),
          Text(isEdit ? 'Modify user permissions' : 'Set up a new staff member', style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w500)),
        ]),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 12),
              _formField(nameCtrl, 'Full Name', Icons.person_outline_rounded),
              const SizedBox(height: 16),
              _formField(usernameCtrl, 'Username', Icons.alternate_email_rounded),
              const SizedBox(height: 16),
              _formField(passwordCtrl, 'Private Password', Icons.lock_outline_rounded, obscure: true),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey(selectedRole),
                initialValue: AppData.rolePermissions.keys.map((e) => e.toLowerCase()).contains(selectedRole.toLowerCase()) ? (selectedRole[0].toUpperCase() + selectedRole.substring(1).toLowerCase()) : 'Barista',
                decoration: _inputDeco('Access Role', Icons.shield_outlined),
                items: [
                  ...AppData.rolePermissions.keys
                      .map((r) => r[0].toUpperCase() + r.substring(1).toLowerCase())
                      .map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)))),
                  const DropdownMenuItem(value: '+add_role', child: Row(children: [Icon(Icons.add_rounded, size: 16, color: Colors.blue), SizedBox(width: 8), Text('Add Custom Role', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.blue))])),
                ],
                onChanged: isSaving ? null : (val) {
                  if (val == '+add_role') {
                    final newRoleCtrl = TextEditingController();
                    showDialog(
                      context: ctx,
                      builder: (innerCtx) => AlertDialog(
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        title: const Text('New Custom Role', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        content: TextField(
                          controller: newRoleCtrl,
                          decoration: InputDecoration(
                            hintText: 'e.g. Supervisor',
                            filled: true,
                            fillColor: const Color(0xFFF5F3F0),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          ),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(innerCtx), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                            onPressed: () {
                              final newRoleStr = newRoleCtrl.text.trim().toLowerCase();
                              if (newRoleStr.isNotEmpty && !AppData.rolePermissions.containsKey(newRoleStr)) {
                                AppData.rolePermissions[newRoleStr] = ['sales'];
                                PersistenceService.saveState();
                                setDlg(() {
                                  selectedRole = newRoleStr[0].toUpperCase() + newRoleStr.substring(1).toLowerCase();
                                });
                              }
                              Navigator.pop(innerCtx);
                            },
                            child: const Text('Create Role'),
                          ),
                        ],
                      ),
                    );
                  } else if (val != null) {
                    setDlg(() => selectedRole = val);
                  }
                },
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(12)),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Account Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    Text(isActive ? 'Can access system' : 'Access denied', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                  ]),
                  Switch(value: isActive, onChanged: isSaving ? null : (v) => setDlg(() => isActive = v), activeThumbColor: accent),
                ]),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: isSaving ? null : () => Navigator.pop(ctx), child: Text('Discard', style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w700))),
          ElevatedButton(
            onPressed: isSaving ? null : () async {
              final name = nameCtrl.text.trim();
              final username = usernameCtrl.text.trim();
              if (name.isEmpty || username.isEmpty || passwordCtrl.text.isEmpty) return;
              
              setDlg(() => isSaving = true);

              final accountData = {
                if (isEdit) 'id': account['id'],
                'name': name,
                'username': username,
                'password': passwordCtrl.text,
                'role': selectedRole,
                'is_active': isActive,
              };

              try {
                await SupabaseService.upsert('accounts', accountData);
                await SupabaseService.pullFromCloud();
                
                if (!ctx.mounted) return;
                setState(() {});
                Navigator.pop(ctx);
                
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Account ${isEdit ? 'updated' : 'created'} successfully!'),
                    backgroundColor: Colors.green,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              } catch (e) {
                setDlg(() => isSaving = false);
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0),
            child: isSaving 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Confirm', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          ),
        ],
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    int activeCount = AppData.accounts.where((a) => a['is_active'] == true).length;
    int adminCount = AppData.accounts.where((a) => a['role'] == 'Admin').length;

    return Container(
      color: _bg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Premium Header
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('ACCESS CONTROL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 2)),
              Text('User Accounts', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: _dark, letterSpacing: -0.5)),
            ]),
            ElevatedButton.icon(
              onPressed: () => _showAccountDialog(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add User'),
              style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
            ),
          ]),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Summary Cards
              Row(children: [
                Expanded(child: _statCard('Total Members', '${AppData.accounts.length}', Icons.people_outline_rounded, accent)),
                const SizedBox(width: 20),
                Expanded(child: _statCard('Active Now', '$activeCount', Icons.verified_user_outlined, Colors.green)),
                const SizedBox(width: 20),
                Expanded(child: _statCard('Administrators', '$adminCount', Icons.admin_panel_settings_outlined, Colors.indigo)),
              ]),

              const SizedBox(height: 32),

              // Spreadsheet Style Surface
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFEEECEC)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 20, offset: const Offset(0, 10))]),
                child: Column(children: [
                  // Table Header
                  Container(
                    height: 54,
                    color: const Color(0xFFF9F8F6),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(children: [
                      _th('Member Identification', flex: 4),
                      _th('Designated Role', flex: 2),
                      _th('Login Status', flex: 2),
                      const SizedBox(width: 60), // Actions width
                    ]),
                  ),
                  // List
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: AppData.accounts.length,
                    separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFEEECEC), indent: 24, endIndent: 24),
                    itemBuilder: (context, i) {
                      final a = AppData.accounts[i];
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        child: Row(children: [
                          Expanded(flex: 4, child: Row(children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: accent.withValues(alpha: 0.1),
                              child: Text(a['name'][0].toUpperCase(), style: TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: 13)),
                            ),
                            const SizedBox(width: 16),
                            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(a['name'], style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _dark)),
                              Text('@${a['username']}', style: TextStyle(fontSize: 11, color: Colors.grey[500], fontWeight: FontWeight.w600)),
                            ]),
                          ])),
                          Expanded(flex: 2, child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            width: 100,
                            decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(8)),
                            child: Text(a['role'].toString().toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.grey[700])),
                          )),
                          Expanded(flex: 2, child: Row(children: [
                            Container(width: 8, height: 8, decoration: BoxDecoration(color: (a['is_active'] == true) ? Colors.green : Colors.grey[300], shape: BoxShape.circle)),
                            const SizedBox(width: 10),
                            Text((a['is_active'] == true) ? 'ACTIVE' : 'LOCKED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: (a['is_active'] == true) ? Colors.green : Colors.grey[400])),
                          ])),
                          PopupMenuButton(
                            padding: EdgeInsets.zero,
                            surfaceTintColor: Colors.white,
                            icon: const Icon(Icons.more_vert_rounded, size: 20, color: Colors.grey),
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                onTap: () => Future.delayed(Duration.zero, () => _showAccountDialog(account: a)),
                                child: const Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 12), Text('Edit Details', style: TextStyle(fontSize: 13))]),
                              ),
                              PopupMenuItem(
                                onTap: () async {
                                  await SupabaseService.delete('accounts', a['id']);
                                  await SupabaseService.pullFromCloud();
                                  if (mounted) setState(() {});
                                },
                                child: const Row(children: [Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red), SizedBox(width: 12), Text('Remove User', style: TextStyle(fontSize: 13, color: Colors.red, fontWeight: FontWeight.w600))]),
                              ),
                            ],
                          ),
                        ]),
                      );
                    },
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFEEECEC))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 16),
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.grey[500], letterSpacing: 1)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: _dark)),
      ]),
    );
  }

  Widget _th(String label, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(label.toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.5)),
    );
  }

  Widget _formField(TextEditingController ctrl, String label, IconData icon, {bool obscure = false}) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      decoration: _inputDeco(label, icon),
    );
  }

  InputDecoration _inputDeco(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, size: 18),
    labelStyle: TextStyle(fontSize: 13, color: Colors.grey[500], fontWeight: FontWeight.w500),
    filled: true,
    fillColor: Colors.white,
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E2DD))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: accent, width: 2)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  );
}
