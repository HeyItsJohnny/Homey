-- Home invitation discovery and acceptance RPCs.
-- These functions intentionally derive the acting user from auth.uid() and the
-- authenticated email in auth.users. The iOS client supplies only an invitation ID.

create unique index if not exists home_members_one_active_user_per_home
on public.home_members (home_id, user_id)
where status = 'active';

create unique index if not exists home_invitations_one_pending_per_home_email
on public.home_invitations (home_id, lower(trim(email)))
where status = 'pending';

create or replace function public.get_my_pending_home_invitations()
returns table (
    id uuid,
    home_id uuid,
    home_name text,
    email text,
    role text,
    status text,
    invited_by uuid,
    inviter_display_name text,
    created_at timestamptz,
    expires_at timestamptz
)
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
    current_email text;
begin
    if auth.uid() is null then
        raise exception 'unauthenticated';
    end if;

    select lower(trim(u.email))
    into current_email
    from auth.users u
    where u.id = auth.uid();

    if current_email is null or current_email = '' then
        raise exception 'authenticated email not found';
    end if;

    return query
    select
        i.id,
        i.home_id,
        h.name::text as home_name,
        i.email::text,
        i.role::text,
        i.status::text,
        i.invited_by,
        coalesce(p.display_name, p.full_name, split_part(inviter.email, '@', 1))::text as inviter_display_name,
        i.created_at,
        i.expires_at
    from public.home_invitations i
    join public.homes h on h.id = i.home_id
    left join public.profiles p on p.id = i.invited_by
    left join auth.users inviter on inviter.id = i.invited_by
    where lower(trim(i.email)) = current_email
      and i.status = 'pending'
      and (i.expires_at is null or i.expires_at > now())
    order by i.created_at desc, i.email asc;
end;
$$;

create or replace function public.accept_home_invitation(invitation_id uuid)
returns table (
    home_id uuid,
    home_name text
)
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
    current_user_id uuid;
    current_email text;
    invitation_record public.home_invitations%rowtype;
    target_home_name text;
    update_sql text;
begin
    current_user_id := auth.uid();

    if current_user_id is null then
        raise exception 'unauthenticated';
    end if;

    select lower(trim(u.email))
    into current_email
    from auth.users u
    where u.id = current_user_id;

    if current_email is null or current_email = '' then
        raise exception 'authenticated email not found';
    end if;

    select *
    into invitation_record
    from public.home_invitations
    where id = invitation_id
    for update;

    if not found then
        raise exception 'invitation not found';
    end if;

    if invitation_record.status <> 'pending' then
        raise exception 'invitation not pending';
    end if;

    if lower(trim(invitation_record.email)) <> current_email then
        raise exception 'invitation email mismatch';
    end if;

    if invitation_record.expires_at is not null and invitation_record.expires_at <= now() then
        raise exception 'invitation expired';
    end if;

    if invitation_record.role not in ('member', 'admin') then
        raise exception 'unsupported invitation role';
    end if;

    select h.name::text
    into target_home_name
    from public.homes h
    where h.id = invitation_record.home_id;

    if target_home_name is null then
        raise exception 'home not found';
    end if;

    insert into public.home_members (home_id, user_id, role, status)
    select invitation_record.home_id, current_user_id, invitation_record.role, 'active'
    where not exists (
        select 1
        from public.home_members hm
        where hm.home_id = invitation_record.home_id
          and hm.user_id = current_user_id
          and hm.status = 'active'
    );

    update_sql := 'update public.home_invitations set status = ''accepted''';

    if exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'home_invitations'
          and column_name = 'accepted_at'
    ) then
        update_sql := update_sql || ', accepted_at = now()';
    end if;

    if exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'home_invitations'
          and column_name = 'accepted_by'
    ) then
        update_sql := update_sql || ', accepted_by = $2';
    end if;

    update_sql := update_sql || ' where id = $1';

    if position('accepted_by = $2' in update_sql) > 0 then
        execute update_sql using invitation_id, current_user_id;
    else
        execute update_sql using invitation_id;
    end if;

    return query
    select invitation_record.home_id, target_home_name;
end;
$$;

create or replace function public.decline_home_invitation(invitation_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
    current_user_id uuid;
    current_email text;
    invitation_record public.home_invitations%rowtype;
    update_sql text;
begin
    current_user_id := auth.uid();

    if current_user_id is null then
        raise exception 'unauthenticated';
    end if;

    select lower(trim(u.email))
    into current_email
    from auth.users u
    where u.id = current_user_id;

    if current_email is null or current_email = '' then
        raise exception 'authenticated email not found';
    end if;

    select *
    into invitation_record
    from public.home_invitations
    where id = invitation_id
    for update;

    if not found then
        raise exception 'invitation not found';
    end if;

    if invitation_record.status <> 'pending' then
        raise exception 'invitation not pending';
    end if;

    if lower(trim(invitation_record.email)) <> current_email then
        raise exception 'invitation email mismatch';
    end if;

    update_sql := 'update public.home_invitations set status = ''declined''';

    if exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'home_invitations'
          and column_name = 'declined_at'
    ) then
        update_sql := update_sql || ', declined_at = now()';
    end if;

    update_sql := update_sql || ' where id = $1';
    execute update_sql using invitation_id;
end;
$$;

revoke all on function public.get_my_pending_home_invitations() from public, anon;
revoke all on function public.accept_home_invitation(uuid) from public, anon;
revoke all on function public.decline_home_invitation(uuid) from public, anon;

grant execute on function public.get_my_pending_home_invitations() to authenticated;
grant execute on function public.accept_home_invitation(uuid) to authenticated;
grant execute on function public.decline_home_invitation(uuid) to authenticated;
