-- =============================================================
--  OULAD Learning Analytics — PostgreSQL Schema Setup
--  Run this FIRST to create the database and load all tables.
--
--  Usage:
--    1. Create a database:
--         createdb oulad
--    2. Run this file:
--         psql -d oulad -f sql/01_setup_schema.sql
--    3. Then run queries from 02_queries.sql
-- =============================================================

-- ── Drop tables if re-running ──────────────────────────────
DROP TABLE IF EXISTS student_vle        CASCADE;
DROP TABLE IF EXISTS student_assessment CASCADE;
DROP TABLE IF EXISTS student_registration CASCADE;
DROP TABLE IF EXISTS student_info       CASCADE;
DROP TABLE IF EXISTS assessments        CASCADE;
DROP TABLE IF EXISTS vle                CASCADE;
DROP TABLE IF EXISTS courses            CASCADE;


-- ── Create tables ──────────────────────────────────────────

CREATE TABLE courses (
    code_module         VARCHAR(10)  NOT NULL,
    code_presentation   VARCHAR(10)  NOT NULL,
    module_presentation_length INT,
    PRIMARY KEY (code_module, code_presentation)
);

CREATE TABLE assessments (
    id_assessment       INT          PRIMARY KEY,
    code_module         VARCHAR(10)  NOT NULL,
    code_presentation   VARCHAR(10)  NOT NULL,
    assessment_type     VARCHAR(10),    -- TMA, CMA, Exam
    assessment_date     INT,            -- day relative to module start (can be NULL for exams)
    weight              NUMERIC(5,2)
);

CREATE TABLE vle (
    id_site             INT          PRIMARY KEY,
    code_module         VARCHAR(10)  NOT NULL,
    code_presentation   VARCHAR(10)  NOT NULL,
    activity_type       VARCHAR(30),
    week_from           INT,
    week_to             INT
);

CREATE TABLE student_info (
    id_student          INT          NOT NULL,
    code_module         VARCHAR(10)  NOT NULL,
    code_presentation   VARCHAR(10)  NOT NULL,
    gender              CHAR(1),
    region              VARCHAR(60),
    highest_education   VARCHAR(60),
    imd_band            VARCHAR(10),
    age_band            VARCHAR(10),
    num_of_prev_attempts INT,
    studied_credits     INT,
    disability          CHAR(1),
    final_result        VARCHAR(15),
    PRIMARY KEY (id_student, code_module, code_presentation)
);

CREATE TABLE student_registration (
    id_student          INT          NOT NULL,
    code_module         VARCHAR(10)  NOT NULL,
    code_presentation   VARCHAR(10)  NOT NULL,
    date_registration   INT,            -- days relative to module start (negative = enrolled early)
    date_unregistration INT,            -- NULL if student did not withdraw
    PRIMARY KEY (id_student, code_module, code_presentation)
);

CREATE TABLE student_assessment (
    id_assessment       INT          NOT NULL,
    id_student          INT          NOT NULL,
    date_submitted      INT,            -- day relative to module start
    is_banked           SMALLINT,
    score               NUMERIC(5,2),  -- NULL if not submitted
    PRIMARY KEY (id_assessment, id_student)
);

-- date is a reserved word in PostgreSQL; column is quoted in queries
CREATE TABLE student_vle (
    id_student          INT          NOT NULL,
    code_module         VARCHAR(10)  NOT NULL,
    code_presentation   VARCHAR(10)  NOT NULL,
    id_site             INT          NOT NULL,
    "date"              INT          NOT NULL,  -- day relative to module start
    sum_click           INT
);


-- ── Indexes for query performance ──────────────────────────
CREATE INDEX idx_svle_student   ON student_vle (id_student, code_module, code_presentation);
CREATE INDEX idx_svle_date      ON student_vle ("date");
CREATE INDEX idx_svle_site      ON student_vle (id_site);
CREATE INDEX idx_sassess_student ON student_assessment (id_student);
CREATE INDEX idx_info_result    ON student_info (final_result);
CREATE INDEX idx_info_module    ON student_info (code_module, code_presentation);


-- ── Load data from CSV files ────────────────────────────────
-- Adjust the path to match where you unzipped anonymisedData.zip
-- Run from the project root directory.

\COPY courses (code_module, code_presentation, module_presentation_length) FROM 'data/raw/courses.csv' WITH (FORMAT csv, HEADER true, NULL '');
\COPY assessments (code_module, code_presentation, id_assessment, assessment_type, assessment_date, weight) FROM 'data/raw/assessments.csv' WITH (FORMAT csv, HEADER true, NULL '', FORCE_NULL (assessment_date));
\COPY vle (id_site, code_module, code_presentation, activity_type, week_from, week_to) FROM 'data/raw/vle.csv' WITH (FORMAT csv, HEADER true, NULL '', FORCE_NULL (week_from, week_to));
\COPY student_info (code_module, code_presentation, id_student, gender, region, highest_education, imd_band, age_band, num_of_prev_attempts, studied_credits, disability, final_result) FROM 'data/raw/studentInfo.csv' WITH (FORMAT csv, HEADER true, NULL '');
\COPY student_registration (code_module, code_presentation, id_student, date_registration, date_unregistration) FROM 'data/raw/studentRegistration.csv' WITH (FORMAT csv, HEADER true, NULL '', FORCE_NULL (date_registration, date_unregistration));
\COPY student_assessment (id_assessment, id_student, date_submitted, is_banked, score) FROM 'data/raw/studentAssessment.csv' WITH (FORMAT csv, HEADER true, NULL '', FORCE_NULL (score));
\COPY student_vle (code_module, code_presentation, id_student, id_site, "date", sum_click) FROM 'data/raw/studentVle.csv' WITH (FORMAT csv, HEADER true, NULL '');


-- ── Verify row counts ──────────────────────────────────────
SELECT 'courses'              AS tbl, COUNT(*) AS rows FROM courses
UNION ALL SELECT 'assessments',        COUNT(*) FROM assessments
UNION ALL SELECT 'vle',                COUNT(*) FROM vle
UNION ALL SELECT 'student_info',       COUNT(*) FROM student_info
UNION ALL SELECT 'student_registration', COUNT(*) FROM student_registration
UNION ALL SELECT 'student_assessment', COUNT(*) FROM student_assessment
UNION ALL SELECT 'student_vle',        COUNT(*) FROM student_vle
ORDER BY rows DESC;
