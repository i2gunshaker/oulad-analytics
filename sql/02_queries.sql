-- =============================================================
--  OULAD Learning Analytics — Analytical Query Library
--  Dialect: PostgreSQL 14+
--
--  Prerequisites: run 01_setup_schema.sql first.
--
--  Note: "date" is quoted throughout because it is a reserved
--  word in PostgreSQL (the column in student_vle is called date).
-- =============================================================


-- =============================================================
-- SECTION 1: DATA OVERVIEW
-- =============================================================

-- 1.1  Row counts
SELECT tbl, rows FROM (VALUES
    ('student_info',         (SELECT COUNT(*) FROM student_info)),
    ('student_registration', (SELECT COUNT(*) FROM student_registration)),
    ('student_assessment',   (SELECT COUNT(*) FROM student_assessment)),
    ('student_vle',          (SELECT COUNT(*) FROM student_vle)),
    ('assessments',          (SELECT COUNT(*) FROM assessments)),
    ('vle',                  (SELECT COUNT(*) FROM vle)),
    ('courses',              (SELECT COUNT(*) FROM courses))
) AS t(tbl, rows)
ORDER BY rows DESC;


-- 1.2  Final result distribution with percentage
SELECT
    final_result,
    COUNT(*)                                                    AS students,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1)         AS pct
FROM student_info
GROUP BY final_result
ORDER BY students DESC;


-- 1.3  Enrollment and distinct student counts
SELECT COUNT(*) AS enrollments, COUNT(DISTINCT id_student) AS distinct_students
FROM student_info;


-- 1.4  Enrollments per module × presentation
SELECT
    code_module,
    code_presentation,
    COUNT(*)   AS students,
    ROUND(AVG(CASE WHEN final_result IN ('Pass','Distinction') THEN 1.0 ELSE 0 END) * 100, 1)
               AS completion_rate_pct
FROM student_info
GROUP BY code_module, code_presentation
ORDER BY students DESC;


-- =============================================================
-- SECTION 2: FUNNEL ANALYSIS
-- =============================================================

-- 2.1  Five engagement milestones, counted independently
WITH base AS (
    SELECT
        si.id_student,
        si.code_module,
        si.code_presentation,
        si.final_result,
        COALESCE(eng.total_clicks,    0) AS total_clicks,
        COALESCE(sub.submitted_count, 0) AS submitted_count
    FROM student_info si

    LEFT JOIN (
        SELECT
            id_student,
            code_module,
            code_presentation,
            SUM(sum_click) AS total_clicks
        FROM student_vle
        GROUP BY id_student, code_module, code_presentation
    ) eng USING (id_student, code_module, code_presentation)

    -- Assessment submissions must be scoped to the correct module
    LEFT JOIN (
        SELECT
            sa.id_student,
            a.code_module,
            a.code_presentation,
            COUNT(*) FILTER (WHERE sa.score IS NOT NULL) AS submitted_count
        FROM student_assessment sa
        JOIN assessments a USING (id_assessment)
        GROUP BY sa.id_student, a.code_module, a.code_presentation
    ) sub USING (id_student, code_module, code_presentation)
),
funnel AS (
    SELECT 1 AS ord, 'Registered'              AS stage, COUNT(*)                                        AS students FROM base
    UNION ALL
    SELECT 2,        'Active (any click)',                COUNT(*) FROM base WHERE total_clicks    > 0
    UNION ALL
    SELECT 3,        'Scored ≥1 Assessment',           COUNT(*) FROM base WHERE submitted_count > 0
    UNION ALL
    SELECT 4,        'Passed',                            COUNT(*) FROM base WHERE final_result IN ('Pass','Distinction')
    UNION ALL
    SELECT 5,        'Distinction',                       COUNT(*) FROM base WHERE final_result  = 'Distinction'
)
SELECT
    ord,
    stage,
    students,
    ROUND(students * 100.0 / FIRST_VALUE(students) OVER (ORDER BY ord), 1) AS pct_of_registered,
    COALESCE(ROUND(students * 100.0 / NULLIF(LAG(students) OVER (ORDER BY ord), 0), 1),
             CASE WHEN ord = 1 THEN 100.0 END)                           AS stage_conversion_pct
FROM funnel
ORDER BY ord;


-- 2.2  Funnel by module — which course has the worst activation rate?
WITH eng AS (
    SELECT id_student, code_module, code_presentation,
           SUM(sum_click) AS total_clicks
    FROM student_vle
    GROUP BY id_student, code_module, code_presentation
),
sub AS (
    SELECT sa.id_student, a.code_module, a.code_presentation,
           COUNT(*) FILTER (WHERE sa.score IS NOT NULL) AS submitted_count
    FROM student_assessment sa
    JOIN assessments a USING (id_assessment)
    GROUP BY sa.id_student, a.code_module, a.code_presentation
)
SELECT
    si.code_module,
    COUNT(*)                                                                                AS registered,
    COUNT(*) FILTER (WHERE COALESCE(eng.total_clicks,    0) > 0)                           AS active,
    COUNT(*) FILTER (WHERE COALESCE(sub.submitted_count, 0) > 0)                           AS submitted,
    COUNT(*) FILTER (WHERE si.final_result IN ('Pass','Distinction'))                      AS passed,

    ROUND(COUNT(*) FILTER (WHERE COALESCE(eng.total_clicks, 0) > 0)
          * 100.0 / NULLIF(COUNT(*), 0), 1)                                                AS activation_rate_pct,
    ROUND(COUNT(*) FILTER (WHERE COALESCE(sub.submitted_count, 0) > 0)
          * 100.0 / NULLIF(COUNT(*), 0), 1)                                                AS submission_rate_pct,
    ROUND(COUNT(*) FILTER (WHERE si.final_result IN ('Pass','Distinction'))
          * 100.0 / NULLIF(COUNT(*), 0), 1)                                                AS completion_rate_pct
FROM student_info si
LEFT JOIN eng USING (id_student, code_module, code_presentation)
LEFT JOIN sub USING (id_student, code_module, code_presentation)
GROUP BY si.code_module
ORDER BY activation_rate_pct ASC;


-- =============================================================
-- SECTION 3: COHORT RETENTION
-- =============================================================

-- 3.1  Weekly retention index by presentation (notebook 02)
--      Denominator: peak active IDs in weeks 0–2. Index capped at 100%.
WITH weekly AS (
    SELECT sv.code_presentation AS cohort, sv."date" / 7 AS week_num,
           COUNT(DISTINCT sv.id_student) AS active_students
    FROM student_vle sv
    JOIN student_info si USING (id_student, code_module, code_presentation)
    WHERE sv."date" BETWEEN 0 AND 181 AND sv.sum_click > 0
    GROUP BY sv.code_presentation, week_num
), baseline AS (
    SELECT cohort, MAX(active_students) AS cohort_size
    FROM weekly
    WHERE week_num <= 2
    GROUP BY cohort
), retention AS (
    SELECT b.cohort, weeks.week_num, COALESCE(w.active_students, 0) AS active_students,
           b.cohort_size,
           LEAST(COALESCE(w.active_students, 0)::NUMERIC / b.cohort_size, 1.0) * 100 AS retention_pct
    FROM baseline b
    CROSS JOIN generate_series(0, 25) AS weeks(week_num)
    LEFT JOIN weekly w ON w.cohort = b.cohort AND w.week_num = weeks.week_num
)
SELECT cohort, week_num, active_students, cohort_size, ROUND(retention_pct, 1) AS retention_pct
FROM retention
ORDER BY cohort, week_num;


-- 3.2  Equal-weight average by presentation. Round after taking the difference.
WITH weekly AS (
    SELECT sv.code_presentation AS cohort, sv."date" / 7 AS week_num,
           COUNT(DISTINCT sv.id_student) AS active_students
    FROM student_vle sv
    JOIN student_info si USING (id_student, code_module, code_presentation)
    WHERE sv."date" BETWEEN 0 AND 181 AND sv.sum_click > 0
    GROUP BY sv.code_presentation, week_num
), baseline AS (
    SELECT cohort, MAX(active_students) AS cohort_size
    FROM weekly
    WHERE week_num <= 2
    GROUP BY cohort
), retention AS (
    SELECT b.cohort, weeks.week_num, COALESCE(w.active_students, 0) AS active_students,
           b.cohort_size,
           LEAST(COALESCE(w.active_students, 0)::NUMERIC / b.cohort_size, 1.0) * 100 AS retention_pct
    FROM baseline b
    CROSS JOIN generate_series(0, 25) AS weeks(week_num)
    LEFT JOIN weekly w ON w.cohort = b.cohort AND w.week_num = weeks.week_num
),
weekly_average AS (
    SELECT week_num, AVG(retention_pct) AS avg_retention_pct
    FROM retention
    GROUP BY week_num
)
SELECT week_num, ROUND(avg_retention_pct, 1) AS avg_retention_pct,
       ROUND(avg_retention_pct - LAG(avg_retention_pct) OVER (ORDER BY week_num), 1) AS wow_change_pp
FROM weekly_average
ORDER BY week_num;


-- =============================================================
-- SECTION 4: RETROSPECTIVE ENGAGEMENT FLAGS
-- =============================================================

-- 4.1  Match notebook 01. Full-course submissions make this a descriptive flag.
WITH engagement AS (
    SELECT id_student, code_module, code_presentation,
           SUM(sum_click) AS total_clicks
    FROM student_vle
    GROUP BY id_student, code_module, code_presentation
), early AS (
    SELECT DISTINCT id_student, code_module, code_presentation
    FROM student_vle
    WHERE "date" BETWEEN 0 AND 13 AND sum_click > 0
), submission AS (
    SELECT sa.id_student, a.code_module, a.code_presentation,
           COUNT(sa.score)::NUMERIC / COUNT(*) AS submission_rate,
           AVG(sa.score) AS avg_score
    FROM student_assessment sa
    JOIN assessments a USING (id_assessment)
    GROUP BY sa.id_student, a.code_module, a.code_presentation
), flags AS (
    SELECT si.id_student, si.code_module, si.code_presentation, si.final_result,
           COALESCE(e.total_clicks, 0) AS total_clicks,
           early.id_student IS NOT NULL AS early_active,
           COALESCE(s.submission_rate, 0) AS submission_rate,
           s.avg_score,
           early.id_student IS NULL AND COALESCE(s.submission_rate, 0) < 0.5 AS at_risk
    FROM student_info si
    LEFT JOIN engagement e USING (id_student, code_module, code_presentation)
    LEFT JOIN early USING (id_student, code_module, code_presentation)
    LEFT JOIN submission s USING (id_student, code_module, code_presentation)
)
SELECT id_student, code_module, code_presentation, final_result, total_clicks,
       early_active, ROUND(submission_rate, 2) AS submission_rate,
       ROUND(avg_score, 1) AS avg_score, at_risk
FROM flags
ORDER BY total_clicks, id_student, code_module, code_presentation;


-- 4.2  Flag summaries by module
WITH engagement AS (
    SELECT id_student, code_module, code_presentation,
           SUM(sum_click) AS total_clicks
    FROM student_vle
    GROUP BY id_student, code_module, code_presentation
), early AS (
    SELECT DISTINCT id_student, code_module, code_presentation
    FROM student_vle
    WHERE "date" BETWEEN 0 AND 13 AND sum_click > 0
), submission AS (
    SELECT sa.id_student, a.code_module, a.code_presentation,
           COUNT(sa.score)::NUMERIC / COUNT(*) AS submission_rate,
           AVG(sa.score) AS avg_score
    FROM student_assessment sa
    JOIN assessments a USING (id_assessment)
    GROUP BY sa.id_student, a.code_module, a.code_presentation
), flags AS (
    SELECT si.id_student, si.code_module, si.code_presentation, si.final_result,
           COALESCE(e.total_clicks, 0) AS total_clicks,
           early.id_student IS NOT NULL AS early_active,
           COALESCE(s.submission_rate, 0) AS submission_rate,
           s.avg_score,
           early.id_student IS NULL AND COALESCE(s.submission_rate, 0) < 0.5 AS at_risk
    FROM student_info si
    LEFT JOIN engagement e USING (id_student, code_module, code_presentation)
    LEFT JOIN early USING (id_student, code_module, code_presentation)
    LEFT JOIN submission s USING (id_student, code_module, code_presentation)
)
SELECT code_module, COUNT(*) AS enrollments,
       COUNT(*) FILTER (WHERE total_clicks = 0) AS inactive,
       COUNT(*) FILTER (WHERE at_risk) AS at_risk,
       ROUND(AVG((total_clicks = 0)::INT) * 100, 1) AS inactive_pct,
       ROUND(AVG((final_result = 'Withdrawn')::INT) * 100, 1) AS withdrawal_pct
FROM flags
GROUP BY code_module
ORDER BY inactive_pct DESC;


-- =============================================================
-- SECTION 5: STUDENT LIFETIME VALUE
-- =============================================================

-- 5.1  Completion probability and estimated LTV by engagement tier
--      LTV formula: module_fee + reenroll_revenue + referral_revenue
WITH engagement AS (
    SELECT id_student, code_module, code_presentation,
           SUM(sum_click) AS total_clicks
    FROM student_vle
    GROUP BY id_student, code_module, code_presentation
),
tiered AS (
    SELECT
        si.id_student,
        si.code_module,
        si.code_presentation,
        si.final_result,
        CASE
            WHEN COALESCE(e.total_clicks, 0)  = 0    THEN 'Inactive'
            WHEN COALESCE(e.total_clicks, 0) <= 500  THEN 'Low'
            WHEN COALESCE(e.total_clicks, 0) <= 2000 THEN 'Medium'
            ELSE                                           'High'
        END AS engagement_tier,
        CASE WHEN si.final_result IN ('Pass','Distinction') THEN 1 ELSE 0 END AS completed
    FROM student_info si
    LEFT JOIN engagement e USING (id_student, code_module, code_presentation)
),
tier_stats AS (
    SELECT
        engagement_tier,
        COUNT(*)                                AS students,
        ROUND(AVG(completed::NUMERIC) * 100, 1) AS completion_rate_pct,
        AVG(completed::NUMERIC)                 AS p_complete
    FROM tiered
    GROUP BY engagement_tier
)
SELECT
    engagement_tier,
    students,
    completion_rate_pct,
    -- LTV components (assumptions: £2,500 module, 45% re-enroll, 15%/2% referral)
    ROUND(
        2500                                                -- module fee
        + (p_complete * 0.45 * 2500)                       -- re-enrollment
        + (p_complete * 0.15 * 300)                        -- referral (passers)
        + ((1 - p_complete) * 0.02 * 300)                  -- referral (incomplete)
    , 0) AS estimated_ltv_gbp
FROM tier_stats
ORDER BY estimated_ltv_gbp DESC;


-- =============================================================
-- SECTION 6: B/J QUASI-EXPERIMENT
-- =============================================================

-- 6.0  Balanced module panel used by notebook 03. Raw risks among all enrolled.
WITH balanced AS (
    SELECT code_module
    FROM courses
    WHERE code_presentation IN ('2013B', '2013J', '2014B', '2014J')
    GROUP BY code_module
    HAVING COUNT(DISTINCT code_presentation) = 4
)
SELECT code_presentation, COUNT(*) AS enrolled,
       COUNT(*) FILTER (WHERE final_result IN ('Pass', 'Distinction')) AS completed,
       ROUND(AVG((final_result IN ('Pass', 'Distinction'))::INT), 4) AS completion_risk
FROM student_info JOIN balanced USING (code_module)
WHERE code_presentation IN ('2013B', '2013J', '2014B', '2014J')
GROUP BY code_presentation
ORDER BY code_presentation;


-- 6.1  Raw completion among all enrollments, earliest B versus latest J per module
--      Covariate adjustment and clustered inference are computed in notebook 03.
WITH pairs AS (
    SELECT code_module,
           MIN(code_presentation) FILTER (WHERE RIGHT(code_presentation, 1) = 'B') AS b,
           MAX(code_presentation) FILTER (WHERE RIGHT(code_presentation, 1) = 'J') AS j
    FROM courses
    GROUP BY code_module
), rates AS (
    SELECT p.code_module, p.b, p.j,
           COUNT(*) FILTER (WHERE si.code_presentation = p.b) AS b_enrolled,
           COUNT(*) FILTER (WHERE si.code_presentation = p.j) AS j_enrolled,
           COUNT(*) FILTER (WHERE si.code_presentation = p.b AND si.final_result IN ('Pass', 'Distinction'))
               AS b_completed,
           COUNT(*) FILTER (WHERE si.code_presentation = p.j AND si.final_result IN ('Pass', 'Distinction'))
               AS j_completed
    FROM pairs p
    JOIN student_info si ON si.code_module = p.code_module AND si.code_presentation IN (p.b, p.j)
    WHERE p.b IS NOT NULL AND p.j IS NOT NULL
    GROUP BY p.code_module, p.b, p.j
)
SELECT code_module, b, j, b_enrolled, b_completed, j_enrolled, j_completed,
       ROUND(100.0 * b_completed / b_enrolled, 2) AS b_rate_pct,
       ROUND(100.0 * j_completed / j_enrolled, 2) AS j_rate_pct,
       ROUND(100.0 * (j_completed::NUMERIC / j_enrolled - b_completed::NUMERIC / b_enrolled), 2)
           AS j_minus_b_pp
FROM rates
ORDER BY code_module;


-- 6.2  BBB secondary outcome. Give each scored enrollment equal weight.
WITH enrollment_scores AS (
    SELECT sa.id_student, a.code_module, a.code_presentation, AVG(sa.score) AS score
    FROM student_assessment sa
    JOIN assessments a USING (id_assessment)
    WHERE a.code_module = 'BBB'
      AND a.code_presentation IN ('2013B', '2014J')
      AND sa.score IS NOT NULL
    GROUP BY sa.id_student, a.code_module, a.code_presentation
)
SELECT si.code_presentation, COUNT(*) AS enrolled, COUNT(es.score) AS scored,
       ROUND(AVG(es.score), 2) AS mean_score,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY es.score)::NUMERIC, 2) AS median_score,
       ROUND(STDDEV_SAMP(es.score), 2) AS stddev_score,
       ROUND(100.0 * COUNT(es.score) / COUNT(*), 2) AS coverage_pct,
       ROUND(PERCENTILE_CONT(0.1) WITHIN GROUP (ORDER BY es.score)::NUMERIC, 2) AS p10,
       ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY es.score)::NUMERIC, 2) AS p90
FROM student_info si
LEFT JOIN enrollment_scores es USING (id_student, code_module, code_presentation)
WHERE si.code_module = 'BBB' AND si.code_presentation IN ('2013B', '2014J')
GROUP BY si.code_presentation
ORDER BY si.code_presentation;


-- =============================================================
-- SECTION 7: CONTENT & ACTIVITY INSIGHTS
-- =============================================================

-- 7.1  Which activity types generate the most engagement?
SELECT
    v.activity_type,
    COUNT(DISTINCT sv.id_student)                         AS unique_students,
    SUM(sv.sum_click)                                     AS total_clicks,
    ROUND(AVG(sv.sum_click), 1)                           AS avg_clicks_per_interaction,
    ROUND(SUM(sv.sum_click)::NUMERIC
          / NULLIF(SUM(SUM(sv.sum_click)) OVER (), 0) * 100, 1) AS pct_of_all_clicks
FROM student_vle sv
JOIN vle v ON sv.id_site         = v.id_site
          AND sv.code_module      = v.code_module
          AND sv.code_presentation = v.code_presentation
GROUP BY v.activity_type
ORDER BY total_clicks DESC;


-- 7.2  Activity usage breakdown by outcome — do completers interact differently?
SELECT
    v.activity_type,
    si.final_result,
    COUNT(DISTINCT sv.id_student)   AS students,
    ROUND(AVG(sv.sum_click), 1)     AS avg_clicks_per_session
FROM student_vle sv
JOIN vle         v  ON sv.id_site          = v.id_site
                   AND sv.code_module       = v.code_module
                   AND sv.code_presentation = v.code_presentation
JOIN student_info si ON sv.id_student       = si.id_student
                    AND sv.code_module       = si.code_module
                    AND sv.code_presentation = si.code_presentation
WHERE si.final_result IN ('Pass', 'Distinction', 'Withdrawn')
GROUP BY v.activity_type, si.final_result
ORDER BY v.activity_type, avg_clicks_per_session DESC;


-- 7.3  Regional completion and withdrawal rates
SELECT
    region,
    COUNT(*)                                                                        AS students,
    ROUND(COUNT(*) FILTER (WHERE final_result IN ('Pass','Distinction'))
          * 100.0 / NULLIF(COUNT(*), 0), 1)                                         AS completion_pct,
    ROUND(COUNT(*) FILTER (WHERE final_result = 'Withdrawn')
          * 100.0 / NULLIF(COUNT(*), 0), 1)                                         AS withdrawal_pct,
    ROUND(AVG(studied_credits), 0)                                                  AS avg_credits
FROM student_info
GROUP BY region
ORDER BY completion_pct DESC;


-- 7.4  Any positive VLE click on course days 0–13 (notebook 01)
WITH early AS (
    SELECT DISTINCT id_student, code_module, code_presentation
    FROM student_vle
    WHERE "date" BETWEEN 0 AND 13 AND sum_click > 0
)
SELECT early.id_student IS NOT NULL AS early_active,
       COUNT(*) AS enrollments,
       ROUND(AVG((si.final_result IN ('Pass', 'Distinction'))::INT) * 100, 1) AS completion_pct,
       ROUND(AVG((si.final_result = 'Withdrawn')::INT) * 100, 1) AS withdrawal_pct
FROM student_info si
LEFT JOIN early USING (id_student, code_module, code_presentation)
GROUP BY early_active
ORDER BY early_active;
