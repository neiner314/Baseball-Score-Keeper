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
  and lets you tap out the whole fielding chain, then commit it. Nothing is
  written until you do, so a stray tap costs a dismissal rather than an undo.
- **Press the IN PLAY pad and drag** — the dial tracks your finger. Release on
  whoever is lit; that's a one-fielder chain, straight to the result ring.

Either way a field appears in the lower third of the screen, inside the thumb's
arc, with all nine positions laid out where they actually stand — so "it went
to left" is a move toward the upper left rather than a menu item to hunt for.
Each position you cross ticks.

Then a result ring appears centred where your thumb already is, with **OUT**
directly under it — the common case is a tap with no travel — and 1B / 2B / 3B
/ HR / E / FC / DP / TP / SF / SH fanned around it.

Turn on **"Drag straight to an out"** in Settings and the ring is skipped for
the drag gesture entirely: drag, release, done.

#### The fielding chain

Tapping the dial open puts it in chain mode, and every tap **appends**. Tap 6,
then 4, then 3 and you get `6-4-3`. Tap 3 then 1 and you get `3-1`. Tap
6-4-3-2-5-1-6 and that is exactly what goes in the book — there is no cap and
no assumed shape. Each fielder picks up a numbered badge as you go, the path is
drawn on the field, and `⌫` takes back the last one.

A chain of one is completed the way a scorer would assume: a grounder to short
becomes `6-3`, a fly to centre stays `F8`, a grounder the first baseman handled
himself stays `3U`. **A chain of two or more is never second-guessed** — `6-4`
stays `6-4` rather than growing a throw to first that never happened.

The one-gesture drag path is unchanged and still costs one motion: it enters a
one-fielder chain and goes straight to the ring.

#### Balls nobody fielded

A home run can't be attributed to a fielder, so it doesn't have to be. With the
dial open and nothing tapped, the primary button reads **"NOBODY FIELDED IT"**
and opens a ring of 1B / 2B / 3B / HR only. Every outcome that genuinely needs
someone to have touched the ball still requires a chain.

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
starts with two. In extra innings any team that has run out is topped back up
to one at the start of every inning — it repeats each frame, it doesn't
accumulate, and a team still holding a challenge gets nothing extra, so both
sides always have exactly one available.

**A won challenge really does rewind the game.** Win one on ball four and the
walk un-happens — the runner comes off first, the same batter is back up, and
the count reads 3-1. Win one on strike three and the out comes off the board.
A correction that ends the at-bat works the same way in reverse: overturn a
ball into strike three and the strikeout is recorded. Corrected pitches keep a
flag in the sequence strip so the change is visible rather than silent, and the
box score lists every challenge with who made it, when, and whether it was won.

## Importing rosters and lineups

Typing twenty-six names before first pitch is the worst part of scorekeeping,
so **New Game → Import a game** pulls both rosters and the posted lineup off
the league feed. After that a pinch runner or a pitching change is picking a
name off a list — a pitching change narrows the list to pitchers, because
that's the only thing you're choosing between.

Where the data comes from, honestly:

| League | Rosters & lineups | Official scoring |
| --- | --- | --- |
| **MLB** | Live, from MLB's public Stats API — no key, no account | Yes |
| **NPB** | Paste a roster file | No |
| **KBO** | Paste a roster file | No |
| Anything else | Paste a roster file | No |

**Only MLB publishes a free feed.** NPB and the KBO put rosters on the web but
not behind an API — there are community scrapers and paid commercial feeds,
neither of which belongs baked into an app like this. So those leagues import
from text instead: one line per player as `number, name, position`, pasted
once per team and reusable all season. It's two minutes of copy-paste against
a lifetime of typing lineups, and it doesn't break when someone's website
changes.

MLB data usage is subject to
[MLB's copyright notice](http://gdx.mlb.com/components/copyright.txt), which
permits individual, non-commercial use. Fine for keeping score; not fine for
shipping commercially without their written permission.

## Checking yourself against the official scorer

For an imported MLB game, the seal button pulls the official play-by-play back
and diffs it against what you scored:

```
                    94%
          47 of 50 plays match

  Top 4   Chisholm Jr.
          You scored single; official is error
          Chisholm Jr. reaches on a fielding error by the shortstop.
```

It compares the *call*, not the paperwork — hit versus error versus fielder's
choice, and RBI counts. Disagreeing about whether the chain was 6-3 or 6-4-3
isn't interesting; disagreeing about whether that was a hit is. Plays are
aligned within each half-inning, so one missed play throws off that half and
nothing after it, and anything you missed or invented is called out as such.

## The scorebook

The `⊞` button in the top strip opens the page itself: rows are batting-order
slots, columns are innings, and each box carries the notation plus a diamond
shaded as far as that runner got.

It behaves like paper. The box is written when the at-bat ends — `1B` — and
then **keeps filling in** as later batters move the runner along, closing all
four sides when they score. A stranded runner gets the open circle, a runner
thrown out on the bases gets a grey path, the batter's out number goes in the
top-left corner and RBIs in the bottom-right. Tap any box for it in words.

It is built by replaying the log through the same engine the live screen uses
and writing down what happens to the bases — it re-implements no rules of its
own. A slot that bats around in one inning gets two boxes and the column
widens.

The live screen carries the same information at a glance: a **base diamond**
that fills as runners reach, both teams' runs in large type with the batting
side highlighted, and count and outs as pips.

## The other layout

Flip between the two with the top-left button, or set a default in Settings.

| Layout | For |
| --- | --- |
| **One-handed** | Thumb cluster in the bottom corner, scored without looking |
| **Full sheet** | Everything reachable at once on one fixed screen, two hands |

There were three. Two of them were the same one-handed screen with a different
readout on top, which is a setting rather than a layout, so they're now one.
Saved games carrying the retired values migrate on load rather than failing to
decode.

**The full sheet does not scroll.** Header, pitch buttons, field, results and
the baserunning rail are all fixed rows, and the field absorbs whatever height
is left over — so the same screen composes on an SE and a Pro Max without a
scroll view. Results are laid out the way a scorer thinks: everything that puts
the batter on base in one row, everything that retires him in the row below,
fourteen outcomes with nothing hidden.

Velocity and pitch type are menus in the bottom rail rather than rows of chips.
Two taps instead of one, for the two things nobody logs every pitch, and ninety
points of screen back.

Settings decides how much the live screen has to carry. Turning off pitch
velocity, ball location, pitch type or foul counts **removes** those controls
rather than greying them out — fewer things to hit means less looking.

On the one-handed screen they live in a collapsed rail just above the thumb
cluster rather than open in the middle of the screen. Collapsed, it still shows
what's armed for the next pitch.

## Look

Dark by default, and neutral on purpose: near-black greys with no tint, so the
six action colors — ball, called strike, swinging strike, foul, in play, hit by
pitch — are the only saturated things on screen. If everything is colorful,
nothing reads at a glance. Light and System are both available under
Settings → Appearance.

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
Engine/    ScoringEngine, BoxScoreBuilder, ScorebookBuilder, Notation — pure functions
League/    Roster providers, league feeds, file import
Verify/    Official-scoring comparison
Store/     GameStore (the only mutable thing) + file persistence
Design/    Theme, Haptics, Announcer, field geometry
Features/  One directory per screen
```

`RosterProvider` is a protocol with one conformance today. A league with no
API is a *missing conformance*, not a special case threaded through the app —
which is why NPB and the KBO cost nothing to support badly now and will cost
one file to support properly if a feed ever appears.

The engine is a **pure function of an append-only event log**. The UI never
edits game state; it appends events, and state is whatever the log adds up to.
That's what makes undo a matter of dropping the last event and replaying, and
it's why the box score can be rebuilt from scratch at any moment.

The scorebook leans on the same property from the other direction. Rather than
re-deriving where runners went, `ScorebookBuilder` replays the log through the
engine and records what the engine did to the bases after each event — so the
page can never disagree with the live screen about who scored.

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

Roughly 190 tests cover the engine (count handling, forced advancement, the
third-out rule that cancels runs, earned vs. unearned runs, walk-offs, extra
innings, substitutions), scorebook notation, the box score and decision
assignment, the flick-direction and dial hit-testing maths, the pitch pad
mapping — including that hit-by-pitch is unreachable by any flick — and
challenges, including a won challenge on ball four unwalking the batter and on
strike three erasing the out. The import layer is covered at its pure edges:
roster-file parsing, position-code mapping, play-by-play mapping, and the
official-scoring diff.

The fielding chain is pinned end to end — `3-1`, `6-4`, `6-4-3 DP`,
`5-4-3 TP`, `3U`, `F8`, the seven-link rundown, and that a home run builds with
no fielder while everything that needs one refuses to. The scorebook page has
its own tests for the part most likely to be subtly wrong: that a box opened as
a single closes as a run two batters later, that a stranded runner is marked
left on base rather than thrown out, and that a runner erased on a double play
is marked the other way round.

**The network calls themselves are not covered, and have never run.** The
container this was built in blocks `statsapi.mlb.com` at the egress proxy, so
every MLB request path has never touched the real API. Field shapes were
written from community documentation and then cross-checked field-by-field
against [python-mlb-statsapi](https://github.com/zero-sum-seattle/python-mlb-statsapi)'s
typed models, which agree on the play-by-play and boxscore structures.

The two sources *disagree* about whether a few values are strings or numbers
(jersey numbers, position codes, batting-order slots). Since `decodeIfPresent`
throws on a type mismatch rather than yielding nil, guessing wrong would fail
an entire boxscore rather than drop one field — so those decode from either,
via `MLBStatsDTO.LooseString`. Still: run one import against a live game before
trusting any of it.

## Known simplifications

Deliberate v1 choices, all overridable by the scorer:

- **Runner advancement** uses conventional defaults (everyone up one on a
  single, two on a double). A runner who takes an extra base needs a manual
  override from the full sheet layout.
- **Double plays** record whatever chain you tap. Which *runners* they erase
  still defaults to the 6-4-3 shape — the batter and the runner on first — and
  any other combination is a manual override. The notation and the outs are
  independent: `3-6-3 DP` writes correctly, but who it retired is still the
  default pair unless you say otherwise.
- **Earned runs** use the standard approximation: a run is unearned if the
  runner reached on an error, or if it scored after the inning's third out
  *should* have been made. Full inning reconstruction (replaying the half as if
  the defence were flawless) is not done.
- **Win / loss / save** follow the decisive-run rule, the five-inning
  requirement for a starter, and the standard save conditions. Unusual cases —
  a scorer's discretionary win between two equally effective relievers — may
  need a manual correction.
- **Challenge rules** follow MLB's 2026 ABS system and are configurable in
  `GameRules` because leagues differ: `challengesPerTeam` (2),
  `challengeRetainedWhenOverturned` (true) and `extraInningsChallengeGrant`
  (1, applied each extra inning to any team that has run out). Set
  `challengesPerTeam` to 0, or turn the setting off, for leagues that don't
  review calls at all. A challenge is only allowed against the pitch it
  immediately follows, which is both the rule and what keeps the correction
  unambiguous.
