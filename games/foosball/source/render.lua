import "CoreLibs/graphics"
import "geom"
import "field"
import "player"
import "ball"
import "goalie"
import "game"

local gfx = playdate.graphics

Render = {}

-- setDitherPattern's alpha runs backwards for black ink (0 = solid black),
-- so express everything as "darkness" in [0,1] and invert here.
-- (Observed SDK behavior, capture-verified; the manual documents the
-- opposite convention — don't "fix" this from the docs.)
local function setInk(darkness)
    gfx.setColor(gfx.kColorBlack)
    gfx.setDitherPattern(1 - darkness, gfx.image.kDitherTypeBayer8x8)
end

function Render.init()
end

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

local function drawGoal()
    setInk(0.15)
    gfx.fillRect(Field.GOAL_MIN, Field.GOAL_Y - 22, Field.GOAL_MAX - Field.GOAL_MIN, 22)
    setInk(1.0)
    gfx.drawRect(Field.GOAL_MIN, Field.GOAL_Y - 22, Field.GOAL_MAX - Field.GOAL_MIN, 22)
end

-- The rod the player figure hangs from, at chest height.
local ROD_Y = Field.PLAYER_Y - 8

local function drawRod()
    -- Wall-to-wall between the sidelines like a real table rod; mid-gray
    -- dither so the solid-black figure spinning over it stays readable.
    setInk(0.5)
    local leftX = sidelineX(Field.TRACK_MIN - PITCH_MARGIN, ROD_Y)
    local rightX = sidelineX(Field.TRACK_MAX + PITCH_MARGIN, ROD_Y)
    gfx.fillRect(leftX, ROD_Y - 2, rightX - leftX, 4)
end

-- Foosball-man silhouettes in figure-local coordinates: origin at the rod
-- boss in the chest, y down, upright pose, matching the classic molded
-- table man seen from behind: boxy square-shouldered torso and a foot
-- block wider than the ankles. The player has a shirt-hem step into a
-- narrower fused-leg column; the keeper spreads its arms into a wide bar
-- (its reach — see KEEPER_HALF in field.lua) over a wider foot block.
local PLAYER_FIGURE = {
    body = {
        -10, -10, 10, -10, -- shoulders
        10, 4, 4, 4, -- right torso side, shirt hem step
        4, 14, 7, 14, -- right leg, step out to the foot block
        7, 20, -7, 20, -- foot block side, sole
        -7, 14, -4, 14, -- left foot step back to the leg
        -4, 4, -10, 4, -- left leg, shirt hem step
    },
    footLY = 17,
    footHalfW = 7,
}
local KEEPER_FIGURE = {
    body = {
        -15, -10, 15, -10, -- arms-out span, tip to tip
        15, -5, 7, -5, -- right arm underside, back to the torso
        7, 6, 4, 6, -- right torso side, waist step
        4, 12, 10, 12, -- right leg, step out to the foot block
        10, 18, -10, 18, -- foot block side, sole
        -10, 12, -4, 12, -- left foot step back to the leg
        -4, 6, -7, 6, -- left leg, waist step
        -7, -5, -15, -5, -- left torso side, left arm underside
    },
    footLY = 15,
    footHalfW = 10,
}
local HEAD_LY, HEAD_R = -16, 6

-- Draws one molded man hanging on a rod at (x, rodY), tipped by the pose
-- (c, s) = (cos, sin) of its rotation around the rod axis. A body vertex
-- keeps its x and has its y foreshortened by c; the head stays a circle
-- at every angle, as a sphere should; whichever end is nearer the camera
-- (s > 0 = head) draws last. The white halo keeps each part legible over
-- the rod, the ball, and the part behind it. Placeholder art; swapping in
-- sprites later only touches this function and its two thin callers.
local function drawManFigure(fig, x, rodY, scale, c, s)
    local body = fig.body
    local pts = {}
    for i = 1, #body, 2 do
        pts[i] = x + body[i] * scale
        pts[i + 1] = rodY + body[i + 1] * scale * c
    end
    -- drawPolygon strokes the closing edge only if the first point is
    -- repeated, so append it for the halo pass.
    pts[#pts + 1] = pts[1]
    pts[#pts + 1] = pts[2]

    -- The head swells slightly as it comes at you (and shrinks tipped
    -- away) for a bit of depth.
    local headY = rodY + HEAD_LY * scale * c
    local headR = (HEAD_R + 1.5 * s) * scale

    local function drawBody()
        gfx.setColor(gfx.kColorWhite)
        gfx.setLineWidth(5 * scale)
        gfx.drawPolygon(table.unpack(pts))
        gfx.setColor(gfx.kColorBlack)
        gfx.fillPolygon(table.unpack(pts))
        gfx.setLineWidth(1)
        -- The rod boss in the chest, like the molded hole in a real man.
        -- It sits on the rotation axis, so it never moves with the tip.
        gfx.setColor(gfx.kColorWhite)
        gfx.fillCircleAtPoint(x, rodY, 2 * scale)
    end
    local function drawHead()
        gfx.setColor(gfx.kColorWhite)
        gfx.fillCircleAtPoint(x, headY, headR + 2 * scale)
        gfx.setColor(gfx.kColorBlack)
        gfx.fillCircleAtPoint(x, headY, headR)
    end
    -- The sole of the foot block, seen face-on. Unlike the body polygon
    -- it grows with |sin| instead of collapsing with cos — it's the
    -- surface you're looking at when the feet point at the camera, and
    -- its own halo keeps the figure from vanishing there.
    local function drawFoot()
        local footY = rodY + fig.footLY * scale * c
        local halfW = fig.footHalfW * scale
        local h = (2 + 6 * math.abs(s)) * scale
        gfx.setColor(gfx.kColorWhite)
        gfx.fillRoundRect(x - halfW - 2, footY - h / 2 - 2,
            halfW * 2 + 4, h + 4, 4)
        gfx.setColor(gfx.kColorBlack)
        gfx.fillRoundRect(x - halfW, footY - h / 2,
            halfW * 2, h, 3)
    end

    if s >= 0 then
        drawFoot()
        drawBody()
        drawHead()
    else
        drawHead()
        drawBody()
        drawFoot()
    end
end

local function drawPlayerMarker()
    -- The figure tips 1:1 with the crank (0 = upright); sin is negated so
    -- the on-screen tip matches the crank's felt direction (checked in
    -- live play — the raw sign spun opposite).
    local rad = math.rad(Player.crankAngle)
    drawManFigure(PLAYER_FIGURE, Player.x, ROD_Y, 1, math.cos(rad), -math.sin(rad))
end

local KEEPER_ROD_Y = Field.GOAL_Y - 13
local KEEPER_SCALE = 0.75

local function drawGoalieMarker()
    -- Keeper rod across the goal mouth, then the arms-out keeper, always
    -- upright (no crank on that rod). Its drawn arm span (KEEPER_HALF)
    -- plus the ball's goal-scale radius is what SAVE_RADIUS promises, so
    -- a "SAVED" always looks like contact.
    setInk(0.5)
    gfx.fillRect(Field.GOAL_MIN - 10, KEEPER_ROD_Y - 1,
        (Field.GOAL_MAX - Field.GOAL_MIN) + 20, 3)
    drawManFigure(KEEPER_FIGURE, Goalie.x, KEEPER_ROD_Y, KEEPER_SCALE, 1, 0)
end

local function drawBallMarker()
    gfx.setColor(gfx.kColorBlack)
    gfx.fillCircleAtPoint(Ball.screenX(), Ball.screenY(), 6 * Ball.screenScale())
end

local function drawHUD()
    gfx.drawTextAligned(string.format("STREAK %d", Game.streak), 80, 12, kTextAlignment.center)
    gfx.drawTextAligned(string.format("BEST %d", Game.bestStreak), 320, 12, kTextAlignment.center)
end

local RESULT_TEXT = {
    goal = "GOAL!",
    save = "SAVED",
    missedBall = "MISSED THE BALL",
    tooSlow = "TOO SLOW",
}

local function drawResultBanner()
    if Ball.state == "resolved" and RESULT_TEXT[Ball.result] then
        gfx.drawTextAligned(RESULT_TEXT[Ball.result], 200, 120, kTextAlignment.center)
    end
end

-- A scored ball draws before the goal and goalie, so it sits behind the
-- net plane and the goalie occludes it while drifting home — visibly *in*
-- the net. (The net's dither fill only adds black pixels, so it can't
-- hatch over a black ball; the layering is what sells the depth.) A saved
-- ball draws after the goalie (normal order), in front of the figure
-- that blocked it.
local function ballInNet()
    return Ball.state == "resolved" and Ball.result == "goal"
end

function Render.draw(dt)
    gfx.clear(gfx.kColorWhite)
    drawPitch()
    if ballInNet() then
        drawBallMarker()
    end
    drawGoal()
    drawGoalieMarker()
    drawRod()
    if not ballInNet() then
        drawBallMarker()
    end
    drawPlayerMarker()
    drawHUD()
    drawResultBanner()
end
