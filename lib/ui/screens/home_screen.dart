/// Home shell: bottom navigation over the three screens, wallet coins in
/// the app bar, the stale-data banner, and refresh-on-resume for passive
/// mode.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/permissions.dart';
import '../../state/app_state.dart';
import '../widgets/coins_text.dart';
import '../widgets/stale_banner.dart';
import 'held_screen.dart';
import 'inventory_screen.dart';
import 'orders_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _tab = 0;

  static const _titles = ['Listings', 'Deliveries', 'Holdings'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // ignore: discarded_futures
      context.read<AppState>().onResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tab]),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: CoinsText(
                app.walletCoins,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            const StaleBanner(),
            if (app.hasMissingPermissions) _MissingPermissionsBanner(app),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: const [
                  OrdersScreen(),
                  HeldScreen(),
                  InventoryScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.swap_horiz_outlined),
            activeIcon: Icon(Icons.swap_horiz),
            label: 'Listings',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.inbox_outlined),
            activeIcon: Icon(Icons.inbox),
            label: 'Deliveries',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.inventory_2_outlined),
            activeIcon: Icon(Icons.inventory_2),
            label: 'Holdings',
          ),
        ],
      ),
    );
  }
}

/// Warning shown when the API key is missing permissions the app needs.
/// Tapping opens Settings, where each permission is explained.
class _MissingPermissionsBanner extends StatelessWidget {
  final AppState app;
  const _MissingPermissionsBanner(this.app);

  @override
  Widget build(BuildContext context) {
    const fg = Color(0xFF664D03);
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      ),
      child: Container(
        width: double.infinity,
        color: const Color(0xFFFFF3CD),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.key_off_outlined, size: 16, color: fg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'API key is missing: ${app.missingPermissions.map(displayPermissionName).join(', ')}. '
                'Some sections will stay empty — tap for details.',
                style: const TextStyle(color: fg, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
