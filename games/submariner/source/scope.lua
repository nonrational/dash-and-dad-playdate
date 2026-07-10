import "geom"

-- 3 crank revolutions sweep the full height range [-1, +1].
local HEIGHT_PER_CRANK_DEG = 2 / 1080
local DROPLET_WINDOW = 0.5

Scope = {
    bearing = 47,
    height = -0.4,   -- start submerged: cranking up reveals the surface
    holdTime = 0,
    surfacedTimer = 999,
    surfacedNow = false,
}

function Scope.update(dt)
    Scope.surfacedNow = false

    local dir = 0
    if playdate.buttonIsPressed(playdate.kButtonLeft) then
        dir = dir - 1
    end
    if playdate.buttonIsPressed(playdate.kButtonRight) then
        dir = dir + 1
    end
    if dir ~= 0 then
        Scope.holdTime = Scope.holdTime + dt
        Scope.bearing = Geom.wrap360(
            Scope.bearing + dir * Geom.rotationSpeed(Scope.holdTime) * dt)
    else
        Scope.holdTime = 0
    end

    if not playdate.isCrankDocked() then
        local change = playdate.getCrankChange()
        local prev = Scope.height
        Scope.height = Geom.clamp(
            Scope.height + change * HEIGHT_PER_CRANK_DEG, -1, 1)
        if prev < 0 and Scope.height >= 0 then
            Scope.surfacedTimer = 0
            Scope.surfacedNow = true
        end
    end

    Scope.surfacedTimer = Scope.surfacedTimer + dt
end

function Scope.surfacedProgress()
    if Scope.surfacedTimer < DROPLET_WINDOW then
        return Scope.surfacedTimer / DROPLET_WINDOW
    end
    return nil
end
