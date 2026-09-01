BEGIN;

ALTER TABLE public.chore_rooms
    ADD COLUMN IF NOT EXISTS room_type text,
    ADD COLUMN IF NOT EXISTS preferred_cleaning_weekday integer,
    ADD COLUMN IF NOT EXISTS preferred_cleaning_frequency text;

ALTER TABLE public.chore_rooms
    DROP CONSTRAINT IF EXISTS chore_rooms_room_type_check,
    ADD CONSTRAINT chore_rooms_room_type_check
        CHECK (
            room_type IS NULL
            OR room_type IN (
                'bedroom',
                'kitchen',
                'bathroom',
                'living_room',
                'dining_room',
                'laundry_room',
                'office',
                'garage',
                'outdoor',
                'other'
            )
        );

ALTER TABLE public.chore_rooms
    DROP CONSTRAINT IF EXISTS chore_rooms_preferred_cleaning_weekday_check,
    ADD CONSTRAINT chore_rooms_preferred_cleaning_weekday_check
        CHECK (
            preferred_cleaning_weekday IS NULL
            OR preferred_cleaning_weekday BETWEEN 1 AND 7
        );

ALTER TABLE public.chore_rooms
    DROP CONSTRAINT IF EXISTS chore_rooms_preferred_cleaning_frequency_check,
    ADD CONSTRAINT chore_rooms_preferred_cleaning_frequency_check
        CHECK (
            preferred_cleaning_frequency IS NULL
            OR preferred_cleaning_frequency IN (
                'daily',
                'multiple_times_week',
                'weekly',
                'every_two_weeks',
                'monthly',
                'custom'
            )
        );

ALTER TABLE public.chore_templates
    ADD COLUMN IF NOT EXISTS contributes_to_room_cleaning boolean NOT NULL DEFAULT false;

ALTER TABLE public.chore_occurrences
    ADD COLUMN IF NOT EXISTS contributes_to_room_cleaning_snapshot boolean NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS public.room_cleaning_history (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    home_id uuid NOT NULL REFERENCES public.homes(id) ON DELETE CASCADE,
    room_id uuid NOT NULL REFERENCES public.chore_rooms(id) ON DELETE CASCADE,
    cleaning_cycle_date date NOT NULL,
    cleaned_at timestamptz NOT NULL DEFAULT now(),
    completed_chore_count integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT room_cleaning_history_completed_chore_count_check
        CHECK (completed_chore_count >= 0),
    CONSTRAINT room_cleaning_history_home_room_cycle_key
        UNIQUE (home_id, room_id, cleaning_cycle_date)
);

CREATE INDEX IF NOT EXISTS room_cleaning_history_home_room_cleaned_at_idx
    ON public.room_cleaning_history (home_id, room_id, cleaned_at DESC);

CREATE INDEX IF NOT EXISTS room_cleaning_history_home_cleaned_at_idx
    ON public.room_cleaning_history (home_id, cleaned_at DESC);

CREATE INDEX IF NOT EXISTS chore_rooms_home_room_type_idx
    ON public.chore_rooms (home_id, room_type)
    WHERE archived_at IS NULL;

CREATE INDEX IF NOT EXISTS chore_rooms_home_preferred_cleaning_idx
    ON public.chore_rooms (home_id, preferred_cleaning_weekday, preferred_cleaning_frequency)
    WHERE archived_at IS NULL;

CREATE INDEX IF NOT EXISTS chore_templates_room_cleaning_idx
    ON public.chore_templates (home_id, room_id, contributes_to_room_cleaning)
    WHERE archived_at IS NULL;

CREATE INDEX IF NOT EXISTS chore_occurrences_room_cleaning_snapshot_idx
    ON public.chore_occurrences (home_id, room_id_snapshot, due_local_date)
    WHERE contributes_to_room_cleaning_snapshot = true;

ALTER TABLE public.room_cleaning_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Home members can view room cleaning history" ON public.room_cleaning_history;
CREATE POLICY "Home members can view room cleaning history"
    ON public.room_cleaning_history
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.home_members hm
            WHERE hm.home_id = room_cleaning_history.home_id
              AND hm.user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Home admins can insert room cleaning history" ON public.room_cleaning_history;
CREATE POLICY "Home admins can insert room cleaning history"
    ON public.room_cleaning_history
    FOR INSERT
    TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.home_members hm
            WHERE hm.home_id = room_cleaning_history.home_id
              AND hm.user_id = auth.uid()
              AND hm.role IN ('owner', 'admin')
        )
    );

DROP POLICY IF EXISTS "Home admins can update room cleaning history" ON public.room_cleaning_history;
CREATE POLICY "Home admins can update room cleaning history"
    ON public.room_cleaning_history
    FOR UPDATE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.home_members hm
            WHERE hm.home_id = room_cleaning_history.home_id
              AND hm.user_id = auth.uid()
              AND hm.role IN ('owner', 'admin')
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.home_members hm
            WHERE hm.home_id = room_cleaning_history.home_id
              AND hm.user_id = auth.uid()
              AND hm.role IN ('owner', 'admin')
        )
    );

DROP POLICY IF EXISTS "Home admins can delete room cleaning history" ON public.room_cleaning_history;
CREATE POLICY "Home admins can delete room cleaning history"
    ON public.room_cleaning_history
    FOR DELETE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.home_members hm
            WHERE hm.home_id = room_cleaning_history.home_id
              AND hm.user_id = auth.uid()
              AND hm.role IN ('owner', 'admin')
        )
    );

CREATE OR REPLACE VIEW public.chore_room_cleaning_summaries AS
SELECT
    cr.id,
    cr.home_id,
    cr.name,
    cr.room_type,
    cr.preferred_cleaning_weekday,
    cr.preferred_cleaning_frequency,
    cr.sort_order,
    cr.archived_at,
    cr.created_by,
    cr.created_at,
    cr.updated_at,
    latest.cleaned_at AS last_cleaned_at,
    COALESCE(latest.completed_chore_count, 0) AS completed_chore_count
FROM public.chore_rooms cr
LEFT JOIN LATERAL (
    SELECT
        rch.cleaned_at,
        rch.completed_chore_count
    FROM public.room_cleaning_history rch
    WHERE rch.home_id = cr.home_id
      AND rch.room_id = cr.id
    ORDER BY rch.cleaned_at DESC
    LIMIT 1
) latest ON true;

GRANT SELECT ON public.chore_room_cleaning_summaries TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.room_cleaning_history TO authenticated;

CREATE OR REPLACE FUNCTION public.get_chore_room_cleaning_summaries(requested_home_id uuid)
RETURNS TABLE (
    id uuid,
    home_id uuid,
    name text,
    room_type text,
    preferred_cleaning_weekday integer,
    preferred_cleaning_frequency text,
    sort_order integer,
    archived_at timestamptz,
    created_by uuid,
    created_at timestamptz,
    updated_at timestamptz,
    last_cleaned_at timestamptz,
    completed_chore_count integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id uuid := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.home_members hm
        WHERE hm.home_id = requested_home_id
          AND hm.user_id = v_user_id
    ) THEN
        RAISE EXCEPTION 'Home membership required';
    END IF;

    RETURN QUERY
    SELECT
        crs.id,
        crs.home_id,
        crs.name,
        crs.room_type,
        crs.preferred_cleaning_weekday,
        crs.preferred_cleaning_frequency,
        crs.sort_order,
        crs.archived_at,
        crs.created_by,
        crs.created_at,
        crs.updated_at,
        crs.last_cleaned_at,
        crs.completed_chore_count
    FROM public.chore_room_cleaning_summaries crs
    WHERE crs.home_id = requested_home_id
      AND crs.archived_at IS NULL
    ORDER BY crs.sort_order ASC, crs.name ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_chore_room_cleaning_summaries(uuid) TO authenticated;

COMMIT;
