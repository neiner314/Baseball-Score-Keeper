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
                      ↑ Foul (tipped up and back)
                      │
  Ball ←────────  ● tap = in play  ────────→ Miss (swinging)
                      │
                      ↓ Call (called strike)

              press and hold  =  hit by pitch
```

**Balls flick left, strikes flick right**, the way a count is written and read
everywhere in baseball — a full count is 3-2, not 2-3. Ball is the only
leftward gesture on the pad; everything else is a strike.

The vertical axis is mimetic rather than notational. **Foul is up**, because a
tipped ball flies up and back over the catcher — the flick traces where the
ball actually went. **Called strike is down**: nothing moved, the ball just
settled in the zone.

Together the four flicks are the four things a pitch can do, which is what
makes them recallable without looking:

| Flick | Outcome | |
| --- | --- | --- |
| ← | Ball | no swing, out of the zone |
| ↓ | Called strike | no swing, in the zone |
| → | Swinging strike | swung and missed |
| ↑ | Foul | swung and caught a piece of it |

That mapping is deliberately **not** mirrored for left-handed scorers. The
cluster moves to whichever corner your thumb lives in, but ball stays left and
strike stays right for everyone, because the gesture stands in for the
scoreboard, not for the hand.

- **Tap** = the ball was put in play (see below).
- **Press and hold** ≈ half a second = hit by pitch. It's rare, it ends the
  plate appearance, and undoing one you triggered by accident is exactly the
  interruption this app exists to avoid — so it's on a gesture you can't
  stumble into. The pad fills a ring the whole time you hold, turns purple,
  and double-thumps when it arms; sliding away at any point disarms it and
  hands the gesture back to the flick directions.
- Flicking to a direction with nothing on it **cancels**, so a fumbled drag
  costs nothing.
- At rest the pad wears four small dots in the flick colors on its rim, so the
  mapping is readable before you ever press it.

### Ball in play — the fielder dial

Two ways in, the same duality iOS menus have:

- **Tap** — either the pitch pad or the **IN PLAY** pad. The dial latches open
  and waits for a second, deliberate tap on a fielder. Nothing is written
  until you pick one, so a stray tap costs a dismissal rather than an undo.
- **Press the IN PLAY pad and drag** — the dial tracks your finger. Release on
  whoever is lit.

Either way a field appears in the lower third of the screen, inside the thumb's
arc, with all nine positions laid out where they actually stand — so "it went
to left" is a move toward the upper left rather than a menu item to hunt for.
Each position you cross ticks.

Then a result ring appears centred where your thumb already is, with **OUT**
directly under it — the common case is a tap with no travel — and 1B / 2B / 3B
/ HR / E / FC / DP fanned around it.

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

### Challenging a ball or strike

The moment you record a ball or a called strike, a **Challenge** prompt appears
— and it disappears as soon as the next pitch does. That's not a UI shortcut,
it's the rule: challenges have to be immediate, so if the prompt isn't on
screen the window has closed. Swings, fouls and balls in play never show it;
they aren't umpire judgements about the strike zone, so there's nothing to
review.

Tapping it opens a bottom-anchored sheet: who challenged (batter, pitcher or
catcher — the only three who may), and how it came back. The header shows the
correction that's at stake, e.g. `Called strike → Ball`.

- **Overturned** — the call is corrected and the team **keeps** the challenge.
- **Call stands** — the team is **charged** one.

The challenging team is derived from who asked: the batter challenges for the
side at bat, the pitcher and catcher for the side in the field. Each team
starts with two, and any team that has run out gets one back on reaching extra
innings.

**A won challenge really does rewind the game.** Win one on ball four and the
walk un-happens — the runner comes off first, the same batter is back up, and
the count reads 3-1. Win one on strike three and the out comes off the board.
A correction that ends the at-bat works the same way in reverse: overturn a
ball into strike three and the strikeout is recorded. Corrected pitches keep a
flag in the sequence strip so the change is visible rather than silent, and the
box score lists every challenge with who made it, when, and whether it was won.

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
- Ball-strike challenges, including the correction rewinding a walk or a
  strikeout that the original call had already produced
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

Challenges are where that design pays for itself. A won challenge is resolved
by **rewriting the pitch it points at and replaying**, rather than trying to
unwind a walk or a strikeout inside a running fold. The count, the plate
appearance, the batting order and the box score all come out right for free —
and undoing the challenge un-corrects the pitch just as automatically, because
the correction only ever existed in the resolved stream.

## Tests

`⌘U` in Xcode, or:

```sh
xcodebuild test -scheme BaseballScoreKeeper \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Roughly 100 tests cover the engine (count handling, forced advancement, the
third-out rule that cancels runs, earned vs. unearned runs, walk-offs, extra
innings, substitutions), scorebook notation, the box score and decision
assignment, the flick-direction and dial hit-testing maths, the pitch pad
mapping — including that hit-by-pitch is unreachable by any flick — and
challenges, including a won challenge on ball four unwalking the batter and on
strike three erasing the out.

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
- **Challenge rules** are configurable in `GameRules` because leagues differ:
  `challengesPerTeam` (2), `challengeRetainedWhenOverturned` (true) and
  `extraInningsChallengeGrant` (1 to any team that has run out). Set
  `challengesPerTeam` to 0, or turn the setting off, for leagues that don't
  review calls at all. A challenge is only allowed against the pitch it
  immediately follows, which is both the rule and what keeps the correction
  unambiguous.
