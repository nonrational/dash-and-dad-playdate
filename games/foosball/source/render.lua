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

local function drawGoalieMarker()
    gfx.setColor(gfx.kColorBlack)
    local x, y = Goalie.x, Field.GOAL_Y - 11
    gfx.fillRoundRect(x - 14, y - 6, 28, 12, 4)
end

local function drawPlayerMarker()
    gfx.setColor(gfx.kColorBlack)
    local x, y = Player.x, Field.PLAYER_Y
    gfx.fillCircleAtPoint(x, y - 14, 8)
    gfx.fillTriangle(x - 12, y + 20, x + 12, y + 20, x, y - 4)
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

-- A scored ball draws before the goal so the net's dither hatches over it
-- — visibly *in* the net. A saved ball draws after the goalie (normal
-- order), sitting in front of the figure that blocked it.
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
    if not ballInNet() then
        drawBallMarker()
    end
    drawPlayerMarker()
    drawHUD()
    drawResultBanner()
end
