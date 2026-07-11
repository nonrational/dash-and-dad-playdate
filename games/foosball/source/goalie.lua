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
