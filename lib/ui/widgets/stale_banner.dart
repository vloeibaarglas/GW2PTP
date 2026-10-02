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
      bg = const Color(0xFFFFF3CD);
      fg = const Color(0xFF664D03);
      icon = Icons.warning_amber_outlined;
      text = 'Data May Be Stale — Updated ${state.lastSyncLabel}.';
    } else if (state.sectionNotice != null) {
      // Some sections failed but others loaded: keep the data, flag the gap.
      bg = const Color(0xFFFFF3CD);
      fg = const Color(0xFF664D03);
      icon = Icons.warning_amber_outlined;
      text = 'Partial sync — ${state.sectionNotice} Tap to retry.';
    } else {
      bg = scheme.surfaceContainerHighest;
      fg = scheme.onSurfaceVariant;
      icon = Icons.check_circle_outline;
      text = 'Updated ${state.lastSyncLabel}.';
    }

    return InkWell(
      onTap: loading ? null : () => state.refreshAll(),
      child: Container(
        width: double.infinity,
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: fg, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (loading)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: fg,
                ),
              )
            else
              Icon(Icons.refresh, size: 16, color: fg),
          ],
        ),
      ),
    );
  }
}
