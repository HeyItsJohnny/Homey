create or replace function public.clear_home_meals(requested_home_id uuid)
returns table(
    meals_deleted integer,
    meal_recipes_deleted integer,
    recipe_ingredients_deleted integer,
    recipe_steps_deleted integer,
    meal_photos_deleted integer,
    meal_favorites_deleted integer,
    meal_collections_deleted integer,
    meal_collection_items_deleted integer,
    meal_event_details_deleted integer,
    calendar_events_deleted integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id uuid := auth.uid();
    v_meal_ids uuid[];
    v_recipe_ids uuid[];
    v_collection_ids uuid[];
    v_calendar_event_ids uuid[];
    v_calendar_event_id uuid;
    v_deleted_count integer;
begin
    if v_user_id is null then
        raise exception 'Authentication required'
            using errcode = '28000';
    end if;

    if not exists (
        select 1
        from public.home_members hm
        where hm.home_id = requested_home_id
          and hm.user_id = v_user_id
          and hm.role = 'owner'
    ) then
        raise exception 'Only the Home owner can clear meals.'
            using errcode = '42501';
    end if;

    select coalesce(array_agg(m.id), array[]::uuid[])
    into v_meal_ids
    from public.meals m
    where m.home_id = requested_home_id;

    select coalesce(array_agg(mr.id), array[]::uuid[])
    into v_recipe_ids
    from public.meal_recipes mr
    where mr.meal_id = any(v_meal_ids);

    select coalesce(array_agg(mc.id), array[]::uuid[])
    into v_collection_ids
    from public.meal_collections mc
    where mc.home_id = requested_home_id;

    select coalesce(array_agg(distinct med.calendar_event_id), array[]::uuid[])
    into v_calendar_event_ids
    from public.meal_event_details med
    where med.meal_id = any(v_meal_ids);

    meals_deleted := coalesce(array_length(v_meal_ids, 1), 0);
    meal_recipes_deleted := coalesce(array_length(v_recipe_ids, 1), 0);
    calendar_events_deleted := coalesce(array_length(v_calendar_event_ids, 1), 0);

    select count(*)::integer
    into meal_event_details_deleted
    from public.meal_event_details med
    where med.meal_id = any(v_meal_ids);

    foreach v_calendar_event_id in array v_calendar_event_ids loop
        perform public.delete_calendar_event(v_calendar_event_id);
    end loop;

    with deleted as (
        delete from public.meal_event_details med
        where med.meal_id = any(v_meal_ids)
           or med.calendar_event_id = any(v_calendar_event_ids)
        returning 1
    )
    select count(*)::integer
    into v_deleted_count
    from deleted;

    if meal_event_details_deleted = 0 then
        meal_event_details_deleted := v_deleted_count;
    end if;

    with deleted as (
        delete from public.meal_collection_items mci
        where mci.meal_id = any(v_meal_ids)
           or mci.collection_id = any(v_collection_ids)
        returning 1
    )
    select count(*)::integer into meal_collection_items_deleted from deleted;

    with deleted as (
        delete from public.meal_favorites mf
        where mf.meal_id = any(v_meal_ids)
        returning 1
    )
    select count(*)::integer into meal_favorites_deleted from deleted;

    with deleted as (
        delete from public.meal_photos mp
        where mp.home_id = requested_home_id
           or mp.meal_id = any(v_meal_ids)
        returning 1
    )
    select count(*)::integer into meal_photos_deleted from deleted;

    with deleted as (
        delete from public.recipe_ingredients ri
        where ri.recipe_id = any(v_recipe_ids)
        returning 1
    )
    select count(*)::integer into recipe_ingredients_deleted from deleted;

    with deleted as (
        delete from public.recipe_steps rs
        where rs.recipe_id = any(v_recipe_ids)
        returning 1
    )
    select count(*)::integer into recipe_steps_deleted from deleted;

    with deleted as (
        delete from public.meal_recipes mr
        where mr.id = any(v_recipe_ids)
        returning 1
    )
    select count(*)::integer into meal_recipes_deleted from deleted;

    with deleted as (
        delete from public.meal_collections mc
        where mc.id = any(v_collection_ids)
        returning 1
    )
    select count(*)::integer into meal_collections_deleted from deleted;

    with deleted as (
        delete from public.meals m
        where m.id = any(v_meal_ids)
          and m.home_id = requested_home_id
        returning 1
    )
    select count(*)::integer into meals_deleted from deleted;

    return next;
end;
$$;

revoke all on function public.clear_home_meals(uuid) from public;
revoke all on function public.clear_home_meals(uuid) from anon;

grant execute
on function public.clear_home_meals(uuid)
to authenticated;

create or replace function public.clear_home_calendar(requested_home_id uuid)
returns table(calendar_events_deleted integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id uuid := auth.uid();
    v_event_ids uuid[];
    v_event_id uuid;
begin
    if v_user_id is null then
        raise exception 'Authentication required'
            using errcode = '28000';
    end if;

    if not exists (
        select 1
        from public.home_members hm
        where hm.home_id = requested_home_id
          and hm.user_id = v_user_id
          and hm.role = 'owner'
    ) then
        raise exception 'Only the Home owner can clear calendar events.'
            using errcode = '42501';
    end if;

    select coalesce(array_agg(ce.id order by ce.starts_at, ce.created_at), array[]::uuid[])
    into v_event_ids
    from public.calendar_events ce
    where ce.home_id = requested_home_id
      and not exists (
          select 1
          from public.meal_event_details med
          where med.calendar_event_id = ce.id
      )
      and not exists (
          select 1
          from public.chore_occurrences co
          where co.calendar_event_id = ce.id
      );

    calendar_events_deleted := coalesce(array_length(v_event_ids, 1), 0);

    foreach v_event_id in array v_event_ids loop
        perform public.delete_calendar_event(v_event_id);
    end loop;

    return next;
end;
$$;

revoke all on function public.clear_home_calendar(uuid) from public;
revoke all on function public.clear_home_calendar(uuid) from anon;

grant execute
on function public.clear_home_calendar(uuid)
to authenticated;
