// Claude API proxy — wired up in Phase 5.
//
// Routes:
//   POST /rewrite   { language, note }  -> rewritten reminder text (Haiku)
//   POST /suggest   { coupleId }        -> 5 suggested reminders (Sonnet)
//   POST /digest    { coupleId }        -> monthly recap (Sonnet)
//
// Uses Anthropic prompt caching on the system prompt + per-couple history.
// Rate-limits via the `ai_usage` table.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

serve(async (_req) => {
  return new Response(
    JSON.stringify({ ok: false, error: "not_implemented" }),
    { status: 501, headers: { "content-type": "application/json" } },
  );
});
