/// App-updates bottom sheet: check, auto-check, and install.
///
/// Styled like the Settings screen (16px card padding, SwitchListTile with
/// zero content padding, 12px status lines, 11px grey notes). Every step
/// is user-approved: the sheet only checks when the user taps Check (or
/// the 3-day auto-check fires on open), downloads only after Install is
/// tapped, and Android itself asks the user to confirm the install.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_update_state.dart';
import '../../util/time_ago.dart';

Future<void> showUpdateSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const UpdateSheet(),
  );
}

class UpdateSheet extends StatelessWidget {
  const UpdateSheet({super.key});

  String _lastCheckedLabel(AppUpdateState updates) {
    final ms = updates.lastCheckAtMs;
    if (ms <= 0) return 'Never checked';
    return 'Last checked ${timeAgo(
      DateTime.fromMillisecondsSinceEpoch(ms),
    )}';
  }

  @override
  Widget build(BuildContext context) {
    final updates = context.watch<AppUpdateState>();
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('App updates', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              updates.currentVersion != null
                  ? 'Version ${updates.currentVersion}'
                  : 'Version unknown',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            _statusBody(context, updates),
            const Divider(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto-check for updates'),
              subtitle: Text(
                updates.autoCheck
                    ? 'Checks every 3 days when you open the app.'
                    : 'Only checks when you tap Check for updates.',
              ),
              value: updates.autoCheck,
              onChanged: (on) => updates.setAutoCheck(on),
            ),
            const SizedBox(height: 8),
            Text(
              _lastCheckedLabel(updates),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            const Text(
              'Updates never install on their own — installing starts from '
              'your tap, and Android asks you to confirm.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBody(BuildContext context, AppUpdateState updates) {
    switch (updates.status) {
      case UpdateStatus.checking:
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(),
            SizedBox(height: 8),
            Text('Checking GitHub…', style: TextStyle(fontSize: 12)),
          ],
        );
      case UpdateStatus.downloading:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: updates.downloadProgress),
            const SizedBox(height: 8),
            Text(
              updates.downloadProgress != null
                  ? 'Downloading… ${(updates.downloadProgress! * 100).round()}%'
                  : 'Downloading…',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        );
      case UpdateStatus.available:
        final release = updates.latest!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.system_update_outlined, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Version ${release.version} is available',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            if (release.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              ExpansionTile(
                title: const Text(
                  "What's new",
                  style: TextStyle(fontSize: 12),
                ),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      release.notes.trim(),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton(
                  onPressed: () => updates.install(),
                  child: const Text('Install update'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => updates.dismiss(),
                  child: const Text('Later'),
                ),
              ],
            ),
          ],
        );
      case UpdateStatus.upToDate:
        return const Row(
          children: [
            Icon(Icons.check_circle_outline, size: 16),
            SizedBox(width: 6),
            Text("You're up to date.", style: TextStyle(fontSize: 12)),
          ],
        );
      case UpdateStatus.handedToInstaller:
        return const Row(
          children: [
            Icon(Icons.check_circle_outline, size: 16),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'Download complete — Android will ask you to confirm '
                'the install.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        );
      case UpdateStatus.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_outlined, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    updates.error ?? 'Check failed.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => updates.check(),
              child: const Text('Try again'),
            ),
          ],
        );
      case UpdateStatus.idle:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Check GitHub for a newer release.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => updates.check(),
              child: const Text('Check for updates'),
            ),
          ],
        );
    }
  }
}
