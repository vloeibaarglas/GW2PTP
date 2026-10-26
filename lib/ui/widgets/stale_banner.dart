/// Data-age banner shown above every screen in passive mode.
///
/// Shows "Updating…" with a spinner while a sync is in flight; once done it
/// shows when the app last synced ("Updated at 3:42 PM", device local time); turns into an amber stale warning past an hour; shows the
/// error with a retry affordance when the last sync failed. Tapping
/// refreshes.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import 'notice_banner.dart';

class StaleBanner extends StatelessWidget {
  const StaleBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;

    final bool failed = state.status == LoadStatus.error;
    final bool loading = state.status == LoadStatus.loading;

    Color bg;
    Color fg;
    IconData icon;
    String text;

    if (failed) {
      bg = scheme.errorContainer;
      fg = scheme.onErrorContainer;
      icon = Icons.cloud_off_outlined;
      text = state.errorMessage ?? 'Sync failed.';
    } else if (loading) {
      // Sync in flight: say so instead of showing a stale/null timestamp.
      bg = scheme.surfaceContainerHighest;
      fg = scheme.onSurfaceVariant;
      icon = Icons.sync_outlined;
      text = 'Updating…';
    } else if (state.neverSynced) {
      bg = scheme.surfaceContainerHighest;
      fg = scheme.onSurfaceVariant;
      icon = Icons.schedule_outlined;
      text = 'No Data Yet.';
    } else if (state.isStale) {
      // Old data is not an alarm: the age itself says how old it is,
      // and amber is reserved for error and partial-sync states.
      bg = scheme.surfaceContainerHighest;
      fg = scheme.onSurfaceVariant;
      icon = Icons.schedule_outlined;
      text = 'Updated ${state.lastSyncLabel} — pull to refresh.';
    } else if (state.sectionNotice != null) {
      // Some sections failed but others loaded: keep the data, flag the gap.
      bg = const Color(0xFFFFF3CD);
      fg = const Color(0xFF664D03);
      icon = Icons.warning_amber_outlined;
      text = 'Partial sync — ${state.sectionNotice} Tap to retry.';
    } else if (state.refreshNotice != null) {
      // Cooldown skip or no-change refresh: say so instead of
      // finishing silently, or the user pulls again.
      bg = scheme.surfaceContainerHighest;
      fg = scheme.onSurfaceVariant;
      icon = Icons.check_circle_outline;
      text = '${state.refreshNotice} · synced ${state.lastSyncLabel}.';
    } else {
      bg = scheme.surfaceContainerHighest;
      fg = scheme.onSurfaceVariant;
      icon = Icons.check_circle_outline;
      text = 'Updated ${state.lastSyncLabel}.';
    }

    return NoticeBanner(
      icon: icon,
      text: text,
      background: bg,
      foreground: fg,
      onTap: loading ? null : () => state.refreshAll(),
      trailing: loading
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: fg,
              ),
            )
          : Icon(Icons.refresh, size: 16, color: fg),
    );
  }
}
