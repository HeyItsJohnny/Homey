-- Recipe URL import is now parse -> review -> commit.
-- Source mappings should not outlive their global recipe, while import history
-- can remain as audit data without reserving a URL after deletion.

delete from public.global_recipe_sources grs
where not exists (
    select 1
    from public.global_recipes gr
    where gr.id = grs.global_recipe_id
);

update public.recipe_imports ri
set global_recipe_id = null
where global_recipe_id is not null
  and not exists (
      select 1
      from public.global_recipes gr
      where gr.id = ri.global_recipe_id
  );

alter table public.recipe_imports
alter column global_recipe_id drop not null;

do $$
declare
    constraint_record record;
begin
    for constraint_record in
        select con.conname
        from pg_constraint con
        join pg_class rel
          on rel.oid = con.conrelid
        join pg_namespace nsp
          on nsp.oid = rel.relnamespace
        join unnest(con.conkey) as key(attnum)
          on true
        join pg_attribute att
          on att.attrelid = rel.oid
         and att.attnum = key.attnum
        where nsp.nspname = 'public'
          and rel.relname = 'recipe_imports'
          and con.contype = 'u'
          and att.attname in ('normalized_url', 'normalized_url_hash')
    loop
        execute format('alter table public.recipe_imports drop constraint %I', constraint_record.conname);
    end loop;
end $$;

do $$
declare
    index_record record;
begin
    for index_record in
        select idx.relname as index_name
        from pg_index i
        join pg_class tbl
          on tbl.oid = i.indrelid
        join pg_namespace nsp
          on nsp.oid = tbl.relnamespace
        join pg_class idx
          on idx.oid = i.indexrelid
        where nsp.nspname = 'public'
          and tbl.relname = 'recipe_imports'
          and i.indisunique
          and not exists (
              select 1
              from pg_constraint con
              where con.conindid = i.indexrelid
          )
          and exists (
              select 1
              from unnest(i.indkey) as key(attnum)
              join pg_attribute att
                on att.attrelid = tbl.oid
               and att.attnum = key.attnum
              where att.attname in ('normalized_url', 'normalized_url_hash')
          )
    loop
        execute format('drop index if exists public.%I', index_record.index_name);
    end loop;
end $$;

do $$
declare
    constraint_record record;
begin
    for constraint_record in
        select con.conname
        from pg_constraint con
        join pg_class rel
          on rel.oid = con.conrelid
        join pg_namespace nsp
          on nsp.oid = rel.relnamespace
        join pg_class referenced_rel
          on referenced_rel.oid = con.confrelid
        join pg_namespace referenced_nsp
          on referenced_nsp.oid = referenced_rel.relnamespace
        join unnest(con.conkey) as key(attnum)
          on true
        join pg_attribute att
          on att.attrelid = rel.oid
         and att.attnum = key.attnum
        where nsp.nspname = 'public'
          and rel.relname = 'global_recipe_sources'
          and referenced_nsp.nspname = 'public'
          and referenced_rel.relname = 'global_recipes'
          and con.contype = 'f'
          and att.attname = 'global_recipe_id'
    loop
        execute format('alter table public.global_recipe_sources drop constraint %I', constraint_record.conname);
    end loop;
end $$;

alter table public.global_recipe_sources
add constraint global_recipe_sources_global_recipe_id_fkey
foreign key (global_recipe_id)
references public.global_recipes(id)
on delete cascade;

do $$
declare
    constraint_record record;
begin
    for constraint_record in
        select con.conname
        from pg_constraint con
        join pg_class rel
          on rel.oid = con.conrelid
        join pg_namespace nsp
          on nsp.oid = rel.relnamespace
        join pg_class referenced_rel
          on referenced_rel.oid = con.confrelid
        join pg_namespace referenced_nsp
          on referenced_nsp.oid = referenced_rel.relnamespace
        join unnest(con.conkey) as key(attnum)
          on true
        join pg_attribute att
          on att.attrelid = rel.oid
         and att.attnum = key.attnum
        where nsp.nspname = 'public'
          and rel.relname = 'recipe_imports'
          and referenced_nsp.nspname = 'public'
          and referenced_rel.relname = 'global_recipes'
          and con.contype = 'f'
          and att.attname = 'global_recipe_id'
    loop
        execute format('alter table public.recipe_imports drop constraint %I', constraint_record.conname);
    end loop;
end $$;

alter table public.recipe_imports
add constraint recipe_imports_global_recipe_id_fkey
foreign key (global_recipe_id)
references public.global_recipes(id)
on delete set null;
