# Foosball Shootout — Arcade Foosball for Playdate

**Date:** 2026-07-10\
**Status:** Approved design, pending implementation plan\
**Target:** Playdate SDK 3.0.6 (Lua), simulator first, device later

## Overview

An arcade shootout, not a full foosball sim. The camera sits behind your
player figure looking down the pitch at a distant goal and goalie. A ball is
served toward you along a randomized lane; you slide left/right on the d-pad
to line up with it, then flick the crank to strike when it arrives. Endless
streak mode: score, and the next ball comes; get saved or whiff, and your
streak resets. The goalie gets tougher the longer your streak runs. Best
streak persists across sessions.

## Goals

- A single, legible skill loop: line up, time the flick, place the shot.
- Real tension between intercepting the ball and placing the shot well —
  aim is derived from exactly where you make contact, not a separate input.
- A goalie that reacts fairly (only after you've committed to a shot) but
  gets genuinely harder to beat as your streak grows.
- Sprite art for the characters (player, goalie, ball) over a code-drawn
  pitch, and synthesized audio, matching submariner's audio approach but not
  its zero-image-assets rule.

## Non-Goals (v1)

- Multiplayer, full multi-rod table simulation, passing or rebounds.
- Wide/crossbar misses — shot aim is always clamped to land somewhere in the
  goal frame; the only failure modes are a save or a whiff before contact.
- Difficulty modes/settings, online leaderboards.
- A day/night or venue-variety layer — one pitch, one look.

## Controls

| Input | Action |
|---|---|
| D-pad left/right | Slides the player along the track (foreground). Position at the moment of contact also sets fine shot aim. |
| Crank flick | A fast crank motion during the contact window strikes the ball. Flick speed sets shot power. |
| Crank docked | Crank indicator shown (same convention as submariner); no shots possible while docked. |
| A / B | Dismiss the title/instructions screen. Unused during play in v1. |

## Screen Layout & Coordinate Model

- Screen 400×240, 1-bit. Code-drawn pitch as a converging trapezoid: wide at
  the bottom (near edge, the player's end) narrowing toward the goal line
  near the top of the screen.
- **Track (player):** a horizontal x-range at the near edge, e.g. x ∈
  [50, 350] (300px). The player sprite sits at a fixed y near the bottom,
  large scale (foreground).
- **Goal (far edge):** a narrower x-range near the top, e.g. x ∈ [140, 260]
  (120px). The goalie sprite moves along this same range — since shot aim
  is always clamped inside the goal frame (no wide misses, see Non-Goals),
  the goalie never needs to defend outside the posts either. Small scale
  (background), consistent with submariner's "distance = smaller + higher
  on screen" depth cue.
- **Ball:** one `progress` value p ∈ [0, 1] per serve drives both position
  and scale. The ball's *lane* is fixed in track-space, but its on-screen x
  converges toward the lane's goal-space image as it recedes
  (`Geom.projectX`, mapping [50, 350] onto [140, 260] at the goal line) —
  at p=0 it sits between the posts, at p=1 it is exactly at lane x on the
  track; `ball.y` and `ball.scale` interpolate from the goal end (p=0,
  small/high) to the player's track (p=1, large/low). Pure math in
  `geom.lua` (`lerp`, `projectX`), same spirit as submariner keeping
  projection math SDK-free and testable.

## Shot Mechanics — the Core Loop

Each serve:

1. A ball approaches along a randomized lane x (within the track range) over
   `T_serve` ≈ 1.6s, growing larger and closer as `p` goes 0→1.
2. A **contact window** opens for the final ~18% of the approach
   (`p ∈ [0.82, 1.0]`).
3. A **contact band** ~90px wide, centered on the serve lane x, defines how
   close the player must be to touch the ball at all.
4. If the player is inside the band and flicks the crank past a velocity
   threshold (900°/s, measured over a short rolling window of
   `playdate.getCrankChange()` samples) *while the window is open*, contact
   registers:
   - **Aim** = the player's exact x-position within the band at that instant
     — not just "in range," but precisely where, so lining up isn't binary.
   - **Power** = measured flick speed normalized against a reference velocity
     of 1800°/s, clamped to [0.5, 1.0] — 0.5 is the power at exactly the
     900°/s threshold velocity, so there's no lower floor to reach below
     that; a sub-threshold flick never registers as a strike in the first
     place.
5. Flicks before the window opens are simply not evaluated yet — winding up
   early costs nothing; only the flick's state once the window is open
   matters, so a sustained fast spin carried into the window still registers.

Two ways to whiff (streak resets to 0, with distinct feedback each):

- Flicking while outside the contact band during the window ("missed the
  ball").
- The window closing with no qualifying flick at all ("too slow").

On contact, the ball transitions to a short flight back toward the goal over
`T_shot`, which shortens from 0.55s at minimum power to 0.22s at maximum
power — harder shots leave the goalie less time to react.

## Goalie & Difficulty

The goalie has no information before contact — it only starts moving once
your shot's target x is known, which keeps it feeling fair rather than
psychic. It moves toward that target at `min(60 + 4 × streak, 100)` px/s
(base 60px/s, ramping 4px/s per streak point, capped at 100px/s — the ramp
reaches its cap right around streak 10). It rests at center between serves,
so the worst case for the player is a maxed-out goalie already centered
when a maximum-power shot is aimed at either post — 60px away, half the
120px goal width.

The save check isn't "did the goalie reach the exact target x" — it's
`Geom.inBand(goalieX, shotTargetX, saveRadius)`, a save radius of 26px
standing in for the goalie's reach around its center. That radius is free
coverage the goalie doesn't have to travel for, so the distance it actually
needs to *close* is `60 − 26 = 34px`, not the full 60. At max difficulty and
max power, it can close `100 × 0.22 ≈ 22px` — short of the 34px it needs,
leaving a persistent ~12px gap near each post that's unreachable even at
max difficulty. (An earlier draft of these constants — 140/8/220 — sized
the goalie speed against the full 60px, missing the save radius entirely;
with a 26px save radius that math was wrong regardless of top speed,
since even 220px/s comfortably closes the true 34px gap. Any future
retuning of `Field.SAVE_RADIUS`, the goal width, or these speed constants
must re-derive the "always beatable" margin from `halfGoalWidth −
saveRadius`, not `halfGoalWidth` alone.) Exact constants are starting
points, to be tuned by playtesting like submariner's.

- Streak +1 on a goal.
- Streak resets to 0 on a save or either whiff type.
- Best streak is written to `playdate.datastore` whenever the current streak
  exceeds it, and shown alongside the live streak in the HUD.

## Visuals & Audio

- Pitch, goal frame, and HUD: code-drawn, dithered, matching submariner's
  1-bit rendering approach (`setInk(darkness)` helper reused).
- Player, goalie, and ball: image sprites (assets allowed for this project,
  unlike submariner). Ball likely needs a couple of scale variants or a
  single scalable draw call, tuned during implementation.
- Audio, synthesized via `playdate.sound` (no audio files), mirroring
  submariner's `ambience.lua` pattern:
  - Kick thump on contact.
  - Net swish + short chime on a goal.
  - Goalie whoosh/thud on a save.
  - A whiff sting, distinguishing "missed the ball" from "too slow" if it
    reads well in testing (otherwise one shared sting).
  - A light, low crowd-murmur bed underneath, continuous.

## Persistence

- `playdate.datastore.write`/`read` for a single `bestStreak` integer.
  Loaded at boot, saved whenever beaten. No other save state in v1.

## Module Structure

```
source/
  main.lua     -- wiring: init, update loop, splash gate
  geom.lua     -- pure math: clamp, lerp, band/velocity checks (SDK-free, tested)
  field.lua    -- shared pitch/goal/track layout constants
  player.lua   -- d-pad -> track position
  ball.lua     -- serve state machine: approach -> contact window -> flight -> resolved
  goalie.lua   -- AI target tracking, speed-by-streak
  game.lua     -- streak/best-streak state, datastore load/save
  render.lua   -- pitch, goal, sprites, HUD, result banners
  audio.lua    -- synthesized SFX + crowd bed
  splash.lua   -- title/instructions gate
  tests.lua    -- boot-time assertions (geom), simulator only
  shots.lua    -- simulator-only screenshot harness for verification
  pdxinfo      -- metadata
Makefile       -- pdc build + `make run` (simulator)
```

Dependencies are one-way: `main → splash/game/player/ball/goalie/render/audio`;
`render` reads player/ball/goalie/game state; `audio` reacts to game/ball
events. `geom.lua` stays free of `playdate.*` calls, same discipline as
submariner, so the contact-band/velocity math is unit-testable without the
SDK.

## Reused from Submariner (hand-copied, not shared code)

No shared package between the two projects — these patterns get copied and
adapted by hand into the new repo:

- `Makefile` (build/run/clean targets, just rename the `.pdx`).
- `pdxinfo` shape (name/author/description/bundleID/version/buildNumber).
- `tests.lua`'s boot-assertion harness pattern (`eq`/`ok` helpers, `runTests()`
  called from `main.lua` only `if playdate.isSimulator`).
- `shots.lua`'s screenshot harness, generalized off `Scope` to whichever
  state table needs pinning for deterministic captures.
- The `setInk(darkness)` dithering helper in `render.lua`.
- `Geom.clamp` (plus a new `Geom.lerp`).
- The crank-docked indicator snippet in `main.lua`
  (`if playdate.isCrankDocked() then playdate.ui.crankIndicator:draw() end`).
- The project conventions themselves: `docs/superpowers/specs/` for design
  docs, a `docs/human-acceptance-checklist.md` for feel-only verification
  items, and the screenshot-harness-based visual verification workflow
  described in submariner's `CLAUDE.md`.

## Error Handling

Clamping is the whole story, same philosophy as submariner: player track
position clamped to its range, shot aim clamped to land inside the goal
frame, flick power clamped to its min/max. No failure states beyond the two
whiff types, which are normal gameplay outcomes, not errors.

## Verification

- Manual-first in the Playdate Simulator (`make run`) — timing and feel are
  the real test here, same as submariner.
- Pure-math functions (`geom.lua`: clamp, lerp, band/velocity checks)
  unit-tested at boot without the SDK.
- Simulator screenshots via the `shots.lua` harness to check pitch/goal/HUD
  composition at rest and mid-serve.

**v1 acceptance criteria:**

1. Builds clean with `pdc`, runs at 30fps in the simulator.
2. D-pad slides the player smoothly within track bounds.
3. Ball serve → contact window → strike (or either whiff type) all feel
   readable and distinct from each other.
4. Goalie visibly reacts only after contact is made; difficulty ramps
   noticeably as streak grows.
5. Streak/best-streak HUD is correct; best survives a simulator restart.
6. Goal, save, and each whiff type have distinct visual and audio feedback.

## Stretch (post-v1)

- A second rod/defender between you and the goal for a real interception
  layer.
- Curved shots (crank direction, not just speed, bending the flight path).
- Wide/crossbar misses instead of always-clamped aim.

## Addendum (2026-07-11): trap-and-hold

Requested from live play. If the contact window expires while the player is
**inside the contact band** (lined up, but no flick), the ball is trapped
at the player's feet instead of whiffing "TOO SLOW" — a new `held` state in
`ball.lua`'s machine, between `window` and `flight`:

- While `held`, the ball rides `Player.x` (drawn slightly below the track
  line, at the figure's feet) and there is no time limit on the hold.
- Any flick past the normal threshold kicks it through the standard
  contact path — aim from the current player x (clamped into the goal),
  power from flick velocity. No band check: a held ball is at the feet by
  definition.
- The goalie shadows the held ball (`Ball.screenX()` clamped into the goal
  range) at its normal streak-ramped speed, so holding repositions the duel
  but never freezes the keeper — fairness comes from the same speed math as
  a normal serve.
- An expiry **outside** the band still whiffs "TOO SLOW"; flicking while
  out of band still whiffs "MISSED THE BALL".

## Addendum (2026-07-11): honest keeper reach

From live play: saves were registering with visible daylight between ball
and keeper. Two causes — `SAVE_RADIUS = 26` stood in for reach while the
drawn goalie was only 14px half-wide (+3px ball ≈ 17px of believable
contact, leaving a 9px phantom band), and the save rest pose teleported the
ball to the keeper's center, up to 26px sideways.

The keeper is now an arms-out foosball man whose drawn reach *is* the save
band, and the saved ball parks against the reach edge on the side it
arrived:

- Drawn arm span ±`Field.KEEPER_HALF` (11px) + ball at goal scale (3px) +
  <1px grace = `Field.SAVE_RADIUS` (15px).
- Re-derived fairness ledger (was: need 60−26=34, max close 100×0.22≈22,
  gap ≈12px): need = 60−15 = **45px**; max close = 150×0.22 = **33px**;
  persistent near-post gap ≈ **12px** — unchanged target. Soft shots
  (0.55s) at max close 82px: still always saveable. Streak-0 (base 70):
  hard corner shots need ~30px displacement to score, close to the old
  beginner feel.
- Goalie constants moved 60/4/100 → **70/6/150** (base/ramp/cap); the cap
  now lands at streak ~13 instead of ~10.
