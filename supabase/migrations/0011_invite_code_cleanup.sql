-- Let an inviter retire their own codes. Regenerating an invite previously
-- left every prior (still unexpired) code valid and stale rows accumulating
-- forever — there was no delete policy at all, so the client's cleanup
-- delete silently affected zero rows.

create policy "invite_codes_owner_delete"
    on public.invite_codes for delete
    using (created_by = auth.uid());
