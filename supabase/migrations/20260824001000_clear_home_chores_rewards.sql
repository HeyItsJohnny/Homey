create or replace function public.clear_home_chores(requested_home_id uuid)
returns table (
    chore_definitions_deleted integer,
    recurrence_rules_deleted integer,
    occurrences_deleted integer,
    occurrence_assignees_deleted integer,
    claims_deleted integer,
    submissions_deleted integer,
    approvals_deleted integer,
    point_transactions_deleted integer,
    calendar_events_deleted integer,
    categories_deleted integer,
    rooms_deleted integer,
    rewards_deleted integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id uuid := auth.uid();
    v_template_ids uuid[];
    v_occurrence_ids uuid[];
    v_calendar_event_ids uuid[];
    v_reward_ids uuid[];
    v_template_assignees_deleted integer := 0;
    v_reward_redemptions_deleted integer := 0;
begin
    if v_user_id is null then
        raise exception 'Authentication required';
    end if;

    if not exists (
        select 1
        from public.home_members hm
        where hm.home_id = requested_home_id
          and hm.user_id = v_user_id
          and hm.role = 'owner'
    ) then
        raise exception 'Only the Home owner can clear chores';
    end if;

    select coalesce(array_agg(ct.id), array[]::uuid[])
    into v_template_ids
    from public.chore_templates ct
    where ct.home_id = requested_home_id;

    select coalesce(array_agg(co.id), array[]::uuid[])
    into v_occurrence_ids
    from public.chore_occurrences co
    where co.home_id = requested_home_id;

    select coalesce(array_agg(co.calendar_event_id), array[]::uuid[])
    into v_calendar_event_ids
    from public.chore_occurrences co
    where co.home_id = requested_home_id
      and co.calendar_event_id is not null;

    select coalesce(array_agg(cr.id), array[]::uuid[])
    into v_reward_ids
    from public.chore_rewards cr
    where cr.home_id = requested_home_id;

    chore_definitions_deleted := 0;
    recurrence_rules_deleted := 0;
    occurrences_deleted := 0;
    occurrence_assignees_deleted := 0;
    claims_deleted := 0;
    submissions_deleted := 0;
    approvals_deleted := 0;
    point_transactions_deleted := 0;
    calendar_events_deleted := 0;
    categories_deleted := 0;
    rooms_deleted := 0;
    rewards_deleted := 0;

    with deleted as (
        delete from public.chore_reward_redemptions crr
        where crr.home_id = requested_home_id
        returning 1
    )
    select count(*)::integer into v_reward_redemptions_deleted from deleted;

    with deleted as (
        delete from public.chore_point_transactions cpt
        where cpt.home_id = requested_home_id
        returning 1
    )
    select count(*)::integer into point_transactions_deleted from deleted;

    with deleted as (
        delete from public.chore_approvals ca
        where ca.occurrence_id = any(v_occurrence_ids)
        returning 1
    )
    select count(*)::integer into approvals_deleted from deleted;

    with deleted as (
        delete from public.chore_submissions cs
        where cs.occurrence_id = any(v_occurrence_ids)
        returning 1
    )
    select count(*)::integer into submissions_deleted from deleted;

    with deleted as (
        delete from public.chore_claims cc
        where cc.occurrence_id = any(v_occurrence_ids)
        returning 1
    )
    select count(*)::integer into claims_deleted from deleted;

    with deleted as (
        delete from public.chore_occurrence_assignees coa
        where coa.occurrence_id = any(v_occurrence_ids)
        returning 1
    )
    select count(*)::integer into occurrence_assignees_deleted from deleted;

    update public.chore_occurrences co
    set calendar_event_id = null
    where co.home_id = requested_home_id
      and co.calendar_event_id = any(v_calendar_event_ids);

    with deleted as (
        delete from public.calendar_events ce
        where ce.home_id = requested_home_id
          and ce.id = any(v_calendar_event_ids)
        returning 1
    )
    select count(*)::integer into calendar_events_deleted from deleted;

    with deleted as (
        delete from public.chore_occurrences co
        where co.home_id = requested_home_id
        returning 1
    )
    select count(*)::integer into occurrences_deleted from deleted;

    with deleted as (
        delete from public.chore_recurrence_rules crr
        where crr.template_id = any(v_template_ids)
        returning 1
    )
    select count(*)::integer into recurrence_rules_deleted from deleted;

    with deleted as (
        delete from public.chore_template_assignees cta
        where cta.template_id = any(v_template_ids)
        returning 1
    )
    select count(*)::integer into v_template_assignees_deleted from deleted;

    occurrence_assignees_deleted := occurrence_assignees_deleted + v_template_assignees_deleted;

    with deleted as (
        delete from public.chore_templates ct
        where ct.home_id = requested_home_id
        returning 1
    )
    select count(*)::integer into chore_definitions_deleted from deleted;

    with deleted as (
        delete from public.chore_categories cc
        where cc.home_id = requested_home_id
        returning 1
    )
    select count(*)::integer into categories_deleted from deleted;

    with deleted as (
        delete from public.chore_rooms cr
        where cr.home_id = requested_home_id
        returning 1
    )
    select count(*)::integer into rooms_deleted from deleted;

    with deleted as (
        delete from public.chore_rewards cr
        where cr.home_id = requested_home_id
          and cr.id = any(v_reward_ids)
        returning 1
    )
    select count(*)::integer into rewards_deleted from deleted;

    return next;
end;
$$;

revoke all on function public.clear_home_chores(uuid) from public;
grant execute on function public.clear_home_chores(uuid) to authenticated;
