create or replace function public.get_chore_history(
    requested_home_id uuid,
    requested_user_id uuid,
    requested_limit integer default 10,
    requested_offset integer default 0
)
returns table (
    activity_id text,
    activity_type text,
    home_id uuid,
    user_id uuid,
    title text,
    subtitle text,
    occurred_at timestamptz,
    points_delta integer,
    occurrence_id uuid,
    submission_id uuid,
    approval_id uuid,
    reward_id uuid,
    redemption_id uuid,
    related_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_actor_id uuid := auth.uid();
    v_limit integer := greatest(coalesce(requested_limit, 10), 1);
    v_offset integer := greatest(coalesce(requested_offset, 0), 0);
begin
    if v_actor_id is null then
        raise exception 'Authentication required';
    end if;

    if not exists (
        select 1
        from public.home_members hm
        where hm.home_id = requested_home_id
          and hm.user_id = requested_user_id
    ) then
        raise exception 'The selected user is not a member of this Home';
    end if;

    if requested_user_id <> v_actor_id and not exists (
        select 1
        from public.home_members hm
        where hm.home_id = requested_home_id
          and hm.user_id = v_actor_id
          and hm.role in ('owner', 'admin')
    ) then
        raise exception 'Only Home owners and admins can view another member''s chore history';
    end if;

    return query
    with activities as (
        select
            'assigned:' || coa.occurrence_id::text || ':' || coa.user_id::text as activity_id,
            'chore_assigned'::text as activity_type,
            co.home_id,
            coa.user_id,
            co.title_snapshot || ' assigned' as title,
            'Assigned'::text as subtitle,
            coa.assigned_at as occurred_at,
            null::integer as points_delta,
            coa.occurrence_id,
            null::uuid as submission_id,
            null::uuid as approval_id,
            null::uuid as reward_id,
            null::uuid as redemption_id,
            coa.occurrence_id as related_id
        from public.chore_occurrence_assignees coa
        join public.chore_occurrences co on co.id = coa.occurrence_id
        where co.home_id = requested_home_id
          and coa.user_id = requested_user_id
          and coa.assigned_at is not null

        union all

        select
            'started:' || coa.occurrence_id::text || ':' || coa.user_id::text,
            'chore_started'::text,
            co.home_id,
            coa.user_id,
            co.title_snapshot || ' started',
            'Chore started'::text,
            coa.started_at,
            null::integer,
            coa.occurrence_id,
            null::uuid,
            null::uuid,
            null::uuid,
            null::uuid,
            coa.occurrence_id
        from public.chore_occurrence_assignees coa
        join public.chore_occurrences co on co.id = coa.occurrence_id
        where co.home_id = requested_home_id
          and coa.user_id = requested_user_id
          and coa.started_at is not null

        union all

        select
            'submission:' || cs.id::text,
            'chore_submitted'::text,
            co.home_id,
            cs.submitted_by,
            co.title_snapshot || ' submitted',
            'Pending Approval'::text,
            cs.submitted_at,
            null::integer,
            cs.occurrence_id,
            cs.id,
            null::uuid,
            null::uuid,
            null::uuid,
            cs.id
        from public.chore_submissions cs
        join public.chore_occurrences co on co.id = cs.occurrence_id
        where co.home_id = requested_home_id
          and cs.submitted_by = requested_user_id

        union all

        select
            'approval:' || ca.id::text,
            case
                when ca.decision = 'approved'::public.chore_approval_decision then 'chore_approved'
                else 'chore_needs_redo'
            end,
            co.home_id,
            cs.submitted_by,
            case
                when ca.decision = 'approved'::public.chore_approval_decision then co.title_snapshot || ' approved'
                else co.title_snapshot || ' needs redo'
            end,
            case
                when ca.decision = 'approved'::public.chore_approval_decision then 'Approved'
                else 'Admin requested redo'
            end,
            ca.reviewed_at,
            case
                when ca.decision = 'approved'::public.chore_approval_decision then coalesce(ca.points_awarded, earned.points, co.points_value_snapshot)
                else null::integer
            end,
            ca.occurrence_id,
            ca.submission_id,
            ca.id,
            null::uuid,
            null::uuid,
            ca.id
        from public.chore_approvals ca
        join public.chore_submissions cs on cs.id = ca.submission_id
        join public.chore_occurrences co on co.id = ca.occurrence_id
        left join lateral (
            select cpt.points
            from public.chore_point_transactions cpt
            where cpt.home_id = requested_home_id
              and cpt.user_id = requested_user_id
              and cpt.transaction_type = 'chore_earned'::public.chore_point_transaction_type
              and cpt.approval_id = ca.id
            order by cpt.created_at desc, cpt.id desc
            limit 1
        ) earned on true
        where co.home_id = requested_home_id
          and cs.submitted_by = requested_user_id

        union all

        select
            'completed:' || coa.occurrence_id::text || ':' || coa.user_id::text,
            'chore_completed'::text,
            co.home_id,
            coa.user_id,
            co.title_snapshot || ' completed',
            'Completed'::text,
            coa.completed_at,
            coalesce(earned.points, co.points_value_snapshot),
            coa.occurrence_id,
            null::uuid,
            null::uuid,
            null::uuid,
            null::uuid,
            coa.occurrence_id
        from public.chore_occurrence_assignees coa
        join public.chore_occurrences co on co.id = coa.occurrence_id
        left join lateral (
            select cpt.points
            from public.chore_point_transactions cpt
            where cpt.home_id = requested_home_id
              and cpt.user_id = requested_user_id
              and cpt.transaction_type = 'chore_earned'::public.chore_point_transaction_type
              and cpt.occurrence_id = co.id
            order by cpt.created_at desc, cpt.id desc
            limit 1
        ) earned on true
        where co.home_id = requested_home_id
          and coa.user_id = requested_user_id
          and coa.completed_at is not null
          and co.requires_approval_snapshot = false

        union all

        select
            'claim:' || cc.id::text,
            'chore_claimed'::text,
            co.home_id,
            cc.user_id,
            co.title_snapshot || ' claimed',
            'Open chore claimed'::text,
            cc.claimed_at,
            null::integer,
            cc.occurrence_id,
            null::uuid,
            null::uuid,
            null::uuid,
            null::uuid,
            cc.id
        from public.chore_claims cc
        join public.chore_occurrences co on co.id = cc.occurrence_id
        where co.home_id = requested_home_id
          and cc.user_id = requested_user_id

        union all

        select
            'skipped:' || co.id::text,
            'chore_skipped'::text,
            co.home_id,
            requested_user_id,
            co.title_snapshot || ' skipped',
            'Skipped'::text,
            co.skipped_at,
            null::integer,
            co.id,
            null::uuid,
            null::uuid,
            null::uuid,
            null::uuid,
            co.id
        from public.chore_occurrences co
        where co.home_id = requested_home_id
          and co.skipped_at is not null
          and (
              co.claimed_by = requested_user_id
              or exists (
                  select 1
                  from public.chore_occurrence_assignees coa
                  where coa.occurrence_id = co.id
                    and coa.user_id = requested_user_id
              )
          )

        union all

        select
            'cancelled:' || co.id::text,
            'chore_cancelled'::text,
            co.home_id,
            requested_user_id,
            co.title_snapshot || ' cancelled',
            'Cancelled'::text,
            co.cancelled_at,
            null::integer,
            co.id,
            null::uuid,
            null::uuid,
            null::uuid,
            null::uuid,
            co.id
        from public.chore_occurrences co
        where co.home_id = requested_home_id
          and co.cancelled_at is not null
          and (
              co.claimed_by = requested_user_id
              or exists (
                  select 1
                  from public.chore_occurrence_assignees coa
                  where coa.occurrence_id = co.id
                    and coa.user_id = requested_user_id
              )
          )

        union all

        select
            'points:' || cpt.id::text,
            case cpt.transaction_type
                when 'admin_adjustment'::public.chore_point_transaction_type then 'points_adjustment'
                when 'reward_redemption'::public.chore_point_transaction_type then 'reward_redeemed'
                when 'reward_refund'::public.chore_point_transaction_type then 'reward_refunded'
                else 'points_earned'
            end,
            cpt.home_id,
            cpt.user_id,
            coalesce(
                nullif(btrim(cpt.description), ''),
                case cpt.transaction_type
                    when 'admin_adjustment'::public.chore_point_transaction_type then 'Adjustment'
                    when 'reward_redemption'::public.chore_point_transaction_type then 'Reward redeemed'
                    when 'reward_refund'::public.chore_point_transaction_type then 'Reward refund'
                    else 'Points earned'
                end
            ),
            case cpt.transaction_type
                when 'admin_adjustment'::public.chore_point_transaction_type then 'Adjustment'
                when 'reward_redemption'::public.chore_point_transaction_type then 'Reward redeemed'
                when 'reward_refund'::public.chore_point_transaction_type then 'Reward refund'
                else 'Points earned'
            end,
            cpt.created_at,
            cpt.points,
            cpt.occurrence_id,
            cpt.submission_id,
            cpt.approval_id,
            cpt.reward_id,
            null::uuid,
            cpt.id
        from public.chore_point_transactions cpt
        where cpt.home_id = requested_home_id
          and cpt.user_id = requested_user_id
          and (
              cpt.transaction_type <> 'chore_earned'::public.chore_point_transaction_type
              or (cpt.approval_id is null and cpt.occurrence_id is null)
          )
    )
    select
        a.activity_id,
        a.activity_type,
        a.home_id,
        a.user_id,
        a.title,
        a.subtitle,
        a.occurred_at,
        a.points_delta,
        a.occurrence_id,
        a.submission_id,
        a.approval_id,
        a.reward_id,
        a.redemption_id,
        a.related_id
    from activities a
    where a.occurred_at is not null
    order by a.occurred_at desc, a.activity_id desc
    limit v_limit
    offset v_offset;
end;
$$;

revoke all on function public.get_chore_history(uuid, uuid, integer, integer) from public;
grant execute on function public.get_chore_history(uuid, uuid, integer, integer) to authenticated;
