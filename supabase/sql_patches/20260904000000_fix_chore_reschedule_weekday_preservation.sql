-- Fix chore rescheduling so destination dates preserve semantic weekdays.
-- Run this manually in Supabase SQL editor.

CREATE OR REPLACE FUNCTION public.chore_postgres_dow_from_swift_weekday(swift_weekday integer)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN swift_weekday BETWEEN 1 AND 7 THEN swift_weekday - 1
        ELSE NULL
    END;
$$;

CREATE OR REPLACE FUNCTION public.chore_date_in_week_for_postgres_dow(
    week_start date,
    target_postgres_dow integer
)
RETURNS date
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT week_start + ((target_postgres_dow - EXTRACT(DOW FROM week_start)::integer + 7) % 7);
$$;

CREATE OR REPLACE FUNCTION public.chore_week_start_for_home(
    target_date date,
    target_home_id uuid
)
RETURNS date
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    home_week_starts_on integer;
    home_week_start_dow integer;
BEGIN
    SELECT h.week_starts_on
    INTO home_week_starts_on
    FROM public.homes h
    WHERE h.id = target_home_id
    LIMIT 1;

    home_week_start_dow := COALESCE(
        public.chore_postgres_dow_from_swift_weekday(home_week_starts_on),
        0
    );

    RETURN (
        target_date
        - (((EXTRACT(DOW FROM target_date)::integer - home_week_start_dow + 7) % 7) * INTERVAL '1 day')::interval
    )::date;
END;
$$;

CREATE OR REPLACE FUNCTION public.chore_reschedule_occurrence_due_at(
    destination_date date,
    original_due_at timestamptz,
    requested_timezone text
)
RETURNS timestamptz
LANGUAGE sql
STABLE
AS $$
    SELECT (destination_date::timestamp + (original_due_at AT TIME ZONE requested_timezone)::time) AT TIME ZONE requested_timezone;
$$;

CREATE OR REPLACE FUNCTION public.chore_occurrence_is_reschedule_eligible(occurrence_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.chore_occurrences co
        WHERE co.id = occurrence_id
          AND co.status = 'not_started'
          AND co.completed_at IS NULL
          AND co.approved_at IS NULL
          AND co.skipped_at IS NULL
          AND co.cancelled_at IS NULL
          AND co.claimed_by IS NULL
          AND NOT EXISTS (
              SELECT 1
              FROM public.chore_submissions cs
              WHERE cs.occurrence_id = co.id
          )
          AND NOT EXISTS (
              SELECT 1
              FROM public.chore_approvals ca
              WHERE ca.occurrence_id = co.id
          )
          AND NOT EXISTS (
              SELECT 1
              FROM public.chore_point_transactions cpt
              WHERE cpt.occurrence_id = co.id
                AND cpt.transaction_type = 'chore_earned'::public.chore_point_transaction_type
          )
          AND NOT EXISTS (
              SELECT 1
              FROM public.chore_occurrence_assignees coa
              WHERE coa.occurrence_id = co.id
                AND (
                    coa.status <> 'assigned'
                    OR coa.started_at IS NOT NULL
                    OR coa.submitted_at IS NOT NULL
                    OR coa.completed_at IS NOT NULL
                )
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.preview_chore_reschedule(
    requested_home_id uuid,
    requested_source_start date,
    requested_source_end date,
    requested_new_start date,
    requested_mode text
)
RETURNS TABLE(
    eligible_count integer,
    protected_count integer,
    source_start date,
    source_end date,
    destination_start date,
    destination_end date
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    caller_user_id uuid;
    resolved_destination_start date;
BEGIN
    caller_user_id := auth.uid();

    IF caller_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF requested_mode NOT IN ('move_unstarted', 'restart_schedule') THEN
        RAISE EXCEPTION 'Unsupported chore reschedule mode';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.home_members hm
        WHERE hm.home_id = requested_home_id
          AND hm.user_id = caller_user_id
          AND hm.role IN ('owner', 'admin')
    ) THEN
        RAISE EXCEPTION 'Only Home owners and admins can reschedule chores';
    END IF;

    resolved_destination_start := public.chore_week_start_for_home(requested_new_start, requested_home_id);

    RETURN QUERY
    WITH source_occurrences AS (
        SELECT co.*
        FROM public.chore_occurrences co
        WHERE co.home_id = requested_home_id
          AND co.due_local_date BETWEEN requested_source_start AND requested_source_end
          AND co.status <> 'cancelled'
    ),
    eligible AS (
        SELECT so.id
        FROM source_occurrences so
        WHERE public.chore_occurrence_is_reschedule_eligible(so.id)
    )
    SELECT
        (SELECT COUNT(*)::integer FROM eligible),
        (SELECT (COUNT(*) - (SELECT COUNT(*) FROM eligible))::integer FROM source_occurrences),
        requested_source_start,
        requested_source_end,
        resolved_destination_start,
        resolved_destination_start + 6;
END;
$$;

CREATE OR REPLACE FUNCTION public.reschedule_chore_schedule(
    requested_home_id uuid,
    requested_source_start date,
    requested_source_end date,
    requested_new_start date,
    requested_mode text,
    requested_generate_through date
)
RETURNS TABLE(
    moved_occurrence_count integer,
    protected_occurrence_count integer,
    rebased_template_count integer,
    deleted_future_occurrence_count integer,
    updated_calendar_event_count integer,
    deleted_calendar_event_count integer,
    generated_occurrence_count integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    caller_user_id uuid;
    resolved_destination_start date;
    resolved_destination_end date;
    calendar_event_id_to_delete uuid;
    generated_ids uuid[];
    generated_for_template uuid;
    debug_enabled boolean;
    debug_row record;
BEGIN
    caller_user_id := auth.uid();

    IF caller_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF requested_mode NOT IN ('move_unstarted', 'restart_schedule') THEN
        RAISE EXCEPTION 'Unsupported chore reschedule mode';
    END IF;

    IF requested_generate_through < requested_new_start THEN
        RAISE EXCEPTION 'Generate-through date must be on or after the requested new start';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.home_members hm
        WHERE hm.home_id = requested_home_id
          AND hm.user_id = caller_user_id
          AND hm.role IN ('owner', 'admin')
    ) THEN
        RAISE EXCEPTION 'Only Home owners and admins can reschedule chores';
    END IF;

    resolved_destination_start := public.chore_week_start_for_home(requested_new_start, requested_home_id);
    resolved_destination_end := resolved_destination_start + 6;
    debug_enabled := COALESCE(current_setting('app.debug_chore_reschedule', true), '') = 'on';

    CREATE TEMP TABLE IF NOT EXISTS pg_temp.chore_reschedule_eligible (
        occurrence_id uuid PRIMARY KEY,
        template_id uuid NOT NULL,
        chore_title text NOT NULL,
        room_name text,
        room_preferred_weekday integer,
        recurrence_weekdays smallint[],
        original_due_local_date date NOT NULL,
        original_due_at timestamptz NOT NULL,
        original_end_at timestamptz NOT NULL,
        original_calendar_event_id uuid,
        semantic_postgres_dow integer NOT NULL,
        uses_room_preferred_weekday boolean NOT NULL,
        destination_due_local_date date NOT NULL,
        destination_due_at timestamptz NOT NULL,
        destination_end_at timestamptz NOT NULL
    ) ON COMMIT DROP;

    TRUNCATE TABLE pg_temp.chore_reschedule_eligible;

    INSERT INTO pg_temp.chore_reschedule_eligible (
        occurrence_id,
        template_id,
        chore_title,
        room_name,
        room_preferred_weekday,
        recurrence_weekdays,
        original_due_local_date,
        original_due_at,
        original_end_at,
        original_calendar_event_id,
        semantic_postgres_dow,
        uses_room_preferred_weekday,
        destination_due_local_date,
        destination_due_at,
        destination_end_at
    )
    SELECT
        co.id,
        co.template_id,
        co.title_snapshot,
        cr.name,
        cr.preferred_cleaning_weekday,
        COALESCE(rr.weekdays, ARRAY[]::smallint[]),
        co.due_local_date,
        co.due_at,
        co.end_at,
        co.calendar_event_id,
        weekday_choice.semantic_postgres_dow,
        weekday_choice.uses_room_preferred_weekday,
        public.chore_date_in_week_for_postgres_dow(resolved_destination_start, weekday_choice.semantic_postgres_dow),
        public.chore_reschedule_occurrence_due_at(
            public.chore_date_in_week_for_postgres_dow(resolved_destination_start, weekday_choice.semantic_postgres_dow),
            co.due_at,
            COALESCE(NULLIF(rr.timezone, ''), 'UTC')
        ),
        public.chore_reschedule_occurrence_due_at(
            public.chore_date_in_week_for_postgres_dow(resolved_destination_start, weekday_choice.semantic_postgres_dow),
            co.due_at,
            COALESCE(NULLIF(rr.timezone, ''), 'UTC')
        ) + (co.end_at - co.due_at)
    FROM public.chore_occurrences co
    JOIN public.chore_templates ct ON ct.id = co.template_id
    LEFT JOIN public.chore_recurrence_rules rr ON rr.template_id = co.template_id
    LEFT JOIN public.chore_rooms cr ON cr.id = COALESCE(co.room_id_snapshot, ct.room_id)
    CROSS JOIN LATERAL (
        SELECT EXTRACT(DOW FROM co.due_local_date)::integer AS occurrence_postgres_dow
    ) occurrence_dow
    CROSS JOIN LATERAL (
        SELECT CASE
            WHEN rr.frequency = 'weekly'
              AND ct.contributes_to_room_cleaning IS TRUE
              AND cr.id IS NOT NULL
              AND cr.preferred_cleaning_weekday BETWEEN 1 AND 7
                THEN public.chore_postgres_dow_from_swift_weekday(cr.preferred_cleaning_weekday)
            WHEN rr.frequency = 'weekly'
              AND COALESCE(array_length(rr.weekdays, 1), 0) = 1
                THEN rr.weekdays[1]
            WHEN rr.frequency = 'weekly'
              AND occurrence_dow.occurrence_postgres_dow = ANY(COALESCE(rr.weekdays, ARRAY[]::smallint[]))
                THEN occurrence_dow.occurrence_postgres_dow
            ELSE occurrence_dow.occurrence_postgres_dow
        END AS semantic_postgres_dow,
        (
            rr.frequency = 'weekly'
            AND ct.contributes_to_room_cleaning IS TRUE
            AND cr.id IS NOT NULL
            AND cr.preferred_cleaning_weekday BETWEEN 1 AND 7
        ) AS uses_room_preferred_weekday
    ) weekday_choice
    WHERE co.home_id = requested_home_id
      AND co.due_local_date BETWEEN requested_source_start AND requested_source_end
      AND public.chore_occurrence_is_reschedule_eligible(co.id);

    IF debug_enabled THEN
        RAISE LOG 'CHORE RESCHEDULE DEBUG: mode %, source % - %, destination % - %',
            requested_mode, requested_source_start, requested_source_end, resolved_destination_start, resolved_destination_end;

        FOR debug_row IN
            SELECT
                e.chore_title,
                e.room_name,
                e.room_preferred_weekday,
                e.original_due_local_date,
                EXTRACT(DOW FROM e.original_due_local_date)::integer AS original_dow,
                e.recurrence_weekdays,
                e.destination_due_local_date,
                EXTRACT(DOW FROM e.destination_due_local_date)::integer AS destination_dow
            FROM pg_temp.chore_reschedule_eligible e
        LOOP
            RAISE LOG 'Chore: % | Room: % | Room preferred weekday: % | Original: % / % | Recurrence weekdays: % | Destination week: % - % | Computed: % / % %',
                debug_row.chore_title,
                COALESCE(debug_row.room_name, 'No Room'),
                COALESCE(debug_row.room_preferred_weekday::text, 'nil'),
                debug_row.original_due_local_date,
                debug_row.original_dow,
                debug_row.recurrence_weekdays::text,
                resolved_destination_start,
                resolved_destination_end,
                debug_row.destination_due_local_date,
                debug_row.destination_dow,
                CASE
                    WHEN debug_row.original_dow <> debug_row.destination_dow THEN 'WEEKDAY MISMATCH'
                    ELSE ''
                END;
        END LOOP;
    END IF;

    SELECT COUNT(*)::integer
    INTO moved_occurrence_count
    FROM pg_temp.chore_reschedule_eligible;

    SELECT (COUNT(*) - moved_occurrence_count)::integer
    INTO protected_occurrence_count
    FROM public.chore_occurrences co
    WHERE co.home_id = requested_home_id
      AND co.due_local_date BETWEEN requested_source_start AND requested_source_end
      AND co.status <> 'cancelled';

    rebased_template_count := 0;
    deleted_future_occurrence_count := 0;
    updated_calendar_event_count := 0;
    deleted_calendar_event_count := 0;
    generated_occurrence_count := 0;

    IF requested_mode = 'move_unstarted' THEN
        UPDATE public.chore_occurrences co
        SET due_local_date = e.destination_due_local_date,
            due_at = e.destination_due_at,
            end_at = e.destination_end_at,
            scheduled_key = co.template_id::text || ':' || e.destination_due_local_date::text,
            updated_at = now()
        FROM pg_temp.chore_reschedule_eligible e
        WHERE co.id = e.occurrence_id;

        UPDATE public.calendar_events ce
        SET starts_at = e.destination_due_at,
            ends_at = e.destination_end_at,
            updated_at = now()
        FROM pg_temp.chore_reschedule_eligible e
        WHERE ce.id = e.original_calendar_event_id;

        GET DIAGNOSTICS updated_calendar_event_count = ROW_COUNT;
    ELSE
        CREATE TEMP TABLE IF NOT EXISTS pg_temp.chore_reschedule_rebased_templates (
            template_id uuid PRIMARY KEY,
            new_start_date date NOT NULL,
            canonical_weekdays smallint[]
        ) ON COMMIT DROP;

        CREATE TEMP TABLE IF NOT EXISTS pg_temp.chore_reschedule_deleted_events (
            calendar_event_id uuid PRIMARY KEY
        ) ON COMMIT DROP;

        TRUNCATE TABLE pg_temp.chore_reschedule_rebased_templates;
        TRUNCATE TABLE pg_temp.chore_reschedule_deleted_events;

        INSERT INTO pg_temp.chore_reschedule_rebased_templates (template_id, new_start_date, canonical_weekdays)
        SELECT
            e.template_id,
            MIN(e.destination_due_local_date),
            CASE
                WHEN BOOL_OR(e.uses_room_preferred_weekday)
                    THEN ARRAY[MIN(e.semantic_postgres_dow)::smallint]
                ELSE NULL
            END
        FROM pg_temp.chore_reschedule_eligible e
        GROUP BY e.template_id;

        UPDATE public.chore_recurrence_rules rr
        SET start_date = rt.new_start_date,
            weekdays = CASE
                WHEN rr.frequency = 'weekly' AND rt.canonical_weekdays IS NOT NULL
                    THEN rt.canonical_weekdays
                ELSE rr.weekdays
            END,
            ends_on = CASE
                WHEN rr.ends_on IS NULL THEN NULL
                ELSE rr.ends_on + (rt.new_start_date - rr.start_date)
            END,
            updated_at = now()
        FROM pg_temp.chore_reschedule_rebased_templates rt
        WHERE rr.template_id = rt.template_id;

        GET DIAGNOSTICS rebased_template_count = ROW_COUNT;

        INSERT INTO pg_temp.chore_reschedule_deleted_events (calendar_event_id)
        SELECT DISTINCT co.calendar_event_id
        FROM public.chore_occurrences co
        JOIN pg_temp.chore_reschedule_rebased_templates rt ON rt.template_id = co.template_id
        WHERE co.home_id = requested_home_id
          AND co.due_local_date >= requested_source_start
          AND co.due_local_date <= requested_generate_through
          AND co.calendar_event_id IS NOT NULL
          AND public.chore_occurrence_is_reschedule_eligible(co.id)
        ON CONFLICT DO NOTHING;

        DELETE FROM public.chore_occurrence_assignees coa
        USING public.chore_occurrences co
        JOIN pg_temp.chore_reschedule_rebased_templates rt ON rt.template_id = co.template_id
        WHERE coa.occurrence_id = co.id
          AND co.home_id = requested_home_id
          AND co.due_local_date >= requested_source_start
          AND co.due_local_date <= requested_generate_through
          AND public.chore_occurrence_is_reschedule_eligible(co.id);

        DELETE FROM public.chore_occurrences co
        USING pg_temp.chore_reschedule_rebased_templates rt
        WHERE co.template_id = rt.template_id
          AND co.home_id = requested_home_id
          AND co.due_local_date >= requested_source_start
          AND co.due_local_date <= requested_generate_through
          AND public.chore_occurrence_is_reschedule_eligible(co.id);

        GET DIAGNOSTICS deleted_future_occurrence_count = ROW_COUNT;

        FOR calendar_event_id_to_delete IN
            SELECT de.calendar_event_id
            FROM pg_temp.chore_reschedule_deleted_events de
        LOOP
            PERFORM public.delete_calendar_event(calendar_event_id_to_delete);
            deleted_calendar_event_count := deleted_calendar_event_count + 1;
        END LOOP;

        FOR generated_for_template IN
            SELECT rt.template_id
            FROM pg_temp.chore_reschedule_rebased_templates rt
        LOOP
            generated_ids := public.generate_chore_occurrences(generated_for_template, requested_generate_through);
            generated_occurrence_count := generated_occurrence_count + COALESCE(array_length(generated_ids, 1), 0);
        END LOOP;
    END IF;

    RETURN NEXT;
END;
$$;

GRANT EXECUTE ON FUNCTION public.chore_postgres_dow_from_swift_weekday(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chore_date_in_week_for_postgres_dow(date, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chore_week_start_for_home(date, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chore_occurrence_is_reschedule_eligible(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.preview_chore_reschedule(uuid, date, date, date, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reschedule_chore_schedule(uuid, date, date, date, text, date) TO authenticated;
