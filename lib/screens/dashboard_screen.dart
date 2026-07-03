import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../providers/transaction_provider.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  static final _currency = NumberFormat.currency(locale: 'en_KE', symbol: 'KSh ', decimalDigits: 0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(monthlyStatsProvider);
    final transactions = ref.watch(transactionListProvider);
    final recent = transactions.take(5).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      body: RefreshIndicator(
        onRefresh: () => ref.read(transactionListProvider.notifier).refreshFromSms(),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              backgroundColor: const Color(0xFF0B1120),
              expandedHeight: 100,
              flexibleSpace: const FlexibleSpaceBar(
                title: Text('M-Pesa AI Tracker', style: TextStyle(fontWeight: FontWeight.bold)),
                titlePadding: EdgeInsets.only(left: 20, bottom: 16),
              ),
            ),
            SliverToBoxAdapter(child: _balanceCard(stats)),
            SliverToBoxAdapter(child: _pieChartCard(stats)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Text('Recent transactions',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white70)),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _transactionTile(recent[i]),
                childCount: recent.length,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  Widget _balanceCard(MonthlyStats stats) {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF16A34A), Color(0xFF0D9488)], // Kenyan green-teal
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('This month\'s net flow', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          Text(_currency.format(stats.net),
              style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _flowStat('Income', stats.income, Icons.arrow_downward),
              _flowStat('Expenses', stats.expense, Icons.arrow_upward),
            ],
          ),
        ],
      ),
    );
  }

  Widget _flowStat(String label, double value, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 18),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
            Text(_currency.format(value),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }

  Widget _pieChartCard(MonthlyStats stats) {
    if (stats.byCategory.isEmpty) return const SizedBox.shrink();
    final colors = [
      const Color(0xFF16A34A), const Color(0xFF0D9488), const Color(0xFFF59E0B),
      const Color(0xFFEF4444), const Color(0xFF8B5CF6), const Color(0xFF3B82F6),
    ];
    final entries = stats.byCategory.entries.toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05), // glassmorphism accent
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Text('Spend by category', style: TextStyle(color: Colors.white.withOpacity(0.9))),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: PieChart(
              PieChartData(
                sectionsSpace: 3,
                centerSpaceRadius: 40,
                sections: [
                  for (int i = 0; i < entries.length; i++)
                    PieChartSectionData(
                      value: entries[i].value,
                      title: '${(entries[i].value / stats.expense * 100).round()}%',
                      color: colors[i % colors.length],
                      radius: 55,
                      titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _transactionTile(MpesaTransaction t) {
    final isExpense = t.isExpense;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isExpense ? Colors.red.withOpacity(0.15) : Colors.green.withOpacity(0.15),
        child: Icon(isExpense ? Icons.arrow_upward : Icons.arrow_downward,
            color: isExpense ? Colors.redAccent : Colors.greenAccent, size: 18),
      ),
      title: Text(t.counterparty, style: const TextStyle(color: Colors.white)),
      subtitle: Text(t.category.name, style: const TextStyle(color: Colors.white54)),
      trailing: Text(
        '${isExpense ? '-' : '+'}${_currency.format(t.amount)}',
        style: TextStyle(
          color: isExpense ? Colors.redAccent : Colors.greenAccent,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
