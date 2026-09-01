BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_type t
        JOIN pg_enum e ON e.enumtypid = t.oid
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'public'
          AND t.typname = 'chore_occurrence_status'
          AND e.enumlabel = 'skipped'
    ) THEN
        RAISE EXCEPTION 'public.chore_occurrence_status must include skipped before applying skip_chore RPCs';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_type t
        JOIN pg_enum e ON e.enumtypid = t.oid
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'public'
          AND t.typname = 'chore_assignee_status'
          AND e.enumlabel = 'skipped'
    ) THEN
        RAISE EXCEPTION 'public.chore_assignee_status must include skipped before applying skip_chore RPCs';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.skip_chore(
    requested_occurrence_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_actor_id uuid := auth.uid();
    v_occurrence public.chore_occurrences;
    v_assignee public.chore_occurrence_assignees;
BEGIN
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    PERFORM pg_advisory_xact_lock(
        ('x' || substr(md5(requested_occurrence_id::text || ':' || v_actor_id::text), 1, 16))::bit(64)::bigint
    );

    SELECT *
    INTO v_occurrence
    FROM public.chore_occurrences
    WHERE id = requested_occurrence_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Chore occurrence not found';
    END IF;

    IF v_occurrence.status IN ('completed', 'skipped', 'cancelled') THEN
        RAISE EXCEPTION 'This chore is no longer active';
    END IF;

    IF v_occurrence.assignment_mode = 'open' THEN
        IF v_occurrence.claimed_by IS DISTINCT FROM v_actor_id THEN
            RAISE EXCEPTION 'You must claim this chore before skipping it';
        END IF;

        IF v_occurrence.status <> 'not_started' THEN
            RAISE EXCEPTION 'Only not started chores can be skipped';
        END IF;

        UPDATE public.chore_occurrences
        SET status = 'skipped',
            skipped_at = COALESCE(skipped_at, now()),
            updated_at = now()
        WHERE id = requested_occurrence_id;

        RETURN requested_occurrence_id;
    END IF;

    SELECT *
    INTO v_assignee
    FROM public.chore_occurrence_assignees
    WHERE occurrence_id = requested_occurrence_id
      AND user_id = v_actor_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'You are not assigned to this chore';
    END IF;

    IF v_assignee.status <> 'assigned' THEN
        RAISE EXCEPTION 'Only not started chores can be skipped';
    END IF;

    UPDATE public.chore_occurrence_assignees
    SET status = 'skipped'
    WHERE occurrence_id = requested_occurrence_id
      AND user_id = v_actor_id;

    IF v_occurrence.completion_mode = 'any_assignee'
       AND EXISTS (
           SELECT 1
           FROM public.chore_occurrence_assignees coa
           WHERE coa.occurrence_id = requested_occurrence_id
             AND coa.status = 'completed'
       ) THEN
        UPDATE public.chore_occurrences
        SET status = 'completed',
            completed_at = COALESCE(completed_at, now()),
            updated_at = now()
        WHERE id = requested_occurrence_id;
    ELSIF NOT EXISTS (
        SELECT 1
        FROM public.chore_occurrence_assignees coa
        WHERE coa.occurrence_id = requested_occurrence_id
          AND coa.status NOT IN ('completed', 'skipped', 'cancelled')
    ) THEN
        UPDATE public.chore_occurrences
        SET status = CASE
                WHEN EXISTS (
                    SELECT 1
                    FROM public.chore_occurrence_assignees coa
                    WHERE coa.occurrence_id = requested_occurrence_id
                      AND coa.status = 'completed'
                ) THEN 'completed'
                ELSE 'skipped'
            END,
            completed_at = CASE
                WHEN EXISTS (
                    SELECT 1
                    FROM public.chore_occurrence_assignees coa
                    WHERE coa.occurrence_id = requested_occurrence_id
                      AND coa.status = 'completed'
                ) THEN COALESCE(completed_at, now())
                ELSE completed_at
            END,
            skipped_at = CASE
                WHEN EXISTS (
                    SELECT 1
                    FROM public.chore_occurrence_assignees coa
                    WHERE coa.occurrence_id = requested_occurrence_id
                      AND coa.status = 'completed'
                ) THEN skipped_at
                ELSE COALESCE(skipped_at, now())
            END,
            updated_at = now()
        WHERE id = requested_occurrence_id;
    ELSE
        UPDATE public.chore_occurrences
        SET status = CASE
                WHEN EXISTS (
                    SELECT 1
                    FROM public.chore_occurrence_assignees coa
                    WHERE coa.occurrence_id = requested_occurrence_id
                      AND coa.status = 'awaiting_approval'
                ) THEN 'awaiting_approval'
                WHEN EXISTS (
                    SELECT 1
                    FROM public.chore_occurrence_assignees coa
                    WHERE coa.occurrence_id = requested_occurrence_id
                      AND coa.status = 'needs_redo'
                ) THEN 'needs_redo'
                WHEN EXISTS (
                    SELECT 1
                    FROM public.chore_occurrence_assignees coa
                    WHERE coa.occurrence_id = requested_occurrence_id
                      AND coa.status = 'in_progress'
                ) THEN 'in_progress'
                ELSE 'not_started'
            END,
            updated_at = now()
        WHERE id = requested_occurrence_id;
    END IF;

    RETURN requested_occurrence_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.skip_chore_as_admin(
    requested_occurrence_id uuid,
    requested_user_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_actor_id uuid := auth.uid();
    v_occurrence public.chore_occurrences;
    v_assignee public.chore_occurrence_assignees;
BEGIN
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    PERFORM pg_advisory_xact_lock(
        ('x' || substr(md5(requested_occurrence_id::text || ':' || requested_user_id::text), 1, 16))::bit(64)::bigint
    );

    SELECT *
    INTO v_occurrence
    FROM public.chore_occurrences
    WHERE id = requested_occurrence_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Chore occurrence not found';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.home_members hm
        WHERE hm.home_id = v_occurrence.home_id
          AND hm.user_id = v_actor_id
          AND hm.role IN ('owner', 'admin')
    ) THEN
        RAISE EXCEPTION 'Only Home owners and admins can skip chores for another member';
    END IF;

    IF v_occurrence.assignment_mode <> 'assigned' THEN
        RAISE EXCEPTION 'Admin skip is only available for assigned chores';
    END IF;

    IF v_occurrence.status IN ('completed', 'skipped', 'cancelled') THEN
        RAISE EXCEPTION 'This chore is no longer active';
    END IF;

    SELECT *
    INTO v_assignee
    FROM public.chore_occurrence_assignees
    WHERE occurrence_id = requested_occurrence_id
      AND user_id = requested_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Requested user is not assigned to this chore';
    END IF;

    IF v_assignee.status <> 'assigned' THEN
        RAISE EXCEPTION 'Only not started chores can be skipped';
    END IF;

    UPDATE public.chore_occurrence_assignees
    SET status = 'skipped'
    WHERE occurrence_id = requested_occurrence_id
      AND user_id = requested_user_id;

    IF v_occurrence.completion_mode = 'any_assignee'
       AND EXISTS (
           SELECT 1
           FROM public.chore_occurrence_assignees coa
           WHERE coa.occurrence_id = requested_occurrence_id
             AND coa.status = 'completed'
       ) THEN
        UPDATE public.chore_occurrences
        SET status = 'completed',
            completed_at = COALESCE(completed_at, now()),
            updated_at = now()
        WHERE id = requested_occurrence_id;
    ELSIF NOT EXISTS (
        SELECT 1
        FROM public.chore_occurrence_assignees coa
        WHERE coa.occurrence_id = requested_occurrence_id
          AND coa.status NOT IN ('completed', 'skipped', 'cancelled')
    ) THEN
        UPDATE public.chore_occurrences
        SET status = CASE
                WHEN EXISTS (
                    SELECT 1
                    FROM public.chore_occurrence_assignees coa
                    WHERE coa.occurrence_id = requested_occurrence_id
                      AND coa.status = 'completed'
                ) THEN 'completed'
                ELSE 'skipped'
            END,
            completed_at = CASE
                WHEN EXISTS (
                    SELECT 1
                    FROM public.chore_occurrence_assignees coa
                    WHERE coa.occurrence_id = requested_occurrence_id
                      AND coa.status = 'completed'
                ) THEN COALESCE(completed_at, now())
                ELSE completed_at
            END,
            skipped_at = CASE
                WHEN EXISTS (
                    SELECT 1
                    FROM public.chore_occurrence_assignees coa
                    WHERE coa.occurrence_id = requested_occurrence_id
                      AND coa.status = 'completed'
                ) THEN skipped_at
                ELSE COALESCE(skipped_at, now())
            END,
            updated_at = now()
        WHERE id = requested_occurrence_id;
    ELSE
        UPDATE public.chore_occurrences
        SET status = CASE
                WHEN EXISTS (
                    SELECT 1
                    FROM public.chore_occurrence_assignees coa
                    WHERE coa.occurrence_id = requested_occurrence_id
                      AND coa.status = 'awaiting_approval'
                ) THEN 'awaiting_approval'
                WHEN EXISTS (
                    SELECT 1
                    FROM public.chore_occurrence_assignees coa
                    WHERE coa.occurrence_id = requested_occurrence_id
                      AND coa.status = 'needs_redo'
                ) THEN 'needs_redo'
                WHEN EXISTS (
                    SELECT 1
                    FROM public.chore_occurrence_assignees coa
                    WHERE coa.occurrence_id = requested_occurrence_id
                      AND coa.status = 'in_progress'
                ) THEN 'in_progress'
                ELSE 'not_started'
            END,
            updated_at = now()
        WHERE id = requested_occurrence_id;
    END IF;

    RETURN requested_occurrence_id;
END;
$$;

REVOKE ALL ON FUNCTION public.skip_chore(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.skip_chore(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.skip_chore_as_admin(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.skip_chore_as_admin(uuid, uuid) TO authenticated;

COMMIT;
