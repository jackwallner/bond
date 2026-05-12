-- Atomic per-user, per-day AI usage increment.
-- Returns true if the call is under cap and the counter was incremented;
-- false if the user has already hit the cap for today.

create or replace function public.increment_ai_usage(
    p_user uuid,
    p_column text,
    p_cap integer
)
returns boolean
language plpgsql
security definer set search_path = public
as $$
declare
    v_count integer;
begin
    if p_column not in ('rewrites', 'suggests') then
        raise exception 'invalid column: %', p_column;
    end if;

    insert into public.ai_usage (user_id, day)
    values (p_user, current_date)
    on conflict (user_id, day) do nothing;

    if p_column = 'rewrites' then
        update public.ai_usage
        set rewrites = rewrites + 1
        where user_id = p_user and day = current_date and rewrites < p_cap
        returning rewrites into v_count;
    else
        update public.ai_usage
        set suggests = suggests + 1
        where user_id = p_user and day = current_date and suggests < p_cap
        returning suggests into v_count;
    end if;

    return v_count is not null;
end;
$$;

grant execute on function public.increment_ai_usage(uuid, text, integer) to service_role;
