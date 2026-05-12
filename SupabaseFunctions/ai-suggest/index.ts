// Claude proxy for Bond — handles AI rewrites, weekly suggestions, monthly digest.
//
// Routes (selected by `action` field in the JSON body):
//   { action: "rewrite", language: "words"|"acts"|"gifts"|"time"|"touch", note: string }
//     → { text: string }
//   { action: "suggest", coupleId: string }
//     → { suggestions: { title: string; love_language: string; rationale: string }[] }
//   { action: "digest", coupleId: string }
//     → { digest: string }
//
// Auth: requires the caller's Supabase JWT (sent automatically by supabase-swift's
// functions.invoke). We use it to derive auth.uid() for rate-limiting.
//
// Secrets:
//   ANTHROPIC_API_KEY              – required
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_ANON_KEY – auto-provided

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ANTHROPIC_API_KEY = mustEnv("ANTHROPIC_API_KEY");
const SUPABASE_URL = mustEnv("SUPABASE_URL");
const SERVICE_KEY = mustEnv("SUPABASE_SERVICE_ROLE_KEY");
const ANON_KEY = mustEnv("SUPABASE_ANON_KEY");

const HAIKU = "claude-haiku-4-5-20251001";
const SONNET = "claude-sonnet-4-6";

// Daily caps to stop runaway bills.
const DAILY_REWRITES = 50;
const DAILY_SUGGESTS = 10;

interface ReminderRow {
  title: string;
  body: string | null;
  love_language: string;
  trigger_type: string;
  created_at: string;
  target_id: string;
}

interface RewriteBody {
  action: "rewrite";
  language: string;
  note: string;
}
interface SuggestBody {
  action: "suggest";
  coupleId: string;
}
interface DigestBody {
  action: "digest";
  coupleId: string;
}
type RequestBody = RewriteBody | SuggestBody | DigestBody;

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("method not allowed", { status: 405 });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData?.user) {
    return jsonErr("unauthorized", 401);
  }
  const userId = userData.user.id;

  const body = (await req.json()) as RequestBody;

  switch (body.action) {
    case "rewrite":
      return await handleRewrite(body, userId);
    case "suggest":
      return await handleSuggest(body, userId, userClient);
    case "digest":
      return await handleDigest(body, userId, userClient);
    default:
      return jsonErr("unknown action", 400);
  }
});

// ---------- handlers ----------

async function handleRewrite(body: RewriteBody, userId: string) {
  const note = body.note?.trim();
  if (!note) return jsonErr("note is required", 400);
  if (!(await checkAndIncrementUsage(userId, "rewrites", DAILY_REWRITES))) {
    return jsonErr("daily limit reached", 429);
  }

  const language = describeLanguage(body.language);
  const system = [
    "You are Bond, a relationship co-pilot. Rewrite the user's rough reminder note",
    "into a warm, specific, ≤140-character message they can leave for themselves",
    "or their partner. Keep their voice — don't be saccharine. No emojis.",
  ].join(" ");

  const payload = {
    model: HAIKU,
    max_tokens: 200,
    system: [{ type: "text", text: system, cache_control: { type: "ephemeral" } }],
    messages: [
      {
        role: "user",
        content: `Love language: ${language}\n\nRough note:\n${note}\n\nRewrite:`,
      },
    ],
  };
  const result = await callClaude(payload);
  return jsonOK({ text: result });
}

async function handleSuggest(
  body: SuggestBody,
  userId: string,
  client: ReturnType<typeof createClient>,
) {
  if (!(await checkAndIncrementUsage(userId, "suggests", DAILY_SUGGESTS))) {
    return jsonErr("daily limit reached", 429);
  }
  const history = await loadHistory(client, body.coupleId);
  const counts = countByLanguage(history);

  const system = [
    "You are Bond, a relationship co-pilot. Given a couple's recent reminder",
    "history grouped by the five love languages (words, acts, gifts, time, touch),",
    "propose five new reminders that gently rebalance toward neglected languages.",
    "Each reminder must be concrete, ≤120 characters, and feel like something the",
    "user would actually write to their partner. Respond with strict JSON, no prose.",
    "",
    "Output schema:",
    `{"suggestions": [{"title": string, "love_language": "words"|"acts"|"gifts"|"time"|"touch", "rationale": string}]}`,
  ].join("\n");

  const historyBlock = history
    .slice(0, 30)
    .map(
      (r) =>
        `- [${r.love_language}] ${r.title}${r.body ? ` — ${r.body}` : ""}`,
    )
    .join("\n");
  const countBlock = Object.entries(counts)
    .map(([k, v]) => `${k}: ${v}`)
    .join(", ");

  const payload = {
    model: SONNET,
    max_tokens: 800,
    system: [{ type: "text", text: system, cache_control: { type: "ephemeral" } }],
    messages: [
      {
        role: "user",
        content: `Counts (last 30 days): ${countBlock}\n\nRecent reminders:\n${
          historyBlock || "(none)"
        }`,
      },
    ],
  };
  const raw = await callClaude(payload);
  try {
    const parsed = JSON.parse(stripCodeFence(raw));
    return jsonOK({ suggestions: parsed.suggestions ?? [] });
  } catch {
    return jsonErr("invalid model output", 502);
  }
}

async function handleDigest(
  body: DigestBody,
  userId: string,
  client: ReturnType<typeof createClient>,
) {
  if (!(await checkAndIncrementUsage(userId, "suggests", DAILY_SUGGESTS))) {
    return jsonErr("daily limit reached", 429);
  }
  const history = await loadHistory(client, body.coupleId);
  const counts = countByLanguage(history);

  const system = [
    "You are Bond, a relationship co-pilot. Write a warm 2-paragraph monthly",
    "digest reflecting on the couple's recent reminders: what they're leaning",
    "into, what's been quiet, and one small specific suggestion. Plain text.",
  ].join(" ");

  const payload = {
    model: SONNET,
    max_tokens: 500,
    system: [{ type: "text", text: system, cache_control: { type: "ephemeral" } }],
    messages: [
      {
        role: "user",
        content: `Per-language counts: ${JSON.stringify(counts)}\nRecent titles: ${
          history
            .slice(0, 20)
            .map((r) => `${r.love_language}:${r.title}`)
            .join(" | ")
        }`,
      },
    ],
  };
  const text = await callClaude(payload);
  return jsonOK({ digest: text });
}

// ---------- helpers ----------

async function callClaude(payload: unknown): Promise<string> {
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`anthropic ${res.status}: ${text}`);
  }
  const data = await res.json();
  const block = data?.content?.[0]?.text;
  if (typeof block !== "string") throw new Error("no text in response");
  return block.trim();
}

async function loadHistory(
  client: ReturnType<typeof createClient>,
  coupleId: string,
): Promise<ReminderRow[]> {
  const since = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
  const { data, error } = await client
    .from("reminders")
    .select("title,body,love_language,trigger_type,created_at,target_id")
    .eq("couple_id", coupleId)
    .gte("created_at", since)
    .order("created_at", { ascending: false })
    .limit(100);
  if (error) throw new Error(error.message);
  return (data ?? []) as ReminderRow[];
}

function countByLanguage(rows: ReminderRow[]): Record<string, number> {
  const counts: Record<string, number> = {
    words: 0, acts: 0, gifts: 0, time: 0, touch: 0,
  };
  for (const r of rows) {
    if (counts[r.love_language] !== undefined) counts[r.love_language]++;
  }
  return counts;
}

function describeLanguage(raw: string): string {
  switch (raw) {
    case "words":  return "Words of Affirmation";
    case "acts":   return "Acts of Service";
    case "gifts":  return "Receiving Gifts";
    case "time":   return "Quality Time";
    case "touch":  return "Physical Touch";
    default:       return raw;
  }
}

function stripCodeFence(raw: string): string {
  const fenced = raw.match(/```(?:json)?\s*([\s\S]*?)```/);
  return (fenced ? fenced[1] : raw).trim();
}

async function checkAndIncrementUsage(
  userId: string,
  column: "rewrites" | "suggests",
  cap: number,
): Promise<boolean> {
  const admin = createClient(SUPABASE_URL, SERVICE_KEY);
  const { data, error } = await admin.rpc("increment_ai_usage", {
    p_user: userId,
    p_column: column,
    p_cap: cap,
  });
  if (error) {
    console.error("usage rpc failed:", error.message);
    return false;
  }
  return data === true;
}

function mustEnv(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`missing env: ${name}`);
  return v;
}

function jsonOK(body: object) {
  return new Response(JSON.stringify({ ok: true, ...body }), {
    headers: { "content-type": "application/json" },
  });
}

function jsonErr(message: string, status: number) {
  return new Response(JSON.stringify({ ok: false, error: message }), {
    status,
    headers: { "content-type": "application/json" },
  });
}
