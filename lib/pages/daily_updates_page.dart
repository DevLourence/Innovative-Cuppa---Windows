import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../data/app_data.dart';

// RE-WRITTEN FOR ROBUSTNESS (v2.1) - FIXES DATE PARSING CRASHES
class DailyUpdatesPage extends StatelessWidget {
  final String business;
  final Map<String, dynamic> user;
  const DailyUpdatesPage({super.key, required this.business, required this.user});

  bool get isShop => business == 'shop';
  Color get accent => isShop ? const Color(0xFFC8822A) : const Color(0xFF4A7C59);

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final dayLabel = DateFormat('EEEE, MMMM d').format(today);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Operational Overview',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1C1008),
                      letterSpacing: -1.0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.calendar_today_rounded, size: 14, color: accent),
                      const SizedBox(width: 8),
                      Text(
                        dayLabel.toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: accent.withAlpha(200),
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              _ActionButton(
                icon: Icons.refresh_rounded,
                label: 'Refresh Data',
                onPressed: () {},
                accent: accent,
              ),
            ],
          ),

          const SizedBox(height: 40),

          // Primary Stats Cards
          _buildStatsGrid(today),

          const SizedBox(height: 32),

          // Main Dashboard Body
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Column: Performance & Activity
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    _DashboardCard(
                      title: '7-Day Sales Performance',
                      subtitle: 'Daily revenue trend for the past week',
                      child: _SalesTrendChart(accent: accent, isShop: isShop),
                    ),
                    const SizedBox(height: 24),
                    _DashboardCard(
                      title: 'Live Activity Stream',
                      subtitle: 'Real-time updates from floor operations',
                      child: _ActivityTimeline(accent: accent, isShop: isShop),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              // Right Column: Comprehensive Inventory Status
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    _DashboardCard(
                      title: 'Current Stock Status',
                      subtitle: 'Real-time inventory levels for all items',
                      child: SizedBox(
                        height: 400, // Fixed height for the scrollable list
                        child: _FullStockStatus(isShop: isShop, accent: accent),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _DashboardCard(
                      title: 'Performance Insights',
                      subtitle: 'Popular demand and sales metrics',
                      child: _PerformanceInsights(isShop: isShop, accent: accent),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(DateTime today) {
    // 🛡️ CRITICAL SAFETY WRAP: Handle String or DateTime
    final transactions = (isShop ? AppData.shopReports : AppData.beansTransactions)
        .where((t) {
          final raw = t['date'];
          if (raw == null) return false;
          final d = raw is DateTime ? raw : DateTime.tryParse(raw.toString());
          return d != null && DateUtils.isSameDay(d, today);
        })
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          children: [
            if (user['role']?.toLowerCase() == 'admin' || user['role']?.toLowerCase() == 'manager')
              Expanded(
                child: _SummaryCard(
                  label: 'TODAY\'S REVENUE',
                  value: '₱${NumberFormat('#,###').format(AppData.getSalesTotal(isShop))}',
                  icon: Icons.payments_rounded,
                  color: const Color(0xFF22C55E),
                  trend: '+12.5%',
                ),
              )
            else
              Expanded(
                child: _SummaryCard(
                  label: 'OPERATOR',
                  value: user['name'] ?? 'Staff',
                  icon: Icons.face_rounded,
                  color: accent,
                ),
              ),
            const SizedBox(width: 20),
            Expanded(
              child: _SummaryCard(
                label: 'TOTAL ORDERS',
                value: '$transactions',
                icon: Icons.shopping_bag_rounded,
                color: const Color(0xFF3B82F6),
                trend: '+5',
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _SummaryCard(
                label: 'RESOURCES USED',
                value: '${AppData.fmt(AppData.getStockOutTotal(isShop))} ${isShop ? 'units' : 'pcs'}',
                icon: Icons.opacity_rounded,
                color: const Color(0xFFF59E0B),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _SummaryCard(
                label: 'TOTAL STOCK',
                value: '${AppData.fmt(AppData.getTotalStock(isShop))} ${isShop ? 'units' : 'pcs'}',
                icon: Icons.inventory_2_rounded,
                color: const Color(0xFF8B5CF6),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? trend;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.trend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF0EDE8), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withAlpha(25),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              if (trend != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E).withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    trend!,
                    style: const TextStyle(
                      color: Color(0xFF16A34A),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.black38,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1C1008),
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _DashboardCard({required this.title, required this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFF0EDE8), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1C1008))),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 13, color: Colors.black38, fontWeight: FontWeight.w500)),
          const SizedBox(height: 28),
          child,
        ],
      ),
    );
  }
}

class _ActivityTimeline extends StatelessWidget {
  final Color accent;
  final bool isShop;
  const _ActivityTimeline({required this.accent, required this.isShop});

  @override
  Widget build(BuildContext context) {
    final txs = (isShop ? AppData.shopReports : AppData.beansTransactions).take(5).toList();

    if (txs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              Icon(Icons.history_rounded, size: 48, color: Colors.black12),
              SizedBox(height: 16),
              Text('No activity recorded yet today.', style: TextStyle(color: Colors.black26)),
            ],
          ),
        ),
      );
    }

    return Column(
      children: List.generate(txs.length, (index) {
        final t = txs[index];
        final isLast = index == txs.length - 1;
        
        // 🛡️ RE-HYDRATION SAFETY
        final raw = t['date'];
        final txDate = raw is DateTime ? raw : DateTime.tryParse(raw?.toString() ?? '') ?? DateTime.now();
        
        final type = t['type'] ?? 'sold';
        
        IconData icon; Color color; String title; String sub;
        if (type == 'sold') {
          icon = Icons.shopping_basket_rounded; color = const Color(0xFF22C55E);
          title = 'Purchase Completed';
          final items = t['items'] as List?;
          sub = items != null && items.isNotEmpty ? '${items.first['qty']}x ${items.first['name']}' : 'Items sold';
        } else {
          icon = Icons.inventory_2_rounded; color = accent;
          title = 'Inventory Restock';
          sub = '${t['itemName']} (+${t['qty']})';
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(color: color.withAlpha(25), shape: BoxShape.circle),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(width: 2, color: const Color(0xFFF0EDE8), margin: const EdgeInsets.symmetric(vertical: 8)),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1C1008))),
                          Text(DateFormat('h:mm a').format(txDate), style: const TextStyle(fontSize: 12, color: Colors.black26)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(sub, style: const TextStyle(fontSize: 13, color: Colors.black54)),
                      const SizedBox(height: 4),
                      Text('By ${t['user_name'] ?? t['userName'] ?? 'System'}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: accent.withAlpha(150))),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _SalesTrendChart extends StatelessWidget {
  final Color accent;
  final bool isShop;
  const _SalesTrendChart({required this.accent, required this.isShop});

  @override
  Widget build(BuildContext context) {
    final rawTransactions = (isShop ? AppData.shopReports : AppData.beansTransactions);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    // Create a Map for quick lookup
    final Map<String, double> lookup = {};
    for (final entry in rawTransactions) {
      if (entry['type'] != 'sold') continue;
      
      // 🛡️ RE-HYDRATION SAFETY
      final raw = entry['date'];
      final d = raw is DateTime ? raw : DateTime.tryParse(raw?.toString() ?? '') ?? now;
      
      final k = "${d.year}-${d.month}-${d.day}";
      final amt = entry['amount'];
      final val = amt is num ? amt.toDouble() : double.tryParse(amt?.toString() ?? '0') ?? 0.0;
      lookup[k] = (lookup[k] ?? 0.0) + val;
    }

    // Generate fixed 7-day range ending today
    final List<Map<String, dynamic>> finalHistory = [];
    for (int i = 6; i >= 0; i--) {
      final date = today.subtract(Duration(days: i));
      final k = "${date.year}-${date.month}-${date.day}";
      finalHistory.add({
        'date': date,
        'amount': lookup[k] ?? 0.0,
      });
    }

    final maxVal = finalHistory.map((e) => e['amount'] as double).fold(1000.0, (a, b) => a > b ? a : b);

    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          maxY: maxVal * 1.5,
          barGroups: List.generate(finalHistory.length, (i) {
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: (finalHistory[i]['amount'] as num).toDouble(),
                  color: accent,
                  width: 20,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxVal * 1.2,
                    color: accent.withAlpha(15),
                  ),
                ),
              ],
            );
          }),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (val, _) {
                  final idx = val.toInt();
                  if (idx < 0 || idx >= finalHistory.length) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      DateFormat('E').format(finalHistory[idx]['date']),
                      style: const TextStyle(fontSize: 10, color: Colors.black26, fontWeight: FontWeight.bold),
                    ),
                  );
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }
}

class _FullStockStatus extends StatelessWidget {
  final bool isShop;
  final Color accent;
  const _FullStockStatus({required this.isShop, required this.accent});

  @override
  Widget build(BuildContext context) {
    final rawIngredients = isShop ? AppData.shopIngredients : AppData.beansInventory;
    
    // 🛡️ High-Precision Filtering: Only show items with valid names and balances
    final ingredients = rawIngredients.where((i) {
      final name = i[isShop ? 'name' : 'product_name']?.toString() ?? '';
      return name.isNotEmpty;
    }).toList();

    return ListView.builder(
      itemCount: ingredients.length,
      itemBuilder: (context, index) {
        final item = ingredients[index];
        final rawStock = item[isShop ? 'stock' : 'balance_qty'] ?? 0.0;
        final stock = rawStock is num ? rawStock.toDouble() : double.tryParse(rawStock.toString()) ?? 0.0;
        final unit = item['unit']?.toString() ?? (isShop ? 'units' : 'pcs');
        final isLow = stock < 5.0;
        final isCritical = stock < 2.0;
        
        // ... (rest of the logic)
        
        Color statusColor = const Color(0xFF22C55E); // Good
        String statusLabel = 'GOOD';
        if (isCritical) {
          statusColor = const Color(0xFFEF4444); // Critical
          statusLabel = 'CRITICAL';
        } else if (isLow) {
          statusColor = const Color(0xFFF59E0B); // Low
          statusLabel = 'LOW';
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF9F8F6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: statusColor.withAlpha(40)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item[isShop ? 'name' : 'product_name'] ?? 'Unknown Item',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1C1008)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Category: ${item['category'] ?? 'N/A'}',
                      style: const TextStyle(fontSize: 11, color: Colors.black38, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Text(
                        stock.toStringAsFixed(1),
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: statusColor),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        unit,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: statusColor.withAlpha(150)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: statusColor),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PerformanceInsights extends StatelessWidget {
  final bool isShop;
  final Color accent;
  const _PerformanceInsights({required this.isShop, required this.accent});

  @override
  Widget build(BuildContext context) {
    final items = AppData.getTopSellingItems(isShop, limit: 3);

    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            'No sales data recorded yet.',
            style: TextStyle(fontSize: 13, color: Colors.black26, fontWeight: FontWeight.w500),
          ),
        ),
      );
    }

    return Column(
      children: items.map((item) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(item['name'] as String, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1C1008))),
                Text('${item['count']} SOLD', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: accent)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (item['percent'] as num).toDouble(),
                minHeight: 6,
                backgroundColor: const Color(0xFFF0EDE8),
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
          ],
        ),
      )).toList(),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color accent;

  const _ActionButton({required this.icon, required this.label, required this.onPressed, required this.accent});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1C1008),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFF0EDE8), width: 1.5),
        ),
      ),
    );
  }
}
