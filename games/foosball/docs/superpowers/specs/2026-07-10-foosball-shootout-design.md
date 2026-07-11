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
  (120px), with a goalie sprite that moves within a slightly wider band
  (small overhang past the posts so it can commit toward a corner). Small
  scale (background), consistent with submariner's "distance = smaller +
  higher on screen" depth cue.
- **Ball:** one `progress` value p ∈ [0, 1] per serve drives both position
  and scale. `ball.x` stays fixed at that serve's lane x (it's travelling
  straight toward the camera, not sideways); `ball.y` and `ball.scale`
  interpolate from the goal end (p=0, small/high) to the player's track (p=1,
  large/low). Reused as pure math in `geom.lua` (`lerp`), same spirit as
  submariner keeping projection math SDK-free and testable.

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
     of 1800°/s, clamped to [0.4, 1.0].
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
psychic. It moves toward that target at `min(220 + 15 × streak, 520)` px/s
(base 220px/s, ramping 15px/s per streak point, capped at 520px/s). The
goalie's track spans the goal width plus a 40px overhang on each side (200px
total, ±100px from center), so a maxed-out goalie starting from center can
cover at most `520 × 0.22 ≈ 114px` before a maximum-power shot arrives —
short of the 200px full width, meaning a hard-hit, well-placed corner shot
always has a mathematical chance even at max difficulty. Exact constants are
starting points, to be tuned by playtesting like submariner's.

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
