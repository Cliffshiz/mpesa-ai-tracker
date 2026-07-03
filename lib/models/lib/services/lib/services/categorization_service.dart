import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import '../models/transaction.dart';

/// Categorizes transactions using a fast on-device rules engine first,
/// falling back to a cloud LLM only for ambiguous merchant names â€” this
/// keeps 90%+ of categorization free, instant, and fully offline.
class CategorizationService {
  /// Known merchant/paybill name fragments â†’ category. This list grows
  /// over time; ship it as a remote-updatable JSON asset so it can improve
  /// without an app store release.
  static final Map<Category, List<String>> _keywordMap = {
    Category.food: [
      'restaurant', 'hotel', 'cafe', 'kfc', 'java', 'naivas', 'quickmart',
      'carrefour', 'supermarket', 'butchery', 'bakery', 'eatery', 'chicken',
    ],
    Category.transport: [
      'uber', 'bolt', 'little cab', 'matatu', 'sacco', 'shell', 'total energies',
      'rubis', 'ola energy', 'fuel', 'petrol station',
    ],
    Category.rent: ['rent', 'landlord', 'estate', 'property'],
    Category.airtime: ['airtime', 'safaricom postpay', 'bundles'],
    Category.shopping: [
      'jumia', 'mall', 'boutique', 'fashion', 'shoe', 'electronics', 'hardware',
    ],
    Category.bills: [
      'kplc', 'kenya power', 'nairobi water', 'dstv', 'gotv', 'zuku', 'startimes',
      'wifi', 'internet',
    ],
    Category.entertainment: ['cinema', 'imax', 'bet', 'sportpesa', 'betika', 'movie'],
    Category.savings: ['mshwari', 'kcb mpesa', 'sacco savings', 'chama'],
    Category.health: ['hospital', 'clinic', 'pharmacy', 'chemist', 'nhif', 'sha'],
    Category.education: ['school', 'university', 'college', 'fees'],
  };

  /// Fast local categorization by merchant name keyword match.
  static Category categorizeLocally(MpesaTransaction txn) {
    if (txn.isIncome) return Category.income;
    if (txn.type == TransactionType.airtime) return Category.airtime;

    final name = txn.counterparty.toLowerCase();
    for (final entry in _keywordMap.entries) {
      for (final keyword in entry.value) {
        if (name.contains(keyword)) return entry.key;
      }
    }
    return Category.uncategorized;
  }

  /// For merchants the local rules can't classify, optionally call a cloud
  /// LLM (Claude/GPT/Grok) to guess the category from the merchant name.
  /// This is opt-in only â€” gated by the user's cloud-backup/AI-insights
  /// setting â€” and sends ONLY the merchant name, never full SMS content
  /// or account numbers, to preserve privacy.
  static Future<Category> categorizeWithLlm({
    required String merchantName,
    required String apiKey,
    required String apiUrl, // your backend proxy, not the raw provider key on-device
  }) async {
    final prompt = 'Classify this Kenyan merchant/paybill name into exactly '
        'one category: food, transport, rent, airtime, shopping, bills, '
        'entertainment, savings, health, education, transfer, or uncategorized. '
        'Merchant: "$merchantName". Respond with only the category word.';

    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': 'claude-sonnet-5',
          'max_tokens': 10,
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
        }),
      );
      if (response.statusCode != 200) return Category.uncategorized;
      final data = jsonDecode(response.body);
      final text =
          (data['content'][0]['text'] as String).trim().toLowerCase();
      return Category.values.firstWhere(
        (c) => c.name.toLowerCase() == text,
        orElse: () => Category.uncategorized,
      );
    } catch (_) {
      return Category.uncategorized; // graceful offline fallback
    }
  }

  /// Simple anomaly detection: flags a transaction if its amount is a
  /// statistical outlier vs. the user's recent spend in that category
  /// (z-score style, computed on-device â€” no data leaves the phone).
  static bool isAnomalous(MpesaTransaction txn, List<MpesaTransaction> recentSameCategory) {
    if (recentSameCategory.length < 5) return false; // not enough history
    final amounts = recentSameCategory.map((t) => t.amount).toList();
    final mean = amounts.reduce((a, b) => a + b) / amounts.length;
    final variance = amounts.map((a) => (a - mean) * (a - mean)).reduce((a, b) => a + b) /
        amounts.length;
    final stdDev = math.sqrt(variance);
    final zScore = (txn.amount - mean) / (stdDev == 0 ? 1 : stdDev);
    return zScore.abs() > 2.5; // flag outliers beyond 2.5 std devs
  }
}
