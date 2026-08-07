create or replace function public.retire_chore_template(
    requested_template_id uuid,
    effective_from timestamptz
)
returns table(calendar_event_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
    resolved_home_id uuid;
    caller_user_id uuid;
begin
    caller_user_id := auth.uid();

    if caller_user_id is null then
        raise exception 'Authentication required';
    end if;

    select ct.home_id
    into resolved_home_id
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
        raise exception 'Only Home owners and admins can delete chores';
    end if;

    update public.chore_templates
    set
        is_active = false,
        archived_at = coalesce(archived_at, effective_from),
        updated_by = caller_user_id,
        updated_at = now()
    where id = requested_template_id;

    return query
    with affected_future_occurrences as (
        select
            co.id,
            co.calendar_event_id
        from public.chore_occurrences co
        where co.template_id = requested_template_id
          and co.due_at >= effective_from
          and co.status <> 'completed'
          and co.completed_at is null
          and co.approved_at is null
    ),
    cancelled_occurrences as (
        update public.chore_occurrences co
        set
            status = 'cancelled',
            cancelled_at = coalesce(co.cancelled_at, now()),
            updated_at = now()
        where co.id in (
            select afo.id
            from affected_future_occurrences afo
        )
          and co.status <> 'cancelled'
        returning co.id
    ),
    cancelled_assignees as (
        update public.chore_occurrence_assignees coa
        set status = 'cancelled'
        where coa.occurrence_id in (
            select afo.id
            from affected_future_occurrences afo
        )
          and coa.status not in ('completed', 'cancelled')
        returning coa.occurrence_id
    )
    select distinct afo.calendar_event_id
    from affected_future_occurrences afo
    where afo.calendar_event_id is not null;
end;
$$;

grant execute on function public.retire_chore_template(uuid, timestamptz) to authenticated;
