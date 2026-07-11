# Human acceptance checklist

Everything below requires live play (d-pad/crank feel, timing, or actual
audio) and could not be verified by the autonomous screenshot harness used
in Tasks 1-11. Run `make run`, play for a few minutes, and check each item.

## Player movement (Task 4)

- [ ] **Track speed**: 260px/s — check whether sliding corner-to-corner
  feels responsive or sluggish/twitchy.
- [ ] **Figure tip**: the whole foosball man tips forward/backward on its
  rod 1:1 with the crank, with no perceptible lag; tipped toward you it
  collapses to just the head circle, tipped away the feet swing up toward
  the goal (with the outlined sole of the foot block keeping the figure
  visible when the feet face you), and docking the crank freezes the pose.
  If cranking forward tips the man the wrong way, flip the sign of `s` in
  `drawPlayerMarker` (`source/render.lua`).

## Contact mechanics (Task 6)

- [ ] **Flick threshold feel**: 900°/s — check whether a natural, confident
  crank flick reliably registers, and a light wrist twitch doesn't
  accidentally fire a shot.
- [ ] **Contact band width**: 45px half-width (90px total) — check whether
  lining up feels achievably precise, not frustratingly narrow or trivially
  wide.
- [ ] **Contact window timing**: the window opens at 82% of a 1.6s serve
  (~0.29s to react) — check whether this gives enough time to read the ball
  and react, without feeling like there's no urgency at all.
- [ ] **Missed-ball vs too-slow distinction**: intentionally flick
  early/out-of-band once, and intentionally not flick at all once — check
  that "MISSED THE BALL" and "TOO SLOW" each feel like the right
  explanation for what happened.
- [ ] **Power feel**: a hard, fast flick should visibly send the ball to
  the goal noticeably faster than a light one at/near the threshold.
- [ ] **Trap-and-hold**: let a serve run out while lined up (in band, no
  flick) — the ball should stick at your feet instead of "TOO SLOW", ride
  with you as you slide, and a later flick should kick it with normal
  aim/power; the goalie should keep shadowing you the whole hold. An
  out-of-band expiry should still read "TOO SLOW".

## Goalie difficulty (Task 7)

- [ ] **Difficulty ramp**: build a streak of 10+ — the goalie should feel
  noticeably tougher to beat than on the first few shots, without feeling
  impossible.
- [ ] **Corner shots still work at high difficulty**: at a long streak, a
  hard, well-placed corner shot should still occasionally beat the goalie
  (the spec's fairness math targets a persistent ~12px gap near each post
  the goalie can never cover in time — confirm this holds up in practice,
  not just on paper).
- [ ] **Goalie doesn't react early**: watch the goalie during the
  approach/window phases (before your flick) — it should sit near center,
  not visibly anticipate your shot.
- [ ] **Save contact honesty**: watch several saves — "SAVED" should only
  appear when the ball visibly meets the keeper's arms or body (the ball
  parks against the keeper's edge, never floating beside it), and a
  near-missed corner shot should score rather than phantom-save.

## Audio (Task 9) — all items require actually hearing the game

- [ ] **Kick thump**: on contact, check it reads as a satisfying "kick,"
  and that harder flicks noticeably sound harder.
- [ ] **Goal net swish**: check it reads distinctly as a "score" sound, not
  similar to the save whoosh.
- [ ] **Save whoosh**: check it reads distinctly as a "blocked" sound.
- [ ] **Whiff sting**: check it reads as a clear "miss" cue, and doesn't
  sound so similar to the other three that outcomes blur together with
  your eyes closed.
- [ ] **Crowd bed**: check the constant low murmur sits under everything
  else at a sensible volume — audible but not distracting.

## Splash screen (Task 10)

- [ ] **Dismiss feel**: pressing A should immediately drop into gameplay
  with no flash, stutter, or stuck frame.
- [ ] **Best streak display**: confirm the number shown on the splash
  matches the actual persisted best (check after intentionally beating
  your best once, then relaunching).

## Overall loop

- [ ] **Endless streak pacing**: play for several minutes — check whether
  "reset to 0 on any miss" feels appropriately tense/replayable rather
  than punishing enough to make you want to quit.
- [ ] **Placeholder art readability**: the player/goalie/ball are simple
  code-drawn shapes (sprite art was deferred — see the implementation
  plan's Global Constraints) — confirm they're still readable at a glance
  from the "behind the player" camera angle, distinguishing which is which
  without hesitation.
- [ ] **Device-only**: if testing on real hardware, confirm the 1-bit
  display reads clearly in different lighting, and that the crank feels
  good physically (not just in the simulator's mouse-drag crank emulation).
- [ ] **Save rest pose**: a save reads at a glance in live play — the ball
  stops at the goalie (never in the net) and the goalie holds the block for
  the whole SAVED banner.
- [ ] **Goal rest pose**: a goal reads at a glance in live play — the ball
  sits inside the net frame, behind the goalie.
