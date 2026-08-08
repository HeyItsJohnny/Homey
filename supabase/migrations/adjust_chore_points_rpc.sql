create or replace function public.adjust_chore_points(
    requested_home_id uuid,
    requested_user_id uuid,
    requested_points integer,
    requested_description text,
    requested_transaction_at timestamptz
)
returns public.chore_point_transactions
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_actor_id uuid := auth.uid();
    v_description text := nullif(btrim(requested_description), '');
    v_current_balance integer := 0;
    v_inserted_transaction public.chore_point_transactions;
begin
    if v_actor_id is null then
        raise exception 'Authentication required';
    end if;

    if not exists (
        select 1
        from public.home_members hm
        where hm.home_id = requested_home_id
          and hm.user_id = v_actor_id
          and hm.role in ('owner', 'admin')
    ) then
        raise exception 'Only Home owners and admins can adjust rewards';
    end if;

    if not exists (
        select 1
        from public.home_members hm
        where hm.home_id = requested_home_id
          and hm.user_id = requested_user_id
    ) then
        raise exception 'The selected user is not a member of this Home';
    end if;

    if requested_points = 0 then
        raise exception 'Point adjustment cannot be zero';
    end if;

    if v_description is null then
        raise exception 'Adjustment description is required';
    end if;

    perform pg_advisory_xact_lock(
        ('x' || substr(md5(requested_home_id::text || ':' || requested_user_id::text), 1, 16))::bit(64)::bigint
    );

    select coalesce(sum(cpt.points), 0)::integer
    into v_current_balance
    from public.chore_point_transactions cpt
    where cpt.home_id = requested_home_id
      and cpt.user_id = requested_user_id;

    if requested_points < 0 and v_current_balance + requested_points < 0 then
        raise exception 'Cannot remove more points than this member currently has available';
    end if;

    insert into public.chore_point_transactions (
        home_id,
        user_id,
        transaction_type,
        points,
        description,
        created_by,
        created_at
    )
    values (
        requested_home_id,
        requested_user_id,
        'admin_adjustment'::public.chore_point_transaction_type,
        requested_points,
        v_description,
        v_actor_id,
        coalesce(requested_transaction_at, now())
    )
    returning *
    into v_inserted_transaction;

    return v_inserted_transaction;
end;
$$;

revoke all on function public.adjust_chore_points(uuid, uuid, integer, text, timestamptz) from public;
grant execute on function public.adjust_chore_points(uuid, uuid, integer, text, timestamptz) to authenticated;
