import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/transaction.dart';

/// Handles all local persistence. Uses Hive with an AES-256 encryption key
/// stored in the platform Keystore/Keychain via flutter_secure_storage —
/// so even a rooted-device file copy of the .hive box is unreadable
/// without the secure-storage key. No data ever leaves the device unless
/// the user explicitly enables cloud backup elsewhere in Settings.
class DatabaseService {
  static const _boxName = 'mpesa_transactions';
  static const _secureStorage = FlutterSecureStorage();
  static const _keyStorageKey = 'hive_encryption_key';
  static late Box<MpesaTransaction> _box;

  static Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(TransactionTypeAdapter());
    Hive.registerAdapter(CategoryAdapter());
    Hive.registerAdapter(MpesaTransactionAdapter());

    final encryptionKey = await _getOrCreateEncryptionKey();
    _box = await Hive.openBox<MpesaTransaction>(
      _boxName,
      encryptionCipher: HiveAesCipher(encryptionKey),
    );
  }

  static Future<List<int>> _getOrCreateEncryptionKey() async {
    final existing = await _secureStorage.read(key: _keyStorageKey);
    if (existing != null) return base64Url.decode(existing);

    final key = Hive.generateSecureKey();
    await _secureStorage.write(key: _keyStorageKey, value: base64UrlEncode(key));
    return key;
  }

  /// De-duplicates by transactionId before inserting — safe to call this
  /// repeatedly on every SMS scan without creating duplicate entries.
  static Future<bool> insertIfNew(MpesaTransaction txn) async {
    final exists = _box.values.any((t) => t.transactionId == txn.transactionId);
    if (exists) return false;
    await _box.put(txn.transactionId, txn);
    return true;
  }

  static List<MpesaTransaction> getAll() => _box.values.toList()
    ..sort((a, b) => b.date.compareTo(a.date));

  static List<MpesaTransaction> getByDateRange(DateTime start, DateTime end) =>
      getAll().where((t) => t.date.isAfter(start) && t.date.isBefore(end)).toList();

  static List<MpesaTransaction> getByCategory(Category cat) =>
      getAll().where((t) => t.category == cat).toList();

  static Future<void> updateCategory(String transactionId, Category newCategory) async {
    final txn = _box.get(transactionId);
    if (txn == null) return;
    txn.category = newCategory;
    await txn.save();
  }

  /// Full wipe — used for the "Delete All Data" privacy control. Also
  /// rotates the encryption key so nothing is recoverable from disk.
  static Future<void> wipeAllData() async {
    await _box.clear();
    await _secureStorage.delete(key: _keyStorageKey);
  }

  static ValueListenable<Box<MpesaTransaction>> listenable() => _box.listenable();
}
