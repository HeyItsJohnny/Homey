create or replace function public.save_global_recipe(
    requested_title text,
    requested_description text,
    requested_image_url text,
    requested_prep_time_minutes integer,
    requested_cook_time_minutes integer,
    requested_total_time_minutes integer,
    requested_servings text,
    requested_cuisine text,
    requested_meal_types text[],
    requested_keywords text[],
    requested_ingredients jsonb,
    requested_steps jsonb,
    requested_source_type text,
    requested_source_name text,
    requested_source_url text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    requesting_user_id uuid := auth.uid();
    new_global_recipe_id uuid;
    normalized_meal_types text[];
    normalized_keywords text[];
    normalized_ingredients jsonb;
    normalized_steps jsonb;
    normalized_source_type text;
    normalized_source_url text;
    source_domain text;
begin
    if requesting_user_id is null then
        raise exception 'Authentication required'
            using errcode = '28000';
    end if;

    if nullif(btrim(requested_title), '') is null then
        raise exception 'Recipe title is required'
            using errcode = '22023';
    end if;

    select coalesce(
        array_agg(distinct normalized_meal_type order by normalized_meal_type),
        '{}'::text[]
    )
    into normalized_meal_types
    from (
        select lower(btrim(meal_type_text)) as normalized_meal_type
        from unnest(coalesce(requested_meal_types, '{}'::text[])) as meal_type_items(meal_type_text)
    ) meal_types
    where normalized_meal_type in ('breakfast', 'lunch', 'dinner', 'snack', 'dessert', 'drink');

    select coalesce(
        array_agg(distinct normalized_keyword order by normalized_keyword),
        '{}'::text[]
    )
    into normalized_keywords
    from (
        select btrim(keyword_text) as normalized_keyword
        from unnest(coalesce(requested_keywords, '{}'::text[])) as keyword_items(keyword_text)
    ) keywords
    where normalized_keyword <> '';

    with ingredient_rows as (
        select
            ingredient,
            ingredient_ordinality
        from jsonb_array_elements(coalesce(requested_ingredients, '[]'::jsonb))
            with ordinality as ingredient_items(ingredient, ingredient_ordinality)
    )
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'quantity', nullif(btrim(ingredient ->> 'quantity'), ''),
                'sort_order', ingredient_ordinality::integer - 1,
                'is_optional', coalesce((ingredient ->> 'is_optional')::boolean, false),
                'section_name', nullif(btrim(ingredient ->> 'section_name'), ''),
                'ingredient_name', nullif(btrim(ingredient ->> 'ingredient_name'), '')
            )
            order by ingredient_ordinality
        ),
        '[]'::jsonb
    )
    into normalized_ingredients
    from ingredient_rows
    where nullif(btrim(ingredient ->> 'ingredient_name'), '') is not null;

    with step_rows as (
        select
            step_item,
            step_ordinality
        from jsonb_array_elements(coalesce(requested_steps, '[]'::jsonb))
            with ordinality as step_items(step_item, step_ordinality)
    )
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'step_text', nullif(btrim(step_item ->> 'step_text'), ''),
                'sort_order', step_ordinality::integer - 1,
                'section_name', nullif(btrim(step_item ->> 'section_name'), '')
            )
            order by step_ordinality
        ),
        '[]'::jsonb
    )
    into normalized_steps
    from step_rows
    where nullif(btrim(step_item ->> 'step_text'), '') is not null;

    normalized_source_type := coalesce(nullif(btrim(requested_source_type), ''), 'manual');

    insert into public.global_recipes (
        title,
        description,
        image_url,
        prep_time_minutes,
        cook_time_minutes,
        total_time_minutes,
        servings,
        cuisine,
        meal_types,
        keywords,
        ingredients,
        steps,
        nutrition,
        source_type,
        status,
        save_count,
        created_at,
        updated_at,
        last_verified_at
    )
    values (
        btrim(requested_title),
        nullif(btrim(requested_description), ''),
        nullif(btrim(requested_image_url), ''),
        requested_prep_time_minutes,
        requested_cook_time_minutes,
        coalesce(
            requested_total_time_minutes,
            nullif(coalesce(requested_prep_time_minutes, 0) + coalesce(requested_cook_time_minutes, 0), 0)
        ),
        nullif(btrim(requested_servings), ''),
        nullif(btrim(requested_cuisine), ''),
        normalized_meal_types,
        normalized_keywords,
        normalized_ingredients,
        normalized_steps,
        null::jsonb,
        normalized_source_type,
        'active',
        0,
        now(),
        now(),
        now()
    )
    returning id into new_global_recipe_id;

    normalized_source_url := nullif(btrim(requested_source_url), '');
    if normalized_source_url is not null then
        source_domain := lower(regexp_replace(normalized_source_url, '^https?://([^/?#]+).*$'::text, '\1'::text));

        insert into public.global_recipe_sources (
            global_recipe_id,
            original_url,
            normalized_url,
            normalized_url_hash,
            source_domain,
            source_name,
            source_recipe_id,
            is_primary,
            last_verified_at
        )
        values (
            new_global_recipe_id,
            normalized_source_url,
            normalized_source_url,
            md5(lower(normalized_source_url)),
            nullif(source_domain, normalized_source_url),
            nullif(btrim(requested_source_name), ''),
            null,
            true,
            now()
        );
    end if;

    return new_global_recipe_id;
end;
$$;

revoke all on function public.save_global_recipe(
    text,
    text,
    text,
    integer,
    integer,
    integer,
    text,
    text,
    text[],
    text[],
    jsonb,
    jsonb,
    text,
    text,
    text
) from public;

revoke all on function public.save_global_recipe(
    text,
    text,
    text,
    integer,
    integer,
    integer,
    text,
    text,
    text[],
    text[],
    jsonb,
    jsonb,
    text,
    text,
    text
) from anon;

grant execute
on function public.save_global_recipe(
    text,
    text,
    text,
    integer,
    integer,
    integer,
    text,
    text,
    text[],
    text[],
    jsonb,
    jsonb,
    text,
    text,
    text
)
to authenticated;
