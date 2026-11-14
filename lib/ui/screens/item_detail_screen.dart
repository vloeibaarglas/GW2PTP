/// Item details page: opened by tapping an item's icon anywhere an
/// [ItemTile] appears.
///
/// Fetch-on-open only: nothing is prefetched. The [ItemDetailCache] holds
/// an opened item for 60 seconds; every load path shows a spinner while
/// the API responds and degrades per-section on failure instead of
/// failing the page.
///
/// Casing note: this page deliberately uses natural casing (not the
/// app-wide all-caps rule) — dense market data is unreadable in caps.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/models.dart';
import '../../store/item_detail_cache.dart';
import '../../state/app_state.dart';
import '../../util/coins.dart';
import '../../util/craft_pricing.dart';
import '../widgets/coins_text.dart';
import '../widgets/item_icon.dart';

/// History range chips; all ranges re-filter the cached points locally.
enum _Range { d7, d30, y1, max }

/// "CraftingMaterial" -> "Crafting Material".
String _humanize(String s) {
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (i > 0 &&
        c.toUpperCase() == c &&
        c.toLowerCase() != c &&
        s[i - 1].toLowerCase() == s[i - 1] &&
        s[i - 1].toUpperCase() != s[i - 1]) {
      out.write(' ');
    }
    out.write(c);
  }
  return out.toString();
}

/// Rarity -> accent color (GW2 rarity palette).
Color _rarityColor(String rarity) {
  switch (rarity.toLowerCase()) {
    case 'junk':
      return const Color(0xFF9E9E9E);
    case 'basic':
      return const Color(0xFFE0E0E0);
    case 'fine':
      return const Color(0xFF62A4DA);
    case 'masterwork':
      return const Color(0xFF1A9306);
    case 'rare':
      return const Color(0xFFFCD00B);
    case 'exotic':
      return const Color(0xFFFFA405);
    case 'ascended':
      return const Color(0xFFFB3E8D);
    case 'legendary':
      return const Color(0xFF4C139D);
    default:
      return const Color(0xFF9E9E9E);
  }
}

class ItemDetailScreen extends StatefulWidget {
  final int itemId;

  const ItemDetailScreen({super.key, required this.itemId});

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  ItemDetailBundle? _bundle;
  Object? _phase1Error;

  bool _bookLoading = false;
  Object? _bookError;

  bool _historyLoading = false;
  Object? _historyError;

  bool _craftLoading = false;
  Object? _craftError;
  Map<int, CommerceQuote>? _ingredientPrices;

  _Range _range = _Range.d30;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _set(void Function() fn) {
    if (!_disposed) setState(fn);
  }

  Future<void> _load() async {
    _set(() {
      _bundle = null;
      _phase1Error = null;
      _bookError = null;
      _historyError = null;
      _craftError = null;
      _ingredientPrices = null;
    });
    final app = context.read<AppState>();
    try {
      final bundle = await app.detailCache.get(widget.itemId, app.api);
      _set(() => _bundle = bundle);
      // Book, history, and craft prices fill in behind the first paint.
      _loadBook();
      _loadHistory();
      if (bundle.recipes.isNotEmpty) _loadCraftPrices(bundle.recipes.first);
    } catch (e) {
      _set(() => _phase1Error = e);
    }
  }

  Future<void> _loadBook() async {
    final app = context.read<AppState>();
    _set(() {
      _bookLoading = true;
      _bookError = null;
    });
    try {
      await app.detailCache.book(widget.itemId, app.api);
      _set(() => _bookLoading = false);
    } catch (e) {
      _set(() {
        _bookLoading = false;
        _bookError = e;
      });
    }
  }

  Future<void> _loadHistory() async {
    final app = context.read<AppState>();
    _set(() {
      _historyLoading = true;
      _historyError = null;
    });
    try {
      await app.detailCache.history(widget.itemId, app.api);
      _set(() => _historyLoading = false);
    } catch (e) {
      _set(() {
        _historyLoading = false;
        _historyError = e;
      });
    }
  }

  Future<void> _loadCraftPrices(CraftRecipe recipe) async {
    final app = context.read<AppState>();
    _set(() {
      _craftLoading = true;
      _craftError = null;
    });
    try {
      final prices = await app.detailCache.ingredientPrices(
        [for (final i in recipe.ingredients) i.itemId],
        app.api,
      );
      _set(() {
        _ingredientPrices = prices;
        _craftLoading = false;
      });
    } catch (e) {
      _set(() {
        _craftLoading = false;
        _craftError = e;
      });
    }
  }

  Future<void> _refresh() async {
    context.read<AppState>().detailCache.invalidate(widget.itemId);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Item details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _bundle == null ? null : _refresh,
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_phase1Error != null) {
      return _ErrorBlock(
        message: 'Could not load item details.',
        onRetry: _load,
      );
    }
    final bundle = _bundle;
    if (bundle == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _HeaderCard(detail: bundle.detail),
          const SizedBox(height: 12),
          _DescriptionCard(detail: bundle.detail),
          const SizedBox(height: 12),
          _MarketCard(quote: bundle.quote),
          const SizedBox(height: 12),
          _BookCard(
            book: bundle.book,
            loading: _bookLoading,
            error: _bookError,
            onRetry: _loadBook,
          ),
          const SizedBox(height: 12),
          _HistoryCard(
            points: bundle.history,
            loading: _historyLoading,
            error: _historyError,
            range: _range,
            onRange: (r) => _set(() => _range = r),
            onRetry: _loadHistory,
          ),
          const SizedBox(height: 12),
          _CraftCard(
            recipes: bundle.recipes,
            quote: bundle.quote,
            ingredientPrices: _ingredientPrices,
            loading: _craftLoading,
            error: _craftError,
            onRetry: bundle.recipes.isNotEmpty
                ? () => _loadCraftPrices(bundle.recipes.first)
                : null,
          ),
          const SizedBox(height: 12),
          _PositionCard(itemId: widget.itemId),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Inline error with a retry button; used per-section and full-page.
class _ErrorBlock extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBlock({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

/// Small note line for a section that failed but must not break the page.
class _SectionNote extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _SectionNote({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final Widget child;

  const _Card({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _KvRow extends StatelessWidget {
  final String label;
  final Widget value;

  const _KvRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          value,
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final ItemDetail detail;

  const _HeaderCard({required this.detail});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _rarityColor(detail.rarity);
    final typeLine = [
      _humanize(detail.type),
      if (detail.level > 0) 'Level ${detail.level}',
    ].join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: accent, width: 2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ItemIcon(url: detail.iconUrl, size: 64),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        detail.name,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: accent),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          detail.rarity,
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (typeLine.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                typeLine,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (detail.chatLink.isNotEmpty) ...[
              const SizedBox(height: 10),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: detail.chatLink));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Chat link copied'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color:
                        theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          detail.chatLink,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                      ),
                      Icon(
                        Icons.copy,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DescriptionCard extends StatelessWidget {
  final ItemDetail detail;

  const _DescriptionCard({required this.detail});

  @override
  Widget build(BuildContext context) {
    final lines = detail.detailLines();
    return _Card(
      title: 'Description',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (detail.description.isNotEmpty)
            Text(
              detail.description,
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(line),
            ),
          if (detail.vendorValue > 0)
            _KvRow(
              label: 'Vendor value',
              value: CoinsText(detail.vendorValue),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              // NoSell is a vendor flag, not a TP flag (Quip carries it
              // yet trades at ~1,499g), so it gates neither chip: an
              // unbound item reads Sellable, a bound one reads Bound.
              // SoulbindOnAcquire binds every owned copy, so it counts
              // as bound here (unlike SoulBindOnUse / AccountBindOnUse,
              // where an unused copy is still sellable).
              if (!detail.accountBound && !detail.soulbindOnAcquire)
                const Chip(label: Text('Sellable')),
              if (detail.accountBound || detail.soulbindOnAcquire)
                const Chip(label: Text('Bound')),
              for (final r in detail.restrictions)
                Chip(label: Text(_humanize(r))),
            ],
          ),
        ],
      ),
    );
  }
}

class _MarketCard extends StatelessWidget {
  final CommerceQuote? quote;

  const _MarketCard({required this.quote});

  @override
  Widget build(BuildContext context) {
    final q = quote;
    if (q == null) {
      return const _Card(
        title: 'Live market',
        child: _SectionNote(message: 'Not listed on the Trading Post.'),
      );
    }
    final margin = q.flipMargin;
    final marginColor = margin >= 0 ? Colors.green : Colors.red;
    return _Card(
      title: 'Live market',
      child: Column(
        children: [
          _KvRow(
            label: 'Best bid',
            value: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CoinsText(q.buyPrice,
                    style: const TextStyle(color: Colors.green)),
                Text(' ×${q.buyQuantity}'),
              ],
            ),
          ),
          _KvRow(
            label: 'Best ask',
            value: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CoinsText(q.sellPrice,
                    style: const TextStyle(color: Colors.red)),
                Text(' ×${q.sellQuantity}'),
              ],
            ),
          ),
          const Divider(),
          _KvRow(label: 'Spread', value: CoinsText(q.spread)),
          _KvRow(
            label: 'Net after 15% fees',
            value: CoinsText((q.sellPrice * 0.85).round()),
          ),
          _KvRow(
            label: 'Flip margin / unit',
            value: CoinsText(
              margin,
              style: TextStyle(
                color: marginColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (margin < 0)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Fee-negative at top of book — no naive flip.',
                style: TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

/// Clean two-column order book table: no depth bars, no shading.
class _BookCard extends StatelessWidget {
  final ListingBook? book;
  final bool loading;
  final Object? error;
  final VoidCallback onRetry;

  const _BookCard({
    required this.book,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget body;
    if (loading) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    } else if (error != null) {
      body = _SectionNote(
        message: 'Could not load the order book.',
        onRetry: onRetry,
      );
    } else {
      final b = book;
      if (b == null || b.levelCount == 0) {
        body = const _SectionNote(message: 'No open listings.');
      } else {
        final bids = b.bids.take(10).toList();
        final asks = b.asks.take(10).toList();
        final rows = bids.length > asks.length ? bids.length : asks.length;
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${b.levelCount} price levels',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(1),
                1: FlexColumnWidth(1),
              },
              children: [
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('Bids',
                          style: theme.textTheme.labelLarge?.copyWith(
                              color: Colors.green)),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('Asks',
                          style: theme.textTheme.labelLarge
                              ?.copyWith(color: Colors.red)),
                    ),
                  ],
                ),
                for (var i = 0; i < rows; i++)
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: i < bids.length
                            ? Text(
                                '${formatCoins(bids[i].unitPrice)} × ${_compact(bids[i].quantity)}')
                            : const Text(''),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: i < asks.length
                            ? Text(
                                '${formatCoins(asks[i].unitPrice)} × ${_compact(asks[i].quantity)}')
                            : const Text(''),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        );
      }
    }
    return _Card(title: 'Order book', child: body);
  }

  static String _compact(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(2)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}

class _HistoryCard extends StatefulWidget {
  final List<PricePoint>? points;
  final bool loading;
  final Object? error;
  final _Range range;
  final ValueChanged<_Range> onRange;
  final VoidCallback onRetry;

  const _HistoryCard({
    required this.points,
    required this.loading,
    required this.error,
    required this.range,
    required this.onRange,
    required this.onRetry,
  });

  @override
  State<_HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends State<_HistoryCard> {
  int? _selected;

  List<PricePoint> _filtered() {
    final all = widget.points ?? const <PricePoint>[];
    if (all.isEmpty) return all;
    final now = DateTime.now().toUtc();
    Duration? window;
    switch (widget.range) {
      case _Range.d7:
        window = const Duration(days: 7);
      case _Range.d30:
        window = const Duration(days: 30);
      case _Range.y1:
        window = const Duration(days: 365);
      case _Range.max:
        window = null;
    }
    if (window == null) return all;
    final cutoff = now.subtract(window);
    // Local re-filter: range switches never hit the network.
    final out = [for (final p in all) if (!p.time.isBefore(cutoff)) p];
    if (_selected != null && _selected! >= out.length) _selected = null;
    return out;
  }

  void _pick(Offset local, double width, int count) {
    if (count < 2) return;
    // Map against the drawn points, not the full history (see
    // priceChartPickIndex): the painter downsamples long histories.
    setState(() => _selected = priceChartPickIndex(local.dx, width, count));
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (widget.loading) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    } else if (widget.error != null) {
      body = _SectionNote(
        message: 'Price history unavailable.',
        onRetry: widget.onRetry,
      );
    } else {
      final data = _filtered();
      if (data.length < 2) {
        body = const _SectionNote(message: 'No history data.');
      } else {
        body = Column(
          children: [
            // Full-width range selector.
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<_Range>(
                segments: const [
                  ButtonSegment(value: _Range.d7, label: Text('7D')),
                  ButtonSegment(value: _Range.d30, label: Text('30D')),
                  ButtonSegment(value: _Range.y1, label: Text('1Y')),
                  ButtonSegment(value: _Range.max, label: Text('Max')),
                ],
                selected: {widget.range},
                onSelectionChanged: (s) => widget.onRange(s.single),
              ),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) =>
                      _pick(d.localPosition, width, data.length),
                  onPanUpdate: (d) =>
                      _pick(d.localPosition, width, data.length),
                  child: SizedBox(
                    height: 190,
                    width: width,
                    child: CustomPaint(
                      painter: _ChartPainter(data, _selected),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            Text(
              'Tap or drag the chart to inspect values.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color:
                        Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        );
      }
    }
    return _Card(title: 'Price history · GW2BLTC', child: body);
  }
}

/// Drawn-point index nearest the touch at [dx] in a plot [width] wide
/// holding [count] history points.
///
/// Must map against the points the painter actually draws, not the full
/// history: the painter downsamples long histories to
/// [_ChartPainter.maxPoints], so mapping against the full count picks a
/// point far to the right of the touch (by the downsample factor) and,
/// past ~1/factor across the plot, past the last drawn point entirely —
/// the tooltip races ahead of the finger and off the panel. Clamped to
/// the drawn range, so the tooltip stops at the first/last drawn point.
int priceChartPickIndex(double dx, double width, int count) {
  final drawn = count > _ChartPainter.maxPoints ? _ChartPainter.maxPoints : count;
  if (drawn < 2) return 0;
  final plotW = width - _ChartPainter.leftPad - _ChartPainter.rightPad;
  var i =
      ((dx - _ChartPainter.leftPad) / plotW * (drawn - 1)).round();
  if (i < 0) i = 0;
  if (i > drawn - 1) i = drawn - 1;
  return i;
}

/// Price chart with y (price) and x (date) axes, plus a touch crosshair.
class _ChartPainter extends CustomPainter {
  final List<PricePoint> points;
  final int? selected;

  _ChartPainter(this.points, this.selected);

  static const leftPad = 48.0;
  static const rightPad = 8.0;
  static const _topPad = 10.0;
  static const _bottomPad = 22.0;

  /// Most points the painter draws; longer histories are downsampled.
  static const maxPoints = 400;

  @override
  void paint(Canvas canvas, Size size) {
    // Downsample to at most ~400 points so years of history stay cheap.
    List<PricePoint> data = points;
    if (points.length > maxPoints) {
      final step = points.length / maxPoints;
      data = [for (var i = 0; i < maxPoints; i++) points[(i * step).floor()]];
    }
    if (data.length < 2) return;

    var lo = data.first.sell;
    var hi = data.first.sell;
    for (final p in data) {
      if (p.sell < lo) lo = p.sell;
      if (p.sell > hi) hi = p.sell;
      if (p.buy < lo) lo = p.buy;
      if (p.buy > hi) hi = p.buy;
    }
    final pad = ((hi - lo) * 0.15).round();
    lo -= pad;
    hi += pad;
    if (hi <= lo) hi = lo + 1;

    final plotW = size.width - leftPad - rightPad;
    final plotH = size.height - _topPad - _bottomPad;
    double x(int i) => leftPad + i / (data.length - 1) * plotW;
    double y(int v) => _topPad + (1 - (v - lo) / (hi - lo)) * plotH;

    final grid = Paint()
      ..color = const Color(0xFF3A3A48)
      ..strokeWidth = 1;
    final labelStyle = const TextStyle(color: Color(0xFF9A93B8), fontSize: 10);

    void drawLabel(String text, double lx, double ly) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(lx, ly - tp.height / 2));
    }

    // Y axis: 4 price ticks.
    for (var t = 0; t < 4; t++) {
      final v = (lo + (hi - lo) * t / 3).round();
      final yy = y(v);
      canvas.drawLine(
          Offset(leftPad, yy), Offset(size.width - rightPad, yy), grid);
      drawLabel(_axisCoins(v), 2, yy);
    }
    // X axis: 4 date ticks.
    for (var t = 0; t < 4; t++) {
      final i = (t * (data.length - 1) / 3).round();
      final tp = TextPainter(
        text: TextSpan(text: _axisDate(data[i].time), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
          canvas,
          Offset((x(i) - tp.width / 2).clamp(0.0, size.width - tp.width),
              size.height - _bottomPad + 5));
    }

    void stroke(int Function(PricePoint) pick, Color color) {
      final path = Path();
      for (var i = 0; i < data.length; i++) {
        final px = x(i);
        final py = y(pick(data[i]));
        if (i == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }

    stroke((p) => p.buy, const Color(0xFF4DD0A6));
    stroke((p) => p.sell, const Color(0xFFFFA405));

    // Touch crosshair: vertical line + dots + value box.
    final sel = selected;
    if (sel != null && sel >= 0 && sel < data.length) {
      final p = data[sel];
      final cx = x(sel);
      canvas.drawLine(
        Offset(cx, _topPad),
        Offset(cx, _topPad + plotH),
        Paint()
          ..color = const Color(0xFF8A84A8)
          ..strokeWidth = 1,
      );
      for (final entry in [(p.sell, const Color(0xFFFFA405)),
          (p.buy, const Color(0xFF4DD0A6))]) {
        canvas.drawCircle(
            Offset(cx, y(entry.$1)), 4, Paint()..color = entry.$2);
      }
      final lines = [
        _axisDate(p.time),
        'Sell ${formatCoins(p.sell)}',
        'Buy ${formatCoins(p.buy)}',
      ];
      final tps = [
        for (final l in lines)
          TextPainter(
            text: TextSpan(
                text: l,
                style: const TextStyle(color: Colors.white, fontSize: 11)),
            textDirection: TextDirection.ltr,
          )..layout()
      ];
      final bw = tps.map((t) => t.width).reduce((a, b) => a > b ? a : b) + 16;
      final bh = tps.fold<double>(12, (h, t) => h + t.height + 4);
      var bx = (cx + 10).clamp(0.0, size.width - bw);
      final by = _topPad + 4.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(bx, by, bw, bh), const Radius.circular(6)),
        Paint()..color = const Color(0xDD2A2A38),
      );
      var ty = by + 6;
      for (final tp in tps) {
        tp.paint(canvas, Offset(bx + 8, ty));
        ty += tp.height + 4;
      }
    }
  }

  /// Compact coin label for axis ticks ("5s 3c", "22g").
  static String _axisCoins(int copper) {
    if (copper >= 10000) return '${copper ~/ 10000}g';
    if (copper >= 100) return '${copper ~/ 100}s';
    return '${copper}c';
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  static String _axisDate(DateTime t) {
    final local = t.toLocal();
    return '${_months[local.month - 1]} ${local.day}';
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.points != points || old.selected != selected;
}

class _CraftCard extends StatelessWidget {
  final List<CraftRecipe> recipes;
  final CommerceQuote? quote;
  final Map<int, CommerceQuote>? ingredientPrices;
  final bool loading;
  final Object? error;
  final VoidCallback? onRetry;

  const _CraftCard({
    required this.recipes,
    required this.quote,
    required this.ingredientPrices,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    Widget body;
    if (recipes.isEmpty) {
      body = const _SectionNote(
        message: 'No recipe found — not craftable.',
      );
    } else if (loading) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    } else if (error != null) {
      body = _SectionNote(
        message: 'Could not price ingredients.',
        onRetry: onRetry,
      );
    } else {
      final recipe = recipes.first;
      final pricing = CraftPricing.compute(
        recipe: recipe,
        quote: quote,
        ingredientPrices: ingredientPrices ?? const <int, CommerceQuote>{},
      );
      final disc = recipe.disciplines.map(_humanize).join(' · ');
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${disc.isNotEmpty ? '$disc · ' : ''}Makes ${recipe.outputCount}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          for (final line in pricing.lines)
            _KvRow(
              label:
                  '×${line.ingredient.count} ${_ingredientName(app, line.ingredient.itemId)}',
              value: _IngredientPriceLines(line: line),
            ),
          const Divider(),
          if (quote != null)
            _KvRow(
              label: 'Item Buy / Sell',
              value: _BuySellPair(
                buy: pricing.itemBuy == null
                    ? const Text('—')
                    : CoinsText(pricing.itemBuy!),
                sell: pricing.itemSell == null
                    ? const Text('—')
                    : CoinsText(pricing.itemSell!),
              ),
            ),
          _KvRow(
            label: 'Craft cost Buy / Sell',
            value: _BuySellPair(
              buy: pricing.costBuy == null
                  ? const Text('Partial')
                  : CoinsText(pricing.costBuy!,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
              sell: pricing.costSell == null
                  ? const Text('Partial')
                  : CoinsText(pricing.costSell!,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          if (pricing.netBuy != null || pricing.netSell != null)
            _KvRow(
              label: 'Sells for (net) Buy / Sell',
              value: _BuySellPair(
                buy: pricing.netBuy == null
                    ? const Text('—')
                    : CoinsText(pricing.netBuy!),
                sell: pricing.netSell == null
                    ? const Text('—')
                    : CoinsText(pricing.netSell!),
              ),
            ),
          if (pricing.marginBuy != null || pricing.marginSell != null)
            _KvRow(
              label: 'Craft margin Buy / Sell',
              value: _BuySellPair(
                buy: _marginValue(pricing.marginBuy),
                sell: _marginValue(pricing.marginSell),
              ),
            ),
          if (pricing.roiBuy != null || pricing.roiSell != null)
            _KvRow(
              label: 'ROI %',
              value: _BuySellPair(
                buy: _roiValue(pricing.roiBuy, pricing.marginBuy),
                sell: _roiValue(pricing.roiSell, pricing.marginSell),
              ),
            ),
        ],
      );
    }
    return _Card(title: 'Craft', child: body);
  }

  static String _ingredientName(AppState app, int id) {
    try {
      final name = app.meta.lookup(id).name.trim();
      if (name.isNotEmpty && name != 'Item $id') return name;
    } catch (_) {
      // Fall through to the id label.
    }
    return 'Item $id';
  }

  static Widget _marginValue(int? margin) {
    if (margin == null) return const Text('—');
    return CoinsText(
      margin,
      style: TextStyle(
        color: margin >= 0 ? Colors.green : Colors.red,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  static Widget _roiValue(double? roi, int? margin) {
    if (roi == null || margin == null) return const Text('—');
    return Text(
      '${(roi * 100).toStringAsFixed(1)}%',
      style: TextStyle(
        color: margin >= 0 ? Colors.green : Colors.red,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

/// One-line "Buy … · Sell …" pair for the Craft card summary rows.
class _BuySellPair extends StatelessWidget {
  final Widget buy;
  final Widget sell;

  const _BuySellPair({required this.buy, required this.sell});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Buy '),
        buy,
        const Text(' · Sell '),
        sell,
      ],
    );
  }
}

/// Two-line "Buy … / Sell …" value for one ingredient row, with the Vendor
/// marker on the first line the vendor price was used for.
class _IngredientPriceLines extends StatelessWidget {
  final CraftIngredientLine line;

  const _IngredientPriceLines({required this.line});

  @override
  Widget build(BuildContext context) {
    final buyLine = line.buyLine;
    final sellLine = line.sellLine;
    // One marker per row, on the first line the vendor price was used for
    // (Buy preferred).
    final buyMarker = line.vendorUsedBuy;
    final sellMarker = line.vendorUsedSell && !line.vendorUsedBuy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Buy '),
            if (buyLine != null) CoinsText(buyLine) else const Text('—'),
            if (buyMarker) const _VendorTag(),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Sell '),
            if (sellLine != null) CoinsText(sellLine) else const Text('—'),
            if (sellMarker) const _VendorTag(),
          ],
        ),
      ],
    );
  }
}

/// Compact marker for an ingredient line priced from a vendor.
class _VendorTag extends StatelessWidget {
  const _VendorTag();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 6),
      child: Chip(
        label: Text('Vendor', style: TextStyle(fontSize: 11)),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        labelPadding: EdgeInsets.symmetric(horizontal: 6),
      ),
    );
  }
}

class _PositionCard extends StatelessWidget {
  final int itemId;

  const _PositionCard({required this.itemId});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final stacks = [
      for (final e in app.inventory)
        if (e.itemId == itemId) e,
    ];
    final held = stacks.fold<int>(0, (n, e) => n + e.count);
    final locations = {for (final e in stacks) e.location}.length;
    // Aggregate open orders by price: quantity at each price point.
    Map<int, int> byPrice(Iterable<TpOrder> orders) {
      final map = <int, int>{};
      for (final o in orders) {
        if (o.itemId == itemId) {
          map[o.price] = (map[o.price] ?? 0) + o.quantity;
        }
      }
      return map;
    }

    final openBuys = byPrice(app.buys);
    final openSells = byPrice(app.sells);
    final buyPrices = openBuys.keys.toList()..sort((a, b) => b.compareTo(a));
    final sellPrices = openSells.keys.toList()..sort();
    TpTransaction? lastFill;
    for (final t in [...app.soldHistory, ...app.boughtHistory]) {
      if (t.itemId == itemId) {
        lastFill = t;
        break;
      }
    }
    return _Card(
      title: 'Your position',
      child: Column(
        children: [
          _KvRow(
            label: 'Held',
            value: Text(
              '$held · $locations location${locations == 1 ? '' : 's'}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          for (final price in buyPrices)
            _KvRow(
              label: 'Open buy',
              value: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('×${openBuys[price]} '),
                  CoinsText(price,
                      style: const TextStyle(color: Colors.green)),
                ],
              ),
            ),
          for (final price in sellPrices)
            _KvRow(
              label: 'Open sell',
              value: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('×${openSells[price]} '),
                  CoinsText(price,
                      style: const TextStyle(color: Colors.red)),
                ],
              ),
            ),
          if (buyPrices.isEmpty && sellPrices.isEmpty)
            const _SectionNote(message: 'No open orders.'),
          if (lastFill != null)
            _KvRow(
              label: 'Last fill',
              value: CoinsText(lastFill.price),
            ),
        ],
      ),
    );
  }
}
