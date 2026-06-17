-- Schema for the gb-api Postgres store. Applied idempotently at startup.

CREATE TABLE IF NOT EXISTS users (
    username        TEXT PRIMARY KEY,
    password        TEXT   NOT NULL,
    role            INT    NOT NULL DEFAULT 0,
    building_id     BIGINT NOT NULL DEFAULT 0,   -- 0 = no building assigned
    profile_pic_url TEXT   NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS buildings (
    id                BIGSERIAL PRIMARY KEY,
    name              TEXT  NOT NULL DEFAULT '',
    layout            TEXT  NOT NULL DEFAULT '',
    type_allowed_slot JSONB NOT NULL DEFAULT '{}',
    difficulty_type   JSONB NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS items (
    id          BIGSERIAL PRIMARY KEY,
    type        BIGINT NOT NULL,
    question_id BIGINT NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS questions (
    id         BIGSERIAL PRIMARY KEY,
    content    JSONB  NOT NULL,
    answer     JSONB  NOT NULL,
    difficulty BIGINT NOT NULL DEFAULT 0,
    area       BIGINT NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS students (
    id              BIGINT PRIMARY KEY,          -- client-supplied PK
    name            TEXT NOT NULL,
    profile_pic_url TEXT NOT NULL DEFAULT ''
);

-- A user's loose (unslotted) item ids. ON UPDATE CASCADE lets a username rename
-- propagate to these rows.
CREATE TABLE IF NOT EXISTS user_inventory (
    username TEXT   NOT NULL REFERENCES users(username) ON UPDATE CASCADE ON DELETE CASCADE,
    item_id  BIGINT NOT NULL,
    PRIMARY KEY (username, item_id)
);

-- A user's slots: slot_id -> signed item_id (negative = broken).
CREATE TABLE IF NOT EXISTS user_slots (
    username TEXT   NOT NULL REFERENCES users(username) ON UPDATE CASCADE ON DELETE CASCADE,
    slot_id  BIGINT NOT NULL,
    item_id  BIGINT NOT NULL,
    PRIMARY KEY (username, slot_id)
);

-- A user's assigned student roster. The username FK cascades on rename; the student
-- FK cascade removes roster rows when the referenced student is deleted.
CREATE TABLE IF NOT EXISTS user_students (
    username   TEXT   NOT NULL REFERENCES users(username) ON UPDATE CASCADE ON DELETE CASCADE,
    student_id BIGINT NOT NULL REFERENCES students(id)    ON DELETE CASCADE,
    PRIMARY KEY (username, student_id)
);

-- Single-use question sessions; the whole model.QuestionSession is stored as a blob.
CREATE TABLE IF NOT EXISTS sessions (
    id         TEXT        PRIMARY KEY,
    expires_at TIMESTAMPTZ NOT NULL,
    data       JSONB       NOT NULL
);

CREATE TABLE IF NOT EXISTS refresh_tokens (
    jti TEXT PRIMARY KEY
);
