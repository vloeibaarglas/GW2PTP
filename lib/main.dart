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
import 'state/app_update_state.dart';
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

/// Revamp palette (sketch tokens): warm cream surfaces, brass primary.
/// Only the light theme carries it — the dark theme stays the seed-amber
/// one, since the sketch's dark tokens were never specified.
final ColorScheme _revampLightScheme =
    ColorScheme.fromSeed(seedColor: const Color(0xFF8A6D1D)).copyWith(
  primary: const Color(0xFF8A6D1D),
  onPrimary: const Color(0xFFFFFDF4),
  secondary: const Color(0xFFB8860B),
  secondaryContainer: const Color(0xFFF3E3C8),
  onSecondaryContainer: const Color(0xFF2B2115),
  surface: const Color(0xFFFDF8EC),
  onSurface: const Color(0xFF2B2115),
  surfaceContainerLowest: const Color(0xFFFFFDF4),
  surfaceContainerLow: const Color(0xFFFDF6E9),
  onSurfaceVariant: const Color(0xFF7D6C52),
  outline: const Color(0xFFE3D5BA),
  outlineVariant: const Color(0xFFCFC0A0),
  error: const Color(0xFFB03A2E),
);

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
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AppState(
            keys: keys,
            api: api,
            prefs: prefs,
            notifier: notifier,
            syncService: syncService,
          )..init(),
        ),
        // App-update state is separate from the GW2 data state: it owns
        // the release check, the 3-day auto-check, and the install flow.
        ChangeNotifierProvider(
          create: (_) => AppUpdateState(prefs: prefs)..init(),
        ),
      ],
      child: Consumer<AppState>(
        builder: (_, app, __) => MaterialApp(
          title: 'GW2 Personal Trading Post',
          theme: ThemeData(
            colorScheme: _revampLightScheme,
            useMaterial3: true,
            scaffoldBackgroundColor: _revampLightScheme.surface,
            cardTheme: CardThemeData(
              color: _revampLightScheme.surfaceContainerLow,
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: _revampLightScheme.surface,
              elevation: 0,
              scrolledUnderElevation: 0,
              titleTextStyle: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
                color: _revampLightScheme.onSurface,
              ),
              iconTheme: IconThemeData(
                size: 22,
                color: _revampLightScheme.onSurface,
              ),
            ),
            tabBarTheme: TabBarThemeData(
              labelStyle: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
              ),
              labelColor: _revampLightScheme.primary,
              unselectedLabelColor: _revampLightScheme.onSurfaceVariant,
              indicator: UnderlineTabIndicator(
                borderSide: BorderSide(
                  width: 3,
                  color: _revampLightScheme.primary,
                ),
              ),
              indicatorSize: TabBarIndicatorSize.label,
            ),
            bottomNavigationBarTheme: BottomNavigationBarThemeData(
              backgroundColor: _revampLightScheme.surfaceContainerLowest,
              selectedItemColor: _revampLightScheme.primary,
              unselectedItemColor: _revampLightScheme.onSurfaceVariant,
              selectedLabelStyle: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
              selectedIconTheme: const IconThemeData(size: 22),
              unselectedIconTheme: const IconThemeData(size: 22),
              elevation: 0,
            ),
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
