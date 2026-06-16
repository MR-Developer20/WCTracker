# WC Tracker
(Disclaimer: 100% by Claude Code, not a flex I'm just dumb)

An iPad-first **second-screen companion** for the FIFA World Cup 26 — built to sit on
a tablet beside the TV. Landscape layout:

- **Top edge** — broadcast scoreboard (the WorldCup26Widget scorebug look, in SwiftUI)
  for the focused match.
- **Left 2/3** — a live football pitch: both teams' starting XI placed in their real
  formation (names + numbers), with the ball moving per play.
- **Right 1/3** — match data: goals, team stats, stadium, and local weather.

Bundle id `marxthings.wcmatchtracker` · display name **WC Tracker** · iOS 26+, iPad + iPhone (landscape).

## Data sources (free)

| Data | Source |
|------|--------|
| Scores, lineups, events, team stats, venue | **ESPN** free site API (`site.api.espn.com/.../soccer/fifa.world`), `summary?event={id}` |
| Weather | **Apple WeatherKit** (default) · **Open-Meteo** switchable in Settings |

### A note on the ball

No free (or affordable) API provides live player/ball **tracking** coordinates — those
are enterprise feeds (Opta/Sportradar). So both modes place players by their real
formation and move the ball from the **event feed** (it heads toward a goal on
shots/goals), labeled as estimated on the pitch:

- **Live mode** — the current/most-recent **2026** match; the ball reacts to new events as
  they come in.
- **Replay mode** — pick any **finished 2026 match** and step through its real event
  timeline (goals, cards, subs) with play / pause / scrub. (StatsBomb open data, which has
  true x/y, only covers up to the 2022 World Cup, so it can't drive a 2026 replay.)

## Demo mode (testing)

Turn on **Settings → Testing → Demo mode** (or launch with the `--demo` argument) to load a
self-contained sample match — France 2–1 Senegal — with full lineups in formation, goals,
team stats, stadium, weather, a live-ticking scoreboard clock, and a ball that moves around
the pitch. No network or live match required.

The demo **cycles through every clock state** (~8s each) so you can verify them:
1st half → 1st-half added time (45:00 hold + "+2") → **Half time (HT)** → 2nd half (teams
switch ends) → 2nd-half added time (90:00 hold + "+6") → **Full time (FT)**, then loops. The
current state is shown on the **DEMO ·** chip in the top bar. These match the WorldCup26Widget
scorebug exactly and are driven by the live ESPN feed in normal mode.

## Weather (WeatherKit)

WeatherKit is the default provider and is provisioned for this bundle id. It returns live
data when the app runs **signed under the owning Apple Developer team**. If WeatherKit is
unavailable on the current device/simulator, WC Tracker **auto-falls back to Open-Meteo**
and shows the active source on the weather card. You can also force Open-Meteo in
**Settings → Weather → Source**.

## Build & run

The active `xcode-select` here points at Command Line Tools, so set `DEVELOPER_DIR`:

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer

# Compile only (no simulator):
xcodebuild -project WCTracker.xcodeproj -scheme WCTracker \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

To run: open `WCTracker.xcodeproj` in Xcode, select your team under
**Signing & Capabilities** (the WeatherKit capability is already in
`WCTracker/WCTracker.entitlements`), pick an iPad simulator (e.g. *iPad Pro 13-inch*)
or a device, and Run.

It's the **2026 World Cup window**, so the app opens on a real match by default (focus =
live match, else the most recent result). Use the stack icon (top-right) to pick a
different match, or the **Replay** toggle for the StatsBomb true-coordinate mode.

## Project layout

Single iOS app target, Xcode synchronized folder (drop a `.swift` in `WCTracker/` to add it):

- `Models.swift`, `ESPNClient.swift`, `Theme.swift` — ported pure-Swift data layer + brand palette.
- `MatchDetail.swift` — detail models, formation→pitch layout, ball estimator, ESPN summary parser.
- `MatchCenterServices.swift` — ESPN summary, weather (WeatherKit/Open-Meteo), StatsBomb.
- `TournamentStore.swift` / `MatchCenterStore.swift` — scoreboard polling + focus/detail/weather/replay state.
- `PitchView.swift`, `MatchInfoPanel.swift`, `SecondScreenView.swift`, `SettingsView.swift` — UI.
- `WCTrackerApp.swift` — `@main`.
