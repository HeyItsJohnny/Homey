-- READ ONLY diagnostic for weekly chore schedules whose recurrence weekday may
-- no longer match the room cleaning preference or recurrence start date.
--
-- Replace the UUID below before running.
-- This query does not update any data.

WITH target_home AS (
    SELECT '00000000-0000-0000-0000-000000000000'::uuid AS home_id
),
weekday_names AS (
    SELECT *
    FROM (VALUES
        (0, 'Sunday'),
        (1, 'Monday'),
        (2, 'Tuesday'),
        (3, 'Wednesday'),
        (4, 'Thursday'),
        (5, 'Friday'),
        (6, 'Saturday')
    ) AS weekdays(postgres_dow, weekday_name)
),
weekly_rules AS (
    SELECT
        ct.id AS template_id,
        ct.title AS template_title,
        ct.room_id,
        ct.contributes_to_room_cleaning,
        cr.name AS room_name,
        cr.preferred_cleaning_weekday AS room_preferred_weekday_raw,
        CASE
            WHEN cr.preferred_cleaning_weekday BETWEEN 1 AND 7
                THEN cr.preferred_cleaning_weekday - 1
            ELSE NULL
        END AS room_preferred_postgres_dow,
        rr.id AS recurrence_rule_id,
        rr.frequency,
        rr.interval_value,
        rr.weekdays AS recurrence_weekdays,
        rr.start_date,
        EXTRACT(DOW FROM rr.start_date)::integer AS start_date_postgres_dow
    FROM public.chore_templates ct
    JOIN public.chore_recurrence_rules rr ON rr.template_id = ct.id
    LEFT JOIN public.chore_rooms cr ON cr.id = ct.room_id
    JOIN target_home th ON th.home_id = ct.home_id
    WHERE ct.archived_at IS NULL
      AND rr.frequency = 'weekly'
)
SELECT
    wr.template_title,
    wr.room_name,
    wr.contributes_to_room_cleaning,
    wr.room_preferred_weekday_raw,
    room_pref_name.weekday_name AS room_preferred_weekday_semantic_name,
    wr.room_preferred_postgres_dow,
    wr.recurrence_weekdays,
    ARRAY(
        SELECT wn.weekday_name
        FROM unnest(wr.recurrence_weekdays) AS recurrence_dow
        LEFT JOIN weekday_names wn ON wn.postgres_dow = recurrence_dow
        ORDER BY recurrence_dow
    ) AS recurrence_weekday_semantic_names,
    wr.start_date,
    wr.start_date_postgres_dow,
    start_name.weekday_name AS start_date_semantic_weekday_name,
    CASE
        WHEN wr.room_preferred_postgres_dow IS NULL THEN NULL
        ELSE wr.room_preferred_postgres_dow = ANY(wr.recurrence_weekdays)
    END AS room_preference_and_recurrence_agree,
    wr.start_date_postgres_dow = ANY(wr.recurrence_weekdays) AS start_date_and_recurrence_agree,
    CASE
        WHEN wr.contributes_to_room_cleaning IS TRUE
          AND wr.room_preferred_postgres_dow IS NOT NULL
          AND NOT (wr.room_preferred_postgres_dow = ANY(wr.recurrence_weekdays))
            THEN ARRAY[wr.room_preferred_postgres_dow::smallint]
        ELSE NULL
    END AS review_only_possible_room_aligned_weekdays,
    CASE
        WHEN wr.contributes_to_room_cleaning IS TRUE
          AND wr.room_preferred_postgres_dow IS NOT NULL
          AND NOT (wr.room_preferred_postgres_dow = ANY(wr.recurrence_weekdays))
            THEN 'REVIEW: room-cleaning chore recurrence does not include room preferred day'
        WHEN NOT (wr.start_date_postgres_dow = ANY(wr.recurrence_weekdays))
            THEN 'REVIEW: recurrence start_date weekday is outside recurrence weekdays'
        ELSE 'OK'
    END AS diagnostic_status
FROM weekly_rules wr
LEFT JOIN weekday_names room_pref_name ON room_pref_name.postgres_dow = wr.room_preferred_postgres_dow
LEFT JOIN weekday_names start_name ON start_name.postgres_dow = wr.start_date_postgres_dow
ORDER BY
    diagnostic_status DESC,
    wr.room_name NULLS LAST,
    wr.template_title;
