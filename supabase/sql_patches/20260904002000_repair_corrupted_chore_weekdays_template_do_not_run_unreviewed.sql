-- Manual repair template for already-corrupted weekly chore recurrence rows
-- and untouched future occurrences.
--
-- DO NOT run this broadly.
-- First run:
--   20260904001000_diagnose_chore_weekday_corruption_readonly.sql
--
-- Then replace the rows in reviewed_repairs with explicit template IDs and
-- intended PostgreSQL DOW values after human review.
--
-- PostgreSQL DOW:
--   0 Sunday, 1 Monday, 2 Tuesday, 3 Wednesday, 4 Thursday, 5 Friday, 6 Saturday

BEGIN;

WITH reviewed_repairs(template_id, intended_weekdays, intended_start_date, generate_through) AS (
    VALUES
        -- Example only. Replace with real reviewed template IDs before use.
        -- ('00000000-0000-0000-0000-000000000000'::uuid, ARRAY[3]::smallint[], '2026-09-09'::date, '2026-12-08'::date)
        (NULL::uuid, NULL::smallint[], NULL::date, NULL::date)
),
valid_repairs AS (
    SELECT *
    FROM reviewed_repairs
    WHERE template_id IS NOT NULL
      AND intended_weekdays IS NOT NULL
      AND array_length(intended_weekdays, 1) > 0
      AND intended_start_date IS NOT NULL
      AND generate_through IS NOT NULL
),
updated_rules AS (
    UPDATE public.chore_recurrence_rules rr
    SET weekdays = vr.intended_weekdays,
        start_date = vr.intended_start_date,
        updated_at = now()
    FROM valid_repairs vr
    JOIN public.chore_templates ct ON ct.id = vr.template_id
    WHERE rr.template_id = vr.template_id
      AND rr.frequency = 'weekly'
      AND ct.archived_at IS NULL
    RETURNING
        rr.template_id,
        rr.weekdays,
        rr.start_date
),
deleted_events AS (
    SELECT DISTINCT co.calendar_event_id
    FROM public.chore_occurrences co
    JOIN valid_repairs vr ON vr.template_id = co.template_id
    WHERE co.due_local_date >= vr.intended_start_date
      AND co.due_local_date <= vr.generate_through
      AND co.calendar_event_id IS NOT NULL
      AND public.chore_occurrence_is_reschedule_eligible(co.id)
),
deleted_assignees AS (
    DELETE FROM public.chore_occurrence_assignees coa
    USING public.chore_occurrences co
    JOIN valid_repairs vr ON vr.template_id = co.template_id
    WHERE coa.occurrence_id = co.id
      AND co.due_local_date >= vr.intended_start_date
      AND co.due_local_date <= vr.generate_through
      AND public.chore_occurrence_is_reschedule_eligible(co.id)
    RETURNING coa.occurrence_id
),
deleted_occurrences AS (
    DELETE FROM public.chore_occurrences co
    USING valid_repairs vr
    WHERE co.template_id = vr.template_id
      AND co.due_local_date >= vr.intended_start_date
      AND co.due_local_date <= vr.generate_through
      AND public.chore_occurrence_is_reschedule_eligible(co.id)
    RETURNING co.id, co.template_id
),
deleted_calendar_events AS (
    SELECT
        de.calendar_event_id,
        public.delete_calendar_event(de.calendar_event_id)
    FROM deleted_events de
),
generated AS (
    SELECT
        vr.template_id,
        public.generate_chore_occurrences(vr.template_id, vr.generate_through) AS generated_ids
    FROM valid_repairs vr
)
SELECT
    ur.template_id,
    ur.weekdays,
    ur.start_date,
    (SELECT COUNT(*) FROM deleted_occurrences doo WHERE doo.template_id = ur.template_id) AS deleted_untouched_future_occurrences,
    (SELECT COUNT(*) FROM deleted_calendar_events) AS deleted_calendar_events,
    COALESCE(array_length(g.generated_ids, 1), 0) AS generated_occurrences
FROM updated_rules ur
LEFT JOIN generated g ON g.template_id = ur.template_id
ORDER BY ur.template_id;

-- Inspect the RETURNING rows above.
-- Change ROLLBACK to COMMIT only after verifying the exact repaired rows.
ROLLBACK;
