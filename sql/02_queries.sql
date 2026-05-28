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


-- 1.3  Students per module × presentation (useful for picking the A/B test target)
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

-- 2.1  Full five-stage engagement funnel
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
    SELECT 3,        'Submitted ≥1 Assessment',           COUNT(*) FROM base WHERE submitted_count > 0
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
    ROUND(students * 100.0 / LAG(students) OVER (ORDER BY ord), 1)          AS stage_conversion_pct
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

-- 3.1  Weekly retention rate by enrollment cohort
--      Baseline = maximum active students in weeks 0-2 (robust to late joiners)
WITH weekly AS (
    SELECT
        sv.code_presentation                            AS cohort,
        sv."date" / 7                                   AS week_num,
        COUNT(DISTINCT sv.id_student)                   AS active_students
    FROM student_vle sv
    WHERE sv."date" BETWEEN 0 AND 175   -- weeks 0–25
    GROUP BY sv.code_presentation, week_num
),
baseline AS (
    SELECT cohort, MAX(active_students) AS cohort_size
    FROM weekly
    WHERE week_num <= 2
    GROUP BY cohort
)
SELECT
    w.cohort,
    w.week_num,
    w.active_students,
    b.cohort_size,
    ROUND(
        LEAST(w.active_students::NUMERIC / NULLIF(b.cohort_size, 0), 1.0) * 100, 1
    ) AS retention_pct
FROM weekly w
JOIN baseline b USING (cohort)
ORDER BY w.cohort, w.week_num;


-- 3.2  Average week-on-week drop — find the critical churn week
WITH weekly AS (
    SELECT
        sv."date" / 7                       AS week_num,
        sv.code_presentation                AS cohort,
        COUNT(DISTINCT sv.id_student)       AS active_students
    FROM student_vle sv
    WHERE sv."date" BETWEEN 0 AND 175
    GROUP BY week_num, cohort
),
baseline AS (
    SELECT cohort, MAX(active_students) AS cohort_size
    FROM weekly WHERE week_num <= 2
    GROUP BY cohort
),
retention AS (
    SELECT
        w.week_num,
        ROUND(AVG(
            LEAST(w.active_students::NUMERIC / NULLIF(b.cohort_size, 0), 1.0)
        ) * 100, 1) AS avg_retention_pct
    FROM weekly w JOIN baseline b USING (cohort)
    GROUP BY w.week_num
)
SELECT
    week_num,
    avg_retention_pct,
    ROUND(avg_retention_pct
          - LAG(avg_retention_pct) OVER (ORDER BY week_num), 1) AS wow_change_pp
FROM retention
ORDER BY week_num;


-- =============================================================
-- SECTION 4: AT-RISK STUDENT DETECTION
-- =============================================================

-- 4.1  Flag students with low early engagement and poor submission rate
WITH engagement AS (
    SELECT
        id_student, code_module, code_presentation,
        SUM(sum_click)              AS total_clicks,
        COUNT(DISTINCT "date")      AS active_days,
        MIN("date")                 AS first_activity_day
    FROM student_vle
    GROUP BY id_student, code_module, code_presentation
),
submission AS (
    SELECT
        sa.id_student,
        a.code_module,
        a.code_presentation,
        ROUND(COUNT(*) FILTER (WHERE sa.score IS NOT NULL)::NUMERIC
              / NULLIF(COUNT(*), 0), 2)  AS submission_rate,
        ROUND(AVG(COALESCE(sa.score, 0)), 1) AS avg_score
    FROM student_assessment sa
    JOIN assessments a USING (id_assessment)
    GROUP BY sa.id_student, a.code_module, a.code_presentation
)
SELECT
    si.id_student,
    si.code_module,
    si.code_presentation,
    si.final_result,
    COALESCE(e.total_clicks, 0)         AS total_clicks,
    COALESCE(e.first_activity_day, -1)  AS first_activity_day,
    COALESCE(s.submission_rate, 0)      AS submission_rate,
    COALESCE(s.avg_score, 0)            AS avg_score,
    CASE
        WHEN COALESCE(e.total_clicks, 0) = 0
            THEN 'No Activity'
        WHEN COALESCE(e.first_activity_day, 999) > 14
         AND COALESCE(s.submission_rate, 0) < 0.5
            THEN 'At Risk'
        WHEN COALESCE(e.total_clicks, 0) < 500
            THEN 'Low Engagement'
        WHEN COALESCE(e.total_clicks, 0) < 2000
            THEN 'Medium Engagement'
        ELSE 'High Engagement'
    END AS segment
FROM student_info si
LEFT JOIN engagement  e USING (id_student, code_module, code_presentation)
LEFT JOIN submission  s USING (id_student, code_module, code_presentation)
ORDER BY total_clicks ASC;


-- 4.2  At-risk summary per module
WITH engagement AS (
    SELECT id_student, code_module, code_presentation,
           SUM(sum_click) AS total_clicks,
           MIN("date")    AS first_activity_day
    FROM student_vle
    GROUP BY id_student, code_module, code_presentation
),
submission AS (
    SELECT sa.id_student, a.code_module, a.code_presentation,
           ROUND(COUNT(*) FILTER (WHERE sa.score IS NOT NULL)::NUMERIC
                 / NULLIF(COUNT(*), 0), 2) AS submission_rate
    FROM student_assessment sa
    JOIN assessments a USING (id_assessment)
    GROUP BY sa.id_student, a.code_module, a.code_presentation
)
SELECT
    si.code_module,
    COUNT(*)                                                                        AS total_students,
    COUNT(*) FILTER (WHERE COALESCE(e.total_clicks, 0) = 0)                         AS inactive,
    COUNT(*) FILTER (WHERE COALESCE(e.first_activity_day, 999) > 14
                      AND  COALESCE(s.submission_rate, 0) < 0.5)                    AS at_risk,
    ROUND(COUNT(*) FILTER (WHERE COALESCE(e.total_clicks, 0) = 0)
          * 100.0 / NULLIF(COUNT(*), 0), 1)                                         AS inactive_pct,
    ROUND(COUNT(*) FILTER (WHERE final_result = 'Withdrawn')
          * 100.0 / NULLIF(COUNT(*), 0), 1)                                         AS withdrawal_pct
FROM student_info si
LEFT JOIN engagement e USING (id_student, code_module, code_presentation)
LEFT JOIN submission s USING (id_student, code_module, code_presentation)
GROUP BY si.code_module
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
            WHEN COALESCE(e.total_clicks, 0)  < 500  THEN 'Low'
            WHEN COALESCE(e.total_clicks, 0)  < 2000 THEN 'Medium'
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
        + ((1 - p_complete) * 0.02 * 300)                  -- referral (dropouts)
    , 0) AS estimated_ltv_gbp
FROM tier_stats
ORDER BY estimated_ltv_gbp DESC;


-- =============================================================
-- SECTION 6: A/B TEST — QUASI-EXPERIMENT
-- =============================================================

-- 6.1  Completion and withdrawal rates across two presentations of the same module
--      Replace 'BBB' with the module code from your analysis
SELECT
    code_presentation,
    COUNT(*)                                                                        AS students,
    ROUND(COUNT(*) FILTER (WHERE final_result IN ('Pass','Distinction'))
          * 100.0 / NULLIF(COUNT(*), 0), 1)                                         AS completion_pct,
    ROUND(COUNT(*) FILTER (WHERE final_result = 'Withdrawn')
          * 100.0 / NULLIF(COUNT(*), 0), 1)                                         AS withdrawal_pct,
    ROUND(COUNT(*) FILTER (WHERE final_result = 'Fail')
          * 100.0 / NULLIF(COUNT(*), 0), 1)                                         AS fail_pct
FROM student_info
WHERE code_module = 'BBB'
  AND code_presentation IN ('2013B', '2014B')
GROUP BY code_presentation
ORDER BY code_presentation;


-- 6.2  Average assessment score per group (submitted only)
SELECT
    si.code_presentation,
    COUNT(DISTINCT si.id_student)                       AS students_with_scores,
    ROUND(AVG(sa.score), 2)                             AS mean_score,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP
          (ORDER BY sa.score)::NUMERIC, 2)              AS median_score,
    ROUND(STDDEV_SAMP(sa.score)::NUMERIC, 2)            AS stddev_score,
    MIN(sa.score)                                       AS min_score,
    MAX(sa.score)                                       AS max_score
FROM student_info si
JOIN student_assessment sa ON si.id_student = sa.id_student
JOIN assessments         a  ON sa.id_assessment = a.id_assessment
WHERE si.code_module        = 'BBB'
  AND a.code_module         = 'BBB'
  AND si.code_presentation  IN ('2013B', '2014B')
  AND a.code_presentation   = si.code_presentation
  AND sa.score IS NOT NULL
GROUP BY si.code_presentation
ORDER BY si.code_presentation;


-- 6.3  Score percentile distribution — richer than just mean/std
SELECT
    si.code_presentation,
    ROUND(PERCENTILE_CONT(0.10) WITHIN GROUP (ORDER BY sa.score)::NUMERIC, 1) AS p10,
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY sa.score)::NUMERIC, 1) AS p25,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY sa.score)::NUMERIC, 1) AS median,
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY sa.score)::NUMERIC, 1) AS p75,
    ROUND(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY sa.score)::NUMERIC, 1) AS p90
FROM student_info si
JOIN student_assessment sa ON si.id_student = sa.id_student
JOIN assessments         a  ON sa.id_assessment = a.id_assessment
WHERE si.code_module        = 'BBB'
  AND a.code_module         = 'BBB'
  AND si.code_presentation  IN ('2013B', '2014B')
  AND a.code_presentation   = si.code_presentation
  AND sa.score IS NOT NULL
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


-- 7.4  Early engagement lift — confirmation in SQL
--      Students who clicked in their first 14 days vs those who did not
WITH first_click AS (
    SELECT id_student, code_module, code_presentation,
           MIN("date") AS first_activity_day
    FROM student_vle
    GROUP BY id_student, code_module, code_presentation
)
SELECT
    CASE WHEN COALESCE(f.first_activity_day, 999) <= 14
         THEN 'Early active (≤14 days)'
         ELSE 'Not early active (>14 days or never)'
    END                                         AS early_engagement,
    COUNT(*)                                    AS students,
    ROUND(AVG(CASE WHEN si.final_result IN ('Pass','Distinction')
                   THEN 1.0 ELSE 0 END) * 100, 1) AS completion_pct,
    ROUND(AVG(CASE WHEN si.final_result = 'Withdrawn'
                   THEN 1.0 ELSE 0 END) * 100, 1) AS withdrawal_pct
FROM student_info si
LEFT JOIN first_click f USING (id_student, code_module, code_presentation)
GROUP BY early_engagement
ORDER BY completion_pct DESC;
