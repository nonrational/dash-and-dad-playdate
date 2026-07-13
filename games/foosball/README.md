# Foosball Shootout

An arcade foosball shootout for [Playdate](https://play.date).

![The Foosball Shootout splash: a retro cartridge-box foosball match, with the on-boot controls banner reading "D-pad aim, Crank shoot, A start".](docs/screenshots/splash.png)

Slide left and right with the d-pad to line up with the incoming ball. The
crank tips your foosball man forward and back, 1:1 with your hand — flick it
inside the contact window to strike the ball past the goalie. Miss the window
while you're lined up and the man traps the ball at his feet; reposition, then
flick to shoot.

Score, and the next ball comes. Get saved or mistime the flick, and your
streak resets. The goalie gets tougher the longer your streak runs, and your
best streak is saved across sessions.

## Build

Requires the [Playdate SDK](https://play.date/dev/) at `~/Developer/PlaydateSDK`.

- `make build` — compile `Foosball.pdx`
- `make run` — build and launch in the Playdate Simulator

To play on a device, build then sideload `Foosball.pdx` via the simulator
(Device menu) or [play.date/account](https://play.date/account/).

## License

Released into the public domain under [the Unlicense](LICENSE).
