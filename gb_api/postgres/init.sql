-- Postgres bootstrap script for the gb-api database.
--
-- The official postgres image runs every *.sql file in
-- /docker-entrypoint-initdb.d once, the first time the data directory is empty
-- (i.e. on a fresh `pgdata` volume). It creates the schema the API expects.
--
-- This is the single source of truth for the database schema.

-- ---------------------------------------------------------------------------
-- Schema
-- ---------------------------------------------------------------------------

-- Users are keyed by a stable numeric id; username is a unique, mutable handle
-- (renaming a user changes only this column, never the id the child rows reference).
CREATE TABLE IF NOT EXISTS users (
    id              BIGSERIAL PRIMARY KEY,
    username        TEXT   UNIQUE NOT NULL,
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

-- A user's loose (unslotted) item ids. ON DELETE CASCADE drops these rows when
-- the user is deleted.
CREATE TABLE IF NOT EXISTS user_inventory (
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    item_id BIGINT NOT NULL,
    PRIMARY KEY (user_id, item_id)
);

-- A user's slots: slot_id -> signed item_id (negative = broken).
CREATE TABLE IF NOT EXISTS user_slots (
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    slot_id BIGINT NOT NULL,
    item_id BIGINT NOT NULL,
    PRIMARY KEY (user_id, slot_id)
);

-- A user's assigned student roster. The user FK cascade removes roster rows when
-- the user is deleted; the student FK cascade does the same when a student is deleted.
CREATE TABLE IF NOT EXISTS user_students (
    user_id    BIGINT NOT NULL REFERENCES users(id)     ON DELETE CASCADE,
    student_id BIGINT NOT NULL REFERENCES students(id)  ON DELETE CASCADE,
    PRIMARY KEY (user_id, student_id)
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
