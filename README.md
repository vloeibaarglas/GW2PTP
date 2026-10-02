# TP Console

A personal Guild Wars 2 Trading Post companion for Android. Three screens,
no market data, no valuation — just your account's live Trading Post state:

- **Inventory** — searchable list of every stack across bank, materials,
  shared inventory slots, and character bags.
- **TP Held** — coins and items waiting in the delivery box.
- **TP Buy/Sell** — open orders valued at their listed prices (sells show
  net proceeds after the 15% cut).

## Sync modes

- **Passive** (default): fetches when the app opens. The banner shows data
  age and turns into a stale warning past an hour. Minimal battery use.
- **Active**: a foreground service pings the API every 1–60 minutes
  (user-chosen) and posts a notification for every filled buy/sell order.
  Uses more battery — the settings screen says so, and prompts to disable
  battery optimization. Note: on Android 15+, the system caps background
  data-sync at 6 h/day; opening the app resets the timer.

## Key handling

The GW2 API key lives in the Android Keystore via `flutter_secure_storage`.
It is validated against the API before being stored, shown only as
`********` in Settings, and never logged.

## Item icons

Loaded from `render.guildwars2.com` on demand and cached on disk forever
(render URLs are content-hashed, so they never go stale). Nothing is
bundled — the APK stays small.

## API footprint

Per open (passive): wallet, delivery, current buys/sells, bank, materials,
shared inventory, characters + one inventory call per character, and item
metadata only for uncached ids. Per active tick: history buys/sells only
(fill detection), ~2 calls.

No market-price, listing-book, or history-chart calls anywhere.

## Build

```sh
flutter pub get
flutter analyze   # must be clean (flutter_lints, same bar as Sundown)
flutter test
flutter build apk --debug
```

## Releases

Releases are cut by hand from the Actions tab: the **Release APK**
workflow (`workflow_dispatch` only — never on push/PR) lints, tests,
builds the release APK, and uploads it as an artifact named
`gw2-ptp-<sha8>.apk` with a matching `.sha256` file.

Release builds are debug-signed (Flutter template default). The signing
key lives at `android/debug.keystore` in this repo — it is the identity of
every installed build, so the same key must sign every release or the APK
won't install as an update. CI restores it to `~/.android/debug.keystore`
before building; the sandbox `rebuild.sh` does the same. Do not lose it.
