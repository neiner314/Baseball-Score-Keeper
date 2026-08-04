# Baseball Score Keeper

Baseball scorekeeper for iPhone with all the features you can imagine, and the
ones you can't. Built in SwiftUI — three scoring layouts share one engine,
including a one-handed mode you can use without looking at the screen.

Requires **Xcode 16 or newer** and **iOS 17+**. Open
`BaseballScoreKeeper.xcodeproj` and run — there are no dependencies and nothing
to install.

## The one-handed mode

The whole point of this app is the bottom-corner thumb cluster. It borrows the
flick-input idea from Japanese smartphone keyboards: press a key, options fan
out around your thumb, slide toward one and lift.

```
                      ↑ Call (called strike)
                      │
   HBP ←────────  ● Ball  ────────→ Miss (swinging)
                      │
                      ↓ Foul
```

- **Tap** the pitch pad for a **ball** — the most common single outcome, so it
  costs no travel at all.
- **Flick up** for a called strike, **outward** for a swinging strike,
  **down** for a foul, **inward** for a hit-by-pitch.
- Flicking to a direction with nothing on it **cancels**, so a fumbled drag
  costs nothing.
- Everything is mirrored for left thumbs in Settings.

### Ball in play — the fielder dial

Press the **IN PLAY** pad and drag. A full-screen field appears under your
thumb with all nine positions laid out where they actually stand, so "it went
to left" is a drag toward the upper left rather than a menu item to hunt for.
Each position you cross ticks. Release on one and a result ring appears
centred where your thumb already is, with **OUT** directly under it — the
common case is a tap with no travel, and 1B / 2B / 3B / HR / E / FC / DP fan
out around it.

Turn on **"Dial releases straight to an out"** in Settings and the ring is
skipped entirely: drag, release, done.

### Scoring without looking

- **Haptics carry the information.** A tick as you cross each flick zone, a
  soft thud for a ball, a sharp rap for an out, a rising double-tap for a run.
- **Spoken confirmations** (optional) say the call out loud and duck other
  audio rather than interrupting it, so the game you're listening to keeps
  playing.
- **Undo** is a dedicated pad in the same thumb cluster. A ball in play and its
  result are recorded as one group, so undoing takes them both back.

## The other two layouts

Cycle between layouts with the top-left button, or set a default in Settings.

| Layout | For |
| --- | --- |
| **Pitch-first** | Compact header, thumb cluster, flips to the field on a ball in play |
| **Full sheet** | Everything visible at once — every rare play is one tap, needs two hands |
| **One-handed** | Big scoreboard-style count lights, nothing but the cluster |

Settings decides how much the live screen has to carry. Turning off pitch
velocity, ball location, pitch type or foul counts **removes** those controls
rather than greying them out — fewer things to hit means less looking.

## What it scores

The engine handles a full game, not just the count:

- Balls, strikes, fouls, outs, innings, line score with `X` for a half that was
  never played
- Every batted-ball outcome: hits, fly/ground/line/pop outs, errors, fielder's
  choice, double and triple plays, sacrifice flies and bunts, catcher's
  interference, uncaught third strikes
- Automatic baserunning with sensible defaults, plus per-runner manual
  overrides when the default guessed wrong
- Stolen bases, caught stealing, pickoffs, balks, wild pitches, passed balls
- Substitutions: pinch hitters, pinch runners, defensive changes, pitching
  changes and position switches, with the DH handled correctly (the pitcher
  never enters the batting order)
- Box score: batting lines with per-at-bat notation (`0-for-3 · K, F5, 6-3`),
  pitching lines with IP/H/R/ER/BB/K/pitches, and win / loss / save
- Standard scorebook notation — `6-3`, `F8`, `3U`, `4-6-3 DP`, `K`, `ꓘ`, `SF8`

### Architecture

```
Models/    Plain value types — no UI, nothing beyond Foundation
Engine/    ScoringEngine, BoxScoreBuilder, Notation — pure functions
Store/     GameStore (the only mutable thing) + file persistence
Design/    Theme, Haptics, Announcer, field geometry
Features/  One directory per screen
```

The engine is a **pure function of an append-only event log**. The UI never
edits game state; it appends events, and state is whatever the log adds up to.
That's what makes undo a matter of dropping the last event and replaying, and
it's why the box score can be rebuilt from scratch at any moment.

## Tests

`⌘U` in Xcode, or:

```sh
xcodebuild test -scheme BaseballScoreKeeper \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Roughly 60 tests cover the engine (count handling, forced advancement, the
third-out rule that cancels runs, earned vs. unearned runs, walk-offs, extra
innings, substitutions), scorebook notation, the box score and decision
assignment, and the flick-direction and dial hit-testing maths.

## Known simplifications

Deliberate v1 choices, all overridable by the scorer:

- **Runner advancement** uses conventional defaults (everyone up one on a
  single, two on a double). A runner who takes an extra base needs a manual
  override from the full sheet layout.
- **Double plays** default to the 6-4-3 shape — the batter and the runner on
  first. Any other combination is a manual override.
- **Earned runs** use the standard approximation: a run is unearned if the
  runner reached on an error, or if it scored after the inning's third out
  *should* have been made. Full inning reconstruction (replaying the half as if
  the defence were flawless) is not done.
- **Win / loss / save** follow the decisive-run rule, the five-inning
  requirement for a starter, and the standard save conditions. Unusual cases —
  a scorer's discretionary win between two equally effective relievers — may
  need a manual correction.
