import "CoreLibs/graphics"
import "geom"

local gfx = playdate.graphics

Render = {
    CENTER_X = 120,
    CENTER_Y = 110,
    RADIUS = 104,
    PX_PER_DEG = 3.5,
    SWING = 120,
    RAIL_CENTER_X = 312, -- (CENTER_X + RADIUS + 400) / 2
}

local mask = nil
local t = 0

-- setDitherPattern's alpha runs backwards for black ink (0 = solid black),
-- so express everything as "darkness" in [0,1] and invert here.
local function setInk(darkness)
    gfx.setColor(gfx.kColorBlack)
    gfx.setDitherPattern(1 - darkness, gfx.image.kDitherTypeBayer8x8)
end

function Render.init()
    -- The image must be created clear: Playdate images only carry an alpha
    -- mask when built on a transparent background, so punching kColorClear
    -- into a black-background image is a no-op and the mask stays opaque.
    mask = gfx.image.new(400, 240, gfx.kColorClear)
    gfx.pushContext(mask)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(0, 0, 400, 240)
    gfx.setColor(gfx.kColorClear)
    gfx.fillCircleAtPoint(Render.CENTER_X, Render.CENTER_Y, Render.RADIUS)
    gfx.popContext()
end

local function waterY()
    return Geom.waterlineY(Scope.height, Render.CENTER_Y, Render.SWING)
end

-- Light surface tint below the line, with short wave strokes that hug the
-- line and drift with time and bearing so the sea feels world-locked.
local function drawSea(wy)
    setInk(0.12)
    gfx.fillRect(0, wy, 400, 240 - wy)
    gfx.setColor(gfx.kColorBlack)
    local left = Render.CENTER_X - Render.RADIUS
    local right = Render.CENTER_X + Render.RADIUS
    for row = 1, 5 do
        local y = wy + 8 + row * 14
        local phase = (t * (14 - row * 2) + row * 53
            - Scope.bearing * Render.PX_PER_DEG) % 40
        for x = left - phase, right, 40 do
            gfx.drawLine(x, y, x + 12 - row, y)
        end
    end
end

-- Boat silhouettes. (x, y) is the hull baseline center; dir = ±1 facing.
local function drawSail(x, y, s, dir)
    local function px(dx) return x + dx * s * dir end
    gfx.setColor(gfx.kColorBlack)
    gfx.fillPolygon(px(-14), y, px(12), y, px(15), y - 4 * s, px(-16), y - 4 * s)
    gfx.drawLine(px(0), y - 4 * s, px(0), y - 30 * s)
    gfx.fillTriangle(px(1), y - 29 * s, px(13), y - 6 * s, px(1), y - 6 * s)
    gfx.fillTriangle(px(-1), y - 26 * s, px(-11), y - 6 * s, px(-1), y - 6 * s)
end

local function drawTrawler(x, y, s, dir)
    local function px(dx) return x + dx * s * dir end
    gfx.setColor(gfx.kColorBlack)
    gfx.fillPolygon(px(-16), y - 8 * s, px(16), y - 8 * s, px(13), y, px(-14), y)
    gfx.fillRect(math.min(px(-11), px(1)), y - 16 * s, 12 * s, 8 * s)
    gfx.drawLine(px(7), y - 8 * s, px(7), y - 22 * s)
    gfx.drawLine(px(7), y - 20 * s, px(14), y - 12 * s)
end

local function drawCargo(x, y, s, dir)
    local function px(dx) return x + dx * s * dir end
    gfx.setColor(gfx.kColorBlack)
    gfx.fillPolygon(px(-24), y - 7 * s, px(24), y - 7 * s, px(21), y, px(-22), y)
    gfx.fillRect(math.min(px(14), px(20)), y - 16 * s, 6 * s, 9 * s)
    gfx.fillRect(math.min(px(-18), px(8)), y - 12 * s, 26 * s, 5 * s)
    gfx.drawLine(px(17), y - 16 * s, px(17), y - 19 * s)
end

-- Rival submarine: low flat hull, small conning tower.
local function drawSub(x, y, s, dir)
    local function px(dx) return x + dx * s * dir end
    gfx.setColor(gfx.kColorBlack)
    gfx.fillPolygon(px(-20), y, px(20), y, px(24), y - 3 * s, px(-24), y - 3 * s)
    gfx.fillRect(math.min(px(-4), px(4)), y - 9 * s, 8 * s, 6 * s)
    gfx.drawLine(px(0), y - 9 * s, px(0), y - 13 * s)
end

local BOAT_DRAWERS = { sail = drawSail, trawler = drawTrawler, cargo = drawCargo, sub = drawSub }
local LANE_ORDER = { "far", "mid", "near" }

local function drawLighthouse(x, y)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillPolygon(x - 3, y - 22, x + 3, y - 22, x + 5, y, x - 5, y)
    gfx.fillRect(x - 4, y - 27, 8, 5)
end

local function drawClouds(wy)
    setInk(0.4)
    for _, c in ipairs(World.clouds) do
        local x = Geom.bearingToScreenX(c.bearing, Scope.bearing,
            Render.CENTER_X, Render.PX_PER_DEG)
        if x > -60 and x < 460 then
            gfx.fillEllipseInRect(x - c.w / 2, wy - c.above, c.w, 14)
            gfx.fillEllipseInRect(x - c.w / 4, wy - c.above - 7, c.w / 2, 12)
        end
    end
end

local function drawPlanes(wy)
    gfx.setColor(gfx.kColorBlack)
    for _, p in ipairs(World.planes) do
        local x = Geom.bearingToScreenX(p.bearing, Scope.bearing,
            Render.CENTER_X, Render.PX_PER_DEG)
        if x > -30 and x < 430 then
            local y = wy - p.above
            gfx.fillPolygon(x - 14, y, x + 14, y - 1, x + 16, y + 1, x - 13, y + 2)
            gfx.fillTriangle(x - 2, y, x - 2, y - 7, x + 4, y)
            gfx.fillTriangle(x - 2, y + 1, x - 2, y + 6, x + 3, y + 1)
        end
    end
end

local function drawHelicopters(wy)
    gfx.setColor(gfx.kColorBlack)
    for _, h in ipairs(World.helicopters) do
        local x = Geom.bearingToScreenX(h.bearing, Scope.bearing,
            Render.CENTER_X, Render.PX_PER_DEG)
        if x > -30 and x < 430 then
            local y = wy - h.above
            gfx.fillRoundRect(x - 9, y - 3, 18, 7, 3)
            gfx.fillRect(x + 7, y - 1, 8, 3)
            local spread = (math.sin(h.rotorPhase) > 0) and 16 or 10
            gfx.drawLine(x - spread, y - 6, x + spread, y - 6)
        end
    end
end

-- Whale spout: a small dithered plume drawn above the waterline at the
-- whale's bearing while it's near-surface. The whale's body always draws
-- in the underwater layer (drawWhales, below) regardless of spout state.
local WHALE_SPOUT_DEPTH = 35

local function drawWhaleSpouts(wy)
    setInk(0.3)
    for _, w in ipairs(World.whales) do
        if w.depth < WHALE_SPOUT_DEPTH then
            local x = Geom.bearingToScreenX(w.bearing, Scope.bearing,
                Render.CENTER_X, Render.PX_PER_DEG)
            if x > -20 and x < 420 then
                gfx.fillPolygon(x - 3, wy, x + 3, wy, x + 5, wy - 18, x - 5, wy - 18)
            end
        end
    end
end

-- Everything above the waterline, clipped to it so hulls sit "in" the water.
local function drawAbove(wy)
    gfx.setClipRect(0, 0, 400, wy)
    drawClouds(wy)
    drawPlanes(wy)
    drawHelicopters(wy)
    drawWhaleSpouts(wy)
    local lx = Geom.bearingToScreenX(World.lighthouse.bearing, Scope.bearing,
        Render.CENTER_X, Render.PX_PER_DEG)
    if lx > -40 and lx < 440 then
        drawLighthouse(lx, wy)
    end
    for _, laneName in ipairs(LANE_ORDER) do
        local lane = World.LANES[laneName]
        -- Extend the clip by the lane's dip so the lower hull stays visible
        -- below the line (the sea tint and chop draw over it afterwards);
        -- clipping exactly at wy would swallow near-lane hulls entirely.
        gfx.setClipRect(0, 0, 400, wy + lane.yOff)
        for _, b in ipairs(World.boats) do
            if b.lane == laneName then
                local x = Geom.bearingToScreenX(b.bearing, Scope.bearing,
                    Render.CENTER_X, Render.PX_PER_DEG)
                if x > -80 and x < 480 then
                    local y = wy + lane.yOff
                        + math.sin(b.bobPhase) * 1.5 * lane.scale
                    BOAT_DRAWERS[b.type](x, y, lane.scale, b.dir)
                end
            end
        end
    end
    gfx.clearClipRect()
end

-- Fish: ellipse body plus a two-frame flapping tail.
local function drawFish(x, y, s, dir, phase)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillEllipseInRect(x - 5 * s, y - 2 * s, 10 * s, 4 * s)
    local up = (math.sin(phase) > 0) and 3 or 1
    local tx = x - 5 * s * dir
    gfx.fillTriangle(tx, y,
        tx - 4 * s * dir, y - up * s,
        tx - 4 * s * dir, y + (4 - up) * s)
end

-- Shark: bigger than a lone fish, with a distinct dorsal fin.
local function drawShark(x, y, dir, phase)
    local function px(dx) return x + dx * dir end
    gfx.setColor(gfx.kColorBlack)
    gfx.fillEllipseInRect(math.min(px(-13), px(13)), y - 4, 26, 8)
    gfx.fillTriangle(px(-2), y - 4, px(2), y - 12, px(5), y - 4)
    local up = (math.sin(phase) > 0) and 5 or 2
    gfx.fillTriangle(px(-13), y, px(-20), y - up, px(-20), y + (6 - up))
end

local function drawSharks(wy)
    for _, sh in ipairs(World.sharks) do
        local x = Geom.bearingToScreenX(sh.bearing, Scope.bearing,
            Render.CENTER_X, Render.PX_PER_DEG)
        if x > -30 and x < 430 then
            local y = wy + sh.depth + math.sin(sh.phase * 0.4) * 3
            drawShark(x, y, sh.dir, sh.phase)
        end
    end
end

-- Whale body: the largest underwater silhouette.
local function drawWhale(x, y, dir, phase)
    local function px(dx) return x + dx * dir end
    gfx.setColor(gfx.kColorBlack)
    gfx.fillEllipseInRect(math.min(px(-30), px(30)), y - 8, 60, 16)
    gfx.fillTriangle(px(-30), y, px(-42), y - 10, px(-42), y + 10)
    local flip = math.sin(phase) * 2
    gfx.fillTriangle(px(28), y + flip, px(28), y - 6 + flip, px(38), y - 10 + flip)
end

local function drawWhales(wy)
    for _, w in ipairs(World.whales) do
        local x = Geom.bearingToScreenX(w.bearing, Scope.bearing,
            Render.CENTER_X, Render.PX_PER_DEG)
        if x > -50 and x < 450 then
            local y = wy + w.depth
            drawWhale(x, y, w.dir, w.phase)
        end
    end
end

local function drawLightRays(wy)
    if Scope.height < -0.6 then
        return
    end
    setInk(0.18)
    for i = -2, 2 do
        local x = Render.CENTER_X + i * 38 + math.sin(t * 0.4 + i) * 6
        gfx.fillPolygon(x - 3, wy, x + 3, wy, x + 14, wy + 90, x + 2, wy + 90)
    end
end

local function drawBubbles(wy)
    gfx.setColor(gfx.kColorBlack)
    for _, bub in ipairs(World.bubbles) do
        local x = Geom.bearingToScreenX(bub.bearing, Scope.bearing,
            Render.CENTER_X, Render.PX_PER_DEG) + math.sin(bub.wobble) * 3
        if x > -10 and x < 410 then
            gfx.drawCircleAtPoint(x, wy + bub.depth, bub.r)
        end
    end
end

-- Depth murk drawn over the fish so they dim as the scope sinks.
local function drawMurk(wy)
    local darkness = Geom.clamp(-Scope.height, 0, 1) * 0.5
    if darkness > 0.03 then
        setInk(darkness)
        gfx.fillRect(0, math.max(wy, 0), 400, 240)
    end
end

local function drawBelow(wy)
    gfx.setClipRect(0, math.max(wy + 1, 0), 400, 240)
    drawLightRays(wy)
    drawBubbles(wy)
    for _, s in ipairs(World.schools) do
        for _, m in ipairs(s.members) do
            local x = Geom.bearingToScreenX(s.bearing + m.dBearing, Scope.bearing,
                Render.CENTER_X, Render.PX_PER_DEG)
            if x > -20 and x < 420 then
                local y = wy + s.depth + m.dDepth + math.sin(m.phase * 0.5) * 2
                drawFish(x, y, 1, s.dir, m.phase)
            end
        end
    end
    for _, f in ipairs(World.fish) do
        local x = Geom.bearingToScreenX(f.bearing, Scope.bearing,
            Render.CENTER_X, Render.PX_PER_DEG)
        if x > -30 and x < 430 then
            local y = wy + f.depth + math.sin(f.phase * 0.4) * 3
            drawFish(x, y, f.size, f.dir, f.phase)
        end
    end
    drawSharks(wy)
    drawWhales(wy)
    drawMurk(wy)
    gfx.clearClipRect()
end

-- Water streaks sliding down the lens just after it breaks the surface.
-- Fixed jitter tables keep it deterministic (no math.random in the loop).
local DROPLET_XS = { -70, -52, -31, -12, 4, 22, 47, 68, 86 }

local function drawDroplets(progress)
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(2)
    for i, dx in ipairs(DROPLET_XS) do
        local stagger = (i % 3) * 0.12
        local p = Geom.clamp((progress - stagger) / (1 - stagger), 0, 1)
        if p > 0 then
            local x = Render.CENTER_X + dx
            local y0 = Render.CENTER_Y - Render.RADIUS
                + p * p * 150 + (i * 17) % 40
            gfx.drawLine(x, y0, x, y0 + 10 + (i % 4) * 3)
        end
    end
    gfx.setLineWidth(1)
end

local function drawWaterline(wy)
    gfx.setColor(gfx.kColorBlack)
    local left = Render.CENTER_X - Render.RADIUS - 4
    local right = Render.CENTER_X + Render.RADIUS + 4
    for x = left, right, 2 do
        local y = wy + math.sin(x * 0.08 + t * 3) * 2
        gfx.fillRect(x, y, 2, 2)
    end
end

local function drawCrosshairs(holdProgress)
    local cx, cy, r = Render.CENTER_X, Render.CENTER_Y, Render.RADIUS
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(1)
    gfx.drawLine(cx, cy - r, cx, cy - 6)
    gfx.drawLine(cx, cy + 6, cx, cy + r)
    gfx.drawLine(cx - r, cy, cx - 6, cy)
    gfx.drawLine(cx + 6, cy, cx + r, cy)
    local filledCount = math.ceil((holdProgress or 0) * 4)
    for i = -4, 4 do
        if i ~= 0 then
            local x = cx + i * 20
            if filledCount > 0 and math.abs(i) <= filledCount then
                gfx.setLineWidth(3)
                gfx.drawLine(x, cy - 4, x, cy + 4)
                gfx.setLineWidth(1)
            else
                gfx.drawLine(x, cy - 3, x, cy + 3)
            end
        end
    end
end

local function drawHUD()
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    local brg = math.floor(Scope.bearing + 0.5) % 360
    gfx.drawTextAligned(string.format("BRG %03d", brg),
        Render.CENTER_X, 220, kTextAlignment.center)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

local function drawBoatIcon(x, y)
    gfx.fillPolygon(x - 30, y + 14, x + 30, y + 14, x + 22, y - 2, x - 22, y - 2)
    gfx.drawLine(x, y - 2, x, y - 30)
    gfx.fillTriangle(x + 2, y - 28, x + 24, y - 4, x + 2, y - 4)
end

local function drawLighthouseIcon(x, y)
    gfx.fillPolygon(x - 8, y + 20, x + 8, y + 20, x + 14, y - 20, x - 14, y - 20)
    gfx.fillRect(x - 11, y - 30, 22, 12)
end

local function drawSchoolIcon(x, y)
    local offsets = { { -20, -10 }, { 0, -16 }, { 20, -8 }, { -10, 8 }, { 12, 12 } }
    for _, o in ipairs(offsets) do
        local fx, fy = x + o[1], y + o[2]
        gfx.fillEllipseInRect(fx - 8, fy - 3, 16, 6)
        gfx.fillTriangle(fx - 8, fy, fx - 14, fy - 3, fx - 14, fy + 3)
    end
end

local function drawSharkIcon(x, y)
    gfx.fillPolygon(x - 32, y + 6, x + 22, y + 10, x + 34, y, x + 20, y - 4, x - 30, y - 4)
    gfx.fillTriangle(x - 4, y - 4, x + 4, y - 22, x + 10, y - 4)
    gfx.fillTriangle(x + 20, y + 8, x + 34, y + 20, x + 20, y + 20)
end

local function drawWhaleIcon(x, y)
    gfx.fillPolygon(x - 34, y, x - 10, y - 16, x + 26, y - 10, x + 34, y + 2, x + 10, y + 14, x - 26, y + 12)
    gfx.fillTriangle(x + 30, y - 2, x + 44, y - 14, x + 44, y + 8)
end

local function drawSubmarineIcon(x, y)
    gfx.fillRoundRect(x - 32, y - 6, 64, 16, 8)
    gfx.fillRect(x - 4, y - 18, 10, 12)
    gfx.drawLine(x + 1, y - 18, x + 1, y - 24)
end

local function drawPlaneIcon(x, y)
    gfx.fillPolygon(x - 30, y, x + 30, y - 2, x + 34, y + 2, x - 28, y + 4)
    gfx.fillTriangle(x - 4, y, x - 16, y - 18, x - 4, y - 4)
    gfx.fillTriangle(x - 4, y + 2, x - 16, y + 18, x - 4, y + 4)
end

local function drawHelicopterIcon(x, y)
    gfx.fillRoundRect(x - 22, y - 6, 40, 16, 8)
    gfx.fillRect(x + 16, y - 1, 16, 5)
    gfx.drawLine(x - 30, y - 16, x + 30, y - 16)
    gfx.fillRect(x - 3, y - 16, 6, 10)
end

local RAIL_ICONS = {
    boat = drawBoatIcon,
    lighthouse = drawLighthouseIcon,
    ["fish school"] = drawSchoolIcon,
    shark = drawSharkIcon,
    whale = drawWhaleIcon,
    submarine = drawSubmarineIcon,
    plane = drawPlaneIcon,
    helicopter = drawHelicopterIcon,
}

local FLASH_BLINK_PERIOD = 0.12

local function drawSpyRail()
    local flashing = Spy.flashTimer < Spy.FLASH_DURATION
    local blinkOn = flashing and (math.floor(Spy.flashTimer / FLASH_BLINK_PERIOD) % 2 == 0)
    local cx = Render.RAIL_CENTER_X

    if blinkOn then
        gfx.setColor(gfx.kColorWhite)
        gfx.fillRoundRect(cx - 84, 30, 168, 180, 8)
        gfx.setColor(gfx.kColorBlack)
        gfx.setImageDrawMode(gfx.kDrawModeCopy)
    else
        gfx.setColor(gfx.kColorWhite)
        gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    end

    gfx.drawTextAligned("FIND A", cx, 46, kTextAlignment.center)
    local iconDrawer = RAIL_ICONS[Spy.target]
    iconDrawer(cx, 110)
    gfx.drawTextAligned(string.upper(Spy.target), cx, 168, kTextAlignment.center)

    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

function Render.draw(dt)
    t = t + dt
    gfx.clear(gfx.kColorWhite)
    local wy = waterY()
    if Geom.aboveVisible(wy, Render.CENTER_Y, Render.RADIUS) then
        drawAbove(wy)
    end
    if Geom.belowVisible(wy, Render.CENTER_Y, Render.RADIUS) then
        drawSea(wy)
        drawBelow(wy)
    end
    drawWaterline(wy)
    local sp = Scope.surfacedProgress()
    if sp then
        drawDroplets(sp)
    end
    mask:draw(0, 0)
    drawCrosshairs(Spy.holdProgress)
    drawHUD()
    drawSpyRail()
end
