#!/usr/bin/env python3
"""Generate lib/store/vendor_prices.dart from the GW2 Trading web app's
vendor price snapshot.

Vendor buy prices are NOT available from the official GW2 API (there is no
vendor/merchant endpoint; /v2/items `vendor_value` is what a vendor pays
*you*, the opposite direction), so the app bakes them in as a static map.
Merchant prices change only when ArenaNet changes them, and the set is
tiny (170 entries), so a build-time snapshot is the right trade — no
network code, no backend client, the app stays official-API-only.

Source: the web repo's vendor_prices.json (cheapest coin-only Merchant
offer per item, built from Peureki's recipes.json). Refresh by re-running
this script after the web snapshot is regenerated.

Usage:
    python3 tool/generate_vendor_prices.py [--source PATH] [--output PATH]
"""

import argparse
import json
import math
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SOURCE = (
    REPO_ROOT.parent
    / "gw2trading"
    / "backend"
    / "app"
    / "data"
    / "vendor_prices.json"
)
DEFAULT_OUTPUT = REPO_ROOT / "lib" / "store" / "vendor_prices.dart"


def round_copper(value: float) -> int:
    # Round half up (matches Dart's double.round()); Python's round() is
    # banker's rounding and would differ on exact .5 values.
    return math.floor(value + 0.5)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    with args.source.open() as f:
        raw = json.load(f)
    entries = raw["prices"] if isinstance(raw, dict) else raw

    prices: dict[int, int] = {}
    for row in entries:
        item_id = int(row["item_id"])
        copper = round_copper(float(row["unit_copper"]))
        if item_id <= 0 or copper <= 0:
            raise ValueError(f"bad entry: {row!r}")
        if item_id in prices:
            raise ValueError(f"duplicate item_id: {item_id}")
        prices[item_id] = copper

    generated = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    source_label = Path(os.path.relpath(args.source.resolve(), REPO_ROOT))
    lines = [
        "/// Vendor buy prices, baked in as a static map.",
        "///",
        "/// Generated — do not edit by hand. Re-run",
        "/// `python3 tool/generate_vendor_prices.py` to refresh from the",
        "/// GW2 Trading web app's vendor snapshot",
        f"/// ({source_label}, {len(prices)} entries, generated {generated}).",
        "///",
        "/// The official GW2 API has no vendor/merchant endpoint, so these",
        "/// prices cannot be fetched at runtime. A missing entry means",
        "/// \"no vendor price\", never 0.",
        "///",
        "/// Vendor stock is unlimited, so a vendor price caps the cost of",
        "/// an ingredient on both the buy-order and instant-buy bases.",
        "library;",
        "",
        "const Map<int, int> kVendorPrices = {",
    ]
    for item_id in sorted(prices):
        lines.append(f"  {item_id}: {prices[item_id]},")
    lines.append("};")
    lines.append("")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(lines))
    print(
        f"wrote {args.output} ({len(prices)} entries, "
        f"{min(prices.values())}c–{max(prices.values())}c)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
