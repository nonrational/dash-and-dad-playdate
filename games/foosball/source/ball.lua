import "geom"
import "field"
import "player"

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
    contactJustNow = false,
    resolvedTimer = 0,
    restX = nil,
    restY = nil,
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
    Ball.restX = nil
    Ball.restY = nil
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
    Ball.contactJustNow = true
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
    Ball.contactJustNow = false

    -- playdate.getCrankChange() returns the delta since it was last called,
    -- not since the last frame — it must be polled (and its value discarded)
    -- every single frame regardless of state, or crank motion during the
    -- ~1.3s "approach" phase accumulates undrained and dumps as one inflated
    -- reading the instant "window" opens, producing a velocity spike the
    -- player never intended. (Splash.active gating Ball.update entirely
    -- doesn't reintroduce this: Ball.state can't leave "approach" while
    -- the splash is up, so the threshold check stays unreachable
    -- regardless.)
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
            if Geom.inBand(Player.x, Ball.laneX, Field.CONTACT_BAND_HALF) then
                -- Lined up but never flicked: the man traps the ball at
                -- his feet instead of whiffing. It rides Player.x until a
                -- flick sends it through the normal contact path.
                Ball.state = "held"
            else
                registerWhiff("tooSlow")
            end
        end
    elseif Ball.state == "held" then
        -- No band check here: a held ball is at the player's feet by
        -- definition, so any strong-enough flick kicks it.
        if crankVelocity >= Ball.FLICK_THRESHOLD then
            registerContact(crankVelocity, dt)
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
    local saved = Geom.inBand(goalieX, Ball.shotTargetX, Field.SAVE_RADIUS)
    Ball.result = saved and "save" or "goal"
    -- Rest pose is where the outcome story ends: a save parks the ball
    -- against the keeper's reach edge on the side the shot arrived —
    -- teleporting it to the keeper's center (or leaving it at an aim
    -- point up to SAVE_RADIUS away) both read as the wrong outcome. A
    -- goal parks it inside the net.
    if saved then
        local reach = Geom.clamp(Ball.shotTargetX - goalieX,
            -Field.KEEPER_HALF, Field.KEEPER_HALF)
        -- Rest on the keeper's arm line: only the arms span the full
        -- reach, so an edge-of-band save at waist height would still
        -- show daylight.
        Ball.restX, Ball.restY = goalieX + reach, Field.GOAL_Y - 18
    else
        Ball.restX, Ball.restY = Ball.shotTargetX, Field.GOAL_Y - 10
    end
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
    elseif Ball.state == "held" then
        return Player.x
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

function Ball.screenY()
    if Ball.state == "flight" or Ball.state == "flightComplete" then
        return Geom.lerp(Field.PLAYER_Y, Field.GOAL_Y, flightProgress())
    elseif Ball.state == "held" then
        -- A touch below the track line, so the ball sits visibly at the
        -- figure's feet instead of hiding behind the foot block.
        return Field.PLAYER_Y + 9
    elseif ballAtGoal() then
        return Ball.restY
    end
    return Geom.lerp(Field.GOAL_Y, Field.PLAYER_Y, Geom.clamp(Ball.progress, 0, 1))
end

function Ball.screenScale()
    if Ball.state == "flight" or Ball.state == "flightComplete" then
        return Geom.lerp(Field.BALL_MAX_SCALE, Field.BALL_MIN_SCALE, flightProgress())
    elseif Ball.state == "held" then
        return Field.BALL_MAX_SCALE
    elseif ballAtGoal() then
        return Field.BALL_MIN_SCALE
    end
    return Geom.lerp(Field.BALL_MIN_SCALE, Field.BALL_MAX_SCALE, Geom.clamp(Ball.progress, 0, 1))
end
