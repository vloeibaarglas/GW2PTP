/// A row showing an item's icon, name, and a subtitle line.
///
/// The icon loads from render.guildwars2.com and is cached on disk with a
/// generous cap (render URLs are content-hashed, so entries never go stale).
/// A missing or failed icon degrades to a generic box glyph — never a broken
/// layout.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../api/models.dart';

/// Icon disk cache: the default manager caps at 200 objects, but an
/// inventory easily holds 1,000+ unique icons — without this, expanding
/// sections churns the LRU and re-downloads evicted icons.
final _iconCacheManager = CacheManager(
  Config(
    'gw2icons',
    maxNrOfCacheObjects: 20000,
    stalePeriod: const Duration(days: 1825),
  ),
);

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
      leading: _Icon(url: meta.iconUrl),
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

class _Icon extends StatelessWidget {
  final String url;

  const _Icon({required this.url});

  @override
  Widget build(BuildContext context) {
    const size = 40.0;
    if (url.isEmpty) return const _FallbackIcon();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CachedNetworkImage(
        imageUrl: url,
        cacheManager: _iconCacheManager,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // Decode near display size: re-expanding a section then hits the
        // memory cache instead of re-decoding full-size bitmaps, and the
        // disk cache (already on) covers fresh process starts.
        memCacheWidth: 96,
        memCacheHeight: 96,
        fadeInDuration: const Duration(milliseconds: 120),
        fadeOutDuration: Duration.zero,
        // Static box, not a spinner: hundreds of rows expanding at once
        // turned into a wall of loading animations.
        placeholder: (_, __) => const _IconPlaceholder(),
        errorWidget: (_, __, ___) => const _FallbackIcon(),
      ),
    );
  }
}

class _FallbackIcon extends StatelessWidget {
  const _FallbackIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(Icons.inventory_2_outlined, size: 22),
    );
  }
}

/// Static placeholder while an icon loads: same footprint as the icon, no
/// animation. (The old spinner turned every section expand into a wall of
/// loading indicators.)
class _IconPlaceholder extends StatelessWidget {
  const _IconPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
