import 'package:telephony/telephony.dart' hide NetworkType;
import 'package:workmanager/workmanager.dart';
import 'sms_parser_service.dart';
import 'categorization_service.dart';
import 'database_service.dart';

const smsScanTaskName = 'mpesaSmsScanTask';

/// Entry point WorkManager calls in the background isolate. Must be a
/// top-level function (not a class method) per the workmanager package
/// contract, and must re-init any services it needs since it runs in a
/// fresh isolate with no shared state from the UI.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == smsScanTaskName) {
      await DatabaseService.init();
      await scanAndImportNewSms();
    }
    return Future.value(true);
  });
}

/// Scans the device SMS inbox for M-Pesa messages, parses new ones, and
/// stores them. Safe to call repeatedly — insertIfNew() de-dupes.
Future<int> scanAndImportNewSms({String accountLabel = 'Default'}) async {
  final telephony = Telephony.instance;
  final granted = await telephony.requestSmsPermissions ?? false;
  if (!granted) return 0;

  final messages = await telephony.getInboxSms(
    columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
    filter: SmsFilter.where(SmsColumn.ADDRESS).equals('MPESA'),
    sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
  );

  int imported = 0;
  for (final sms in messages) {
    final body = sms.body;
    if (body == null) continue;
    final txn = SmsParserService.parse(body, accountLabel: accountLabel);
    if (txn == null) continue;
    txn.category = CategorizationService.categorizeLocally(txn);
    final wasNew = await DatabaseService.insertIfNew(txn);
    if (wasNew) imported++;
  }
  return imported;
}

/// Registers the periodic background scan. Android WorkManager enforces a
/// 15-minute minimum interval for periodic tasks — for near-real-time
/// capture, pair this with a live SMS BroadcastReceiver listener
/// (telephony.listenIncomingSms) while the app is foregrounded/backgrounded
/// but not killed, and rely on this periodic task as the reliability net.
Future<void> registerBackgroundScan() async {
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  await Workmanager().registerPeriodicTask(
    'mpesa-scan',
    smsScanTaskName,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.notRequired),
  );
}

/// Live listener for instant capture while the app has SMS receive
/// permission active in the foreground/background (not killed).
void startLiveSmsListener({required void Function(int newCount) onNewTransactions}) {
  final telephony = Telephony.instance;
  telephony.listenIncomingSms(
    onNewMessage: (SmsMessage message) async {
      if (message.address != 'MPESA' || message.body == null) return;
      final txn = SmsParserService.parse(message.body!);
      if (txn == null) return;
      txn.category = CategorizationService.categorizeLocally(txn);
      final wasNew = await DatabaseService.insertIfNew(txn);
      if (wasNew) onNewTransactions(1);
    },
    listenInBackground: true,
  );
}
