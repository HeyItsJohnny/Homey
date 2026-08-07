create or replace function public.replace_future_chore_occurrences(
    requested_template_id uuid,
    effective_from timestamptz,
    generate_through date
)
returns table(
    occurrence_id uuid,
    calendar_event_id uuid
)
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
        raise exception 'Only Home owners and admins can update chore schedules';
    end if;

    create temporary table if not exists pg_temp.replace_future_chore_occurrences_result (
        occurrence_id uuid primary key,
        calendar_event_id uuid
    ) on commit drop;

    truncate table pg_temp.replace_future_chore_occurrences_result;

    insert into pg_temp.replace_future_chore_occurrences_result (
        occurrence_id,
        calendar_event_id
    )
    select
        co.id,
        co.calendar_event_id
    from public.chore_occurrences co
    where co.template_id = requested_template_id
      and co.due_at >= effective_from
      and co.due_local_date <= generate_through
      and co.status = 'not_started'
      and co.completed_at is null
      and co.approved_at is null
      and co.skipped_at is null
      and co.cancelled_at is null
      and co.claimed_by is null
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

    delete from public.chore_occurrence_assignees coa
    using pg_temp.replace_future_chore_occurrences_result replacement
    where coa.occurrence_id = replacement.occurrence_id;

    delete from public.chore_occurrences co
    using pg_temp.replace_future_chore_occurrences_result replacement
    where co.id = replacement.occurrence_id;

    return query
    select
        replacement.occurrence_id,
        replacement.calendar_event_id
    from pg_temp.replace_future_chore_occurrences_result replacement;
end;
$$;

grant execute on function public.replace_future_chore_occurrences(uuid, timestamptz, date) to authenticated;
