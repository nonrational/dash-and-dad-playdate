# Foosball Shootout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An arcade Playdate game: d-pad slides your foosball player along a track, a ball is served toward a randomized lane, and a crank flick inside a contact window strikes it past a goalie. Endless streak mode; best streak persists.

**Architecture:** A per-frame state machine in `ball.lua` drives serve → contact window → flight → resolution. `player.lua` and `goalie.lua` each own one moving x-position; `goalie.lua` reads `ball.lua`'s state one-way, and `main.lua` (not `ball.lua`) is the only place that reads `goalie.lua`'s position back into `ball.lua`'s resolution call — this keeps every module's dependency direction one-way even though the mechanic itself is mutual. Six Lua modules as globals (`Geom`, `Field`, `Player`, `Ball`, `Goalie`, `Game`) plus `Render`/`Audio`/`Splash`, wired by `main.lua`.

**Tech Stack:** Playdate SDK 3.0.6 (Lua only), `pdc` compiler, Playdate Simulator. Code-drawn pitch/goal/HUD; sprite art deferred (see Global Constraints); synthesized audio only, no audio files.

**Spec:** `docs/superpowers/specs/2026-07-10-foosball-shootout-design.md`

## Global Constraints

- SDK lives at `~/Developer/PlaydateSDK`; compiler `~/Developer/PlaydateSDK/bin/pdc` (3.0.6); simulator app `~/Developer/PlaydateSDK/bin/Playdate Simulator.app`.
- Playdate `import` is a compile-time, once-only textual include; it returns nothing. Modules therefore define globals: `Geom`, `Field`, `Player`, `Ball`, `Goalie`, `Game`, `Render`, `Audio`, `Splash`, `runTests`.
- Screen is 400×240, 1-bit. Target **30fps** (`playdate.display.setRefreshRate(30)`).
- Field layout constants (from spec, do not change without updating the spec first): track `x ∈ [50, 350]`, player y `205`; goal `x ∈ [140, 260]`, goal y `50`, goalie rest position `x = 200` — the goalie moves within this same `[140, 260]` range, since shot aim is always clamped inside the goal frame (no wide misses) and so the goalie never needs to defend outside the posts either; ball scale `0.3` (far) → `1.0` (near); contact band half-width `45px`; save radius `26px`.
- Shot-mechanic constants (from spec): serve duration `1.6s`; contact window opens at `82%` of serve progress; flick velocity threshold `900°/s`; reference velocity `1800°/s` (→ power `1.0`); power range `[0.5, 1.0]` (0.5 is the power at exactly the threshold velocity — there is no lower floor to clamp to, since a sub-threshold flick never registers as a strike in the first place); shot flight time `0.55s` (min power) → `0.22s` (max power); goalie speed `min(60 + 4 × streak, 100)` px/s (ramp caps around streak 10). The save check is `Geom.inBand(goalieX, shotTargetX, Field.SAVE_RADIUS)` — the goalie's 26px save radius is free coverage, so the "always beatable" fairness margin is measured against `halfGoalWidth − saveRadius` (34px), not `halfGoalWidth` alone (60px); an earlier draft of this speed (140/8/220) sized against the full 60px and was wrong once the save radius existed — see the spec's Goalie & Difficulty section.
- **Sprite art deferred.** The spec allows image assets for the player/goalie/ball (unlike submariner's zero-asset rule), but no art exists yet this session. Every task below draws these as simple code-drawn silhouettes instead — small, focused draw functions (`drawPlayerMarker`, `drawGoalieMarker`, `drawBallMarker`) called from one place each in `render.lua`, so swapping in real sprite images later is a localized change to those three functions, not a redesign.
- No host Lua exists on this machine. Pure-math tests run at boot **inside the simulator** (`runTests()` guarded by `playdate.isSimulator`) and print to the simulator console. To see console output, launch the simulator binary directly: `"$HOME/Developer/PlaydateSDK/bin/Playdate Simulator.app/Contents/MacOS/Playdate Simulator" Foosball.pdx`. A failed assertion calls `error()`, which the simulator surfaces as a crash screen.
- `playdate.graphics.setDitherPattern(alpha, ditherType)` has a documented quirk: alpha runs inverted vs. intuition for black ink. All dithered fills go through the `setInk(darkness)` helper defined in Task 3 — never call `setDitherPattern` directly elsewhere.
- Commit messages: plain descriptive sentences. **Never** use Conventional Commit prefixes (`feat:`, `fix:`, etc.). Every commit uses `git -c commit.gpgsign=false commit -m "..."` — the config override goes before the `commit` subcommand, not after (`commit -c` is a different flag meaning "reuse a commit's message," not a config override) — (repo has signing on; the user has authorized unsigned commits while away for this build).
- **Screenshot harness** (`source/shots.lua`, created in Task 3): the simulator-only pattern this project uses for automated visual verification instead of a GUI. Each `Shots.plan` entry is `{ after = <seconds>, target = <a Global table, e.g. Player>, set = { <field> = <value>, ... }, call = <function, optional>, path = "<absolute .png path>" }`. While an entry is pending, its `set` fields are pinned onto `target` every frame (so e.g. `Player.x` can be forced to a specific value for a deterministic capture); `call`, if present, runs once the frame the entry becomes active — used for things a field-pin can't express, like forcing a `playdate.datastore.write`. After the last entry's screenshot is written, the simulator exits. **Committed code always has an empty plan (`Shots.plan = {}`)** — every task below reverts it before committing.
- **Smoke-test recipe** (used throughout this plan in place of GUI `make run`, so a subagent can verify without a human watching the simulator):

  ```bash
  make build
  rm -f /tmp/foosball-<name>*.png
  timeout -k 5 15 "$HOME/Developer/PlaydateSDK/bin/Playdate Simulator.app/Contents/MacOS/Playdate Simulator" Foosball.pdx > /tmp/foosball-<name>.log 2>&1
  ls -la /tmp/foosball-<name>*.png
  ```

  Use `timeout -k 5 15 ...`, not plain `timeout 15 ...` — plain SIGTERM does not reliably kill the GUI simulator app. `-k 5` forces a SIGKILL 5s after the deadline if it doesn't exit on its own.

  If `source/tests.lua`'s boot assertions fail, `runTests()` throws before the update loop (and thus `Shots.update`) ever runs — the simulator hangs on an error dialog with **no screenshot file written** until `timeout -k` kills it. If boot succeeds, `Shots` writes every configured screenshot and then calls `playdate.simulator.exit()`, which segfaults when the simulator is launched this way (bypassing the normal `.app` launch path) — **that segfault is expected and not a failure signal**; only the presence/absence and content of the screenshot file(s) matter. A Lua *runtime* error (as opposed to a syntax error `pdc` would catch) produces this exact same "no screenshot, needs SIGKILL" signature.
- Checks that genuinely need human interaction (crank flick feel, timing-window feel, goalie difficulty ramp feel, audio character) are deferred to the human acceptance pass in the final task — list them explicitly rather than skipping silently.

---

### Task 1: Project skeleton boots in the simulator

**Files:**
- Create: `source/pdxinfo`
- Create: `source/main.lua`
- Create: `Makefile`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: `make build` → `Foosball.pdx`; `make run` → opens simulator. `source/main.lua` with a `playdate.update` loop later tasks extend.

- [ ] **Step 1: Write `source/pdxinfo`**

```
name=Foosball Shootout
author=Super Tiny Labs
description=An arcade foosball shootout.
bundleID=com.supertinylabs.foosball
version=0.1
buildNumber=1
```

- [ ] **Step 2: Write minimal `source/main.lua`**

```lua
import "CoreLibs/graphics"

local gfx = playdate.graphics

playdate.display.setRefreshRate(30)

function playdate.update()
    gfx.clear(gfx.kColorWhite)
    gfx.drawTextAligned("FOOSBALL SHOOTOUT", 200, 112, kTextAlignment.center)
end
```

- [ ] **Step 3: Write `Makefile`**

```make
SDK = $(HOME)/Developer/PlaydateSDK
PDX = Foosball.pdx

build:
	"$(SDK)/bin/pdc" source $(PDX)

run: build
	open -a "$(SDK)/bin/Playdate Simulator.app" $(PDX)

clean:
	rm -rf $(PDX)

.PHONY: build run clean
```

(Indentation under each target must be a TAB, not spaces.)

- [ ] **Step 4: Build**

Run: `make build`
Expected: exits 0; `ls Foosball.pdx` shows `main.pdz` and `pdxinfo`.

- [ ] **Step 5: Smoke-test boot**

```bash
timeout -k 5 15 "$HOME/Developer/PlaydateSDK/bin/Playdate Simulator.app/Contents/MacOS/Playdate Simulator" Foosball.pdx > /tmp/foosball-task1.log 2>&1
cat /tmp/foosball-task1.log
```

Expected: no crash-dialog text in the log (there's no `Shots` harness yet, so this only proves the simulator didn't immediately error on boot — visually confirm with `make run` if you want to see the "FOOSBALL SHOOTOUT" text, but that step is optional here).

- [ ] **Step 6: Commit**

```bash
git add source Makefile
git -c commit.gpgsign=false commit -m "Add Playdate project skeleton that boots in the simulator"
```

---

### Task 2: Geom math module with boot-time test suite

**Files:**
- Create: `source/tests.lua` (first — this is the failing test)
- Create: `source/geom.lua`
- Modify: `source/main.lua`

**Interfaces:**
- Consumes: Task 1 skeleton.
- Produces the `Geom` global used by every later task:
  - `Geom.clamp(v, lo, hi) -> number`
  - `Geom.lerp(a, b, t) -> number`
  - `Geom.inBand(x, center, halfWidth) -> bool`
  - `Geom.flickPower(velocityDegPerSec, referenceVelocity, minPower, maxPower) -> number`
  - `Geom.shotFlightTime(power, powerMin, powerMax, timeAtMin, timeAtMax) -> number`
  - `Geom.goalieSpeed(streak, base, ramp, cap) -> number`
  - Global `runTests()` (asserts, then prints `geom tests: all passed`).

- [ ] **Step 1: Write the failing test — `source/tests.lua`**

```lua
import "geom"

function runTests()
    local function eq(actual, expected, msg)
        if math.abs(actual - expected) > 1e-9 then
            error(string.format("FAIL %s: expected %s, got %s",
                msg, tostring(expected), tostring(actual)))
        end
    end

    eq(Geom.clamp(5, 0, 1), 1, "clamp high")
    eq(Geom.clamp(-5, 0, 1), 0, "clamp low")
    eq(Geom.clamp(0.5, 0, 1), 0.5, "clamp inside")

    eq(Geom.lerp(0, 10, 0), 0, "lerp at 0")
    eq(Geom.lerp(0, 10, 1), 10, "lerp at 1")
    eq(Geom.lerp(0, 10, 0.5), 5, "lerp at midpoint")
    eq(Geom.lerp(10, 0, 0.25), 7.5, "lerp descending")

    eq(Geom.flickPower(1800, 1800, 0.5, 1.0), 1.0, "flick power at reference velocity")
    eq(Geom.flickPower(900, 1800, 0.5, 1.0), 0.5, "flick power at threshold velocity")
    eq(Geom.flickPower(3600, 1800, 0.5, 1.0), 1.0, "flick power clamped at max")

    eq(Geom.shotFlightTime(0.5, 0.5, 1.0, 0.55, 0.22), 0.55, "shot time at min power")
    eq(Geom.shotFlightTime(1.0, 0.5, 1.0, 0.55, 0.22), 0.22, "shot time at max power")
    eq(Geom.shotFlightTime(0.75, 0.5, 1.0, 0.55, 0.22), 0.385, "shot time at half power")

    eq(Geom.goalieSpeed(0, 60, 4, 100), 60, "goalie speed at streak 0")
    eq(Geom.goalieSpeed(5, 60, 4, 100), 80, "goalie speed ramping")
    eq(Geom.goalieSpeed(50, 60, 4, 100), 100, "goalie speed capped")

    print("geom tests: all passed")
end
```

- [ ] **Step 2: Wire tests into `source/main.lua`** (full replacement)

```lua
import "CoreLibs/graphics"
import "tests"

local gfx = playdate.graphics

playdate.display.setRefreshRate(30)

if playdate.isSimulator then
    runTests()
end

function playdate.update()
    gfx.clear(gfx.kColorWhite)
    gfx.drawTextAligned("FOOSBALL SHOOTOUT", 200, 112, kTextAlignment.center)
end
```

- [ ] **Step 3: Run to verify it fails**

Run: `make build`
Expected: FAIL — `pdc` errors because `geom.lua` does not exist (`import "geom"` cannot resolve).

- [ ] **Step 4: Write minimal implementation — `source/geom.lua`**

```lua
Geom = {}

function Geom.clamp(v, lo, hi)
    if v < lo then
        return lo
    elseif v > hi then
        return hi
    end
    return v
end

function Geom.lerp(a, b, t)
    return a + (b - a) * t
end

-- True if x is within halfWidth of center — used both for "is the player
-- close enough to the ball to make contact" and "is the goalie close enough
-- to the shot's target to save it."
function Geom.inBand(x, center, halfWidth)
    return math.abs(x - center) <= halfWidth
end

-- Normalizes a measured crank angular velocity against a reference velocity
-- that maps to full power, clamped to [minPower, maxPower].
function Geom.flickPower(velocityDegPerSec, referenceVelocity, minPower, maxPower)
    return Geom.clamp(velocityDegPerSec / referenceVelocity, minPower, maxPower)
end

-- Harder shots (higher power) fly faster: this lerps from timeAtMin (at
-- powerMin) to timeAtMax (at powerMax).
function Geom.shotFlightTime(power, powerMin, powerMax, timeAtMin, timeAtMax)
    local t = (power - powerMin) / (powerMax - powerMin)
    return Geom.lerp(timeAtMin, timeAtMax, t)
end

-- Goalie reaction speed ramps with streak, capped at a max.
function Geom.goalieSpeed(streak, base, ramp, cap)
    return math.min(base + ramp * streak, cap)
end
```

- [ ] **Step 5: Run to verify it passes**

```bash
make build
timeout -k 5 15 "$HOME/Developer/PlaydateSDK/bin/Playdate Simulator.app/Contents/MacOS/Playdate Simulator" Foosball.pdx > /tmp/foosball-task2.log 2>&1
cat /tmp/foosball-task2.log
```

Expected: log includes `geom tests: all passed`; no crash-dialog text.

- [ ] **Step 6: Commit**

```bash
git add source
git -c commit.gpgsign=false commit -m "Add pure-math geom module with boot-time tests"
```

---

### Task 3: Field layout constants + static pitch/goal view + screenshot harness

**Files:**
- Create: `source/field.lua`
- Create: `source/render.lua`
- Create: `source/shots.lua`
- Modify: `source/main.lua`

**Interfaces:**
- Consumes: nothing new.
- Produces: `Field` global (layout constants table, listed in Global Constraints). `Render.init()`, `Render.draw(dt)`. `Shots.plan`, `Shots.update(dt)` (screenshot harness, described in Global Constraints).

- [ ] **Step 1: Write `source/field.lua`**

```lua
Field = {
    TRACK_MIN = 50,
    TRACK_MAX = 350,
    PLAYER_Y = 205,

    GOAL_MIN = 140,
    GOAL_MAX = 260,
    GOAL_Y = 50,

    BALL_MIN_SCALE = 0.3,
    BALL_MAX_SCALE = 1.0,

    CONTACT_BAND_HALF = 45,
    SAVE_RADIUS = 26,
}

-- The goalie moves within [GOAL_MIN, GOAL_MAX] — the same range shot aim is
-- clamped to (Ball.shotTargetX in ball.lua) — since it never has to defend
-- outside the posts if shots can never aim outside them either.
Field.GOALIE_CENTER = (Field.GOAL_MIN + Field.GOAL_MAX) / 2
```

- [ ] **Step 2: Write `source/render.lua`**

```lua
import "CoreLibs/graphics"
import "geom"
import "field"

local gfx = playdate.graphics

Render = {}

-- setDitherPattern's alpha runs backwards for black ink (0 = solid black),
-- so express everything as "darkness" in [0,1] and invert here.
local function setInk(darkness)
    gfx.setColor(gfx.kColorBlack)
    gfx.setDitherPattern(1 - darkness, gfx.image.kDitherTypeBayer8x8)
end

function Render.init()
end

local NEAR_LEFT, NEAR_RIGHT = Field.TRACK_MIN - 30, Field.TRACK_MAX + 30
local FAR_LEFT, FAR_RIGHT = Field.GOAL_MIN - 20, Field.GOAL_MAX + 20

local function drawPitch()
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(2)
    gfx.drawLine(NEAR_LEFT, 240, FAR_LEFT, Field.GOAL_Y)
    gfx.drawLine(NEAR_RIGHT, 240, FAR_RIGHT, Field.GOAL_Y)
    gfx.setLineWidth(1)
end

local function drawGoal()
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(Field.GOAL_MIN, Field.GOAL_Y - 22, Field.GOAL_MAX - Field.GOAL_MIN, 22)
    setInk(0.15)
    gfx.fillRect(Field.GOAL_MIN, Field.GOAL_Y - 22, Field.GOAL_MAX - Field.GOAL_MIN, 22)
end

function Render.draw(dt)
    gfx.clear(gfx.kColorWhite)
    drawPitch()
    drawGoal()
end
```

- [ ] **Step 3: Write `source/shots.lua`**

```lua
-- Simulator-only screenshot harness for autonomous visual verification.
-- Each Shots.plan entry:
--   { after = <seconds>, target = <a Global table, e.g. Player>,
--     set = { <field> = <value>, ... }, call = <function, optional>,
--     path = "<absolute .png path>" }
-- While a shot is pending, its `set` fields are pinned onto `target` every
-- frame so the captured frame is deterministic. `call`, if present, runs
-- once the frame this entry becomes active, before any `set` pinning.
-- After the last shot the simulator exits. Committed code always has an
-- empty plan.
Shots = { plan = {}, t = 0, i = 1, called = false }

function Shots.update(dt)
    if not playdate.isSimulator then
        return
    end
    -- Guards against a stale Shots.i/t/called left over from a previous
    -- test run: an empty plan is always a no-op, regardless of what those
    -- fields were last set to. Without this, reverting only `Shots.plan`
    -- to `{}` (as every task's smoke test does) while `Shots.i` was left
    -- above 1 would make `make run` exit the simulator on its first frame.
    if #Shots.plan == 0 then
        return
    end
    local shot = Shots.plan[Shots.i]
    if not shot then
        if Shots.i > 1 then
            playdate.simulator.exit()
        end
        return
    end
    if shot.call and not Shots.called then
        shot.call()
        Shots.called = true
    end
    if shot.set and shot.target then
        for k, v in pairs(shot.set) do
            shot.target[k] = v
        end
    end
    Shots.t = Shots.t + dt
    if Shots.t >= shot.after then
        playdate.simulator.writeToFile(playdate.graphics.getDisplayImage(), shot.path)
        Shots.t = 0
        Shots.i = Shots.i + 1
        Shots.called = false
    end
end
```

- [ ] **Step 4: Wire into `source/main.lua`** (full replacement)

```lua
import "CoreLibs/graphics"
import "tests"
import "field"
import "render"
import "shots"

playdate.display.setRefreshRate(30)

Render.init()
if playdate.isSimulator then
    runTests()
end

function playdate.update()
    local dt = playdate.getElapsedTime()
    playdate.resetElapsedTime()
    if dt <= 0 or dt > 0.25 then
        dt = 1 / 30
    end
    Render.draw(dt)
    Shots.update(dt)
end
```

- [ ] **Step 5: Screenshot smoke test of the static pitch/goal**

In `source/shots.lua`, temporarily set:

```lua
Shots = { plan = {
    { after = 0.1, path = "/tmp/foosball-task3.png" },
}, t = 0, i = 1, called = false }
```

Run:

```bash
make build
rm -f /tmp/foosball-task3.png
timeout -k 5 15 "$HOME/Developer/PlaydateSDK/bin/Playdate Simulator.app/Contents/MacOS/Playdate Simulator" Foosball.pdx > /tmp/foosball-task3.log 2>&1
ls -la /tmp/foosball-task3.png
```

Expected: file exists. Use the Read tool to view it: two converging lines from the bottom corners narrowing to a goal-line width near the top, with a dithered goal box sitting on that line. If the trapezoid looks inverted (wider at top) or the goal box is off the line, fix the coordinates in `drawPitch`/`drawGoal` and re-run.

- [ ] **Step 6: Revert the smoke-test probe**

In `source/shots.lua`, set `Shots.plan` back to `{}`: `Shots = { plan = {}, t = 0, i = 1, called = false }`.

- [ ] **Step 7: Commit**

```bash
git add source
git -c commit.gpgsign=false commit -m "Add field layout constants, static pitch/goal view, and screenshot harness"
```

---

### Task 4: Player movement (d-pad → track position)

**Files:**
- Create: `source/player.lua`
- Modify: `source/render.lua`
- Modify: `source/main.lua`
- Modify (temporary, reverted before commit): `source/shots.lua`

**Interfaces:**
- Consumes: `Geom.clamp` (Task 2), `Field.TRACK_MIN`/`TRACK_MAX`/`PLAYER_Y` (Task 3).
- Produces: `Player.x` (number, clamped to `[Field.TRACK_MIN, Field.TRACK_MAX]`), `Player.SPEED` (260 px/s), `Player.init()`, `Player.update(dt)`. Later tasks (`ball.lua`, `render.lua`'s goalie/HUD code) read `Player.x`.

- [ ] **Step 1: Write `source/player.lua`**

```lua
import "geom"
import "field"

Player = { x = 200 }

Player.SPEED = 260

function Player.init()
    Player.x = 200
end

function Player.update(dt)
    if playdate.buttonIsPressed(playdate.kButtonLeft) then
        Player.x = Player.x - Player.SPEED * dt
    end
    if playdate.buttonIsPressed(playdate.kButtonRight) then
        Player.x = Player.x + Player.SPEED * dt
    end
    Player.x = Geom.clamp(Player.x, Field.TRACK_MIN, Field.TRACK_MAX)
end
```

- [ ] **Step 2: Draw the player marker in `source/render.lua`**

Add this function after `drawGoal` (before `function Render.draw`):

```lua
local function drawPlayerMarker()
    gfx.setColor(gfx.kColorBlack)
    local x, y = Player.x, Field.PLAYER_Y
    gfx.fillCircleAtPoint(x, y - 14, 8)
    gfx.fillTriangle(x - 12, y + 20, x + 12, y + 20, x, y - 4)
end
```

Add `import "player"` to the top of `source/render.lua` (after `import "field"`), and in `Render.draw`, call it after `drawGoal()`:

```lua
function Render.draw(dt)
    gfx.clear(gfx.kColorWhite)
    drawPitch()
    drawGoal()
    drawPlayerMarker()
end
```

- [ ] **Step 3: Wire into `source/main.lua`** (full replacement)

```lua
import "CoreLibs/graphics"
import "tests"
import "field"
import "player"
import "render"
import "shots"

playdate.display.setRefreshRate(30)

Render.init()
Player.init()
if playdate.isSimulator then
    runTests()
end

function playdate.update()
    local dt = playdate.getElapsedTime()
    playdate.resetElapsedTime()
    if dt <= 0 or dt > 0.25 then
        dt = 1 / 30
    end
    Player.update(dt)
    Render.draw(dt)
    Shots.update(dt)
end
```

- [ ] **Step 4: Screenshot smoke test at both track extremes**

In `source/shots.lua`, set:

```lua
Shots = { plan = {
    { after = 0.1, target = Player, set = { x = 60 },  path = "/tmp/foosball-task4-left.png" },
    { after = 0.1, target = Player, set = { x = 340 }, path = "/tmp/foosball-task4-right.png" },
}, t = 0, i = 1, called = false }
```

Run:

```bash
make build
rm -f /tmp/foosball-task4-*.png
timeout -k 5 15 "$HOME/Developer/PlaydateSDK/bin/Playdate Simulator.app/Contents/MacOS/Playdate Simulator" Foosball.pdx > /tmp/foosball-task4.log 2>&1
ls -la /tmp/foosball-task4-*.png
```

Expected: both files exist. Use the Read tool to view them: the player marker sits near the left touchline in `-left.png` and near the right touchline in `-right.png`.

- [ ] **Step 5: Revert the smoke-test probe**

In `source/shots.lua`, set `Shots.plan` back to `{}`.

- [ ] **Step 6: Commit**

```bash
git add source
git -c commit.gpgsign=false commit -m "Add player d-pad movement along the track"
```

---

### Task 5: Ball serve state machine (approach → contact window → timeout)

This task builds the serve/approach/timeout cycle in isolation, with no crank input yet — the ball simply approaches, and if nothing intercepts it (nothing does yet), the window times out as a "too slow" whiff and a new ball serves. Task 6 adds the crank-driven contact path.

**Files:**
- Create: `source/ball.lua`
- Modify: `source/render.lua`
- Modify: `source/main.lua`
- Modify (temporary, reverted before commit): `source/shots.lua`

**Interfaces:**
- Consumes: `Geom.clamp`, `Geom.lerp` (Task 2), `Field.TRACK_MIN`/`TRACK_MAX`/`GOAL_Y`/`PLAYER_Y`/`BALL_MIN_SCALE`/`BALL_MAX_SCALE` (Task 3).
- Produces: `Ball.state` (one of `"approach"`, `"window"`, `"resolved"` — Task 6 adds `"flight"`/`"flightComplete"`), `Ball.progress` (0..1), `Ball.laneX`, `Ball.result` (nil or a result string), `Ball.resultPending` (bool, true for exactly one frame when a result was just set), `Ball.T_SERVE` (1.6), `Ball.WINDOW_START` (0.82), `Ball.MISS_PAUSE` (1.5), `Ball.init()`, `Ball.update(dt)`, `Ball.startServe()`, `Ball.screenX()`, `Ball.screenY()`, `Ball.screenScale()`. Later tasks (`goalie.lua`, `game.lua`, `render.lua`) read all of these.

- [ ] **Step 1: Write `source/ball.lua`**

```lua
import "geom"
import "field"

Ball = {
    state = "approach",
    progress = 0,
    laneX = 200,
    result = nil,
    resultPending = false,
    resolvedTimer = 0,
}

Ball.T_SERVE = 1.6
Ball.WINDOW_START = 0.82
Ball.MISS_PAUSE = 1.5

local function randomLaneX()
    return Field.TRACK_MIN + math.random() * (Field.TRACK_MAX - Field.TRACK_MIN)
end

function Ball.startServe()
    Ball.state = "approach"
    Ball.progress = 0
    Ball.laneX = randomLaneX()
    Ball.result = nil
end

function Ball.init()
    Ball.startServe()
    Ball.resolvedTimer = 0
    Ball.resultPending = false
end

function Ball.update(dt)
    Ball.resultPending = false

    if Ball.state == "approach" or Ball.state == "window" then
        Ball.progress = Ball.progress + dt / Ball.T_SERVE
        if Ball.state == "approach" and Ball.progress >= Ball.WINDOW_START then
            Ball.state = "window"
        end
        if Ball.progress >= 1.0 then
            Ball.progress = 1.0
            Ball.result = "tooSlow"
            Ball.resultPending = true
            Ball.state = "resolved"
            Ball.resolvedTimer = 0
        end
    elseif Ball.state == "resolved" then
        Ball.resolvedTimer = Ball.resolvedTimer + dt
        if Ball.resolvedTimer >= Ball.MISS_PAUSE then
            Ball.startServe()
        end
    end
end

function Ball.screenX()
    return Ball.laneX
end

function Ball.screenY()
    return Geom.lerp(Field.GOAL_Y, Field.PLAYER_Y, Geom.clamp(Ball.progress, 0, 1))
end

function Ball.screenScale()
    return Geom.lerp(Field.BALL_MIN_SCALE, Field.BALL_MAX_SCALE, Geom.clamp(Ball.progress, 0, 1))
end
```

- [ ] **Step 2: Draw the ball marker in `source/render.lua`**

Add `import "ball"` to the top (after `import "player"`), and this function after `drawPlayerMarker`:

```lua
local function drawBallMarker()
    gfx.setColor(gfx.kColorBlack)
    gfx.fillCircleAtPoint(Ball.screenX(), Ball.screenY(), 6 * Ball.screenScale())
end
```

In `Render.draw`, draw the ball before the player marker (so the player always reads on top at the point of contact):

```lua
function Render.draw(dt)
    gfx.clear(gfx.kColorWhite)
    drawPitch()
    drawGoal()
    drawBallMarker()
    drawPlayerMarker()
end
```

- [ ] **Step 3: Wire into `source/main.lua`** (full replacement)

```lua
import "CoreLibs/graphics"
import "tests"
import "field"
import "player"
import "ball"
import "render"
import "shots"

playdate.display.setRefreshRate(30)
math.randomseed(playdate.getSecondsSinceEpoch())

Render.init()
Player.init()
Ball.init()
if playdate.isSimulator then
    runTests()
end

function playdate.update()
    local dt = playdate.getElapsedTime()
    playdate.resetElapsedTime()
    if dt <= 0 or dt > 0.25 then
        dt = 1 / 30
    end
    Player.update(dt)
    Ball.update(dt)
    Render.draw(dt)
    Shots.update(dt)
end
```

- [ ] **Step 4: Screenshot smoke test of approach scale/position and the timeout whiff**

In `source/shots.lua`, set:

```lua
Shots = { plan = {
    { after = 0.1, target = Ball, set = { state = "approach", progress = 0.05, laneX = 200 }, path = "/tmp/foosball-task5-far.png" },
    { after = 0.1, target = Ball, set = { state = "window", progress = 0.95, laneX = 100 },   path = "/tmp/foosball-task5-near.png" },
    { after = 0.1, target = Ball, set = { state = "window", progress = 0.999, laneX = 200 },  path = "/tmp/foosball-task5-timeout.png" },
}, t = 0, i = 1, called = false }
```

Run:

```bash
make build
rm -f /tmp/foosball-task5-*.png
timeout -k 5 15 "$HOME/Developer/PlaydateSDK/bin/Playdate Simulator.app/Contents/MacOS/Playdate Simulator" Foosball.pdx > /tmp/foosball-task5.log 2>&1
ls -la /tmp/foosball-task5-*.png
```

Expected: all three files exist. Use the Read tool to view each:
- `foosball-task5-far.png`: a small ball marker near the goal line, at the pitch's horizontal center.
- `foosball-task5-near.png`: a noticeably larger ball marker low on screen, near the left side of the track.
- `foosball-task5-timeout.png`: pinning `progress = 0.999` puts the ball one frame away from `Ball.update` pushing it past `1.0` and resolving to `"tooSlow"` — the ball marker should be at (or very near) full size at the player's y-position. (This step exercises the approach/window rendering path; the timeout transition itself is exercised structurally by the state machine code and re-verified end-to-end once contact exists in Task 6.)

- [ ] **Step 5: Revert the smoke-test probe**

In `source/shots.lua`, set `Shots.plan` back to `{}`.

- [ ] **Step 6: Commit**

```bash
git add source
git -c commit.gpgsign=false commit -m "Add ball serve state machine: approach, contact window, timeout"
```

---

### Task 6: Crank flick, contact band, whiff, and flight

Adds the crank-driven contact path: a qualifying flick inside the contact band transitions the ball to `"flight"`; an out-of-band flick is an immediate `"missedBall"` whiff. There's no goalie yet, so this task ends flight with a placeholder that always resolves as a goal — Task 7 replaces that placeholder with a real save/goal check.

**Files:**
- Modify: `source/ball.lua` (full-file rewrite — many small, non-contiguous edits)
- Modify: `source/render.lua`
- Modify: `source/main.lua`
- Modify (temporary, reverted before commit): `source/shots.lua`

**Interfaces:**
- Consumes: `Player.x` (Task 4); `Geom.inBand`, `Geom.flickPower`, `Geom.shotFlightTime` (Task 2); `Field.CONTACT_BAND_HALF`, `Field.GOAL_MIN`/`GOAL_MAX`, `Field.SAVE_RADIUS` (Task 3).
- Produces: `Ball.state` gains `"flight"` and `"flightComplete"`. New fields `Ball.contactX` (raw player position at contact, track-space), `Ball.shotTargetX` (contact position clamped into goal-space — this is what a goalie compares against), `Ball.contactPower`, `Ball.flightT`, `Ball.flightDuration`, constants `Ball.FLICK_THRESHOLD` (900), `Ball.REFERENCE_VELOCITY` (1800), `Ball.POWER_MIN` (0.5), `Ball.POWER_MAX` (1.0), `Ball.SHOT_TIME_MIN` (0.22), `Ball.SHOT_TIME_MAX` (0.55), `Ball.GOAL_PAUSE` (1.0). New function `Ball.resolve(goalieX)` — compares `goalieX` against `Ball.shotTargetX` within `Field.SAVE_RADIUS` and sets `Ball.result` to `"save"` or `"goal"`. `Ball.update(dt)` stops advancing once `Ball.state == "flightComplete"` and waits for something external to call `Ball.resolve` — Task 7's `Goalie.lua` is what supplies a real `goalieX`; this task's `main.lua` supplies a placeholder.

- [ ] **Step 1: Rewrite `source/ball.lua`**

```lua
import "geom"
import "field"

Ball = {
    state = "approach",
    progress = 0,
    laneX = 200,
    contactX = nil,
    shotTargetX = nil,
    contactPower = nil,
    flightT = 0,
    flightDuration = 0,
    result = nil,
    resultPending = false,
    resolvedTimer = 0,
}

Ball.T_SERVE = 1.6
Ball.WINDOW_START = 0.82
Ball.MISS_PAUSE = 1.5
Ball.GOAL_PAUSE = 1.0

Ball.FLICK_THRESHOLD = 900
Ball.REFERENCE_VELOCITY = 1800
Ball.POWER_MIN = 0.5
Ball.POWER_MAX = 1.0
Ball.SHOT_TIME_MIN = 0.22
Ball.SHOT_TIME_MAX = 0.55

local function randomLaneX()
    return Field.TRACK_MIN + math.random() * (Field.TRACK_MAX - Field.TRACK_MIN)
end

function Ball.startServe()
    Ball.state = "approach"
    Ball.progress = 0
    Ball.laneX = randomLaneX()
    Ball.contactX = nil
    Ball.shotTargetX = nil
    Ball.contactPower = nil
    Ball.result = nil
end

function Ball.init()
    Ball.startServe()
    Ball.resolvedTimer = 0
    Ball.resultPending = false
end

local function registerWhiff(result)
    Ball.result = result
    Ball.resultPending = true
    Ball.state = "resolved"
    Ball.resolvedTimer = 0
end

local function registerContact(velocity, dt)
    Ball.contactX = Player.x
    Ball.shotTargetX = Geom.clamp(Player.x, Field.GOAL_MIN, Field.GOAL_MAX)
    Ball.contactPower = Geom.flickPower(velocity, Ball.REFERENCE_VELOCITY, Ball.POWER_MIN, Ball.POWER_MAX)
    Ball.flightDuration = Geom.shotFlightTime(Ball.contactPower, Ball.POWER_MIN, Ball.POWER_MAX,
        Ball.SHOT_TIME_MAX, Ball.SHOT_TIME_MIN)
    Ball.flightT = 0
    Ball.state = "flight"
end

function Ball.update(dt)
    Ball.resultPending = false

    -- playdate.getCrankChange() returns the delta since it was last called,
    -- not since the last frame — it must be polled (and its value discarded)
    -- every single frame regardless of state, or crank motion during the
    -- ~1.3s "approach" phase (or an entire splash screen, once Splash exists)
    -- accumulates undrained and dumps as one inflated reading the instant
    -- "window" opens, producing a velocity spike the player never intended.
    local crankVelocity = math.abs(playdate.getCrankChange()) / dt

    if Ball.state == "approach" or Ball.state == "window" then
        Ball.progress = Ball.progress + dt / Ball.T_SERVE

        if Ball.state == "approach" and Ball.progress >= Ball.WINDOW_START then
            Ball.state = "window"
        end

        if Ball.state == "window" then
            if crankVelocity >= Ball.FLICK_THRESHOLD then
                if Geom.inBand(Player.x, Ball.laneX, Field.CONTACT_BAND_HALF) then
                    registerContact(crankVelocity, dt)
                else
                    registerWhiff("missedBall")
                end
            end
        end

        if Ball.state == "window" and Ball.progress >= 1.0 then
            Ball.progress = 1.0
            registerWhiff("tooSlow")
        end
    elseif Ball.state == "flight" then
        Ball.flightT = Ball.flightT + dt
        if Ball.flightT >= Ball.flightDuration then
            Ball.state = "flightComplete"
        end
    elseif Ball.state == "resolved" then
        Ball.resolvedTimer = Ball.resolvedTimer + dt
        local pause = (Ball.result == "goal") and Ball.GOAL_PAUSE or Ball.MISS_PAUSE
        if Ball.resolvedTimer >= pause then
            Ball.startServe()
        end
    end
    -- "flightComplete": intentionally left untouched here. main.lua checks
    -- for this state and calls Ball.resolve(goalieX) once, before the next
    -- frame's Ball.update runs — keeps ball.lua from ever reading Goalie
    -- directly, so the dependency between the two modules stays one-way.
end

function Ball.resolve(goalieX)
    Ball.result = Geom.inBand(goalieX, Ball.shotTargetX, Field.SAVE_RADIUS) and "save" or "goal"
    Ball.resultPending = true
    Ball.state = "resolved"
    Ball.resolvedTimer = 0
end

local function flightProgress()
    if Ball.flightDuration <= 0 then
        return 1
    end
    return Geom.clamp(Ball.flightT / Ball.flightDuration, 0, 1)
end

local function ballAtGoal()
    return Ball.state == "resolved" and (Ball.result == "goal" or Ball.result == "save")
end

function Ball.screenX()
    if Ball.state == "flight" or Ball.state == "flightComplete" then
        return Geom.lerp(Ball.contactX, Ball.shotTargetX, flightProgress())
    elseif ballAtGoal() then
        return Ball.shotTargetX
    end
    return Ball.laneX
end

function Ball.screenY()
    if Ball.state == "flight" or Ball.state == "flightComplete" then
        return Geom.lerp(Field.PLAYER_Y, Field.GOAL_Y, flightProgress())
    elseif ballAtGoal() then
        return Field.GOAL_Y
    end
    return Geom.lerp(Field.GOAL_Y, Field.PLAYER_Y, Geom.clamp(Ball.progress, 0, 1))
end

function Ball.screenScale()
    if Ball.state == "flight" or Ball.state == "flightComplete" then
        return Geom.lerp(Field.BALL_MAX_SCALE, Field.BALL_MIN_SCALE, flightProgress())
    elseif ballAtGoal() then
        return Field.BALL_MIN_SCALE
    end
    return Geom.lerp(Field.BALL_MIN_SCALE, Field.BALL_MAX_SCALE, Geom.clamp(Ball.progress, 0, 1))
end
```

- [ ] **Step 2: Wire the placeholder resolution + crank indicator into `source/main.lua`** (full replacement)

```lua
import "CoreLibs/graphics"
import "CoreLibs/ui"
import "tests"
import "field"
import "player"
import "ball"
import "render"
import "shots"

playdate.display.setRefreshRate(30)
math.randomseed(playdate.getSecondsSinceEpoch())

Render.init()
Player.init()
Ball.init()
if playdate.isSimulator then
    runTests()
end

function playdate.update()
    local dt = playdate.getElapsedTime()
    playdate.resetElapsedTime()
    if dt <= 0 or dt > 0.25 then
        dt = 1 / 30
    end
    Player.update(dt)
    Ball.update(dt)
    if Ball.state == "flightComplete" then
        -- No goalie until Task 7 — 9999 is outside Field.SAVE_RADIUS of any
        -- possible Ball.shotTargetX, so this always resolves as a goal.
        Ball.resolve(9999)
    end
    Render.draw(dt)
    Shots.update(dt)
    if playdate.isCrankDocked() then
        playdate.ui.crankIndicator:draw()
    end
end
```

- [ ] **Step 3: Screenshot smoke test of the flight and post-goal visuals**

`Ball.update` reads `playdate.getCrankChange()`, which this headless harness has no way to script — real crank-flick feel is unverifiable by screenshot and is deferred to the human acceptance checklist in the final task. This step instead verifies `render.lua`'s new flight-phase drawing by pinning `Ball`'s fields directly, bypassing the crank-reading code entirely.

In `source/shots.lua`, set:

```lua
Shots = { plan = {
    { after = 0.1, target = Ball, set = {
        state = "flight", contactX = 90, shotTargetX = 150, flightT = 0, flightDuration = 0.4,
    }, path = "/tmp/foosball-task6-flight-start.png" },
    { after = 0.1, target = Ball, set = {
        state = "flight", contactX = 90, shotTargetX = 150, flightT = 0.38, flightDuration = 0.4,
    }, path = "/tmp/foosball-task6-flight-end.png" },
    { after = 0.1, target = Ball, set = {
        state = "resolved", result = "goal", shotTargetX = 230,
    }, path = "/tmp/foosball-task6-goal.png" },
}, t = 0, i = 1, called = false }
```

Run:

```bash
make build
rm -f /tmp/foosball-task6-*.png
timeout -k 5 15 "$HOME/Developer/PlaydateSDK/bin/Playdate Simulator.app/Contents/MacOS/Playdate Simulator" Foosball.pdx > /tmp/foosball-task6.log 2>&1
ls -la /tmp/foosball-task6-*.png
```

Expected: all three files exist. Use the Read tool to view each:
- `foosball-task6-flight-start.png`: ball marker large, low on screen, near x=90 (left of center) — just after contact.
- `foosball-task6-flight-end.png`: ball marker much smaller, high on screen, near x=150 — about to reach the goal.
- `foosball-task6-goal.png`: ball marker at minimum size, sitting on the goal line at x=230.

- [ ] **Step 4: Revert the smoke-test probe**

In `source/shots.lua`, set `Shots.plan` back to `{}`.

- [ ] **Step 5: Commit**

```bash
git add source
git -c commit.gpgsign=false commit -m "Add crank flick detection, contact band, whiff, and shot flight"
```

---

### Task 7: Goalie AI and real save/goal resolution

Replaces Task 6's "always a goal" placeholder with a real goalie that only starts moving once a shot's target is known, at a speed passed in from `main.lua` (not read from a `Game` global — `Game` doesn't exist until Task 8, and keeping `Goalie` ignorant of it now means Task 8 only has to change the one call site in `main.lua`).

**Files:**
- Create: `source/goalie.lua`
- Modify: `source/render.lua`
- Modify: `source/main.lua`
- Modify (temporary, reverted before commit): `source/shots.lua`

**Interfaces:**
- Consumes: `Geom.goalieSpeed` (Task 2); `Field.GOALIE_CENTER` (Task 3); `Ball.state`, `Ball.shotTargetX` (Task 5/6).
- Produces: `Goalie.x`, `Goalie.BASE_SPEED` (60), `Goalie.RAMP_PER_STREAK` (4), `Goalie.MAX_SPEED` (100), `Goalie.init()`, `Goalie.update(dt, streak)`. Task 8 is the only later task that changes how `streak` is supplied to this call.

- [ ] **Step 1: Write `source/goalie.lua`**

```lua
import "geom"
import "field"
import "ball"

Goalie = { x = Field.GOALIE_CENTER }

Goalie.BASE_SPEED = 60
Goalie.RAMP_PER_STREAK = 4
Goalie.MAX_SPEED = 100

function Goalie.init()
    Goalie.x = Field.GOALIE_CENTER
end

function Goalie.update(dt, streak)
    local target = Field.GOALIE_CENTER
    if Ball.state == "flight" or Ball.state == "flightComplete" then
        target = Ball.shotTargetX
    end

    local speed = Geom.goalieSpeed(streak, Goalie.BASE_SPEED, Goalie.RAMP_PER_STREAK, Goalie.MAX_SPEED)
    local delta = target - Goalie.x
    local maxStep = speed * dt
    if math.abs(delta) <= maxStep then
        Goalie.x = target
    else
        Goalie.x = Goalie.x + maxStep * (delta > 0 and 1 or -1)
    end
end
```

- [ ] **Step 2: Draw the goalie marker in `source/render.lua`**

Add `import "goalie"` to the top (after `import "ball"`), and this function after `drawGoal` (before `drawPlayerMarker`):

```lua
local function drawGoalieMarker()
    gfx.setColor(gfx.kColorBlack)
    local x, y = Goalie.x, Field.GOAL_Y - 11
    gfx.fillRoundRect(x - 14, y - 6, 28, 12, 4)
end
```

In `Render.draw`, draw it after `drawGoal()` and before `drawBallMarker()`:

```lua
function Render.draw(dt)
    gfx.clear(gfx.kColorWhite)
    drawPitch()
    drawGoal()
    drawGoalieMarker()
    drawBallMarker()
    drawPlayerMarker()
end
```

- [ ] **Step 3: Wire the goalie into the resolution call in `source/main.lua`**

Add `import "goalie"` after `import "ball"`, add `Goalie.init()` after `Ball.init()`, and replace the body of `playdate.update`:

```lua
function playdate.update()
    local dt = playdate.getElapsedTime()
    playdate.resetElapsedTime()
    if dt <= 0 or dt > 0.25 then
        dt = 1 / 30
    end
    Player.update(dt)
    Ball.update(dt)
    Goalie.update(dt, 0) -- streak wiring lands in Task 8
    if Ball.state == "flightComplete" then
        Ball.resolve(Goalie.x)
    end
    Render.draw(dt)
    Shots.update(dt)
    if playdate.isCrankDocked() then
        playdate.ui.crankIndicator:draw()
    end
end
```

- [ ] **Step 4: Screenshot smoke test of goalie tracking and both outcomes**

In `source/shots.lua`, set:

```lua
Shots = { plan = {
    { after = 0.2, target = Ball, set = {
        state = "flight", contactX = 200, shotTargetX = 195, flightT = 0, flightDuration = 5,
    }, path = "/tmp/foosball-task7-save.png" },
    { after = 0.05, target = Ball, set = {
        state = "flight", contactX = 200, shotTargetX = 140, flightT = 0, flightDuration = 5,
    }, path = "/tmp/foosball-task7-goal.png" },
}, t = 0, i = 1, called = false }
```

`shotTargetX = 140` is the left goalpost — the farthest a shot can ever be aimed, since `Ball.shotTargetX` is always clamped to `[Field.GOAL_MIN, Field.GOAL_MAX]` (no wide misses, per spec). Pinning `flightDuration = 5` (far longer than the capture window) keeps `Ball.state` at `"flight"` throughout the capture, so `Goalie.update` keeps tracking `shotTargetX` the whole time without the flight ever completing and resetting the goalie back toward center.

Run:

```bash
make build
rm -f /tmp/foosball-task7-*.png
timeout -k 5 15 "$HOME/Developer/PlaydateSDK/bin/Playdate Simulator.app/Contents/MacOS/Playdate Simulator" Foosball.pdx > /tmp/foosball-task7.log 2>&1
ls -la /tmp/foosball-task7-*.png
```

Expected: both files exist. Use the Read tool to view each:
- `foosball-task7-save.png`: `shotTargetX = 195` is only 5px from the goalie's center rest position; at the base speed of 60px/s (streak hardcoded to 0 in this task's `main.lua`), 0.2s covers 12px — comfortable margin over the 5px needed, even accounting for a frame or two of capture-timing slop. The goalie marker should have already reached and be sitting right under the ball marker.
- `foosball-task7-goal.png`: `shotTargetX = 140` is 60px away (the farthest any shot can be aimed), captured after only ~0.05s — at 60px/s that's 3px of travel, so the goalie marker should have moved only slightly left of center, visibly far from the ball marker at the left post. (There's no on-screen text yet to state "SAVE"/"GOAL" outright — Task 8 adds the HUD that makes outcomes textually explicit. This step is a visual proxy: goalie overlapping the ball reads as a save, goalie visibly short of it reads as a goal.)

- [ ] **Step 5: Revert the smoke-test probe**

In `source/shots.lua`, set `Shots.plan` back to `{}`.

- [ ] **Step 6: Commit**

```bash
git add source
git -c commit.gpgsign=false commit -m "Add goalie AI and real save/goal resolution"
```

---

### Task 8: Game state — streak, best streak, persistence, HUD

**Files:**
- Create: `source/game.lua`
- Modify: `source/render.lua`
- Modify: `source/main.lua`
- Modify (temporary, reverted before commit): `source/shots.lua`

**Interfaces:**
- Consumes: `Ball.result`, `Ball.resultPending` (Task 6); `Goalie.update(dt, streak)` (Task 7, now driven by real streak instead of a hardcoded `0`).
- Produces: `Game.streak`, `Game.bestStreak`, `Game.init()` (loads `bestStreak` via `playdate.datastore.read()`), `Game.onResult(result)` (increments/resets `streak`, persists a new `bestStreak` via `playdate.datastore.write` when beaten).

- [ ] **Step 1: Write `source/game.lua`**

```lua
Game = { streak = 0, bestStreak = 0 }

function Game.init()
    Game.streak = 0
    local saved = playdate.datastore.read()
    Game.bestStreak = (saved and saved.bestStreak) or 0
end

function Game.onResult(result)
    if result == "goal" then
        Game.streak = Game.streak + 1
        if Game.streak > Game.bestStreak then
            Game.bestStreak = Game.streak
            playdate.datastore.write({ bestStreak = Game.bestStreak })
        end
    else
        Game.streak = 0
    end
end
```

- [ ] **Step 2: Draw the HUD in `source/render.lua`**

Add `import "game"` to the top (after `import "goalie"`), and this function after `drawPlayerMarker` (before `Render.draw`):

```lua
local function drawHUD()
    gfx.drawTextAligned(string.format("STREAK %d", Game.streak), 80, 12, kTextAlignment.center)
    gfx.drawTextAligned(string.format("BEST %d", Game.bestStreak), 320, 12, kTextAlignment.center)
end
```

In `Render.draw`, call it last:

```lua
function Render.draw(dt)
    gfx.clear(gfx.kColorWhite)
    drawPitch()
    drawGoal()
    drawGoalieMarker()
    drawBallMarker()
    drawPlayerMarker()
    drawHUD()
end
```

- [ ] **Step 3: Wire `Game` into `source/main.lua`** (full replacement)

```lua
import "CoreLibs/graphics"
import "CoreLibs/ui"
import "tests"
import "field"
import "player"
import "ball"
import "goalie"
import "game"
import "render"
import "shots"

playdate.display.setRefreshRate(30)
math.randomseed(playdate.getSecondsSinceEpoch())

Render.init()
Player.init()
Ball.init()
Goalie.init()
Game.init()
if playdate.isSimulator then
    runTests()
end

function playdate.update()
    local dt = playdate.getElapsedTime()
    playdate.resetElapsedTime()
    if dt <= 0 or dt > 0.25 then
        dt = 1 / 30
    end
    Player.update(dt)
    Ball.update(dt)
    Goalie.update(dt, Game.streak)
    if Ball.state == "flightComplete" then
        Ball.resolve(Goalie.x)
    end
    if Ball.resultPending then
        Game.onResult(Ball.result)
    end
    Render.draw(dt)
    Shots.update(dt)
    if playdate.isCrankDocked() then
        playdate.ui.crankIndicator:draw()
    end
end
```

- [ ] **Step 4: Screenshot smoke test of streak increment/reset and forced persistence**

In `source/shots.lua`, set:

```lua
Shots = { plan = {
    { after = 0.1, call = function() Game.onResult("goal") end, path = "/tmp/foosball-task8-streak-up.png" },
    { after = 0.1, call = function() Game.onResult("save") end, path = "/tmp/foosball-task8-streak-reset.png" },
    { after = 0.1, call = function()
        Game.bestStreak = 7
        playdate.datastore.write({ bestStreak = 7 })
    end, target = Game, set = { bestStreak = 7 }, path = "/tmp/foosball-task8-best-forced.png" },
}, t = 0, i = 1, called = false }
```

Run:

```bash
make build
rm -f /tmp/foosball-task8-*.png
timeout -k 5 15 "$HOME/Developer/PlaydateSDK/bin/Playdate Simulator.app/Contents/MacOS/Playdate Simulator" Foosball.pdx > /tmp/foosball-task8.log 2>&1
ls -la /tmp/foosball-task8-*.png
```

Expected: all three files exist. Use the Read tool to view each:
- `foosball-task8-streak-up.png`: HUD reads `STREAK 1` / `BEST 1` (a goal from a fresh boot's streak of 0 also becomes a new best).
- `foosball-task8-streak-reset.png`: HUD reads `STREAK 0` / `BEST 1` (a save resets the streak; best is untouched).
- `foosball-task8-best-forced.png`: HUD reads `STREAK 0` / `BEST 7`.

- [ ] **Step 5: Smoke test that the forced best streak survives a fresh boot**

Still with the same `source/shots.lua` from Step 4 (this reuses its Step-3 entry's `playdate.datastore.write`, run as a completely separate simulator process from Step 4 — the point is proving persistence, not the HUD math already checked above):

```bash
timeout -k 5 15 "$HOME/Developer/PlaydateSDK/bin/Playdate Simulator.app/Contents/MacOS/Playdate Simulator" Foosball.pdx > /tmp/foosball-task8b.log 2>&1
```

Then, in `source/shots.lua`, replace the plan with a single boot-time capture and re-run:

```lua
Shots = { plan = {
    { after = 0.1, path = "/tmp/foosball-task8-best-loaded.png" },
}, t = 0, i = 1, called = false }
```

```bash
make build
rm -f /tmp/foosball-task8-best-loaded.png
timeout -k 5 15 "$HOME/Developer/PlaydateSDK/bin/Playdate Simulator.app/Contents/MacOS/Playdate Simulator" Foosball.pdx > /tmp/foosball-task8c.log 2>&1
ls -la /tmp/foosball-task8-best-loaded.png
```

Expected: `foosball-task8-best-loaded.png` shows `STREAK 0` / `BEST 7` — `Game.init()` loaded the `bestStreak` the earlier run's `playdate.datastore.write` persisted to disk, with no pinning involved this time.

- [ ] **Step 6: Revert the smoke-test probe**

In `source/shots.lua`, set `Shots.plan` back to `{}`.

- [ ] **Step 7: Commit**

```bash
git add source
git -c commit.gpgsign=false commit -m "Add streak/best-streak state, datastore persistence, and HUD"
```

---

### Task 9: Synthesized audio

Adds a kick thump on contact, a net swish on a goal, a goalie whoosh on a save, a whiff sting on either miss, and a light continuous crowd bed — all via `playdate.sound` synths, no audio files, mirroring submariner's `ambience.lua` pattern.

**Files:**
- Create: `source/audio.lua`
- Modify: `source/ball.lua`
- Modify: `source/main.lua`

**Interfaces:**
- Consumes: `Ball.contactPower` (Task 6); `Ball.result` (Task 6/7).
- Produces: `Audio.init()`, `Audio.onContact(power)`, `Audio.onResult(result)`. New `Ball.contactJustNow` field (true for exactly one frame when contact is registered), mirroring the existing `Ball.resultPending` one-frame-flag convention.

- [ ] **Step 1: Add the contact flag to `source/ball.lua`**

In the `Ball = { ... }` table, add `contactJustNow = false,` (after `resultPending = false,`).

In `Ball.update`, change the top of the function from:

```lua
function Ball.update(dt)
    Ball.resultPending = false
```

to:

```lua
function Ball.update(dt)
    Ball.resultPending = false
    Ball.contactJustNow = false
```

In `registerContact`, add `Ball.contactJustNow = true` as the first line:

```lua
local function registerContact(velocity, dt)
    Ball.contactJustNow = true
    Ball.contactX = Player.x
    Ball.shotTargetX = Geom.clamp(Player.x, Field.GOAL_MIN, Field.GOAL_MAX)
    Ball.contactPower = Geom.flickPower(velocity, Ball.REFERENCE_VELOCITY, Ball.POWER_MIN, Ball.POWER_MAX)
    Ball.flightDuration = Geom.shotFlightTime(Ball.contactPower, Ball.POWER_MIN, Ball.POWER_MAX,
        Ball.SHOT_TIME_MAX, Ball.SHOT_TIME_MIN)
    Ball.flightT = 0
    Ball.state = "flight"
end
```

- [ ] **Step 2: Write `source/audio.lua`**

```lua
local snd = playdate.sound

Audio = {}

local kick, netSwish, goalChime, saveWhoosh, whiffSting

function Audio.init()
    kick = snd.synth.new(snd.kWaveSquare)
    kick:setADSR(0.001, 0.08, 0, 0.05)

    netSwish = snd.synth.new(snd.kWaveNoise)
    netSwish:setADSR(0.005, 0.2, 0, 0.15)

    goalChime = snd.synth.new(snd.kWaveSquare)
    goalChime:setADSR(0.005, 0.15, 0.4, 0.2)

    saveWhoosh = snd.synth.new(snd.kWaveNoise)
    saveWhoosh:setADSR(0.01, 0.15, 0, 0.1)

    whiffSting = snd.synth.new(snd.kWaveSquare)
    whiffSting:setADSR(0.001, 0.1, 0, 0.05)

    local crowdChannel = snd.channel.new()
    local crowdFilter = snd.twopolefilter.new(snd.kFilterLowPass)
    crowdFilter:setFrequency(450)
    crowdChannel:addEffect(crowdFilter)
    crowdChannel:setVolume(0.2)
    local crowd = snd.synth.new(snd.kWaveNoise)
    crowdChannel:addSource(crowd)
    crowd:playNote(140, 0.05) -- no length: sustains for the whole session
end

function Audio.onContact(power)
    kick:playNote(140 + power * 60, 0.4 + power * 0.3, 0.06)
end

function Audio.onResult(result)
    if result == "goal" then
        netSwish:playNote(600, 0.35, 0.2)
        goalChime:playNote(880, 0.3, 0.25)
    elseif result == "save" then
        saveWhoosh:playNote(300, 0.3, 0.15)
    else
        whiffSting:playNote(220, 0.2, 0.08)
    end
end
```

- [ ] **Step 3: Wire audio events into `source/main.lua`**

Add `import "audio"` after `import "game"`, add `Audio.init()` after `Game.init()`, and update the event checks in `playdate.update`:

```lua
    if Ball.contactJustNow then
        Audio.onContact(Ball.contactPower)
    end
    if Ball.resultPending then
        Game.onResult(Ball.result)
        Audio.onResult(Ball.result)
    end
```

(These replace the single `if Ball.resultPending then Game.onResult(Ball.result) end` block from Task 8 — insert the new `contactJustNow` block immediately before it.)

- [ ] **Step 4: Smoke-test that audio setup doesn't crash the boot**

```bash
make build
timeout -k 5 15 "$HOME/Developer/PlaydateSDK/bin/Playdate Simulator.app/Contents/MacOS/Playdate Simulator" Foosball.pdx > /tmp/foosball-task9.log 2>&1
cat /tmp/foosball-task9.log
```

Expected: no crash-dialog text in the log (a bad synth/filter API call would error at `Audio.init()`, before the update loop or `Shots` ever run). Actual audio *character* — kick punchiness, whether the crowd bed sits at a sensible level, whether goal/save/whiff read as distinct — can't be judged from a log and is deferred to the human acceptance checklist in the final task.

- [ ] **Step 5: Commit**

```bash
git add source
git -c commit.gpgsign=false commit -m "Add synthesized kick, goal, save, whiff, and crowd audio"
```

---

### Task 10: Splash/title screen

Adds a title screen shown before gameplay, dismissed by pressing A, mirroring submariner's `Splash` gate pattern. **This changes the smoke-test recipe for every task after this one:** since `Splash.active` starts `true` and gates the entire gameplay loop, any later screenshot plan that needs the pitch/HUD visible must include a `{ target = Splash, set = { active = false }, ... }` pin (or fold `active = false` into an existing entry's `set` table alongside whatever else that entry pins) — otherwise every capture just shows the title screen. Tasks 1–9 above are unaffected; their smoke tests ran before this gate existed.

**Files:**
- Create: `source/splash.lua`
- Modify: `source/main.lua`
- Modify (temporary, reverted before commit): `source/shots.lua`

**Interfaces:**
- Consumes: `Game.bestStreak` (Task 8, shown on the title screen).
- Produces: `Splash.active` (bool, starts `true`), `Splash.update()`, `Splash.draw()`.

- [ ] **Step 1: Write `source/splash.lua`**

```lua
Splash = { active = true }

function Splash.update()
    if playdate.buttonJustPressed(playdate.kButtonA) then
        Splash.active = false
    end
end

function Splash.draw()
    local gfx = playdate.graphics
    gfx.clear(gfx.kColorWhite)
    gfx.drawTextAligned("FOOSBALL SHOOTOUT", 200, 70, kTextAlignment.center)
    gfx.drawTextAligned("D-pad: line up   Crank: shoot", 200, 110, kTextAlignment.center)
    gfx.drawTextAligned(string.format("Best streak: %d", Game.bestStreak), 200, 140, kTextAlignment.center)
    gfx.drawTextAligned("Press A to kick off...", 200, 170, kTextAlignment.center)
end
```

- [ ] **Step 2: Gate the update loop in `source/main.lua`** (full replacement)

```lua
import "CoreLibs/graphics"
import "CoreLibs/ui"
import "tests"
import "field"
import "player"
import "ball"
import "goalie"
import "game"
import "audio"
import "render"
import "splash"
import "shots"

playdate.display.setRefreshRate(30)
math.randomseed(playdate.getSecondsSinceEpoch())

Render.init()
Player.init()
Ball.init()
Goalie.init()
Game.init()
Audio.init()
if playdate.isSimulator then
    runTests()
end

function playdate.update()
    local dt = playdate.getElapsedTime()
    playdate.resetElapsedTime()
    if dt <= 0 or dt > 0.25 then
        dt = 1 / 30
    end

    if Splash.active then
        Splash.update()
        Splash.draw()
    else
        Player.update(dt)
        Ball.update(dt)
        Goalie.update(dt, Game.streak)
        if Ball.state == "flightComplete" then
            Ball.resolve(Goalie.x)
        end
        if Ball.contactJustNow then
            Audio.onContact(Ball.contactPower)
        end
        if Ball.resultPending then
            Game.onResult(Ball.result)
            Audio.onResult(Ball.result)
        end
        Render.draw(dt)
        if playdate.isCrankDocked() then
            playdate.ui.crankIndicator:draw()
        end
    end
    Shots.update(dt)
end
```

- [ ] **Step 3: Screenshot smoke test of the splash screen and the dismiss gate**

`Splash.active` only clears on a real A-button press, which this headless harness can't script (same limitation as the crank) — so this step pins `active` directly to prove the gate's *else* branch renders gameplay correctly, and defers the actual "press A to dismiss" feel to the human acceptance checklist.

In `source/shots.lua`, set:

```lua
Shots = { plan = {
    { after = 0.1, path = "/tmp/foosball-task10-splash.png" },
    { after = 0.1, target = Splash, set = { active = false }, path = "/tmp/foosball-task10-dismissed.png" },
}, t = 0, i = 1, called = false }
```

Run:

```bash
make build
rm -f /tmp/foosball-task10-*.png
timeout -k 5 15 "$HOME/Developer/PlaydateSDK/bin/Playdate Simulator.app/Contents/MacOS/Playdate Simulator" Foosball.pdx > /tmp/foosball-task10.log 2>&1
ls -la /tmp/foosball-task10-*.png
```

Expected: both files exist. Use the Read tool to view each:
- `foosball-task10-splash.png`: title, control hint, "Best streak: 0", and "Press A to kick off..." text, no pitch visible.
- `foosball-task10-dismissed.png`: the pitch/goal/HUD from Task 8 visible, no splash text — proves `Splash.active = false` correctly falls through to the normal game loop.

- [ ] **Step 4: Revert the smoke-test probe**

In `source/shots.lua`, set `Shots.plan` back to `{}`.

- [ ] **Step 5: Commit**

```bash
git add source
git -c commit.gpgsign=false commit -m "Add a title/instructions splash screen before gameplay starts"
```

---

### Task 11: Result banner text

The spec's v1 acceptance criteria require goal/save/each whiff type to have **distinct visual** feedback, not just audio (Task 9 covered audio). Right now a save and a goal look identical on screen (Task 7's screenshot check could only tell them apart by whether the goalie marker happened to overlap the ball). This task adds explicit on-screen text for all four outcomes.

**Files:**
- Modify: `source/render.lua`
- Modify (temporary, reverted before commit): `source/shots.lua`

**Interfaces:**
- Consumes: `Ball.state`, `Ball.result` (Task 6/7).
- Produces: no new public interface — purely a rendering addition.

- [ ] **Step 1: Add the banner in `source/render.lua`**

Add this after `drawHUD` (before `Render.draw`):

```lua
local RESULT_TEXT = {
    goal = "GOAL!",
    save = "SAVED",
    missedBall = "MISSED THE BALL",
    tooSlow = "TOO SLOW",
}

local function drawResultBanner()
    if Ball.state == "resolved" and RESULT_TEXT[Ball.result] then
        gfx.drawTextAligned(RESULT_TEXT[Ball.result], 200, 200, kTextAlignment.center)
    end
end
```

In `Render.draw`, call it last:

```lua
function Render.draw(dt)
    gfx.clear(gfx.kColorWhite)
    drawPitch()
    drawGoal()
    drawGoalieMarker()
    drawBallMarker()
    drawPlayerMarker()
    drawHUD()
    drawResultBanner()
end
```

- [ ] **Step 2: Screenshot smoke test of all four banners**

In `source/shots.lua`, set (recall from Task 10: `Splash.active` must be pinned `false` for gameplay to render):

```lua
Shots = { plan = {
    { after = 0.1, target = Splash, set = { active = false }, path = "/tmp/foosball-task11-splash-off.png" },
    { after = 0.1, target = Ball, set = { state = "resolved", result = "goal" },        path = "/tmp/foosball-task11-goal.png" },
    { after = 0.1, target = Ball, set = { state = "resolved", result = "save" },        path = "/tmp/foosball-task11-save.png" },
    { after = 0.1, target = Ball, set = { state = "resolved", result = "missedBall" },  path = "/tmp/foosball-task11-missed.png" },
    { after = 0.1, target = Ball, set = { state = "resolved", result = "tooSlow" },     path = "/tmp/foosball-task11-tooslow.png" },
}, t = 0, i = 1, called = false }
```

The first entry only exists to dismiss the splash once (pinning persists once a field is set, but each entry's `set` only re-applies while *that* entry is active — the splash dismissal happens in time for every entry after it since `Splash.active` was already flipped to `false` in Lua's shared global state and nothing sets it back to `true`).

Run:

```bash
make build
rm -f /tmp/foosball-task11-*.png
timeout -k 5 15 "$HOME/Developer/PlaydateSDK/bin/Playdate Simulator.app/Contents/MacOS/Playdate Simulator" Foosball.pdx > /tmp/foosball-task11.log 2>&1
ls -la /tmp/foosball-task11-*.png
```

Expected: all five files exist. Use the Read tool to view the last four: each shows the pitch/HUD plus the matching banner text (`GOAL!`, `SAVED`, `MISSED THE BALL`, `TOO SLOW`) centered below the player marker.

- [ ] **Step 3: Revert the smoke-test probe**

In `source/shots.lua`, set `Shots.plan` back to `{}`.

- [ ] **Step 4: Commit**

```bash
git add source
git -c commit.gpgsign=false commit -m "Add distinct result banner text for goal, save, and each whiff"
```

---

### Task 12: Acceptance pass — human checklist, README, CLAUDE.md, sustained-run check

**Files:**
- Create: `docs/human-acceptance-checklist.md`
- Create: `README.md`
- Create: `CLAUDE.md`
- Modify (temporary, reverted before commit): `source/shots.lua`

**Interfaces:**
- Consumes: everything from Tasks 1-11 (this is a documentation + verification pass, no new game code).
- Produces: nothing later tasks depend on — this is the last task.

- [ ] **Step 1: Write `docs/human-acceptance-checklist.md`**

(These three files were already written during the design/planning phase and may already exist in the working tree, uncommitted — if so, this step is a no-op confirming the content below matches; if executing this plan fresh elsewhere, create them now with this exact content.)

```markdown
# Human acceptance checklist

Everything below requires live play (d-pad/crank feel, timing, or actual
audio) and could not be verified by the autonomous screenshot harness used
in Tasks 1-11. Run `make run`, play for a few minutes, and check each item.

## Player movement (Task 4)

- [ ] **Track speed**: 260px/s — check whether sliding corner-to-corner
  feels responsive or sluggish/twitchy.

## Contact mechanics (Task 6)

- [ ] **Flick threshold feel**: 900°/s — check whether a natural, confident
  crank flick reliably registers, and a light wrist twitch doesn't
  accidentally fire a shot.
- [ ] **Contact band width**: 45px half-width (90px total) — check whether
  lining up feels achievably precise, not frustratingly narrow or trivially
  wide.
- [ ] **Contact window timing**: the window opens at 82% of a 1.6s serve
  (~0.29s to react) — check whether this gives enough time to read the ball
  and react, without feeling like there's no urgency at all.
- [ ] **Missed-ball vs too-slow distinction**: intentionally flick
  early/out-of-band once, and intentionally not flick at all once — check
  that "MISSED THE BALL" and "TOO SLOW" each feel like the right
  explanation for what happened.
- [ ] **Power feel**: a hard, fast flick should visibly send the ball to
  the goal noticeably faster than a light one at/near the threshold.

## Goalie difficulty (Task 7)

- [ ] **Difficulty ramp**: build a streak of 10+ — the goalie should feel
  noticeably tougher to beat than on the first few shots, without feeling
  impossible.
- [ ] **Corner shots still work at high difficulty**: at a long streak, a
  hard, well-placed corner shot should still occasionally beat the goalie
  (the spec's fairness math targets a persistent ~12px gap near each post
  the goalie can never cover in time — confirm this holds up in practice,
  not just on paper).
- [ ] **Goalie doesn't react early**: watch the goalie during the
  approach/window phases (before your flick) — it should sit near center,
  not visibly anticipate your shot.

## Audio (Task 9) — all items require actually hearing the game

- [ ] **Kick thump**: on contact, check it reads as a satisfying "kick,"
  and that harder flicks noticeably sound harder.
- [ ] **Goal net swish**: check it reads distinctly as a "score" sound, not
  similar to the save whoosh.
- [ ] **Save whoosh**: check it reads distinctly as a "blocked" sound.
- [ ] **Whiff sting**: check it reads as a clear "miss" cue, and doesn't
  sound so similar to the other three that outcomes blur together with
  your eyes closed.
- [ ] **Crowd bed**: check the constant low murmur sits under everything
  else at a sensible volume — audible but not distracting.

## Splash screen (Task 10)

- [ ] **Dismiss feel**: pressing A should immediately drop into gameplay
  with no flash, stutter, or stuck frame.
- [ ] **Best streak display**: confirm the number shown on the splash
  matches the actual persisted best (check after intentionally beating
  your best once, then relaunching).

## Overall loop

- [ ] **Endless streak pacing**: play for several minutes — check whether
  "reset to 0 on any miss" feels appropriately tense/replayable rather
  than punishing enough to make you want to quit.
- [ ] **Placeholder art readability**: the player/goalie/ball are simple
  code-drawn shapes (sprite art was deferred — see the implementation
  plan's Global Constraints) — confirm they're still readable at a glance
  from the "behind the player" camera angle, distinguishing which is which
  without hesitation.
- [ ] **Device-only**: if testing on real hardware, confirm the 1-bit
  display reads clearly in different lighting, and that the crank feels
  good physically (not just in the simulator's mouse-drag crank emulation).
```

- [ ] **Step 2: Write `README.md`**

```markdown
# Foosball Shootout

An arcade foosball shootout for [Playdate](https://play.date).

Slide left and right with the d-pad to line up with the incoming ball, then
flick the crank to strike it past the goalie. Score, and the next ball
comes; get saved or mistime it, and your streak resets. The goalie gets
tougher the longer your streak runs. Best streak is saved across sessions.

## Build

Requires the [Playdate SDK](https://play.date/dev/) at `~/Developer/PlaydateSDK`.

- `make build` — compile `Foosball.pdx`
- `make run` — build and launch in the Playdate Simulator

To play on a device, build then sideload `Foosball.pdx` via the simulator
(Device menu) or [play.date/account](https://play.date/account/).
```

- [ ] **Step 3: Write `CLAUDE.md`**

```markdown
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

- `main.lua` wires init and the 30fps update loop: `Player.update → Ball.update → Goalie.update → (Ball.resolve, if a flight just completed) → Game/Audio event reactions → Render.draw`
- `ball.lua` owns the serve state machine (`approach → window → flight → flightComplete → resolved`) and never reads `Goalie` — `goalie.lua` reads `Ball.state`/`Ball.shotTargetX` one-way to decide where to move, and it's `main.lua` (not `ball.lua`) that reads `Goalie.x` back and passes it into `Ball.resolve(goalieX)` as an explicit parameter. This keeps every module's dependency direction one-way even though the shot-resolution mechanic itself needs both sides.
- `goalie.lua` takes `streak` as a parameter to `Goalie.update(dt, streak)` rather than reading `Game` directly, for the same reason.
- `render.lua` reads `Player`/`Ball`/`Goalie`/`Game`; `audio.lua` and `game.lua` react to one-frame event flags (`Ball.contactJustNow`, `Ball.resultPending`) that `main.lua` checks and dispatches — neither module polls `Ball`'s state machine directly.
- `geom.lua` is pure math shared by all of the above (`clamp`, `lerp`, `inBand`, `flickPower`, `shotFlightTime`, `goalieSpeed`) — no `playdate.*` calls, so it's the one module with boot-time unit tests.

**Coordinate model**: screen 400×240. Track (player) `x ∈ [50, 350]` at
`y = 205`; goal `x ∈ [140, 260]` at `y = 50`. The goalie moves within that
same `[140, 260]` range, resting at `x = 200` — it never needs to defend
outside the posts, since shot aim (`Ball.shotTargetX`) is always clamped
inside the goal frame too. A served ball's `x` (its lane) stays fixed while
`y`/scale interpolate from the goal
end (small/far) to the player's track (large/near) as approach progress
goes 0→1. On contact, `Ball.contactX` (the raw player position, in
track-space — used for the contact-band check) is distinct from
`Ball.shotTargetX` (that same position clamped into goal-space via
`Geom.clamp` — used for the goalie's target and the save check), so a shot
struck from a wide track position still visually flies toward the goal
mouth rather than clamping instantly to a straight line.

## Constraints and gotchas

- Sprite art (images) is **allowed** in this project, unlike submariner's
  zero-asset rule — but none exists yet. `render.lua`'s player/goalie/ball
  are simple code-drawn placeholder shapes, each behind one small,
  single-purpose draw function, specifically so swapping in real sprites
  later is a localized change rather than a redesign.
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
```

- [ ] **Step 4: Sustained-run smoke test**

Everything so far has been verified frame-by-frame with pinned state. This step runs the real, un-pinned loop for an extended stretch to catch anything that only breaks after many serve cycles (the crank never fires in this headless harness, so every serve in this run will end in a `"tooSlow"` whiff — that's fine, it still repeatedly exercises the full approach → window → resolved → approach cycle, goalie recentering, streak-reset, and HUD/audio event dispatch under sustained real-time play; the `"flight"`/goal/save code paths were already exercised directly via pinning in Tasks 6, 7, and 11).

In `source/shots.lua`, set:

```lua
Shots = { plan = {
    { after = 0.1, target = Splash, set = { active = false }, path = "/tmp/foosball-task12-start.png" },
    { after = 20.0, path = "/tmp/foosball-task12-after20s.png" },
}, t = 0, i = 1, called = false }
```

Run:

```bash
make build
rm -f /tmp/foosball-task12-*.png
timeout -k 5 30 "$HOME/Developer/PlaydateSDK/bin/Playdate Simulator.app/Contents/MacOS/Playdate Simulator" Foosball.pdx > /tmp/foosball-task12.log 2>&1
ls -la /tmp/foosball-task12-*.png
```

(Note the longer `timeout -k 5 30` here — the plan itself runs for 20 simulated seconds, so the wall-clock budget needs headroom beyond the usual 15s.)

Expected: both files exist — the second screenshot only gets written if ~20 seconds of continuous real-time simulation ran without a Lua error freezing the render thread (the same "no screenshot without a SIGKILL" failure signature described in Global Constraints would otherwise apply). View `foosball-task12-after20s.png` with the Read tool as a final sanity check: pitch/HUD should look identical in kind to earlier captures (just mid-cycle at some random approach progress), not corrupted or blank.

- [ ] **Step 5: Revert the smoke-test probe**

In `source/shots.lua`, set `Shots.plan` back to `{}`.

- [ ] **Step 6: Commit**

```bash
git add docs README.md CLAUDE.md source/shots.lua
git -c commit.gpgsign=false commit -m "Add human acceptance checklist, README, and CLAUDE.md after the v1 acceptance pass"
```

- [ ] **Step 7: Note remaining deferred/manual work for the user**

This plan's automated verification is complete once Step 6 lands. Two things remain outside what any of these tasks can do:

1. **Full human acceptance pass** — work through `docs/human-acceptance-checklist.md` via `make run`.
2. **Real sprite art** — the player/goalie/ball are code-drawn placeholders (Global Constraints, Task 6 onward); dropping in real Playdate image sprites later only touches the three marker-drawing functions in `render.lua`.

---
