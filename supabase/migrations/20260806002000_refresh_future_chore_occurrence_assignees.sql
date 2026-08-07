create or replace function public.refresh_future_chore_occurrence_assignees(
    requested_template_id uuid,
    effective_from timestamptz
)
returns table(
    future_occurrences_updated integer,
    new_assignee_count integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
    resolved_home_id uuid;
    caller_user_id uuid;
    current_assignment_mode text;
    current_assignee_count integer := 0;
    replaceable_occurrence_ids uuid[] := array[]::uuid[];
begin
    caller_user_id := auth.uid();

    if caller_user_id is null then
        raise exception 'Authentication required';
    end if;

    select
        ct.home_id,
        ct.assignment_mode::text
    into
        resolved_home_id,
        current_assignment_mode
    from public.chore_templates ct
    where ct.id = requested_template_id
    limit 1;

    if resolved_home_id is null then
        raise exception 'Chore not found';
    end if;

    if not exists (
        select 1
        from public.home_members hm
        where hm.home_id = resolved_home_id
          and hm.user_id = caller_user_id
          and hm.role in ('owner', 'admin')
    ) then
        raise exception 'Only Home owners and admins can update chore assignments';
    end if;

    select count(*)::integer
    into current_assignee_count
    from public.chore_template_assignees cta
    where cta.template_id = requested_template_id;

    select coalesce(array_agg(co.id), array[]::uuid[])
    into replaceable_occurrence_ids
    from public.chore_occurrences co
    where co.template_id = requested_template_id
      and co.due_at >= effective_from
      and co.status = 'not_started'
      and co.completed_at is null
      and co.approved_at is null
      and co.skipped_at is null
      and co.cancelled_at is null
      and not exists (
          select 1
          from public.chore_submissions cs
          where cs.occurrence_id = co.id
      )
      and not exists (
          select 1
          from public.chore_occurrence_assignees coa
          where coa.occurrence_id = co.id
            and (
                coa.status <> 'assigned'
                or coa.started_at is not null
                or coa.submitted_at is not null
                or coa.completed_at is not null
            )
      );

    update public.chore_occurrences co
    set
        title_snapshot = ct.title,
        description_snapshot = ct.description,
        instructions_snapshot = ct.instructions,
        category_id_snapshot = ct.category_id,
        room_id_snapshot = ct.room_id,
        assignment_mode = ct.assignment_mode,
        completion_mode = ct.completion_mode,
        points_value_snapshot = ct.points_value,
        requires_approval_snapshot = ct.requires_approval,
        requires_photo_snapshot = ct.requires_photo,
        updated_at = now()
    from public.chore_templates ct
    where co.id = any(replaceable_occurrence_ids)
      and ct.id = requested_template_id;

    get diagnostics future_occurrences_updated = row_count;

    delete from public.chore_occurrence_assignees coa
    where coa.occurrence_id = any(replaceable_occurrence_ids);

    if current_assignment_mode = 'assigned' then
        insert into public.chore_occurrence_assignees (
            occurrence_id,
            user_id,
            status,
            assigned_at
        )
        select
            occurrence_id,
            cta.user_id,
            'assigned',
            now()
        from unnest(replaceable_occurrence_ids) as occurrence_ids(occurrence_id)
        join public.chore_template_assignees cta
          on cta.template_id = requested_template_id
        on conflict (occurrence_id, user_id) do update
        set
            status = excluded.status,
            assigned_at = excluded.assigned_at,
            started_at = null,
            submitted_at = null,
            completed_at = null;
    end if;

    new_assignee_count := current_assignee_count;
    return next;
end;
$$;

grant execute on function public.refresh_future_chore_occurrence_assignees(uuid, timestamptz) to authenticated;
