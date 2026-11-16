/// Top-right app-updates button, present on every screen's app bar.
///
/// A dot appears when a newer release is known and the user has not tapped
/// Later on it. Tapping opens the update sheet; the button never checks,
/// downloads, or installs anything on its own.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_update_state.dart';
import 'update_sheet.dart';

class UpdateButton extends StatelessWidget {
  const UpdateButton({super.key});

  @override
  Widget build(BuildContext context) {
    final updates = context.watch<AppUpdateState>();
    return Badge(
      isLabelVisible: updates.updateAvailable,
      smallSize: 8,
      child: IconButton(
        icon: const Icon(Icons.system_update_outlined),
        tooltip: 'App updates',
        onPressed: () => showUpdateSheet(context),
      ),
    );
  }
}
