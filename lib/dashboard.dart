import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'data/app_data.dart';

import 'pages/products_page.dart';
import 'pages/sales_page.dart';
import 'pages/reports_page.dart';
import 'pages/accounts_page.dart';
import 'pages/history_page.dart';
import 'pages/settings_page.dart';

class DashboardPage extends StatefulWidget {
  final Map<String, dynamic> user;
  final VoidCallback onLogout;
  const DashboardPage({super.key, required this.user, required this.onLogout});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String _selectedBusiness = 'shop';
  int _selectedIndex    = 0;
  bool _isSettingsSelected = false;

  static const _shopNav = [
    _NavItem('sales',     Icons.point_of_sale_rounded,      'Sales'),
    _NavItem('products',  Icons.local_cafe_rounded,          'Products'),
    _NavItem('reports',   Icons.bar_chart_rounded,           'Reports'),
    _NavItem('accounts',  Icons.manage_accounts_rounded,     'Accounts'),
    _NavItem('history',   Icons.history_rounded,             'History'),
  ];

  static const _beansNav = [
    _NavItem('sales',     Icons.payments_rounded,            'Sales'),
    _NavItem('products',  Icons.grain_rounded,               'Products'),
    _NavItem('reports',   Icons.bar_chart_rounded,           'Reports'),
    _NavItem('accounts',  Icons.manage_accounts_rounded,     'Accounts'),
    _NavItem('history',   Icons.history_rounded,             'History'),
  ];

  List<_NavItem> get _currentNav {
    final nav = _selectedBusiness == 'shop' ? _shopNav : _beansNav;
    final role = widget.user['role']?.toLowerCase() ?? 'barista';
    final allowedIds = AppData.rolePermissions[role] ?? ['sales'];
    return nav.where((item) => allowedIds.contains(item.id)).toList();
  }

  Widget _buildPage() {
    if (_isSettingsSelected) return SettingsPage(business: _selectedBusiness, user: widget.user, onReset: widget.onLogout);
    
    final nav = _currentNav;
    if (nav.isEmpty) return const _ComingSoonPage(title: 'No Access');
    
    // Safety check for index out of bounds
    final index = _selectedIndex >= nav.length ? 0 : _selectedIndex;
    final item = nav[index];
    
    switch (item.id) {
      case 'sales':     return SalesPage(business: _selectedBusiness, user: widget.user);
      case 'products':  return ProductsPage(business: _selectedBusiness, user: widget.user);
      case 'inventory': return ProductsPage(business: _selectedBusiness, user: widget.user);
      case 'reports':   return ReportsPage(business: _selectedBusiness, user: widget.user);
      case 'accounts':  return AccountsPage(business: _selectedBusiness);
      case 'history':   return HistoryPage(business: _selectedBusiness, user: widget.user);
      default:          return _ComingSoonPage(title: item.label);
    }
  }

  void _switchBusiness(String biz) {
    setState(() { _selectedBusiness = biz; _selectedIndex = 0; });
  }

  @override
  Widget build(BuildContext context) {
    final isShop = _selectedBusiness == 'shop';
    final accent = isShop ? const Color(0xFFC8822A) : const Color(0xFF4A7C59);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F3F0),
      body: Row(children: [
        // ── Sidebar ──────────────────────────────────────────────────────
        ValueListenableBuilder<int>(
          valueListenable: AppData.syncNotifier,
          builder: (context, _, child) {
            return Container(
              width: 264,
              color: const Color(0xFF1C1008),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 48),
                // Brand
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: accent.withAlpha(30), borderRadius: BorderRadius.circular(10)),
                      child: Center(child: Image.asset('assets/logo_master.png', width: 22, height: 22, fit: BoxFit.contain, cacheWidth: 44, cacheHeight: 44)),
                    ),
                    const SizedBox(width: 12),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Innovative', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.3, height: 1.1)),
                      Text('CUPPA', style: TextStyle(color: accent.withAlpha(180), fontSize: 9, letterSpacing: 2.5, fontWeight: FontWeight.w600)),
                    ]),
                  ]),
                ),
                const SizedBox(height: 40),
                // Business Switcher
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    _bizTab('Shop',  'shop',  Icons.store_rounded,  accent),
                    const SizedBox(width: 4),
                    _bizTab('Beans', 'beans', Icons.grain_rounded, accent),
                  ]),
                ),
                const SizedBox(height: 36),
                Padding(
                  padding: const EdgeInsets.only(left: 24, bottom: 8),
                  child: Text(isShop ? 'SHOP' : 'BEANS', style: TextStyle(color: Colors.white.withAlpha(35), fontSize: 9, letterSpacing: 2.2, fontWeight: FontWeight.w700)),
                ),
                Expanded(
                  child: ValueListenableBuilder<List<int>>(
                    valueListenable: AppData.lowStockNotifier,
                    builder: (_, lowCounts, _) => ListView(
                      padding: EdgeInsets.zero,
                      children: List.generate(_currentNav.length, (i) => _navTile(i, accent, lowCounts)),
                    ),
                  ),
                ),
                Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8), color: Colors.white.withAlpha(10)),
                _bottomTile(Icons.tune_rounded, 'Settings', selected: _isSettingsSelected, accent: accent, onTap: () => setState(() => _isSettingsSelected = true)),
                _bottomTile(Icons.logout_rounded, 'Sign Out', onTap: widget.onLogout, color: Colors.redAccent.withAlpha(160)),
                const SizedBox(height: 32),
              ]),
            );
          },
        ),
        // ── Main Content ────────────────────────────────────────────────
        Expanded(
          child: Column(children: [
            // Top bar (Static logic move)
            Container(
              height: 60,
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Row(children: [
                Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_isSettingsSelected ? 'Settings' : (_currentNav.isNotEmpty ? _currentNav[_selectedIndex].label : ''), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1C1008))),
                  Text(isShop ? 'Coffee Shop' : 'Beans Business', style: TextStyle(fontSize: 11, color: accent, fontWeight: FontWeight.w600)),
                ]),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFFF5F3F0), borderRadius: BorderRadius.circular(20)),
                  child: Row(children: [
                    CircleAvatar(radius: 13, backgroundColor: accent.withAlpha(20), child: Icon(Icons.person_rounded, color: accent, size: 15)),
                    const SizedBox(width: 8),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.user['name'] ?? 'User', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1C1008))),
                      Text(widget.user['role']?.toUpperCase() ?? '', style: TextStyle(fontSize: 9, color: accent, fontWeight: FontWeight.w700)),
                    ]),
                  ]),
                ),
              ]),
            ),
            // Header Stats Visual (Isolated Listener)
            _WeeklySalesStrip(isShop: isShop, accent: accent),
            // Page content (Preserved Page Instance via buildPage)
            Expanded(child: _buildPage()),
          ]),
        ),
      ]),
    );
  }

  Widget _bizTab(String label, String key, IconData icon, Color accent) {
    final selected = _selectedBusiness == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => _switchBusiness(key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? accent.withAlpha(22) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 14, color: selected ? accent : Colors.white.withAlpha(50)),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(
                color: selected ? Colors.white : Colors.white.withAlpha(50),
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                fontSize: 13,
              )),
            ]),
            const SizedBox(height: 5),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 2, width: selected ? 24 : 0,
              decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _navTile(int index, Color accent, [List<int> lowCounts = const [0, 0]]) {
    final item = _currentNav[index];
    final selected = _selectedIndex == index && !_isSettingsSelected;
    final isShop = _selectedBusiness == 'shop';
    final lowCount = item.id == 'inventory' ? (isShop ? lowCounts[0] : lowCounts[1]) : 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: InkWell(
        onTap: () => setState(() { _selectedIndex = index; _isSettingsSelected = false; }),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? Colors.white.withAlpha(12) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Icon(item.icon, color: selected ? accent : Colors.white.withAlpha(70), size: 18),
            const SizedBox(width: 12),
            Expanded(child: Text(item.label, style: TextStyle(
              color: selected ? Colors.white : Colors.white.withAlpha(70),
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              fontSize: 13,
            ))),
            if (lowCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.red.shade600, borderRadius: BorderRadius.circular(8)),
                child: Text('$lowCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _bottomTile(IconData icon, String label, {
    required VoidCallback onTap,
    bool selected = false,
    Color? accent,
    Color? color,
  }) {
    final c = color ?? (selected ? Colors.white : Colors.white.withAlpha(60));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? Colors.white.withAlpha(12) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Icon(icon, color: selected ? (accent ?? Colors.white) : c, size: 18),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(color: selected ? Colors.white : c, fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
          ]),
        ),
      ),
    );
  }
}

class _NavItem {
  final String id;
  final IconData icon;
  final String label;
  const _NavItem(this.id, this.icon, this.label);
}

class _ComingSoonPage extends StatelessWidget {
  final String title;
  const _ComingSoonPage({required this.title});
  @override
  Widget build(BuildContext context) {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.construction_rounded, size: 48, color: Colors.grey[200]),
      const SizedBox(height: 16),
      Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Color(0xFF2D1B0E))),
      const SizedBox(height: 6),
      Text('Coming soon', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
    ]));
  }
}

// ─── Weekly Sales Strip ───────────────────────────────────────────────────────
class _WeeklySalesStrip extends StatelessWidget {
  final bool isShop;
  final Color accent;
  const _WeeklySalesStrip({required this.isShop, required this.accent});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppData.syncNotifier,
      builder: (context, _, child) {
        final now = DateTime.now();
        final transactions = isShop ? AppData.shopReports : AppData.beansTransactions;
        final Map<int, double> dayTotals = {};
        
        // 🛡️ High-Performance Scan: Compute only for the 7-day window PROFESSIONALLY
        for (int d = 6; d >= 0; d--) {
          final day = now.subtract(Duration(days: d));
          dayTotals[day.day] = 0.0;
        }

        // Single linear scan of history for O(n) parity
        for (final t in transactions) {
          if (t['type'] != 'sold' && t['amount'] == null) continue;
          final rawDate = t['date'] ?? t['generated_at'];
          if (rawDate == null) continue;
          final DateTime td = (rawDate is DateTime ? rawDate : DateTime.tryParse(rawDate.toString()) ?? DateTime(1970)).toLocal();
          
          if (dayTotals.containsKey(td.day) && td.year == now.year && td.month == now.month) {
            dayTotals[td.day] = (dayTotals[td.day] ?? 0.0) + ((t['amount'] as num?)?.toDouble() ?? 0.0);
          }
        }

        final days = List.generate(7, (i) => now.subtract(Duration(days: 6 - i)));
        final maxY = dayTotals.values.fold(0.0, (a, b) => a > b ? a : b);
        final chartMax = maxY < 1000 ? 5000.0 : (maxY * 1.3);

        return Container(
          height: 76,
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(28, 6, 28, 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('7-Day', style: TextStyle(fontSize: 9, color: Colors.grey[350], fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            const SizedBox(width: 14),
            Expanded(
              child: BarChart(BarChartData(
                maxY: chartMax, minY: 0,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, _, rod, _) {
                      final day = days[group.x];
                      return BarTooltipItem(
                        '${_dayLabel(day)}\n₱${rod.toY.toStringAsFixed(0)}',
                        const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final day = days[value.toInt()];
                      final isToday = day.day == now.day;
                      return Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(_dayLabel(day), style: TextStyle(
                          fontSize: 8, fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                          color: isToday ? accent : Colors.grey[350],
                        )),
                      );
                    },
                  )),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(7, (i) {
                  final day = days[i];
                  final val = dayTotals[day.day] ?? 0.0;
                  final isTd = day.day == now.day;
                  return BarChartGroupData(x: i, barRods: [
                    BarChartRodData(
                      toY: val, width: 10,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      color: isTd ? accent : accent.withAlpha(45),
                    ),
                  ]);
                }),
              )),
            ),
          ]),
        );
      },
    );
  }

  String _dayLabel(DateTime d) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[d.weekday - 1];
  }
}
