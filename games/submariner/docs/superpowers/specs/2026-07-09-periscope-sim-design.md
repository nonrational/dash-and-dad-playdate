# Submariner — Periscope Simulation for Playdate

**Date:** 2026-07-09\
**Status:** Approved design, pending implementation plan\
**Target:** Playdate SDK 3.0.6 (Lua), simulator first, device later

## Overview

An ambient toy: you are the periscope of a submarine. The d-pad rotates the
scope through a full 360°; the crank raises and lowers it through the water's
surface. Above the waterline: boats, sky, a lighthouse. Below: fish, bubbles,
deepening murk. No objectives, no score — v1 is purely observational. The win
condition is "feels good to look around."

## Goals

- Nail the physical feel of the periscope: heavy rotation, crank-driven height,
  a waterline that sweeps through the view.
- A persistent little world worth watching: boats you can track around the
  compass, fish that wander below.
- Classic 1-bit aesthetic, everything code-drawn with dither patterns.
- Light synthesized ambience that crossfades as the lens crosses the surface.

## Non-Goals (v1)

- Objectives, scoring, photography, torpedoes.
- Boat hulls visible from underwater (the model supports it; explicitly stretch).
- Day/night cycle, weather, save state.
- Audio files or pre-drawn sprite assets.

## Controls

| Input | Action |
|---|---|
| D-pad left/right | Rotate scope. 25°/s, ramping to 55°/s over the first 0.5s of hold (mechanical feel). Bearing wraps 0–360°. |
| Crank | Scope height. 3 full revolutions sweep bottom-to-top. Crank forward (away from you) raises. |
| Crank docked | Height stays where it is. |
| D-pad up/down, A, B | Unused in v1. |

## View Composition

- Screen 400×240, 1-bit. Circular eyepiece mask, radius ~105px, centered
  slightly above screen middle. Black surround.
- Pre-rendered mask bitmap (black with transparent circle) drawn over the world
  each frame; crosshairs with tick marks and the HUD drawn on top.
- HUD: bearing readout below the circle, e.g. `BRG 047°`.

## Coordinate Model

- **Bearing:** world is a 360° cylinder around the sub. Visible field of view
  ≈ 60° across the circle's diameter (210px → 3.5 px/degree, tunable).
  `screenX = wrappedDelta(entity.bearing, scope.bearing) * pxPerDegree + centerX`.
  Rotation shifts all entities by the same angular amount (rotation has no
  distance parallax); depth cues come from scale, vertical placement, and
  angular drift speed.
- **Height:** normalized `scope.height ∈ [-1, +1]`, 0 = lens exactly at the
  waterline. Waterline screen Y = `centerY + scope.height * 90px` (raised scope
  → line drops in view → more sky; submerged → line exits the top → all water).

## World Model

Fixed persistent population; nothing spawns or despawns. Entities drift around
the cylinder and wrap. All counts/speeds are tunable defaults.

**Above water — boats in 3 lanes:**

| Lane | Scale | Vertical placement | Angular drift |
|---|---|---|---|
| Far | 0.4 | on the waterline | slowest |
| Mid | 0.65 | slightly below the line | medium |
| Near | 1.0 | lowest, hull dips below the line | fastest |

- 5 boats across the lanes; types: sailboat, fishing trawler, cargo ship.
  Code-drawn silhouettes (hull polygon, cabin, mast/rigging lines), gentle sine
  bob, direction varies per boat.
- One lighthouse at a fixed bearing (far lane, never moves) as an orientation
  landmark.
- Sky: white with 2–3 dithered clouds drifting slowly on their own.

**Below water:**

- 2 fish schools (5–6 fish each) + 2 lone big fish. Each fish: bearing, depth,
  speed, sine wiggle; two-frame tail animation, code-drawn.
- 2–3 bubble columns at fixed bearings, bubbles rising continuously.
- Dithered light rays near the surface; dither density (murk) increases as the
  scope goes deeper.

**Waterline:** a few pixels of animated sine chop so it reads as water.

## Rendering Pipeline (per frame, target 30fps)

1. Read input → update scope bearing/height.
2. Update entities (drift, bob, wiggle, bubbles).
3. Draw sky band + clouds (above the waterline).
4. Draw boats, far lane → near lane.
5. Draw waterline chop.
6. Draw underwater gradient/murk, light rays, bubbles, fish.
7. Droplet streak effect for ~0.5s when the lens breaks the surface upward.
8. Mask bitmap, then crosshairs + bearing HUD.

All drawing via `playdate.graphics` primitives and dither patterns. No image
assets.

## Audio (all synthesized, no files)

- **Below bed:** low-pass filtered hum + periodic sonar ping (sine with decay
  envelope).
- **Above bed:** filtered-noise wave lapping + occasional two-note gull chirp.
- **Crossfade:** mix driven by `scope.height` in a narrow band around 0, e.g.
  `mix = clamp01(0.5 + height * 2)`.
- **Surfacing:** short noise-burst splash, triggered with the droplet visual.

## Module Structure

```
source/
  main.lua       -- wiring: init, update loop
  scope.lua      -- input, bearing, height, justSurfaced()
  world.lua      -- entity population, lanes, drift updates
  render.lua     -- all drawing: layers, mask, HUD
  ambience.lua   -- synth setup, crossfade, one-shots
  pdxinfo        -- metadata
Makefile         -- pdc build + `make run` (simulator)
```

Dependencies are one-way: `main → scope/world/render/ambience`;
`render` reads scope+world; `ambience` reads scope. Pure math (bearing wrap,
screen projection, clamps, crossfade curve) lives in plain functions with no
`playdate.*` calls so it can be tested without the SDK.

## Error Handling

Clamping is the whole story: height clamped to [-1, +1], bearing wrapped
0–360°, crank-docked leaves height untouched. No failure states.

## Verification

- Manual-first in the Playdate Simulator (`make run`); it's an ambient toy —
  feel is the test. Simulator screenshots to check composition.
- Pure-math functions unit-testable without the SDK.

**v1 acceptance criteria:**

1. Builds clean with `pdc`, runs in simulator at 30fps.
2. D-pad rotates with wrap; HUD bearing matches; rotation ramp is felt.
3. Crank sweeps full height in ~3 revolutions; waterline visibly crosses the
   view; fully-up shows no underwater, fully-down shows no sky.
4. ≥3 boat silhouette types + lighthouse above; schools, lone fish, and
   bubbles below; murk deepens with depth.
5. Droplet streaks + splash sound on surfacing.
6. Ambience audibly crossfades across the waterline.

## Stretch (post-v1, model already supports)

- Boat hulls visible from below at shared bearings.
- Photography/spotting objectives.
- Weather, day/night.
