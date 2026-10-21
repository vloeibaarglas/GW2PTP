/// A row showing an item's icon, name, and a subtitle line.
///
/// The icon loads from render.guildwars2.com and is cached on disk with a
/// generous cap (render URLs are content-hashed, so entries never go stale).
/// A missing or failed icon degrades to a generic box glyph — never a broken
/// layout.
library;

import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../screens/item_detail_screen.dart';
import 'item_icon.dart';

class ItemTile extends StatelessWidget {
  final int itemId;
  final ItemMeta Function(int id) metaLookup;
  final Widget subtitle;
  final String? titleOverride;
  final VoidCallback? onTap;

  /// When false the subtitle is shown as-is instead of being forced to a
  /// single clipped line (used for tap-to-expand rows).
  final bool clipSubtitle;

  const ItemTile({
    super.key,
    required this.itemId,
    required this.metaLookup,
    required this.subtitle,
    this.titleOverride,
    this.onTap,
    this.clipSubtitle = true,
  });

  @override
  Widget build(BuildContext context) {
    final meta = metaLookup(itemId);
    final title = titleOverride ?? meta.name;
    return ListTile(
      leading: GestureDetector(
        // Icon-only tap: opens the item details page. Tapping anywhere
        // else on the row keeps the row's own onTap (expand) behavior.
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ItemDetailScreen(itemId: itemId),
          ),
        ),
        child: ItemIcon(url: meta.iconUrl),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: clipSubtitle ? _Clipped(child: subtitle) : subtitle,
      dense: true,
      onTap: onTap,
    );
  }
}

/// Single-line ellipsis for any subtitle widget.
class _Clipped extends StatelessWidget {
  final Widget child;
  const _Clipped({required this.child});

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle.merge(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      child: child,
    );
  }
}

