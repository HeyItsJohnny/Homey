create or replace function public.add_global_meal_to_home(
    requested_global_meal_id uuid,
    requested_home_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    requesting_user_id uuid := auth.uid();
    source_recipe public.global_recipes%rowtype;
    primary_source_name text;
    primary_source_domain text;
    primary_original_url text;
    primary_normalized_url text;
    existing_meal_id uuid;
    new_meal_id uuid;
    requested_meal_types public.meal_type[];
    requested_servings numeric;
    parsed_servings_text text;
    requested_ingredients jsonb;
    requested_steps jsonb;
begin
    if requesting_user_id is null then
        raise exception 'Authentication required'
            using errcode = '28000';
    end if;

    if not exists (
        select 1
        from public.home_members hm
        where hm.home_id = requested_home_id
          and hm.user_id = requesting_user_id
          and hm.role in ('owner', 'admin', 'member')
    ) then
        raise exception 'You do not have access to this Home.'
            using errcode = '42501';
    end if;

    select gr.*
    into source_recipe
    from public.global_recipes gr
    where gr.id = requested_global_meal_id
      and gr.status = 'active';

    if not found then
        raise exception 'Global recipe not found'
            using errcode = 'P0002';
    end if;

    select m.id
    into existing_meal_id
    from public.meals m
    where m.home_id = requested_home_id
      and m.origin_global_recipe_id = requested_global_meal_id
    limit 1;

    if existing_meal_id is not null then
        return existing_meal_id;
    end if;

    select
        grs.source_name,
        grs.source_domain,
        grs.original_url,
        grs.normalized_url
    into
        primary_source_name,
        primary_source_domain,
        primary_original_url,
        primary_normalized_url
    from public.global_recipe_sources grs
    where grs.global_recipe_id = requested_global_meal_id
    order by coalesce(grs.is_primary, false) desc
    limit 1;

    select coalesce(
        array_agg(normalized_meal_type::public.meal_type order by meal_type_ordinality),
        '{}'::public.meal_type[]
    )
    into requested_meal_types
    from (
        select lower(btrim(meal_type_text)) as normalized_meal_type, meal_type_ordinality
        from unnest(coalesce(source_recipe.meal_types, '{}'::text[]))
            with ordinality as meal_type_items(meal_type_text, meal_type_ordinality)
    ) normalized_meal_types
    where normalized_meal_type in ('breakfast', 'lunch', 'dinner', 'snack', 'dessert', 'drink');

    parsed_servings_text := substring(source_recipe.servings from '([0-9]+(\.[0-9]+)?)');
    if parsed_servings_text is not null then
        requested_servings := parsed_servings_text::numeric;
    else
        requested_servings := null;
    end if;

    with normalized_ingredients as (
        select
            ingredient,
            case
                when nullif(btrim(ingredient ->> 'sort_order'), '') ~ '^-?[0-9]+$'
                    then (btrim(ingredient ->> 'sort_order'))::integer
                else ingredient_ordinality::integer
            end as sort_order,
            row_number() over (
                order by
                    case
                        when nullif(btrim(ingredient ->> 'sort_order'), '') ~ '^-?[0-9]+$'
                            then (btrim(ingredient ->> 'sort_order'))::integer
                        else ingredient_ordinality::integer
                    end,
                    ingredient_ordinality
            ) as normalized_order
        from jsonb_array_elements(coalesce(source_recipe.ingredients, '[]'::jsonb))
            with ordinality as ingredient_items(ingredient, ingredient_ordinality)
    )
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'section_name', nullif(btrim(ingredient ->> 'section_name'), ''),
                'ingredient_name', coalesce(nullif(btrim(ingredient ->> 'ingredient_name'), ''), 'Ingredient'),
                'quantity',
                    case
                        when nullif(btrim(ingredient ->> 'quantity'), '') ~ '^[0-9]+(\.[0-9]+)?$'
                            then to_jsonb((btrim(ingredient ->> 'quantity'))::numeric)
                        else 'null'::jsonb
                    end,
                'unit', null,
                'preparation', null,
                'notes', null,
                'sort_order', sort_order,
                'is_optional', (ingredient ->> 'is_optional') = 'true'
            )
            order by normalized_order
        ),
        '[]'::jsonb
    )
    into requested_ingredients
    from normalized_ingredients;

    with normalized_steps as (
        select
            step_item,
            case
                when nullif(btrim(step_item ->> 'sort_order'), '') ~ '^-?[0-9]+$'
                    then (btrim(step_item ->> 'sort_order'))::integer + 1
                else step_ordinality::integer
            end as step_number
        from jsonb_array_elements(coalesce(source_recipe.steps, '[]'::jsonb))
            with ordinality as step_items(step_item, step_ordinality)
    )
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'step_number', step_number,
                'instruction', coalesce(nullif(btrim(step_item ->> 'step_text'), ''), 'Step'),
                'timer_minutes', null,
                'photo_path', null
            )
            order by step_number
        ),
        '[]'::jsonb
    )
    into requested_steps
    from normalized_steps;

    select public.save_meal_recipe(
        requested_home_id := requested_home_id,
        requested_meal_id := null::uuid,
        requested_name := source_recipe.title,
        requested_description := source_recipe.description,
        requested_meal_types := requested_meal_types,
        requested_cuisine := source_recipe.cuisine,
        requested_difficulty := null::public.meal_difficulty,
        requested_prep_time_minutes := source_recipe.prep_time_minutes,
        requested_cook_time_minutes := source_recipe.cook_time_minutes,
        requested_servings := requested_servings,
        requested_primary_photo_path := null::text,
        requested_source_name := coalesce(
            nullif(primary_source_name, ''),
            nullif(primary_source_domain, ''),
            nullif(source_recipe.source_type, '')
        ),
        requested_source_url := coalesce(
            nullif(primary_normalized_url, ''),
            nullif(primary_original_url, '')
        ),
        requested_notes := null::text,
        requested_tags := source_recipe.keywords,
        requested_is_draft := false,
        requested_ingredients := requested_ingredients,
        requested_steps := requested_steps
    )
    into new_meal_id;

    update public.meals
    set
        origin_global_recipe_id = source_recipe.id,
        source_type = source_recipe.source_type,
        updated_at = now()
    where id = new_meal_id
      and home_id = requested_home_id;

    update public.global_recipes
    set
        save_count = save_count + 1,
        updated_at = now()
    where id = source_recipe.id;

    return new_meal_id;
end;
$$;

revoke all on function public.add_global_meal_to_home(uuid, uuid) from public;
revoke all on function public.add_global_meal_to_home(uuid, uuid) from anon;

grant execute
on function public.add_global_meal_to_home(uuid, uuid)
to authenticated;
