import "CoreLibs/graphics"
import "CoreLibs/ui"
import "tests"
import "scope"
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
    Scope.update(dt)
    Render.draw(dt)
    if playdate.isCrankDocked() then
        playdate.ui.crankIndicator:draw()
    end
    Shots.update(dt)
end
