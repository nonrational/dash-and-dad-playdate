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
    SAVE_RADIUS = 26,
}

-- The goalie moves within [GOAL_MIN, GOAL_MAX] — the same range shot aim is
-- clamped to (Ball.shotTargetX in ball.lua) — since it never has to defend
-- outside the posts if shots can never aim outside them either.
Field.GOALIE_CENTER = (Field.GOAL_MIN + Field.GOAL_MAX) / 2
