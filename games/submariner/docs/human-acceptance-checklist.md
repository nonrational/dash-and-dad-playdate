# Human acceptance checklist

Everything below requires live play (d-pad/crank feel, timing, or actual
audio) and could not be verified by the autonomous screenshot harness used
in Tasks 1-9. Run `make run`, play for a few minutes, and check each item.

## Controls feel (Task 4)

- [ ] **Rotation ramp**: hold d-pad left or right — rotation should start
  slow (~25°/s) and visibly speed up over the first ~0.5s of holding
  (~55°/s), giving a "heavy periscope" feel rather than an instant snap to
  full speed.
- [ ] **359°→000° wrap**: rotate continuously past due north in either
  direction — the bearing readout should wrap cleanly (359→0 or 0→359) with
  no jump, stall, or reverse-direction glitch.
- [ ] **Crank sweep**: turn the crank through roughly 3 full revolutions —
  height should sweep the complete range from fully submerged to fully
  raised.
- [ ] **Crank clamp**: keep cranking past the top or bottom of the range —
  it should clamp silently (no jitter, no wraparound, no error) at the
  extremes.
- [ ] **Crossing the line while cranking**: crank up and down repeatedly
  across the waterline — no visual glitches or stalls in the
  `surfacedNow`/droplet-timer transition on each upward crossing.

## World feel (Task 5)

- [ ] **Lane drift speed**: near-lane boats should visibly drift faster
  across the view than mid-lane, and mid faster than far-lane.
- [ ] **Boat bob**: boats should have a gentle vertical bobbing motion, not
  sit rigidly still.
- [ ] **Rotation direction**: rotating the scope right should move the
  world (boats, lighthouse, clouds) left across the view (and vice versa).

## Underwater feel (Task 6)

- [ ] **Tail-flap animation**: fish tails currently flip between two static
  poses keyed off a sine sign flip, not a smooth animated flap — check
  whether this reads as "flapping" at a glance or as a distracting flicker.
- [ ] **Bubble recycling**: watch a bubble column continuously — when a
  bubble reaches the top it recycles instantly back to depth 175 (bottom).
  Check whether this instant reset is visually smooth/unnoticeable or looks
  like a pop/glitch.
- [ ] **30fps hold while rotating**: rotate the scope with the full
  underwater scene on screen (both schools + both lone fish + bubbles +
  murk) and watch for frame drops. (Headless FPS check in Task 9 sampled
  ~28-30fps on static frames in this sandboxed dev environment — see
  `task-9-report.md` for the numbers. Confirm live, ideally on-device or in
  a normal desktop simulator session, that rotation doesn't introduce
  additional stutter.)

## Droplets (Task 7)

- [ ] **Live retrigger**: crank across the surface upward repeatedly (dip
  below, come back up, dip below, come back up) — droplets should retrigger
  cleanly on each upward crossing, not stack up or fail to reset.
- [ ] **Downward crossing**: confirm nothing triggers when crossing the
  waterline downward (droplets are surfacing-only by design).

## Audio (Task 8) — all items require actually hearing the game

- [ ] **Submerged hum**: two detuned sines (110/112 Hz) through a low-pass
  filter, beating slowly — check it reads as an ambient underwater hum, not
  an annoying warble.
- [ ] **Sonar ping**: fires every 6-10s while submerged — check level and
  character (should sit under the hum, not startle).
- [ ] **Splash one-shot**: fires on surfacing, alongside the droplet
  visual — check timing lines up with the droplets and the sound reads as
  a "breaking the surface" splash.
- [ ] **Lapping swell**: noise-wash "lap" synth while raised — check it
  reads as waves lapping, with a believable swell (two-term sine sum
  driving the volume).
- [ ] **Gull call**: two-note square-wave call, fires every 8-14s while
  raised — check character and that it doesn't fire too often/rarely to
  feel alive.
- [ ] **Crossfade blend at the waterline**: hover the crank right around
  the surface (mix midpoint) — both the above and below beds should be
  faintly audible at once, crossfading smoothly as you crank through,
  not cutting abruptly from one to the other.

## I Spy objective

- [ ] **Rail readability at a glance**: glance at the rail without studying it —
  the icon and word should be readable/recognizable in under a second, since
  this is meant to work for a 6-year-old without adult help.
- [ ] **Hold-to-confirm feel**: aim at a matching entity and hold — the
  crosshair tick marks should visibly fill in as progress toward the find,
  not feel like a silent/unresponsive wait.
- [ ] **Sweep-past doesn't count**: quickly rotate past a matching entity
  without holding — it should NOT register as a find.
- [ ] **Find flash + chime timing**: on a successful find, the flash and the
  chime should land together, not noticeably out of sync.
- [ ] **Category never repeats immediately**: after several finds in a row,
  confirm the same category doesn't appear twice back to back.
- [ ] **Whale spout timing**: watch the whale's bearing for a while — the
  spout should appear now and then near the surface, not so rarely it's
  never seen in a normal play session, and not so often it looks constant.
- [ ] **New entity silhouettes read clearly**: the rival submarine, plane,
  helicopter, and shark should each look distinct from existing boats/fish
  at a glance, not like a reused/ambiguous shape.
- [ ] **A 6-year-old can play it**: if possible, hand the device to a
  6-year-old (or someone unfamiliar with the game) and see whether they can
  find a few targets in a row without being told how.

## Notes from the Task 9 acceptance pass

- The inverted-rect clip experiment (extending the near-lane clip by the
  2px bob-amplitude ceiling) was tried and reverted — it made no
  measurable difference to the `inverted rect in LCD_addUpdateRect()!`
  warning count (226 before, 226 after, and still 226 with an exaggerated
  +30px clip). The warnings remain unexplained but are console-only with
  no visual artifact in any captured screenshot across Tasks 5-9; treat as
  cosmetic console noise unless a human playtest turns up a visible glitch.
- FPS readings during the Task 9 headless check hovered at 28-29fps
  (occasionally 27 or a clean 30) rather than a rock-steady 30, on both a
  content-light and a content-heavy static frame — the two windows showed
  near-identical distributions, which points at sandbox/host CPU jitter
  in this dev environment rather than a scene-complexity-driven cost in
  the game's own draw code. Worth a live sanity check per the "30fps hold
  while rotating" item above, ideally outside this headless harness.
