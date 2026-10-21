# GW2 Personal Trading Post

An Android companion for Guild Wars 2 traders. Your account's live Trading
Post state — inventory, delivery box, open orders, and fill history — plus
per-item market data, in one fast, private app.

## Features

- **Inventory** — every stack across your bank, crafting materials storage,
  shared inventory slots, character bags, and equipped gear. Full-text
  search with type, rarity, sellable, and bound filters.
- **TP Held** — coins and items waiting in the delivery box, plus your full
  **Sold** and **Bought** fill history: filter by time window (1H / 6H /
  12H / 24H, or a day dial up to 30D), group by transaction, item, or price
  point, and sort by newest or highest price. History is capped at the 25,000
  most recent transactions per side, with a coverage notice when the cap
  bites.
- **TP Buy/Sell** — open buy and sell orders (your listings) valued at
  their listed prices; sells also show net proceeds after the 15% Trading
  Post fee. Group by order, item, or price point; sort by listing order or
  highest price.
- **Item details** — tap any item (or its icon) for live buy/sell prices,
  order-book depth, crafting recipes with profitability, and price history.
- **Fill notifications** (optional) — get notified the moment a buy or sell
  order fills, without opening the app.

## Getting started

1. Install the latest APK from
   [Releases](https://github.com/vloeibaarglas/GW2PTP/releases)
   (or build it yourself — see below).
2. Create a Guild Wars 2 API key at
   <https://account.arena.net/applications> with these permissions:
   - `wallet` — coin balance
   - `tradingpost` — delivery box, open orders, and fill history
   - `inventories` — bank, materials, shared slots, bags, equipped gear
   - `characters` — character list (needed to load bags and gear)
3. Paste the key into the app's Settings. It is validated against the API
   before being stored, and the app warns you if any permission is missing.

## Sync modes

- **Passive** (default): fetches when the app opens. The banner shows data
  age and turns into a stale warning past an hour. Minimal battery use.
- **Active**: a foreground service pings the API every 1–60 minutes
  (your choice) and posts a notification for every filled buy/sell order.
  Uses more battery — the settings screen says so, and prompts you to
  disable battery optimization. Note: on Android 15+, the system caps
  background data-sync at 6 h/day; opening the app resets the timer.

## Privacy & security

- Your API key lives in the Android Keystore via `flutter_secure_storage`.
  It is shown only as `********` in Settings and never logged.
- No accounts, no analytics, no tracking. Your data never leaves the
  device except to the services below, and only to fetch *your* data.

## API footprint

The app talks to three public services and nothing else:

- `api.guildwars2.com` — wallet, delivery box, orders, inventories,
  characters, item metadata (metadata is cached; only uncached ids are
  fetched).
- `www.gw2bltc.com` — price-history charts on the item details page.
- `render.guildwars2.com` — item icons, cached on disk (render URLs are
  content-hashed, so cache entries never go stale).

Per open (passive): wallet, delivery, current buys/sells, bank, materials,
shared inventory, characters + one inventory call per character. History
syncs are incremental — refreshes stop at the first already-known page —
and range widening fetches concurrently in batches.

## Build from source

```sh
flutter pub get
flutter analyze   # must be clean (flutter_lints)
flutter test
flutter build apk --release
```

Release APKs are cut from the Actions tab (`workflow_dispatch`). The
`android/debug.keystore` in this repo is the standard public Android debug
key — it exists so local debug builds install cleanly; release signing
uses a separate key configured outside the repo.

## Tech

Flutter + Dart, `provider` for state. No backend, no build flavors beyond
the standard debug/release split.

## Disclaimer

Not affiliated with ArenaNet or NCSoft. Guild Wars 2 © ArenaNet, LLC.
Market data on the item details page is provided by third-party services.
