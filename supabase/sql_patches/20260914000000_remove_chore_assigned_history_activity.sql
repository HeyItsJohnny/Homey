-- Chore assignments remain operational records in chore_occurrence_assignees.
-- History activities are synthesized by these RPCs; remove only the ASSIGNED
-- branch from each deployed function definition.
DO $migration$
DECLARE
    function_signature regprocedure;
    function_definition text;
    assigned_position integer;
    started_position integer;
BEGIN
    FOREACH function_signature IN ARRAY ARRAY[
        'public.get_chore_history(uuid,uuid,integer,integer)'::regprocedure,
        'public.get_home_chore_history(uuid,integer,integer)'::regprocedure
    ]
    LOOP
        SELECT pg_get_functiondef(function_signature)
        INTO function_definition;

        assigned_position := strpos(function_definition, '-- ASSIGNED');
        IF assigned_position = 0 THEN
            CONTINUE;
        END IF;

        started_position := strpos(function_definition, '-- STARTED');
        IF started_position <= assigned_position THEN
            RAISE EXCEPTION 'STARTED branch not found after ASSIGNED in %', function_signature;
        END IF;

        function_definition :=
            left(function_definition, assigned_position - 1)
            || substring(function_definition FROM started_position);

        IF position('chore_assigned' IN function_definition) > 0 THEN
            RAISE EXCEPTION 'chore_assigned remains in %', function_signature;
        END IF;

        EXECUTE function_definition;
    END LOOP;
END;
$migration$;

-- Deployment verification: both function bodies must no longer synthesize
-- chore_assigned, while chore_occurrence_assignees and assigned_at are untouched.
DO $verification$
BEGIN
    IF position(
        'chore_assigned' IN pg_get_functiondef(
            'public.get_chore_history(uuid,uuid,integer,integer)'::regprocedure
        )
    ) > 0 OR position(
        'chore_assigned' IN pg_get_functiondef(
            'public.get_home_chore_history(uuid,integer,integer)'::regprocedure
        )
    ) > 0 THEN
        RAISE EXCEPTION 'A chore history RPC still generates chore_assigned';
    END IF;
END;
$verification$;
