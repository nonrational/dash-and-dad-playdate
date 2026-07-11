# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An arcade foosball shootout for the Playdate console (Lua, SDK 3.0.6). D-pad
slides your player along a track; a ball is served toward a randomized lane;
a crank flick inside a contact window strikes it past a goalie. Endless
streak mode — no fixed end, the goalie gets tougher as your streak grows.
The authoritative design spec (shot mechanics, goalie fairness math, module
structure, v1 acceptance criteria) is
`docs/superpowers/specs/2026-07-10-foosball-shootout-design.md`; the
implementation plan with exact code and verification steps is
`docs/superpowers/plans/2026-07-10-foosball-shootout.md`.

## Commands

Requires the Playdate SDK at `~/Developer/PlaydateSDK`.

- `make build` — compile `source/` into `Foosball.pdx` with `pdc` (also
  catches Lua syntax errors; there is no separate linter)
- `make run` — build and launch in the Playdate Simulator
- `make clean` — remove the `.pdx`

## Testing and verification

- **Unit tests** live in `source/tests.lua` as boot-time assertions, run
  automatically when the game boots in the simulator (`runTests()` in
  `main.lua`). There is no standalone test runner; a failure errors at
  boot. They only cover `geom.lua`, which is kept free of `playdate.*`
  calls precisely so it stays testable — preserve that boundary.
- **Visual verification** uses the screenshot harness in `source/shots.lua`:
  temporarily populate `Shots.plan` with
  `{ after = <seconds>, target = <a Global table>, set = { <field> = <value> }, call = <function>, path = "<absolute .png path>" }`
  entries, `make run` (or the headless smoke-test recipe in the
  implementation plan's Global Constraints), and the simulator writes each
  frame to disk then exits. `set` fields are pinned onto `target` every
  frame so captures are deterministic; `call` runs once when an entry
  becomes active, for side effects a field-pin can't express (e.g. forcing
  a `playdate.datastore.write`). **Committed code always has an empty plan**
  (`Shots.plan = {}`) — revert before committing.
- Crank input (`playdate.getCrankChange()`) and real button presses
  (`playdate.buttonJustPressed`) can't be scripted through this harness —
  anything gated on them (crank flick feel, splash dismissal) is verified
  by pinning the *downstream* state directly instead (e.g. forcing
  `Ball.state = "flight"`, or `Splash.active = false`), with the actual
  input feel deferred to `docs/human-acceptance-checklist.md`.
- `docs/human-acceptance-checklist.md` lists everything that can only be
  verified by live play (control feel, timing, audio, difficulty ramp) —
  anything changed in those areas lands there for a human pass, not in
  automated checks.

## Architecture

Modules are Playdate-style globals (`Geom`, `Field`, `Player`, `Ball`,
`Goalie`, `Game`, `Render`, `Audio`, `Splash`) loaded via `import`, not
`require`. Dependencies are deliberately one-way, including across the two
modules whose *mechanic* is inherently mutual:

- `main.lua` wires init and the 30fps update loop, gated behind `Splash.active`: while the splash is up, only `Splash.update`/`Splash.draw` run; once dismissed, every frame runs `Player.update → Ball.update → Goalie.update → (Ball.resolve, if a flight just completed) → Game/Audio event reactions → Render.draw`. `Shots.update` always runs, outside that gate, regardless of splash state.
- `ball.lua` owns the serve state machine (`approach → window → flight → flightComplete → resolved`, plus a `held` detour: a window that expires while the player is lined up traps the ball at the feet — it rides `Player.x` until a flick kicks it through the normal contact path) and never reads `Goalie` — `goalie.lua` reads `Ball.state`/`Ball.shotTargetX`/`Ball.screenX()` one-way to decide where to move (during `held` it shadows the ball, which is the player, without reading `Player`), and it's `main.lua` (not `ball.lua`) that reads `Goalie.x` back and passes it into `Ball.resolve(goalieX)` as an explicit parameter. This keeps every module's dependency direction one-way even though the shot-resolution mechanic itself needs both sides.
- `goalie.lua` takes `streak` as a parameter to `Goalie.update(dt, streak)` rather than reading `Game` directly, for the same reason. During a saved ball's resolved pause (`Ball.result == "save"`) the goalie holds its position instead of drifting home, so the block stays visually attached to the ball it stopped.
- `render.lua` reads `Player`/`Ball`/`Goalie`/`Game`; `audio.lua` and `game.lua` react to one-frame event flags (`Ball.contactJustNow`, `Ball.resultPending`) that `main.lua` checks and dispatches — neither module polls `Ball`'s state machine directly.
- `geom.lua` is pure math shared by all of the above (`clamp`, `lerp`, `projectX`, `inBand`, `flickPower`, `shotFlightTime`, `goalieSpeed`) — no `playdate.*` calls, so it's the one module with boot-time unit tests.

**Coordinate model**: screen 400×240. Track (player) `x ∈ [50, 350]` at
`y = 205`; goal `x ∈ [140, 260]` at `y = 50`. The goalie moves within that
same `[140, 260]` range, resting at `x = 200` — it never needs to defend
outside the posts, since shot aim (`Ball.shotTargetX`) is always clamped
inside the goal frame too. A served ball's lane is fixed in track-space, but its on-screen `x` follows
`Geom.projectX(laneX, 1 - progress, …)` — converging toward the lane's
goal-space image at the far end (so wide lanes stay inside the pitch) and
landing exactly on `laneX` at contact — while `y`/scale interpolate from
the goal end (small/far) to the player's track (large/near) as approach
progress goes 0→1. The pitch sidelines and far goal line in `render.lua`
are derived from that same projection. On contact, `Ball.contactX` (the raw player position, in
track-space — used for the contact-band check) is distinct from
`Ball.shotTargetX` (that same position clamped into goal-space via
`Geom.clamp` — used for the goalie's target and the save check), so a shot
struck from a wide track position still visually flies toward the goal
mouth rather than clamping instantly to a straight line.

## Constraints and gotchas

- Sprite art (images) is **allowed** in this project, unlike submariner's
  zero-asset rule. The splash box art (`source/images/splash.png`) is the
  first real asset: `pdc` thresholds images at 50% and does **not**
  dither, so assets must be pre-dithered 1-bit PNGs at their exact
  on-screen size. Regenerate it from the original
  (`assets/splash-box-art.png`, 1024×572 — wider than the screen's 5:3,
  hence the fill-crop) with:
  `ffmpeg -i assets/splash-box-art.png -vf "scale=430:240:flags=lanczos,crop=400:240,format=gray,scale=400:240:sws_dither=bayer,format=monob" source/images/splash.png`.
  The launcher assets in `source/launcher/` (`imagePath=launcher` in
  `pdxinfo`) come from the same art: `card.png` (350×155) uses the same
  ffmpeg pipeline with `scale=350:196…,crop=350:155:0:10`;
  `launchImage.png` is a byte-for-byte copy of the splash;
  `icon.png` (32×32) is NOT a downscale — box art turns to dither noise at
  that size — it's a code-drawn chibi man rasterized by a throwaway PBM
  script (regenerate by redrawing bold shapes, not by scaling art down).
  The player/goalie/ball in `render.lua` are still simple code-drawn
  placeholder shapes, each behind one small, single-purpose draw function,
  specifically so swapping in real sprites later is a localized change
  rather than a redesign.
- Audio stays fully synthesized (`playdate.sound` synths/filters), no audio
  files — this constraint, unlike the image-asset one, was kept from
  submariner's approach.
- `setDitherPattern`'s alpha runs backwards for black ink (0 = solid
  black). Use the `setInk(darkness)` helper in `render.lua` rather than
  calling it directly.
- `Geom.inBand(x, center, halfWidth)` is deliberately generic — it backs
  both the player's contact-band check (is the player close enough to the
  ball's lane?) and the goalie's save check (is the goalie close enough to
  the shot's target?). Don't fork it into two near-duplicate functions.
- `math.random` is used for serve lane randomization in `ball.lua` — fine,
  since automated tests bypass it entirely by pinning `Ball.laneX` directly
  through the `Shots` harness rather than relying on captured randomness.
- The Playdate Lua runtime does math in single-precision floats:
  `math.cos(math.rad(90))` comes back ~4e-8, not ~6e-17 like desktop Lua.
  Any future boot test in `source/tests.lua` asserting on trig-derived
  values needs a loose tolerance (~1e-4), not the `eq` helper's 1e-9 —
  learned the hard way when a rotation-helper test hung boot on exactly
  this.
- `Ball.update` calls `playdate.getCrankChange()` unconditionally on every
  frame, regardless of `Ball.state` — it returns the delta *since it was
  last called*, not since the last frame, so gating the call to only the
  `window` state would let crank motion during the ~1.3s `approach` phase
  accumulate undrained and dump as one inflated reading the instant
  `window` opens, producing a velocity spike the player never intended.
  This was a real bug found and fixed during Task 6's review; see the
  comment above the `playdate.getCrankChange()` call in `source/ball.lua`.
  (The splash screen doesn't reintroduce this: `Ball.update` never runs
  while `Splash.active`, but `Ball.state` also can't move off `"approach"`
  during that time, so the flick-threshold check — nested inside `window`
  only — stays unreachable until well after normal per-frame draining
  resumes post-dismissal.)
  (`player.lua`'s `Player.crankAngle` uses `playdate.getCrankPosition()` — a
  separate absolute read with no accumulator — so it is exempt from this
  rule and safe to guard behind the dock check.)
