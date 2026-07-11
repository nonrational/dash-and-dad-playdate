# Geometry Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the three reviewed visual-geometry defects — the approaching ball floating outside the converging pitch, goal vs. save rendering identically, and the player figure showing no crank position — without touching any gameplay math.

**Architecture:** One new pure projection function (`Geom.projectX`) maps track-space x to screen x at a given depth; the ball's approach, the pitch sidelines, and the new far goal line all derive from that single map. Goal/save get distinct rest poses plus draw-order and goalie-hold changes so the outcome reads on screen. The player figure gains a kick leg that rotates 1:1 with `playdate.getCrankPosition()`.

**Tech Stack:** Playdate SDK 3.0.6 (Lua), `pdc` via `make build`, Playdate Simulator for boot-time tests and the `Shots` screenshot harness.

## Global Constraints

- Playdate SDK lives at `~/Developer/PlaydateSDK`. Build with `make build` (this is also the only syntax check — there is no separate linter).
- Modules are Playdate-style globals (`Geom`, `Field`, `Player`, `Ball`, `Goalie`, `Game`, `Render`, `Audio`, `Splash`) loaded via `import`, not `require`. Dependency directions are one-way and must stay that way: `goalie.lua` may read `Ball`, `ball.lua` must never read `Goalie`; `render.lua` reads state, other modules never read `Render`.
- `source/geom.lua` must stay free of `playdate.*` calls — it is the one module with boot-time unit tests (`source/tests.lua`, run by `runTests()` in `main.lua` when booting in the simulator; a failure errors at boot).
- **Gameplay math must not change.** Contact band check, aim clamp (`Ball.shotTargetX`), save check (`Geom.inBand(goalieX, shotTargetX, SAVE_RADIUS)`), flick power, and flight timing all stay exactly as they are. These fixes are presentation, plus one behavioral nuance called out explicitly in Task 3 (goalie holds a save pose).
- **Committed code always has an empty screenshot plan** (`Shots.plan = {}` in `source/shots.lua`). Every task that captures screenshots must revert the plan before its commit step.
- **Smoke-test recipe** (used in place of GUI `make run` so verification needs no human watching the simulator):

  ```bash
  make build
  rm -f /tmp/foosball-<name>*.png
  timeout -k 5 20 "$HOME/Developer/PlaydateSDK/bin/Playdate Simulator.app/Contents/MacOS/Playdate Simulator" Foosball.pdx > /tmp/foosball-<name>.log 2>&1
  ls -la /tmp/foosball-<name>*.png
  ```

  The simulator exits by itself after the last `Shots.plan` entry captures. Boot-time geom tests run on every launch and gate the update loop: **a failing test freezes boot at an error screen and no PNG is ever written, so the captures appearing IS the test-pass signal.** (`print` output does not reach the launch log in this environment — do not expect `geom tests: all passed` on stdout. A timeout kill with no PNG means a boot failure; a timeout kill after PNGs appeared is normal for plans that don't exhaust their entries.)
- **Environment notes (2026-07-11 session):** the sandboxed simulator cannot write to `/tmp` — substitute the session scratchpad directory for `/tmp` in every capture path. Subagent shells cannot usefully run the simulator at all; the controller runs all capture/verification steps. **Playdate's Lua uses 32-bit floats:** `eq`'s 1e-9 tolerance is effectively exact-match, so every asserted expected value must be exactly representable in single precision (integers, halves, quarters — not values like `-1.6` reached via `0.2` arithmetic).
- The `Shots` harness pins `set` fields onto `target` every frame while an entry is pending, and runs `call` once when the entry becomes active. The splash screen gates the game loop, so the **first** entry of every capture plan must dismiss it with `call = function() Splash.active = false end`.
- Crank input cannot be scripted; captures pin the *downstream* state instead (e.g. `Player.crankAngle`). Live control feel goes on `docs/human-acceptance-checklist.md`, never in automated checks.
- Commit messages are plain and descriptive — **no Conventional Commit prefixes**. Commit with `git -c commit.gpgsign=false commit`.

---

### Task 1: `Geom.projectX` — the shared perspective map

**Files:**
- Modify: `source/geom.lua` (append one function)
- Test: `source/tests.lua` (append assertions inside `runTests()`)

**Interfaces:**
- Consumes: `Geom.lerp(a, b, t)` (already in `source/geom.lua`).
- Produces: `Geom.projectX(x, depth, nearMin, nearMax, farMin, farMax) -> number` — screen x of a near-space (track) x at `depth` (0 = near/track edge, 1 = far/goal edge), where `[nearMin, nearMax]` maps linearly onto `[farMin, farMax]`. Must extrapolate for depths outside [0, 1] (Task 2's sidelines use negative depth to reach the bottom of the screen). Tasks 2 depends on this exact name and argument order.

- [ ] **Step 1: Write the failing tests**

In `source/tests.lua`, immediately after the three `Geom.goalieSpeed` assertions and before the final `print(...)` line, add:

```lua
    -- projectX: screen x of a track-space x at depth d (0 = player track,
    -- 1 = goal line), here mapping the real spans [50,350] -> [140,260].
    eq(Geom.projectX(200, 0, 50, 350, 140, 260), 200, "projectX identity at depth 0")
    eq(Geom.projectX(50, 1, 50, 350, 140, 260), 140, "projectX track min to goal min")
    eq(Geom.projectX(350, 1, 50, 350, 140, 260), 260, "projectX track max to goal max")
    eq(Geom.projectX(200, 1, 50, 350, 140, 260), 200, "projectX center is a fixed point")
    eq(Geom.projectX(60, 1, 50, 350, 140, 260), 144, "projectX wide lane at goal line")
    eq(Geom.projectX(60, 0.5, 50, 350, 140, 260), 102, "projectX wide lane at mid depth")
    eq(Geom.projectX(20, -0.25, 50, 350, 140, 260), -7, "projectX extrapolates below depth 0")
```

- [ ] **Step 2: Run to verify they fail**

Add a temporary one-entry capture plan to `source/shots.lua` (`{ after = 0.2, path = "<scratchpad>/geo1-boot.png" }`) and run the smoke-test recipe with `<name>` = `geo1`.

Expected: **no PNG is written** and the simulator hits the timeout kill — the boot error (`projectX` is nil) freezes the game before the update loop starts.

- [ ] **Step 3: Implement `Geom.projectX`**

Append to `source/geom.lua` (after `Geom.goalieSpeed`, keeping the file `playdate.*`-free):

```lua
-- Screen x of a near-space (track) x at a given depth: 0 = the near edge,
-- 1 = the far (goal-line) edge, with [nearMin, nearMax] mapping linearly
-- onto [farMin, farMax]. Depths outside [0,1] extrapolate — the pitch
-- sidelines use that to run past the track to the bottom of the screen.
function Geom.projectX(x, depth, nearMin, nearMax, farMin, farMax)
    local farX = farMin + (x - nearMin) * (farMax - farMin) / (nearMax - nearMin)
    return Geom.lerp(x, farX, depth)
end
```

- [ ] **Step 4: Run to verify they pass**

Run the smoke-test recipe with `<name>` = `geo1` again (same temporary capture entry).

Expected: the PNG appears and the simulator exits by itself — boot got past `runTests()`. Revert `source/shots.lua` to an empty plan before committing.

- [ ] **Step 5: Commit**

```bash
git add source/geom.lua source/tests.lua
git -c commit.gpgsign=false commit -m "Add Geom.projectX with boot-time tests for lane projection"
```

---

### Task 2: Project the approach ball and derive the pitch from the same map

**Files:**
- Modify: `source/ball.lua:142-149` (`Ball.screenX`)
- Modify: `source/field.lua` (`BALL_MIN_SCALE`)
- Modify: `source/render.lua` (imports, pitch constants, `drawPitch`)
- Modify: `CLAUDE.md` (coordinate-model paragraph)
- Modify: `docs/superpowers/specs/2026-07-10-foosball-shootout-design.md` (the "ball.x stays fixed" bullet)

**Interfaces:**
- Consumes: `Geom.projectX(x, depth, nearMin, nearMax, farMin, farMax)` from Task 1; existing `Field` constants (`TRACK_MIN=50`, `TRACK_MAX=350`, `PLAYER_Y=205`, `GOAL_MIN=140`, `GOAL_MAX=260`, `GOAL_Y=50`).
- Produces: nothing new for later tasks (rendering-internal changes). Note Task 3 rewrites `Ball.screenX`'s `ballAtGoal()` branch — the projection fallthrough added here must survive that edit as shown in Task 3's code.

- [ ] **Step 1: Project the approaching (and whiff-frozen) ball**

In `source/ball.lua`, replace the whole `Ball.screenX` function with:

```lua
function Ball.screenX()
    if Ball.state == "flight" or Ball.state == "flightComplete" then
        return Geom.lerp(Ball.contactX, Ball.shotTargetX, flightProgress())
    elseif ballAtGoal() then
        return Ball.shotTargetX
    end
    -- Approach (and whiff-frozen) ball: converge toward the lane's
    -- goal-space image as it recedes, so a wide lane rides down inside the
    -- narrowing pitch instead of hanging in space beside the goal. At
    -- progress 1 this is exactly laneX — contact geometry is unaffected.
    return Geom.projectX(Ball.laneX, 1 - Geom.clamp(Ball.progress, 0, 1),
        Field.TRACK_MIN, Field.TRACK_MAX, Field.GOAL_MIN, Field.GOAL_MAX)
end
```

(The flight branch stays a straight screen-space lerp on purpose: its endpoints are already consistent, and the "true" projected path deviates by a barely visible quadratic over a 0.22–0.55s flight.)

- [ ] **Step 2: Make the far ball visible**

In `source/field.lua`, change:

```lua
    BALL_MIN_SCALE = 0.3,
```

to:

```lua
    BALL_MIN_SCALE = 0.5,
```

(At 0.3 the far ball is a 1.8px-radius speck — invisible in captures. This constant is render-only; no gameplay reads it.)

- [ ] **Step 3: Derive the pitch from the same projection**

In `source/render.lua`:

1. Add `import "geom"` after `import "CoreLibs/graphics"` (it was removed as unused in an earlier cleanup; this task needs it back).
2. Replace the two constant lines

```lua
local NEAR_LEFT, NEAR_RIGHT = Field.TRACK_MIN - 30, Field.TRACK_MAX + 30
local FAR_LEFT, FAR_RIGHT = Field.GOAL_MIN - 20, Field.GOAL_MAX + 20
```

and the whole `drawPitch` function with:

```lua
local PITCH_MARGIN = 30

-- Depth (0 = player track, 1 = goal line) of a screen y; extrapolates past
-- the track so the sidelines can run to the bottom edge of the screen.
local function depthAtY(y)
    return (Field.PLAYER_Y - y) / (Field.PLAYER_Y - Field.GOAL_Y)
end

local function sidelineX(trackX, y)
    return Geom.projectX(trackX, depthAtY(y),
        Field.TRACK_MIN, Field.TRACK_MAX, Field.GOAL_MIN, Field.GOAL_MAX)
end

local function drawPitch()
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(2)
    local leftEdge = Field.TRACK_MIN - PITCH_MARGIN
    local rightEdge = Field.TRACK_MAX + PITCH_MARGIN
    gfx.drawLine(sidelineX(leftEdge, 240), 240, sidelineX(leftEdge, Field.GOAL_Y), Field.GOAL_Y)
    gfx.drawLine(sidelineX(rightEdge, 240), 240, sidelineX(rightEdge, Field.GOAL_Y), Field.GOAL_Y)
    gfx.drawLine(sidelineX(leftEdge, Field.GOAL_Y), Field.GOAL_Y,
        sidelineX(rightEdge, Field.GOAL_Y), Field.GOAL_Y)
    gfx.setLineWidth(1)
end
```

This keeps the sidelines where they were in spirit (track ±30, reaching y=240) but their far ends now land at the projection of those edges (x ≈ 128 and 272 at the goal line), 12px outside each goal post, connected by a new goal line across the far end.

- [ ] **Step 4: Capture and inspect screenshots**

In `source/shots.lua`, temporarily set:

```lua
Shots = { plan = {
    { after = 0.2, target = Ball, set = { state = "approach", progress = 0.05, laneX = 60 },
      call = function() Splash.active = false end,
      path = "/tmp/foosball-geo2-far.png" },
    { after = 0.15, target = Ball, set = { state = "approach", progress = 0.5, laneX = 60 },
      path = "/tmp/foosball-geo2-mid.png" },
    { after = 0.15, target = Ball, set = { state = "approach", progress = 0.9, laneX = 60 },
      path = "/tmp/foosball-geo2-near.png" },
}, t = 0, i = 1, called = false }
```

Run the smoke-test recipe with `<name>` = `geo2`, then view each PNG (the Read tool renders images).

Expected (the captures appearing is itself the boot-tests-passed signal): `far`: ball (r≈3) at the left end of the goal mouth (x ≈ 138–144 — pin timing adds ~one frame of progress), on/near the new far goal line, **inside** the pitch. `mid`: ball ≈ (102, 127), clearly inside the left sideline. `near`: ball ≈ (68, 190), near the track's left end. In all three: sidelines converge to a goal line at y=50 that connects them, goal frame centered on it.

- [ ] **Step 5: Revert the capture plan**

In `source/shots.lua`, set `Shots.plan` back to empty: `Shots = { plan = {}, t = 0, i = 1, called = false }`. Run `make build` once more to confirm it still compiles.

- [ ] **Step 6: Update the docs that state the old model**

In `CLAUDE.md`, in the **Coordinate model** paragraph, replace the sentence:

```
A served ball's `x` (its lane) stays fixed while
`y`/scale interpolate from the goal
end (small/far) to the player's track (large/near) as approach progress
goes 0→1.
```

with:

```
A served ball's lane is fixed in track-space, but its on-screen `x` follows
`Geom.projectX(laneX, 1 - progress, …)` — converging toward the lane's
goal-space image at the far end (so wide lanes stay inside the pitch) and
landing exactly on `laneX` at contact — while `y`/scale interpolate from
the goal end (small/far) to the player's track (large/near) as approach
progress goes 0→1. The pitch sidelines and far goal line in `render.lua`
are derived from that same projection.
```

In `docs/superpowers/specs/2026-07-10-foosball-shootout-design.md`, replace the bullet beginning `- **Ball:** one \`progress\` value` with:

```
- **Ball:** one `progress` value p ∈ [0, 1] per serve drives both position
  and scale. The ball's *lane* is fixed in track-space, but its on-screen x
  converges toward the lane's goal-space image as it recedes
  (`Geom.projectX`, mapping [50, 350] onto [140, 260] at the goal line) —
  at p=0 it sits between the posts, at p=1 it is exactly at lane x on the
  track; `ball.y` and `ball.scale` interpolate from the goal end (p=0,
  small/high) to the player's track (p=1, large/low). Pure math in
  `geom.lua` (`lerp`, `projectX`), same spirit as submariner keeping
  projection math SDK-free and testable.
```

- [ ] **Step 7: Commit**

```bash
git add source/ball.lua source/field.lua source/render.lua source/shots.lua CLAUDE.md docs/superpowers/specs/2026-07-10-foosball-shootout-design.md
git -c commit.gpgsign=false commit -m "Project the approaching ball and pitch through a shared perspective map"
```

---

### Task 3: Distinct goal vs. save rest poses, goalie holds the save, banner off the player

**Files:**
- Modify: `source/ball.lua` (`Ball` table fields, `Ball.startServe`, `Ball.resolve`, `Ball.screenX`, `Ball.screenY`)
- Modify: `source/goalie.lua` (`Goalie.update` target selection)
- Modify: `source/render.lua` (`Render.draw` order, `drawResultBanner` y)
- Modify: `docs/human-acceptance-checklist.md` (two new live-play checks)
- Modify: `CLAUDE.md` (goalie bullet)

**Interfaces:**
- Consumes: `Geom.inBand`, `Field.SAVE_RADIUS`, `Field.GOAL_Y`; `Ball.screenX` as left by Task 2 (its projection fallthrough must be preserved verbatim below).
- Produces: `Ball.restX`, `Ball.restY` (numbers set by `Ball.resolve`; `nil` between serves) — render-only rest pose of a resolved shot. `Goalie.update` now holds position while `Ball.state == "resolved" and Ball.result == "save"`.

- [ ] **Step 1: Record a rest pose at resolve time**

In `source/ball.lua`:

1. In the `Ball = { ... }` table literal, after `resolvedTimer = 0,` add:

```lua
    restX = nil,
    restY = nil,
```

2. In `Ball.startServe`, after `Ball.result = nil` add:

```lua
    Ball.restX = nil
    Ball.restY = nil
```

3. Replace the whole `Ball.resolve` function with:

```lua
function Ball.resolve(goalieX)
    local saved = Geom.inBand(goalieX, Ball.shotTargetX, Field.SAVE_RADIUS)
    Ball.result = saved and "save" or "goal"
    -- Rest pose is where the outcome story ends: a save parks the ball at
    -- the goalie that blocked it (not at the aim point, which can be up to
    -- SAVE_RADIUS away and reads as "it went in"); a goal parks it inside
    -- the net.
    if saved then
        Ball.restX, Ball.restY = goalieX, Field.GOAL_Y - 8
    else
        Ball.restX, Ball.restY = Ball.shotTargetX, Field.GOAL_Y - 10
    end
    Ball.resultPending = true
    Ball.state = "resolved"
    Ball.resolvedTimer = 0
end
```

4. Replace the whole `Ball.screenX` function with (identical to Task 2's version except the `ballAtGoal` branch):

```lua
function Ball.screenX()
    if Ball.state == "flight" or Ball.state == "flightComplete" then
        return Geom.lerp(Ball.contactX, Ball.shotTargetX, flightProgress())
    elseif ballAtGoal() then
        return Ball.restX
    end
    -- Approach (and whiff-frozen) ball: converge toward the lane's
    -- goal-space image as it recedes, so a wide lane rides down inside the
    -- narrowing pitch instead of hanging in space beside the goal. At
    -- progress 1 this is exactly laneX — contact geometry is unaffected.
    return Geom.projectX(Ball.laneX, 1 - Geom.clamp(Ball.progress, 0, 1),
        Field.TRACK_MIN, Field.TRACK_MAX, Field.GOAL_MIN, Field.GOAL_MAX)
end
```

5. In `Ball.screenY`, replace the `ballAtGoal` branch line

```lua
        return Field.GOAL_Y
```

with:

```lua
        return Ball.restY
```

- [ ] **Step 2: Goalie holds the block**

In `source/goalie.lua`, replace the target selection at the top of `Goalie.update` with:

```lua
    local target = Field.GOALIE_CENTER
    if Ball.state == "flight" or Ball.state == "flightComplete" then
        target = Ball.shotTargetX
    elseif Ball.state == "resolved" and Ball.result == "save" then
        -- Hold the block through the SAVED banner: drifting home would
        -- abandon the ball the goalie just stopped.
        target = Goalie.x
    end
```

(Reading `Ball` from `goalie.lua` is the established one-way direction; nothing new is introduced.)

- [ ] **Step 3: Tell the story in draw order, and move the banner off the player**

In `source/render.lua`:

1. Add above `Render.draw`:

```lua
-- A scored ball draws before the goal so the net's dither hatches over it
-- — visibly *in* the net. A saved ball draws after the goalie (normal
-- order), sitting in front of the figure that blocked it.
local function ballInNet()
    return Ball.state == "resolved" and Ball.result == "goal"
end
```

2. Replace the body of `Render.draw` with:

```lua
function Render.draw(dt)
    gfx.clear(gfx.kColorWhite)
    drawPitch()
    if ballInNet() then
        drawBallMarker()
    end
    drawGoal()
    drawGoalieMarker()
    if not ballInNet() then
        drawBallMarker()
    end
    drawPlayerMarker()
    drawHUD()
    drawResultBanner()
end
```

3. In `drawResultBanner`, change the y coordinate `200` to `120` (at 200 the banner prints on top of the player figure):

```lua
        gfx.drawTextAligned(RESULT_TEXT[Ball.result], 200, 120, kTextAlignment.center)
```

- [ ] **Step 4: Capture and inspect screenshots**

In `source/shots.lua`, temporarily set (note: pinned resolved states never went through `Ball.resolve`, so `restX`/`restY` must be pinned too):

```lua
Shots = { plan = {
    { after = 0.2, target = Ball,
      set = { state = "resolved", result = "goal", shotTargetX = 250, restX = 250, restY = 40, resolvedTimer = 0 },
      call = function() Splash.active = false end,
      path = "/tmp/foosball-geo3-goal.png" },
    { after = 0.3, target = Ball,
      set = { state = "resolved", result = "save", shotTargetX = 250, restX = 226, restY = 42, resolvedTimer = 0 },
      call = function() Goalie.x = 226 end,
      path = "/tmp/foosball-geo3-save.png" },
}, t = 0, i = 1, called = false }
```

Run the smoke-test recipe with `<name>` = `geo3`, then view both PNGs.

Expected (the captures appearing is itself the boot-tests-passed signal): `goal`: ball (r=3) visible at (250, 40) **under** the net's light hatching (goalie drifts back toward center ≈ 200); "GOAL!" centered at y=120, clear of the player. `save`: goalie stays at ≈ 226 for the whole 0.3s (the hold — pre-change code would have drifted ~18px toward center), ball at (226, 42) drawn **on top of** the goalie; "SAVED" at y=120.

- [ ] **Step 5: Revert the capture plan**

In `source/shots.lua`, set `Shots.plan` back to empty: `Shots = { plan = {}, t = 0, i = 1, called = false }`. Run `make build` to confirm it compiles.

- [ ] **Step 6: Update the human checklist and CLAUDE.md**

Append to the list in `docs/human-acceptance-checklist.md` (match the file's existing bullet style):

```
- A save reads at a glance in live play: the ball stops at the goalie (never in the net) and the goalie holds the block for the whole SAVED banner.
- A goal reads at a glance in live play: the ball visibly sits in the net, hatched over by the net fill.
```

In `CLAUDE.md`, in the architecture bullet for `goalie.lua` (the one beginning "`goalie.lua` takes `streak` as a parameter"), append this sentence:

```
During a saved ball's resolved pause (`Ball.result == "save"`) the goalie
holds its position instead of drifting home, so the block stays visually
attached to the ball it stopped.
```

- [ ] **Step 7: Commit**

```bash
git add source/ball.lua source/goalie.lua source/render.lua source/shots.lua docs/human-acceptance-checklist.md CLAUDE.md
git -c commit.gpgsign=false commit -m "Give goals and saves distinct rest poses and hold the goalie on a save"
```

---

### Task 4: Crank-tracking kick leg on the player figure

> **Addendum (2026-07-11):** superseded — the separate kick leg is gone.
> The whole foosball-man silhouette now tips forward/backward around a
> drawn rod, 1:1 with the crank: each vertex keeps its x and has its
> local y foreshortened by `cos(angle)`, and whichever end is nearer the
> camera draws last, so a figure tipped toward you reads as just the head
> circle occluding the body. Step 1's `Player.crankAngle` (and its dock
> guard) is unchanged and still feeds the pose; see `drawPlayerMarker` and
> `drawRod` in `source/render.lua`.

**Files:**
- Modify: `source/player.lua` (`Player` table, `Player.init`, `Player.update`)
- Modify: `source/render.lua` (`drawPlayerMarker`)
- Modify: `docs/human-acceptance-checklist.md` (one new live-play check)
- Modify: `CLAUDE.md` (crank-accumulator gotcha, one clarifying sentence)

**Interfaces:**
- Consumes: nothing from Tasks 1–3.
- Produces: `Player.crankAngle` (degrees, 0–360, Playdate convention: 0 = straight up, increasing clockwise) — read by `render.lua` only.

- [ ] **Step 1: Track the crank angle in Player**

Replace the whole of `source/player.lua` with:

```lua
import "geom"
import "field"

Player = { x = 200, crankAngle = 0 }

Player.SPEED = 260

function Player.init()
    Player.x = 200
    Player.crankAngle = 0
end

function Player.update(dt)
    if playdate.buttonIsPressed(playdate.kButtonLeft) then
        Player.x = Player.x - Player.SPEED * dt
    end
    if playdate.buttonIsPressed(playdate.kButtonRight) then
        Player.x = Player.x + Player.SPEED * dt
    end
    Player.x = Geom.clamp(Player.x, Field.TRACK_MIN, Field.TRACK_MAX)

    -- Absolute crank angle for the kick-leg pose. getCrankPosition() is
    -- independent of ball.lua's getCrankChange() drain — reading it here
    -- touches no accumulator. Guarded on dock state so a docked crank
    -- parks the leg — which also lets the Shots harness pin crankAngle
    -- for deterministic captures (the crank itself can't be scripted).
    if not playdate.isCrankDocked() then
        Player.crankAngle = playdate.getCrankPosition()
    end
end
```

- [ ] **Step 2: Draw the leg**

In `source/render.lua`, replace the whole `drawPlayerMarker` function with:

```lua
local function drawPlayerMarker()
    gfx.setColor(gfx.kColorBlack)
    local x, y = Player.x, Field.PLAYER_Y
    gfx.fillCircleAtPoint(x, y - 14, 8)
    gfx.fillTriangle(x - 12, y + 20, x + 12, y + 20, x, y - 4)
    -- Kick leg, rotating 1:1 with the crank (0 = up, clockwise) so winding
    -- up and flicking read on-screen. The white underlay keeps the leg
    -- legible when it sweeps across the solid black body (about half the
    -- rotation, verified by capture). Placeholder like the rest of the
    -- figure; stays inside this one draw function for the later sprite swap.
    local rad = math.rad(Player.crankAngle)
    local hipX, hipY = x + 6, y + 6
    local footX = hipX + 12 * math.sin(rad)
    local footY = hipY - 12 * math.cos(rad)
    gfx.setColor(gfx.kColorWhite)
    gfx.setLineWidth(5)
    gfx.drawLine(hipX, hipY, footX, footY)
    gfx.fillCircleAtPoint(footX, footY, 4)
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(3)
    gfx.drawLine(hipX, hipY, footX, footY)
    gfx.setLineWidth(1)
    gfx.fillCircleAtPoint(footX, footY, 3)
end
```

- [ ] **Step 3: Capture and inspect screenshots**

In `source/shots.lua`, temporarily set (crank is docked in a headless simulator, so the dock guard from Step 1 lets these pins stick):

```lua
Shots = { plan = {
    { after = 0.2, target = Player, set = { x = 200, crankAngle = 0 },
      call = function() Splash.active = false end,
      path = "/tmp/foosball-geo4-up.png" },
    { after = 0.15, target = Player, set = { x = 200, crankAngle = 90 },
      path = "/tmp/foosball-geo4-right.png" },
    { after = 0.15, target = Player, set = { x = 200, crankAngle = 180 },
      path = "/tmp/foosball-geo4-down.png" },
    { after = 0.15, target = Player, set = { x = 200, crankAngle = 270 },
      path = "/tmp/foosball-geo4-left.png" },
}, t = 0, i = 1, called = false }
```

Run the smoke-test recipe with `<name>` = `geo4`, then view all four PNGs.

Expected (the captures appearing is itself the boot-tests-passed signal): The foot dot sits respectively above, right of, below, and left of the hip pivot at (206, 211) — a leg segment visibly rotating around the figure. (The docked-crank indicator bubble may overlap the lower right; ignore it.)

- [ ] **Step 4: Revert the capture plan**

In `source/shots.lua`, set `Shots.plan` back to empty: `Shots = { plan = {}, t = 0, i = 1, called = false }`. Run `make build` to confirm it compiles.

- [ ] **Step 5: Update the human checklist and CLAUDE.md**

Append to the list in `docs/human-acceptance-checklist.md`:

```
- Kick leg tracks the crank 1:1 with no perceptible lag; a flick reads as a kick through the ball, and docking the crank parks the leg.
```

In `CLAUDE.md`, at the end of the crank-accumulator gotcha bullet (the one explaining `playdate.getCrankChange()` must be polled every frame), append:

```
(`player.lua`'s `Player.crankAngle` uses `playdate.getCrankPosition()` — a
separate absolute read with no accumulator — so it is exempt from this
rule and safe to guard behind the dock check.)
```

- [ ] **Step 6: Commit**

```bash
git add source/player.lua source/render.lua source/shots.lua docs/human-acceptance-checklist.md CLAUDE.md
git -c commit.gpgsign=false commit -m "Add a crank-tracking kick leg to the player figure"
```
