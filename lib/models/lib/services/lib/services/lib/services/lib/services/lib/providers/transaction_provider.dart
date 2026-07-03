import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/transaction.dart';
import '../services/database_service.dart';
import '../services/background_sms_service.dart';

/// Holds the full in-memory transaction list, kept in sync with Hive.
final transactionListProvider =
    StateNotifierProvider<TransactionNotifier, List<MpesaTransaction>>(
  (ref) => TransactionNotifier(),
);

class TransactionNotifier extends StateNotifier<List<MpesaTransaction>> {
  TransactionNotifier() : super([]) {
    _load();
  }

  void _load() => state = DatabaseService.getAll();

  Future<void> refreshFromSms() async {
    await scanAndImportNewSms();
    _load();
  }

  Future<void> setCategory(String txnId, Category category) async {
    await DatabaseService.updateCategory(txnId, category);
    _load();
  }
}

/// Derived provider: current month's totals.
final monthlyStatsProvider = Provider<MonthlyStats>((ref) {
  final txns = ref.watch(transactionListProvider);
  final now = DateTime.now();
  final monthTxns = txns.where(
      (t) => t.date.year == now.year && t.date.month == now.month);

  double income = 0, expense = 0;
  final byCategory = <Category, double>{};

  for (final t in monthTxns) {
    if (t.isIncome) {
      income += t.amount;
    } else if (t.isExpense) {
      expense += t.amount;
      byCategory[t.category] = (byCategory[t.category] ?? 0) + t.amount;
    }
  }

  return MonthlyStats(income: income, expense: expense, byCategory: byCategory);
});

class MonthlyStats {
  final double income;
  final double expense;
  final Map<Category, double> byCategory;
  MonthlyStats({required this.income, required this.expense, required this.byCategory});
  double get net => income - expense;
}
