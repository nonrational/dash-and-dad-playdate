Field = {
    TRACK_MIN = 50,
    TRACK_MAX = 350,
    PLAYER_Y = 205,

    GOAL_MIN = 140,
    GOAL_MAX = 260,
    GOAL_Y = 50,

    BALL_MIN_SCALE = 0.5,
    BALL_MAX_SCALE = 1.0,

    CONTACT_BAND_HALF = 45,
    -- The keeper's reach: drawn arms-out half-width (KEEPER_HALF) plus the
    -- ball's radius at goal scale, with under a pixel of grace — so a
    -- "SAVED" always looks like contact. Retuning this must re-derive the
    -- goalie-speed fairness ledger (see the spec's 2026-07-11 addendum).
    SAVE_RADIUS = 15,
    KEEPER_HALF = 11,
}

-- The goalie moves within [GOAL_MIN, GOAL_MAX] — the same range shot aim is
-- clamped to (Ball.shotTargetX in ball.lua) — since it never has to defend
-- outside the posts if shots can never aim outside them either.
Field.GOALIE_CENTER = (Field.GOAL_MIN + Field.GOAL_MAX) / 2
