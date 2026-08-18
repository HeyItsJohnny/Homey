create or replace function public.update_calendar_category(
    target_category_id uuid,
    category_name text,
    category_color_hex text,
    category_icon_name text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    requesting_user_id uuid := auth.uid();
    existing_category record;
    normalized_name text := btrim(category_name);
    normalized_color_hex text := upper(regexp_replace(btrim(category_color_hex), '^#', ''));
    normalized_icon_name text := nullif(btrim(category_icon_name), '');
begin
    if requesting_user_id is null then
        raise exception 'Authentication required'
            using errcode = '28000';
    end if;

    select
        cc.id,
        cc.home_id,
        cc.name,
        cc.icon_name,
        cc.is_system,
        cc.system_key
    into existing_category
    from public.calendar_categories cc
    where cc.id = target_category_id;

    if not found then
        raise exception 'Calendar category not found'
            using errcode = 'P0002';
    end if;

    if normalized_name is null or normalized_name = '' then
        raise exception 'Enter a category name'
            using errcode = '22023';
    end if;

    if normalized_color_hex is null or normalized_color_hex !~ '^[0-9A-F]{6}$' then
        raise exception 'Choose a valid category color'
            using errcode = '22023';
    end if;

    if not exists (
        select 1
        from public.home_members hm
        where hm.home_id = existing_category.home_id
          and hm.user_id = requesting_user_id
          and hm.role in ('owner', 'admin')
    ) then
        raise exception 'Only Home owners and admins can manage Calendar Categories.'
            using errcode = '42501';
    end if;

    if coalesce(existing_category.is_system, false)
       or existing_category.system_key is not null then
        if normalized_name is distinct from existing_category.name then
            raise exception 'System calendar category names cannot be changed'
                using errcode = '42501';
        end if;

        if normalized_icon_name is distinct from nullif(btrim(existing_category.icon_name), '') then
            raise exception 'System calendar category icons cannot be changed'
                using errcode = '42501';
        end if;

        update public.calendar_categories
        set
            color_hex = normalized_color_hex,
            updated_at = now()
        where id = target_category_id;
    else
        update public.calendar_categories
        set
            name = normalized_name,
            color_hex = normalized_color_hex,
            icon_name = normalized_icon_name,
            updated_at = now()
        where id = target_category_id;
    end if;

    update public.calendar_events
    set
        color_hex = normalized_color_hex,
        updated_at = now()
    where category_id = target_category_id;
end;
$$;

revoke all on function public.update_calendar_category(uuid, text, text, text) from public;
revoke all on function public.update_calendar_category(uuid, text, text, text) from anon;

grant execute
on function public.update_calendar_category(uuid, text, text, text)
to authenticated;
