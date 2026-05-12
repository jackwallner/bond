# ai-suggest

Claude proxy for rewrites, suggestions, and digests.

## Deploy

```sh
supabase functions deploy ai-suggest --project-ref rmtkpokdsyfvrisfygta
```

## Secrets

```sh
supabase secrets set \
  ANTHROPIC_API_KEY="sk-ant-..." \
  --project-ref rmtkpokdsyfvrisfygta
```

`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, and `SUPABASE_ANON_KEY` are auto-injected by the Supabase platform — don't set them manually.

## Models + caps

| Action   | Model                        | Daily cap per user |
|----------|------------------------------|--------------------|
| rewrite  | `claude-haiku-4-5-20251001`  | 50                 |
| suggest  | `claude-sonnet-4-6`          | 10                 |
| digest   | `claude-sonnet-4-6`          | 10 (shares suggest bucket) |

Prompt caching is on the system prompt (`cache_control: ephemeral`). With repeat calls inside the 5-minute TTL, the system prompt is read from cache.

## Migration

`supabase/migrations/0002_ai_usage_rpc.sql` defines `public.increment_ai_usage(p_user, p_column, p_cap)` which atomically increments today's counter and returns `true` if under cap, `false` if over.
