BEGIN;

CREATE OR REPLACE FUNCTION public.submit_chore_as_admin(
    requested_occurrence_id uuid,
    requested_user_id uuid,
    requested_completion_note text DEFAULT NULL,
    requested_photo_path text DEFAULT NULL
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
    v_submission_id uuid;
    v_attempt_number integer;
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
        RAISE EXCEPTION 'Only Home owners and admins can submit chores for another member';
    END IF;

    IF v_occurrence.assignment_mode <> 'assigned' THEN
        RAISE EXCEPTION 'Admin submission is only available for assigned chores';
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

    IF v_assignee.status = 'completed' THEN
        RAISE EXCEPTION 'This member has already completed this chore';
    END IF;

    IF v_assignee.status = 'awaiting_approval' THEN
        RAISE EXCEPTION 'This chore is already awaiting approval';
    END IF;

    IF v_assignee.status NOT IN ('assigned', 'in_progress', 'needs_redo') THEN
        RAISE EXCEPTION 'This member cannot submit this chore';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.chore_submissions cs
        WHERE cs.occurrence_id = requested_occurrence_id
          AND cs.submitted_by = requested_user_id
          AND cs.status = 'pending'
    ) THEN
        RAISE EXCEPTION 'This chore is already awaiting approval';
    END IF;

    SELECT COALESCE(MAX(cs.attempt_number), 0) + 1
    INTO v_attempt_number
    FROM public.chore_submissions cs
    WHERE cs.occurrence_id = requested_occurrence_id
      AND cs.submitted_by = requested_user_id;

    IF v_occurrence.requires_approval_snapshot THEN
        INSERT INTO public.chore_submissions (
            occurrence_id,
            submitted_by,
            completion_note,
            photo_path,
            status,
            attempt_number,
            submitted_at,
            updated_at
        )
        VALUES (
            requested_occurrence_id,
            requested_user_id,
            NULLIF(btrim(requested_completion_note), ''),
            NULLIF(btrim(requested_photo_path), ''),
            'pending',
            v_attempt_number,
            now(),
            now()
        )
        RETURNING id
        INTO v_submission_id;

        UPDATE public.chore_occurrence_assignees
        SET status = 'awaiting_approval',
            submitted_at = now()
        WHERE occurrence_id = requested_occurrence_id
          AND user_id = requested_user_id;

        IF NOT EXISTS (
               SELECT 1
               FROM public.chore_occurrence_assignees coa
               WHERE coa.occurrence_id = requested_occurrence_id
                 AND coa.status <> 'completed'
           ) THEN
            UPDATE public.chore_occurrences
            SET status = 'completed',
                completed_at = COALESCE(completed_at, now()),
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
                    ELSE 'in_progress'
                END,
                updated_at = now()
            WHERE id = requested_occurrence_id;
        END IF;

        RETURN v_submission_id;
    END IF;

    UPDATE public.chore_occurrence_assignees
    SET status = 'completed',
        submitted_at = COALESCE(submitted_at, now()),
        completed_at = now()
    WHERE occurrence_id = requested_occurrence_id
      AND user_id = requested_user_id;

    INSERT INTO public.chore_point_transactions (
        home_id,
        user_id,
        transaction_type,
        points,
        description,
        occurrence_id,
        created_by,
        created_at
    )
    SELECT
        v_occurrence.home_id,
        requested_user_id,
        'chore_earned'::public.chore_point_transaction_type,
        greatest(v_occurrence.points_value_snapshot, 0),
        v_occurrence.title_snapshot || ' completed',
        requested_occurrence_id,
        v_actor_id,
        now()
    WHERE greatest(v_occurrence.points_value_snapshot, 0) > 0
      AND NOT EXISTS (
          SELECT 1
          FROM public.chore_point_transactions cpt
          WHERE cpt.occurrence_id = requested_occurrence_id
            AND cpt.user_id = requested_user_id
            AND cpt.transaction_type = 'chore_earned'::public.chore_point_transaction_type
      );

    IF v_occurrence.completion_mode = 'any_assignee'
       OR NOT EXISTS (
           SELECT 1
           FROM public.chore_occurrence_assignees coa
           WHERE coa.occurrence_id = requested_occurrence_id
             AND coa.status <> 'completed'
       ) THEN
        UPDATE public.chore_occurrences
        SET status = 'completed',
            completed_at = COALESCE(completed_at, now()),
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
                ELSE 'in_progress'
            END,
            updated_at = now()
        WHERE id = requested_occurrence_id;
    END IF;

    RETURN requested_occurrence_id;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_chore_as_admin(uuid, uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_chore_as_admin(uuid, uuid, text, text) TO authenticated;

COMMIT;
