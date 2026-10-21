/// TP Console — a personal Guild Wars 2 Trading Post companion.
///
/// Boot contract (no adb needed to triage crashes):
/// * every async boundary is guarded — a failed keystore read, a dead
///   network, or a malformed API row degrades to an error banner, never a
///   crash;
/// * with no API key the app boots into the Settings gate, not a spinner;
/// * no background work starts unless the user enables Active sync mode.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/gw2_client.dart';
import 'state/app_state.dart';
import 'store/key_store.dart';
import 'sync/background_sync.dart';
import 'sync/fill_notifier.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final notifier = LocalFillNotifier();
  try {
    await notifier.init();
  } catch (_) {
    // Notifications are a nicety; the app boots without them.
  }

  runApp(
    TpConsoleApp(
      prefs: prefs,
      api: HttpGw2Api(),
      keys: SecureKeyStore(),
      notifier: notifier,
      syncService: ForegroundSyncService(),
    ),
  );
}

class TpConsoleApp extends StatelessWidget {
  final SharedPreferences prefs;
  final Gw2Api api;
  final KeyStore keys;
  final FillNotifier notifier;
  final SyncService syncService;

  const TpConsoleApp({
    super.key,
    required this.prefs,
    required this.api,
    required this.keys,
    required this.notifier,
    required this.syncService,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(
        keys: keys,
        api: api,
        prefs: prefs,
        notifier: notifier,
        syncService: syncService,
      )..init(),
      child: Consumer<AppState>(
        builder: (_, app, __) => MaterialApp(
          title: 'GW2 Personal Trading Post',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.amber,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          themeMode: app.themeMode,
          home: const BootGate(),
        ),
      ),
    );
  }
}

/// Routes the first frame: loading splash, first-run key gate, or home.
class BootGate extends StatelessWidget {
  const BootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.keyLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!state.hasKey) {
      return const SettingsScreen(firstRun: true);
    }
    return const HomeScreen();
  }
}
