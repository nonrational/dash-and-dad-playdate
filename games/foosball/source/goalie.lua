import "geom"
import "field"
import "ball"

Goalie = { x = Field.GOALIE_CENTER }

-- Retuned alongside SAVE_RADIUS 26 -> 15 (honest keeper reach): the reach
-- the band lost, speed gives back. Max close = 150 * 0.22s = 33px against
-- the 45px worst-case need, preserving the spec's ~12px near-post gap
-- that stays unreachable at max difficulty. Ledger in the spec's
-- 2026-07-11 addendum.
Goalie.BASE_SPEED = 70
Goalie.RAMP_PER_STREAK = 6
Goalie.MAX_SPEED = 150

function Goalie.init()
    Goalie.x = Field.GOALIE_CENTER
end

function Goalie.update(dt, streak)
    local target = Field.GOALIE_CENTER
    if Ball.state == "flight" or Ball.state == "flightComplete" then
        target = Ball.shotTargetX
    elseif Ball.state == "held" then
        -- Shadow the presumptive shot while the player holds the ball:
        -- the held ball rides the player's x, so tracking the ball keeps
        -- the hold fair without reading Player directly.
        target = Geom.clamp(Ball.screenX(), Field.GOAL_MIN, Field.GOAL_MAX)
    elseif Ball.state == "resolved" and Ball.result == "save" then
        -- Hold the block through the SAVED banner: drifting home would
        -- abandon the ball the goalie just stopped.
        target = Goalie.x
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
