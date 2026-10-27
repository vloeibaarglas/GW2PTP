/// Settings, grouped: Account (API key, securely stored and always
/// masked, plus its permissions), Sync (mode, active-sync options,
/// manual-refresh cooldown), Appearance, and Cached Data diagnostics.
library;

import '../../native/battery_optimization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/permissions.dart';
import '../../build_tag.dart';
import '../../state/app_state.dart';
import '../../store/sync_settings.dart';
import '../../util/clock_time.dart';
import '../../util/day_label.dart';
import '../../util/numbers.dart';
import '../../util/time_ago.dart';

class SettingsScreen extends StatefulWidget {
  /// When true the screen is the first-run gate: no back navigation until
  /// a key is saved.
  final bool firstRun;

  const SettingsScreen({super.key, this.firstRun = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  final _keyController = TextEditingController();
  String? _keyError;
  bool _savingKey = false;
  BatteryMode _batteryMode = BatteryMode.unknown;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshBatteryStatus();
    // Pull the background-tick status (written by the background isolate)
    // and the live service state, so the Active Sync section shows whether
    // the notification pipeline is actually alive.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().refreshSyncStatus();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keyController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-read after returning from system settings: the exemption intent
    // returns as soon as it fires, so a refresh right after the tap races
    // the user's actual choice.
    if (state == AppLifecycleState.resumed) {
      _refreshBatteryStatus();
      context.read<AppState>().refreshSyncStatus();
    }
  }

  Future<void> _refreshBatteryStatus() async {
    final mode = await getBatteryMode();
    if (mounted) setState(() => _batteryMode = mode);
  }

  /// Switch tap is directional: turning optimization OFF fires the system
  /// exemption prompt; turning it back ON opens the app's system Battery
  /// page, because Android offers no API to re-enable it programmatically.
  Future<void> _onBatteryToggle(bool enableOptimization) async {
    try {
      if (enableOptimization) {
        await BatteryOptimization.showAppBatterySettings();
      } else {
        await BatteryOptimization.showDisableBatteryOptimizationSettings();
      }
    } catch (_) {}
    await _refreshBatteryStatus();
  }

  String get _batterySubtitle {
    switch (_batteryMode) {
      case BatteryMode.unrestricted:
        return 'Off — GW2 PTP is unrestricted, sync runs on schedule. '
            'Tap to re-enable in system settings.';
      case BatteryMode.optimized:
        return 'On — Android may delay or kill background sync. '
            'Tap to request unrestricted access.';
      case BatteryMode.restricted:
        return 'On (Restricted) — Android will heavily restrict background '
            'sync. Tap to request unrestricted access.';
      case BatteryMode.unknown:
        return 'Status unknown.';
    }
  }

  Future<void> _saveKey() async {
    final state = context.read<AppState>();
    setState(() {
      _savingKey = true;
      _keyError = null;
    });
    final error = await state.saveKey(_keyController.text);
    if (!mounted) return;
    setState(() {
      _savingKey = false;
      _keyError = error;
      if (error == null) _keyController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final permissionTotal = requiredApiPermissions.length;
    final permissionGranted = state.hasKey
        ? permissionTotal - state.missingPermissions.length
        : 0;
    final accountSubtitle = state.hasKey
        ? 'Key set · $permissionGranted of $permissionTotal permissions'
        : 'Key not set';
    final cooldownLabel = state.settings.refreshCooldownMinutes == 0
        ? 'Off'
        : '${state.settings.refreshCooldownMinutes} min';
    final syncSubtitle = state.settings.mode == SyncMode.active
        ? 'Active · every ${state.settings.intervalMinutes} min · cooldown $cooldownLabel'
        : 'Passive · cooldown $cooldownLabel';
    final themeSubtitle = state.themeMode == ThemeMode.light
        ? 'Light'
        : state.themeMode == ThemeMode.dark
            ? 'Dark'
            : 'System';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        automaticallyImplyLeading: !widget.firstRun,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.firstRun)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Add your Guild Wars 2 API key to get started. '
                    'It is stored only in this device\u2019s secure storage and '
                    'never leaves the phone except in API calls to '
                    'api.guildwars2.com.',
                  ),
                ),
              ),
            _sectionTitle(context, 'Account', accountSubtitle),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: 'Status: '),
                          if (state.hasKey)
                            TextSpan(
                              text: '${state.maskedKey} (Set)',
                              style:
                                  const TextStyle(fontFamily: 'monospace'),
                            )
                          else
                            // Plain text, not monospace: the wide monospace
                            // space made "Not Set" read as "Not  Set".
                            const TextSpan(text: 'Not Set'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _keyController,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: state.hasKey ? 'Replace API Key' : 'API Key',
                        border: const OutlineInputBorder(),
                        errorText: _keyError,
                        isDense: true,
                      ),
                      onSubmitted: (_) => _saveKey(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: _savingKey ? null : _saveKey,
                          child: _savingKey
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(state.hasKey ? 'Replace' : 'Save'),
                        ),
                        const SizedBox(width: 12),
                        if (state.hasKey)
                          TextButton(
                            onPressed: () => _confirmClear(context),
                            child: const Text('Remove'),
                          ),
                      ],
                    ),
                    const Divider(height: 24),
                    const Text(
                      'These permissions are needed for full data.',
                    ),
                    const SizedBox(height: 8),
                    for (final entry in requiredApiPermissions.entries)
                      _PermissionRow(
                        permission: entry.key,
                        description: entry.value,
                        missing: !state.hasKey ||
                            state.missingPermissions.contains(entry.key),
                      ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: state.hasKey
                            ? () => state.recheckPermissions()
                            : null,
                        icon: const Icon(Icons.fact_check_outlined, size: 18),
                        label: const Text('Re-Check Permissions'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _sectionTitle(context, 'Sync', syncSubtitle),
            Card(
              child: RadioGroup<SyncMode>(
                groupValue: state.settings.mode,
                onChanged: (m) => m == null ? null : state.setSyncMode(m),
                child: Column(
                  children: [
                    RadioListTile<SyncMode>(
                      title: const Text('Passive'),
                      subtitle: const Text(
                        'Syncs when the app opens. Shows data age and a stale '
                        'warning. Minimal battery use.',
                      ),
                      value: SyncMode.passive,
                    ),
                    RadioListTile<SyncMode>(
                      title: const Text('Active'),
                      subtitle: const Text(
                        'A foreground service pings the API on a schedule and '
                        'notifies you when buy/sell orders fill. Uses more battery.',
                      ),
                      value: SyncMode.active,
                    ),
                  ],
                ),
              ),
            ),
            if (state.settings.mode == SyncMode.active) ...[
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _IntervalSlider(
                        // Re-seed if the stored value ever changes underneath.
                        key: ValueKey(state.settings.intervalMinutes),
                        initialMinutes: state.settings.intervalMinutes,
                        onCommit: state.setIntervalMinutes,
                      ),
                      SwitchListTile(
                        title: const Text('Fill Notifications'),
                        subtitle: const Text(
                          'Notify when a buy or sell order fills.',
                        ),
                        value: state.settings.notificationsEnabled,
                        onChanged: state.setNotificationsEnabled,
                        contentPadding: EdgeInsets.zero,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Battery Optimization'),
                        subtitle: Text(_batterySubtitle),
                        // The switch mirrors the real three-state system value:
                        // on = optimization applied (Optimized or Restricted),
                        // off = the app is unrestricted. Tapping flips through
                        // the system UI; the value refreshes when they return.
                        value: _batteryMode == BatteryMode.optimized ||
                            _batteryMode == BatteryMode.restricted,
                        onChanged: _batteryMode == BatteryMode.unknown
                            ? null
                            : (on) => _onBatteryToggle(on),
                      ),
                      const Divider(height: 24),
                      const Text(
                        'Status',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            state.serviceRunning
                                ? Icons.check_circle_outline
                                : Icons.pause_circle_outline,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            state.serviceRunning
                                ? 'Background sync is running.'
                                : 'Background sync is not running.',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        state.lastTickLabel,
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Note: on Android 15+, the system limits background '
                        'data sync to 6 hours per day; opening the app resets '
                        'the timer.',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _IntervalSlider(
                      // Re-seed if the stored value ever changes underneath.
                      key: ValueKey(state.settings.refreshCooldownMinutes),
                      initialMinutes: state.settings.refreshCooldownMinutes,
                      onCommit: state.setRefreshCooldownMinutes,
                      title: 'Refresh Cooldown',
                      min: 0,
                      zeroLabel: 'Off',
                      showBatteryWarning: false,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Minimum gap between manual refreshes. Pulls inside '
                      'it show "Already up to date" instead of hitting the '
                      'API. Off means every pull refreshes.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            _sectionTitle(context, 'Appearance', themeSubtitle),
            Card(
              child: RadioGroup<ThemeMode>(
                groupValue: state.themeMode,
                onChanged: (m) => m == null ? null : state.setThemeMode(m),
                child: const Column(
                  children: [
                    RadioListTile<ThemeMode>(
                      title: Text('Light'),
                      value: ThemeMode.light,
                    ),
                    RadioListTile<ThemeMode>(
                      title: Text('Dark'),
                      value: ThemeMode.dark,
                    ),
                    RadioListTile<ThemeMode>(
                      title: Text('System'),
                      subtitle: Text('Follow the device setting.'),
                      value: ThemeMode.system,
                    ),
                  ],
                ),
              ),
            ),
            _sectionTitle(context, 'Cached Data'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HistoryCacheStat(
                      title: 'Sold History',
                      count: state.soldHistoryCachedCount,
                      items: state.soldHistoryCachedItems,
                      oldest: state.soldHistoryCachedOldest,
                      newest: state.soldHistoryCachedNewest,
                      synced: state.soldHistoryFetchedAt,
                      capped: state.soldHistoryCapped,
                    ),
                    const SizedBox(height: 12),
                    _HistoryCacheStat(
                      title: 'Bought History',
                      count: state.boughtHistoryCachedCount,
                      items: state.boughtHistoryCachedItems,
                      oldest: state.boughtHistoryCachedOldest,
                      newest: state.boughtHistoryCachedNewest,
                      synced: state.boughtHistoryFetchedAt,
                      capped: state.boughtHistoryCapped,
                    ),
                    const Divider(height: 24),
                    _simpleCacheStat('Listings',
                        '${state.sells.length} sells · ${state.buys.length} buys'),
                    const SizedBox(height: 8),
                    _simpleCacheStat(
                        'Inventory', '${state.inventory.length} stacks'),
                    const SizedBox(height: 8),
                    _simpleCacheStat('Delivery',
                        '${state.delivery.items.length} items waiting'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Center(
              child: Text(
                'Build $buildTag',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title,
      [String? subtitle]) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (subtitle != null)
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove API Key?'),
        content: const Text(
          'The key will be deleted from secure storage and syncing will stop.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<AppState>().clearKey();
    }
  }
}

/// One row of the API permissions list: green check when granted,
/// amber warning when missing.
class _PermissionRow extends StatelessWidget {
  final String permission;
  final String description;
  final bool missing;

  const _PermissionRow({
    required this.permission,
    required this.description,
    required this.missing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = missing ? const Color(0xFF9A6A00) : Colors.green.shade700;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            missing ? Icons.warning_amber_outlined : Icons.check_circle_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${displayPermissionName(permission)}${missing ? ' — Missing' : ''}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Interval slider with local drag state.
///
/// Dragging updates only this widget (60fps, no I/O); the new value is
/// committed to storage — and the sync service rescheduled — once on
/// release. Committing per-tick did a SharedPreferences write plus a
/// foreground-service restart on every drag event, which made the slider
/// crawl.
class _IntervalSlider extends StatefulWidget {
  final int initialMinutes;
  final ValueChanged<int> onCommit;

  /// Header label above the slider.
  final String title;

  /// Slider minimum. The interval slider uses 1; the cooldown slider
  /// uses 0, meaning "Off". The maximum is 60 for both.
  final double min;

  /// Label shown at the minimum value instead of "0 min", if any.
  final String? zeroLabel;

  /// Whether to warn about battery drain at short values (interval only).
  final bool showBatteryWarning;

  const _IntervalSlider({
    super.key,
    required this.initialMinutes,
    required this.onCommit,
    this.title = 'Check Interval',
    this.min = 1,
    this.zeroLabel,
    this.showBatteryWarning = true,
  });

  @override
  State<_IntervalSlider> createState() => _IntervalSliderState();
}

class _IntervalSliderState extends State<_IntervalSlider> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialMinutes.toDouble();
  }

  String get _label {
    final v = _value.round();
    if (widget.zeroLabel != null && v == widget.min.round()) {
      return widget.zeroLabel!;
    }
    return '$v min';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(widget.title),
            Text(
              _label,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
        Slider(
          min: widget.min,
          max: 60,
          divisions: (60 - widget.min).round(),
          value: _value,
          label: _label,
          onChanged: (v) => setState(() => _value = v),
          onChangeEnd: (v) => widget.onCommit(v.round()),
        ),
        if (widget.showBatteryWarning && _value.round() < 5)
          const Row(
            children: [
              Icon(Icons.battery_alert_outlined,
                  size: 16, color: Colors.orange),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Short intervals keep the radio awake and '
                  'will drain the battery noticeably.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// One cached-history block in the Settings "Cached Data" section:
/// transaction and distinct-item counts, the date span covered, the
/// newest fill timestamp, and when the cache was last synced.
class _HistoryCacheStat extends StatelessWidget {
  final String title;
  final int count;
  final int items;
  final DateTime? oldest;
  final DateTime? newest;
  final DateTime synced;

  /// Whether the cache hit the 25,000-transaction cap: shown as
  /// "(capped)" after the transaction count.
  final bool capped;

  const _HistoryCacheStat({
    required this.title,
    required this.count,
    required this.items,
    required this.oldest,
    required this.newest,
    required this.synced,
    this.capped = false,
  });

  @override
  Widget build(BuildContext context) {
    final sub = Theme.of(context).textTheme.bodySmall;
    // Locals so the null check below promotes the types.
    final oldest = this.oldest;
    final newest = this.newest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        if (count == 0 || oldest == null || newest == null)
          Text('No data yet', style: sub)
        else ...[
          Text(
              '${commas(count)} transactions${capped ? ' (capped)' : ''} · '
              '${commas(items)} items',
              style: sub),
          Text(
              '${dayLabel(oldest)} → ${dayLabel(newest)} · ${_daySpan(oldest, newest)}',
              style: sub),
          Text(
              'Newest fill ${formatClockTime(newest)} · ${_syncedLabel(synced)}',
              style: sub),
        ],
      ],
    );
  }
}

/// One-line cache stat: a label plus its value.
Widget _simpleCacheStat(String title, String value) {
  return Row(
    children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          value,
          textAlign: TextAlign.right,
        ),
      ),
    ],
  );
}
/// "18 days" between two timestamps.
String _daySpan(DateTime oldest, DateTime newest) {
  final days = newest.difference(oldest).inDays;
  if (days < 1) return 'Less than a day';
  return days == 1 ? '1 day' : '$days days';
}

String _syncedLabel(DateTime synced) {
  if (synced.millisecondsSinceEpoch == 0) return 'Never synced';
  return 'Synced ${timeAgo(synced)}';
}
