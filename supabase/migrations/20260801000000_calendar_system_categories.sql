alter table public.calendar_categories
    add column if not exists system_key text,
    add column if not exists is_system boolean not null default false;

create unique index if not exists calendar_categories_home_system_key_uidx
    on public.calendar_categories (home_id, system_key)
    where system_key is not null;

create or replace function public.ensure_meal_calendar_category(requested_home_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    resolved_category_id uuid;
    category_sort_order integer;
    owner_user_id uuid;
begin
    select id
    into resolved_category_id
    from public.calendar_categories
    where home_id = requested_home_id
      and system_key = 'meal'
      and is_system = true
    limit 1;

    if resolved_category_id is not null then
        return resolved_category_id;
    end if;

    update public.calendar_categories
    set
        system_key = 'meal',
        is_system = true,
        name = 'Meal',
        icon_name = coalesce(nullif(icon_name, ''), 'fork.knife')
    where home_id = requested_home_id
      and system_key is null
      and lower(name) = 'meal'
    returning id into resolved_category_id;

    if resolved_category_id is not null then
        return resolved_category_id;
    end if;

    select coalesce(max(sort_order), -1) + 1
    into category_sort_order
    from public.calendar_categories
    where home_id = requested_home_id;

    select hm.user_id
    into owner_user_id
    from public.home_members hm
    where hm.home_id = requested_home_id
      and hm.role = 'owner'
    order by hm.joined_at asc nulls last
    limit 1;

    insert into public.calendar_categories (
        home_id,
        name,
        color_hex,
        icon_name,
        sort_order,
        system_key,
        is_system,
        created_by
    )
    values (
        requested_home_id,
        'Meal',
        'A0643A',
        'fork.knife',
        category_sort_order,
        'meal',
        true,
        owner_user_id
    )
    returning id into resolved_category_id;

    return resolved_category_id;
end;
$$;

update public.calendar_categories
set
    system_key = 'meal',
    is_system = true,
    name = 'Meal',
    icon_name = coalesce(nullif(icon_name, ''), 'fork.knife')
where system_key is null
  and lower(name) = 'meal';

insert into public.calendar_categories (
    home_id,
    name,
    color_hex,
    icon_name,
    sort_order,
    system_key,
    is_system,
    created_by
)
select
    h.id,
    'Meal',
    'A0643A',
    'fork.knife',
    coalesce(max(cc.sort_order), -1) + 1,
    'meal',
    true,
    (
        select hm.user_id
        from public.home_members hm
        where hm.home_id = h.id
          and hm.role = 'owner'
        order by hm.joined_at asc nulls last
        limit 1
    )
from public.homes h
left join public.calendar_categories cc
    on cc.home_id = h.id
where not exists (
    select 1
    from public.calendar_categories existing
    where existing.home_id = h.id
      and existing.system_key = 'meal'
)
group by h.id;

create or replace function public.protect_calendar_system_categories()
returns trigger
language plpgsql
as $$
begin
    if tg_op = 'DELETE' then
        if old.is_system or old.system_key is not null then
            raise exception 'System calendar categories cannot be deleted';
        end if;

        return old;
    end if;

    if old.is_system or old.system_key is not null then
        if new.system_key is distinct from old.system_key then
            raise exception 'System calendar category keys cannot be changed';
        end if;

        if new.name is distinct from old.name then
            raise exception 'System calendar category names cannot be changed';
        end if;

        if new.icon_name is distinct from old.icon_name then
            raise exception 'System calendar category icons cannot be changed';
        end if;

        new.is_system := true;
    end if;

    return new;
end;
$$;

drop trigger if exists protect_calendar_system_categories_update
    on public.calendar_categories;

create trigger protect_calendar_system_categories_update
    before update on public.calendar_categories
    for each row
    execute function public.protect_calendar_system_categories();

drop trigger if exists protect_calendar_system_categories_delete
    on public.calendar_categories;

create trigger protect_calendar_system_categories_delete
    before delete on public.calendar_categories
    for each row
    execute function public.protect_calendar_system_categories();
