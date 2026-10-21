/// Item icon with a shared disk/memory cache.
///
/// The icon URLs from render.guildwars2.com are content-hashed, so disk
/// entries never go stale. Extracted here so both item tiles and the item
/// details page header render the same icon without an import cycle.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

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

class ItemIcon extends StatelessWidget {
  final String url;
  final double size;

  const ItemIcon({super.key, required this.url, this.size = 40.0});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return _FallbackIcon(size: size);
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
        placeholder: (_, __) => _IconPlaceholder(size: size),
        errorWidget: (_, __, ___) => _FallbackIcon(size: size),
      ),
    );
  }
}

class _FallbackIcon extends StatelessWidget {
  final double size;
  const _FallbackIcon({this.size = 40.0});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(Icons.inventory_2_outlined, size: size * 0.55),
    );
  }
}

/// Static placeholder while an icon loads: same footprint as the icon, no
/// animation. (The old spinner turned every section expand into a wall of
/// loading indicators.)
class _IconPlaceholder extends StatelessWidget {
  final double size;
  const _IconPlaceholder({this.size = 40.0});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
