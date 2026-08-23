-- Copy/paste into Supabase SQL Editor after confirming these function signatures
-- match the active database. Do not remove the unique earned-points index.

create or replace function public.start_chore(
    requested_occurrence_id uuid
)
returns public.chore_occurrences
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_actor_id uuid := auth.uid();
    v_occurrence public.chore_occurrences;
    v_assignee public.chore_occurrence_assignees;
begin
    if v_actor_id is null then
        raise exception 'Authentication required';
    end if;

    select *
    into v_occurrence
    from public.chore_occurrences
    where id = requested_occurrence_id
    for update;

    if not found then
        raise exception 'Chore occurrence not found';
    end if;

    if v_occurrence.status in ('completed', 'skipped', 'cancelled') then
        raise exception 'This chore is no longer active';
    end if;

    if v_occurrence.assignment_mode = 'open' then
        if v_occurrence.claimed_by is distinct from v_actor_id then
            raise exception 'You must claim this chore before starting it';
        end if;
    else
        select *
        into v_assignee
        from public.chore_occurrence_assignees
        where occurrence_id = requested_occurrence_id
          and user_id = v_actor_id
        for update;

        if not found then
            raise exception 'You are not assigned to this chore';
        end if;

        if v_assignee.status = 'completed' then
            raise exception 'You have already completed this chore';
        end if;

        if v_assignee.status = 'awaiting_approval' then
            raise exception 'This chore is already awaiting approval';
        end if;

        if v_assignee.status not in ('assigned', 'needs_redo') then
            raise exception 'This chore cannot be started from its current state';
        end if;

        update public.chore_occurrence_assignees
        set status = 'in_progress',
            started_at = coalesce(started_at, now())
        where occurrence_id = requested_occurrence_id
          and user_id = v_actor_id;
    end if;

    update public.chore_occurrences
    set status = 'in_progress',
        updated_at = now()
    where id = requested_occurrence_id
      and status in ('not_started', 'needs_redo')
    returning *
    into v_occurrence;

    if v_occurrence.id is null then
        select *
        into v_occurrence
        from public.chore_occurrences
        where id = requested_occurrence_id;
    end if;

    return v_occurrence;
end;
$$;

create or replace function public.submit_chore(
    requested_occurrence_id uuid,
    requested_completion_note text default null,
    requested_photo_path text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_actor_id uuid := auth.uid();
    v_occurrence public.chore_occurrences;
    v_assignee public.chore_occurrence_assignees;
    v_submission_id uuid;
begin
    if v_actor_id is null then
        raise exception 'Authentication required';
    end if;

    perform pg_advisory_xact_lock(
        ('x' || substr(md5(requested_occurrence_id::text || ':' || v_actor_id::text), 1, 16))::bit(64)::bigint
    );

    select *
    into v_occurrence
    from public.chore_occurrences
    where id = requested_occurrence_id
    for update;

    if not found then
        raise exception 'Chore occurrence not found';
    end if;

    if v_occurrence.status in ('completed', 'skipped', 'cancelled') then
        raise exception 'This chore is no longer active';
    end if;

    if v_occurrence.assignment_mode = 'open' then
        if v_occurrence.claimed_by is distinct from v_actor_id then
            raise exception 'You must claim this chore before submitting it';
        end if;
    else
        select *
        into v_assignee
        from public.chore_occurrence_assignees
        where occurrence_id = requested_occurrence_id
          and user_id = v_actor_id
        for update;

        if not found then
            raise exception 'You are not assigned to this chore';
        end if;

        if v_assignee.status = 'completed' then
            raise exception 'You have already completed this chore';
        end if;

        if v_assignee.status = 'awaiting_approval' then
            raise exception 'This chore is already awaiting approval';
        end if;

        if v_assignee.status <> 'in_progress' then
            raise exception 'Start this chore before submitting it';
        end if;
    end if;

    if exists (
        select 1
        from public.chore_submissions cs
        where cs.occurrence_id = requested_occurrence_id
          and cs.submitted_by = v_actor_id
          and cs.status = 'pending'
    ) then
        raise exception 'This chore is already awaiting approval';
    end if;

    if v_occurrence.requires_approval_snapshot then
        insert into public.chore_submissions (
            occurrence_id,
            submitted_by,
            note,
            photo_path,
            status,
            submitted_at
        )
        values (
            requested_occurrence_id,
            v_actor_id,
            nullif(btrim(requested_completion_note), ''),
            nullif(btrim(requested_photo_path), ''),
            'pending',
            now()
        )
        returning id
        into v_submission_id;

        if v_occurrence.assignment_mode <> 'open' then
            update public.chore_occurrence_assignees
            set status = 'awaiting_approval',
                submitted_at = now()
            where occurrence_id = requested_occurrence_id
              and user_id = v_actor_id;
        end if;

        update public.chore_occurrences
        set status = case
                when status in ('not_started', 'in_progress', 'needs_redo') then 'awaiting_approval'
                else status
            end,
            updated_at = now()
        where id = requested_occurrence_id;

        return v_submission_id;
    end if;

    if v_occurrence.assignment_mode <> 'open' then
        update public.chore_occurrence_assignees
        set status = 'completed',
            completed_at = now()
        where occurrence_id = requested_occurrence_id
          and user_id = v_actor_id;
    end if;

    insert into public.chore_point_transactions (
        home_id,
        user_id,
        transaction_type,
        points,
        description,
        occurrence_id,
        created_by,
        created_at
    )
    select
        v_occurrence.home_id,
        v_actor_id,
        'chore_earned'::public.chore_point_transaction_type,
        greatest(v_occurrence.points_value_snapshot, 0),
        v_occurrence.title_snapshot || ' completed',
        requested_occurrence_id,
        v_actor_id,
        now()
    where greatest(v_occurrence.points_value_snapshot, 0) > 0
      and not exists (
          select 1
          from public.chore_point_transactions cpt
          where cpt.occurrence_id = requested_occurrence_id
            and cpt.user_id = v_actor_id
            and cpt.transaction_type = 'chore_earned'::public.chore_point_transaction_type
      );

    if v_occurrence.assignment_mode = 'open'
       or v_occurrence.completion_mode = 'any_assignee'
       or not exists (
           select 1
           from public.chore_occurrence_assignees coa
           where coa.occurrence_id = requested_occurrence_id
             and coa.status <> 'completed'
       ) then
        update public.chore_occurrences
        set status = 'completed',
            completed_at = coalesce(completed_at, now()),
            updated_at = now()
        where id = requested_occurrence_id;
    else
        update public.chore_occurrences
        set status = 'in_progress',
            updated_at = now()
        where id = requested_occurrence_id;
    end if;

    return requested_occurrence_id;
end;
$$;

create or replace function public.review_chore_submission(
    requested_submission_id uuid,
    requested_decision text,
    requested_admin_note text default null,
    requested_points_awarded integer default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_actor_id uuid := auth.uid();
    v_submission public.chore_submissions;
    v_occurrence public.chore_occurrences;
    v_assignee public.chore_occurrence_assignees;
    v_points integer;
begin
    if v_actor_id is null then
        raise exception 'Authentication required';
    end if;

    if requested_decision not in ('approved', 'needs_redo') then
        raise exception 'Invalid review decision';
    end if;

    select *
    into v_submission
    from public.chore_submissions
    where id = requested_submission_id
    for update;

    if not found then
        raise exception 'Submission not found';
    end if;

    if v_submission.status <> 'pending' or v_submission.reviewed_at is not null then
        raise exception 'This submission has already been reviewed';
    end if;

    select *
    into v_occurrence
    from public.chore_occurrences
    where id = v_submission.occurrence_id
    for update;

    if not found then
        raise exception 'Chore occurrence not found';
    end if;

    if not exists (
        select 1
        from public.home_members hm
        where hm.home_id = v_occurrence.home_id
          and hm.user_id = v_actor_id
          and hm.role in ('owner', 'admin')
    ) then
        raise exception 'Only Home owners and admins can approve chores';
    end if;

    select *
    into v_assignee
    from public.chore_occurrence_assignees
    where occurrence_id = v_occurrence.id
      and user_id = v_submission.submitted_by
    for update;

    if v_occurrence.assignment_mode <> 'open' then
        if not found then
            raise exception 'Submission member is not assigned to this chore';
        end if;

        if v_assignee.status = 'completed' then
            raise exception 'This member has already completed this chore';
        end if;

        if v_assignee.status <> 'awaiting_approval' then
            raise exception 'This member is not awaiting approval for this chore';
        end if;
    end if;

    insert into public.chore_approvals (
        submission_id,
        occurrence_id,
        decision,
        admin_note,
        points_awarded,
        reviewed_by,
        reviewed_at
    )
    values (
        v_submission.id,
        v_occurrence.id,
        requested_decision::public.chore_approval_decision,
        nullif(btrim(requested_admin_note), ''),
        case when requested_decision = 'approved' then requested_points_awarded else null end,
        v_actor_id,
        now()
    );

    update public.chore_submissions
    set status = requested_decision::public.chore_submission_status,
        reviewed_at = now(),
        reviewed_by = v_actor_id
    where id = v_submission.id;

    if requested_decision = 'needs_redo' then
        update public.chore_occurrence_assignees
        set status = 'needs_redo'
        where occurrence_id = v_occurrence.id
          and user_id = v_submission.submitted_by;

        update public.chore_occurrences
        set status = 'needs_redo',
            updated_at = now()
        where id = v_occurrence.id
          and not exists (
              select 1
              from public.chore_occurrence_assignees coa
              where coa.occurrence_id = v_occurrence.id
                and coa.status = 'awaiting_approval'
          );

        return;
    end if;

    update public.chore_occurrence_assignees
    set status = 'completed',
        completed_at = now()
    where occurrence_id = v_occurrence.id
      and user_id = v_submission.submitted_by;

    v_points := greatest(coalesce(requested_points_awarded, v_occurrence.points_value_snapshot, 0), 0);

    insert into public.chore_point_transactions (
        home_id,
        user_id,
        transaction_type,
        points,
        description,
        occurrence_id,
        submission_id,
        created_by,
        created_at
    )
    select
        v_occurrence.home_id,
        v_submission.submitted_by,
        'chore_earned'::public.chore_point_transaction_type,
        v_points,
        v_occurrence.title_snapshot || ' approved',
        v_occurrence.id,
        v_submission.id,
        v_actor_id,
        now()
    where v_points > 0
      and not exists (
          select 1
          from public.chore_point_transactions cpt
          where cpt.occurrence_id = v_occurrence.id
            and cpt.user_id = v_submission.submitted_by
            and cpt.transaction_type = 'chore_earned'::public.chore_point_transaction_type
      );

    if v_occurrence.assignment_mode = 'open'
       or v_occurrence.completion_mode = 'any_assignee'
       or not exists (
           select 1
           from public.chore_occurrence_assignees coa
           where coa.occurrence_id = v_occurrence.id
             and coa.status <> 'completed'
       ) then
        update public.chore_occurrences
        set status = 'completed',
            completed_at = coalesce(completed_at, now()),
            approved_at = coalesce(approved_at, now()),
            updated_at = now()
        where id = v_occurrence.id;
    else
        update public.chore_occurrences
        set status = case
                when exists (
                    select 1
                    from public.chore_occurrence_assignees coa
                    where coa.occurrence_id = v_occurrence.id
                      and coa.status = 'awaiting_approval'
                ) then 'awaiting_approval'
                else 'in_progress'
            end,
            updated_at = now()
        where id = v_occurrence.id;
    end if;
end;
$$;

revoke all on function public.start_chore(uuid) from public;
grant execute on function public.start_chore(uuid) to authenticated;

revoke all on function public.submit_chore(uuid, text, text) from public;
grant execute on function public.submit_chore(uuid, text, text) to authenticated;

revoke all on function public.review_chore_submission(uuid, text, text, integer) from public;
grant execute on function public.review_chore_submission(uuid, text, text, integer) to authenticated;
