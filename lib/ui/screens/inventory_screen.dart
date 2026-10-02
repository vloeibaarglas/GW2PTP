/// Inventory screen: searchable items across bank, materials, shared
/// slots, character bags, and equipped gear — grouped into collapsible
/// sections by area (character sections show the character name).
///
/// Rows build lazily (one SliverList per expanded section) so expanding a
/// hundreds-deep section like the bank never materializes every row up
/// front.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/models.dart';
import '../../state/app_state.dart';
import '../widgets/item_tile.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _search = TextEditingController();

  /// Fixed areas sort first, in this order; character names follow.
  static const _fixedAreas = ['Bank', 'Materials', 'Shared Inventory'];

  /// Locations the user collapsed. Null until first built (all expanded).
  Set<String>? _collapsed;

  // Memoized filter+group: recomputed only when the inventory list
  // instance or the query changes, not on every build.
  List<InventoryEntry>? _memoInventory;
  String _memoQuery = '';
  List<String>? _memoLocations;
  Map<String, List<InventoryEntry>>? _memoGroups;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch only the inventory list: wallet ticks and other state changes
    // must not rebuild the whole screen.
    final inventory = context.select<AppState, List<InventoryEntry>>(
      (s) => s.inventory,
    );
    final app = context.read<AppState>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(
              hintText: 'Search Items…',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(child: _buildList(context, app, inventory)),
      ],
    );
  }

  Widget _buildList(
    BuildContext context,
    AppState app,
    List<InventoryEntry> inventory,
  ) {
    final query = _search.text.trim().toLowerCase();
    if (!identical(inventory, _memoInventory) || query != _memoQuery) {
      final entries = inventory.where((e) {
        if (query.isEmpty) return true;
        final name = app.meta.lookup(e.itemId).name.toLowerCase();
        return name.contains(query);
      }).toList();
      final groups = <String, List<InventoryEntry>>{};
      for (final e in entries) {
        groups.putIfAbsent(e.location, () => []).add(e);
      }
      _memoInventory = inventory;
      _memoQuery = query;
      _memoGroups = groups;
      _memoLocations = [
        for (final a in _fixedAreas)
          if (groups.containsKey(a)) a,
        for (final loc in groups.keys)
          if (!_fixedAreas.contains(loc)) loc,
      ];
    }
    final groups = _memoGroups!;
    final locations = _memoLocations!;

    if (inventory.isEmpty || locations.isEmpty) {
      // Keep pull-to-refresh working in the empty state: the "Pull to
      // refresh" copy promises it.
      return RefreshIndicator(
        onRefresh: app.refreshAll,
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  inventory.isEmpty
                      ? 'No inventory data. Pull to refresh.'
                      : 'No items match "${_search.text.trim()}".',
                ),
              ),
            ),
          ],
        ),
      );
    }

    final searching = query.isNotEmpty;
    final collapsed = _collapsed ??= <String>{};
    if (searching) collapsed.clear();

    return RefreshIndicator(
      onRefresh: app.refreshAll,
      child: CustomScrollView(
        slivers: [
          for (final location in locations)
            // Horizontal 16 to mirror the ListView padding on the
            // Listings/Deliveries tabs; vertical rhythm lives on the cards.
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: _AreaSection(
                location: location,
                entries: groups[location]!,
                metaLookup: app.meta.lookup,
                expanded: searching || !collapsed.contains(location),
                onToggle: () => setState(() {
                  if (collapsed.contains(location)) {
                    collapsed.remove(location);
                  } else {
                    collapsed.add(location);
                  }
                }),
              ),
            ),
          // Matches the other tabs: last row's 4px card margin + 16 = 20px
          // of breathing room at the list end.
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
      ),
    );
  }
}

/// One collapsible inventory area: a tappable header card plus a lazily
/// built row list (SliverList.builder) when expanded.
class _AreaSection extends StatelessWidget {
  final String location;
  final List<InventoryEntry> entries;
  final ItemMeta Function(int id) metaLookup;
  final bool expanded;
  final VoidCallback onToggle;

  const _AreaSection({
    required this.location,
    required this.entries,
    required this.metaLookup,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = entries.fold<int>(0, (sum, e) => sum + e.count);
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          // 8px top (+8 from the search field or the previous section's
          // rows) and 8px bottom mirror the block rhythm on the other tabs.
          child: Card(
            margin: const EdgeInsets.only(top: 8, bottom: 8),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$location (${entries.length})',
                            style: theme.textTheme.titleSmall,
                          ),
                          Text(
                            '$total Items',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (expanded)
          SliverList.builder(
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final e = entries[i];
              final meta = metaLookup(e.itemId);
              // Only the exceptional states get a tag: most items are
              // sellable, so "Sellable" on every row would be noise. Bound
              // implies not sellable.
              final tag = e.isBound(meta)
                  ? ' · Bound'
                  : (e.isSellable(meta) ? '' : ' · Not Sellable');
              return Card(
                margin: const EdgeInsets.only(bottom: 4),
                child: ItemTile(
                  itemId: e.itemId,
                  metaLookup: metaLookup,
                  subtitle: Text(
                    e.detail == null
                        ? '×${e.count}$tag'
                        : '×${e.count} · ${e.detail}$tag',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
