# M-Pesa AI Tracker — Starter Build

Privacy-first personal finance tracker that reads M-Pesa SMS on-device, parses
and categorizes transactions with local AI, and never sends raw data to a
server unless the user opts in.

## What's included (working core)

- `lib/models/transaction.dart` — data model + Hive type adapters
- `lib/services/sms_parser_service.dart` — regex parser for all major M-Pesa
  SMS formats (received, sent, paybill, buy goods, withdraw, deposit,
  airtime, Fuliza, reversal)
- `lib/services/categorization_service.dart` — local keyword-based
  categorizer + optional cloud LLM fallback + anomaly (z-score) detection
- `lib/services/database_service.dart` — AES-256 encrypted Hive storage,
  key held in Android Keystore via `flutter_secure_storage`
- `lib/services/background_sms_service.dart` — WorkManager periodic scan +
  live SMS listener
- `lib/providers/transaction_provider.dart` — Riverpod state
- `lib/screens/dashboard_screen.dart` — dashboard UI with balance card,
  category pie chart, recent transactions

## Not yet built (roadmap)

- Onboarding/permission-explainer flow
- Budgets + alerts screen
- Full transaction history with search/filter
- PDF/CSV export (packages already in pubspec: `pdf`, `csv`, `share_plus`)
- Receipt OCR linking (package included: `google_mlkit_text_recognition`)
- Biometric lock screen (`local_auth` included)
- Multi-account switcher UI
- Goals feature
- Cash-flow forecast model

Each of these is additive — the parser/DB/provider layer already supports
them (e.g. `accountLabel` field is already on the model for multi-SIM).

## Setup

```bash
flutter create --org com.yourcompany mpesa_ai_tracker_shell
# copy lib/ and pubspec.yaml from this project into the shell
cd mpesa_ai_tracker_shell
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs  # generates .g.dart files
```

### Android permissions (`android/app/src/main/AndroidManifest.xml`)

```xml
<uses-permission android:name="android.permission.RECEIVE_SMS"/>
<uses-permission android:name="android.permission.READ_SMS"/>
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.USE_BIOMETRIC"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
```

Request `READ_SMS`/`RECEIVE_SMS` **at runtime**, not just in the manifest,
and only after showing an explainer screen (Play Store policy requires this
— see below).

### Wiring it up in `main.dart`

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseService.init();
  await registerBackgroundScan();
  runApp(const ProviderScope(child: MyApp()));
}
```

## Play Store compliance — READ_SMS is high-risk

Google restricts `READ_SMS`/`RECEIVE_SMS` to apps whose **core function**
requires it (SMS/MMS clients, backup apps, or in narrow cases, default
assistant apps). A finance-tracking app reading M-Pesa SMS is a common
approval flow but you must:

1. Complete the **Permissions Declaration Form** in Play Console explaining
   exactly why SMS access is core to the app (auto-tracking transactions).
2. Restrict the manifest/runtime request to only what's needed — don't
   request `SEND_SMS` or broad SMS permissions you don't use.
3. Provide an in-app disclosure screen (shown *before* the permission
   prompt) describing what's read, why, and that it stays on-device.
4. Expect manual review; approval can take longer than standard releases.
   Have a fallback (manual CSV/statement import, which you already started
   with Pesa Track) for users who decline SMS access or during review gaps.

## Battery / background reliability

- WorkManager's periodic task has a 15-minute Android floor — don't fight it.
- Use `Constraints(networkType: NetworkType.notRequired)` since parsing is
  local — this avoids doze-mode network wake delays.
- The live `listenIncomingSms` listener catches most transactions instantly
  while the app process is alive; WorkManager is the reliability net for
  when Android kills the process.
- Avoid `AlarmManager`-style exact alarms — they hurt battery ratings in
  Play Console vitals and aren't necessary here.

## Monetization ideas

- **Freemium**: free tier = tracking + basic dashboard; premium = budgets,
  forecasting, export, multi-account, LLM-powered insights
- **Subscription** (KSh 199–349/mo) rather than one-time, given ongoing
  cloud LLM inference costs for premium insights
- **White-label**: same core (SMS parser is the hard part) re-templated for
  Tanzania (M-Pesa TZ), Uganda (MTN MoMo), Ghana (MTN MoMo) — each needs its
  own regex pattern set but the architecture is identical
- **B2B**: sell an anonymized/aggregated spend-trends API to banks/SACCOs
  (only with explicit opt-in and real anonymization — treat this carefully)
- **Affiliate**: savings/investment product referrals inside the app
  (relevant given your own interest in investing tools)

## Privacy notes baked into this build

- All data stored in **AES-256 encrypted Hive**, key in platform Keystore
- No network calls unless the user enables an optional AI-insights or
  cloud-backup setting — `categorizeWithLlm` sends only the merchant name
  string, never full SMS, account numbers, or balances
- `DatabaseService.wipeAllData()` gives a real, complete local delete
