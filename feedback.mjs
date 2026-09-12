// The feedback endpoint behind /api/feedback. The app posts one JSON body per
// report; the worker checks its signature, stores it in R2 and pings notifi.
//
// The signature is an HMAC over the timestamp and the body's SHA-256, with a
// key the app carries and the worker holds as a secret. Anyone who pulls the
// key out of the app can sign requests, so the check is there to stop scanners
// and cheap spam, not a determined attacker. The rate limit on the route does
// the rest. Timestamps older than the window are refused, which bounds how
// long a captured request can be replayed.
//
// The report id is the SHA-256 of the body, so a retry of the same bytes lands
// on the same object and sends no second notification.

import { z } from "zod";

const encoder = new TextEncoder();

export const TIMESTAMP_WINDOW_SECONDS = 5 * 60;
export const MAX_BODY_BYTES = 3 * 1024 * 1024;
export const MAX_AUDIO_BYTES = 2 * 1024 * 1024;

export function hex(bytes) {
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function sha256Hex(bytes) {
  return hex(await crypto.subtle.digest("SHA-256", bytes));
}

export async function hmacHex(keyHex, message) {
  const raw = Uint8Array.from(keyHex.match(/.{2}/g), (h) => parseInt(h, 16));
  const key = await crypto.subtle.importKey("raw", raw, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return hex(await crypto.subtle.sign("HMAC", key, encoder.encode(message)));
}

/// Keys come as "id:hex,id:hex". Two entries at once let a release ship a new
/// key while the previous one still signs for users who have not updated.
export function parseKeys(spec) {
  const keys = new Map();
  for (const part of (spec ?? "").split(",")) {
    const [id, key] = part.trim().split(":");
    if (id && /^[0-9a-f]{64}$/.test(key ?? "")) keys.set(id, key);
  }
  return keys;
}

function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let out = 0;
  for (let i = 0; i < a.length; i++) out |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return out === 0;
}

/// Returns null when the request is signed, otherwise a reason string.
export async function verifySignature({ keyId, timestamp, signature, body, keys, now }) {
  const key = keys.get(keyId ?? "");
  if (!key) return "unknown key";
  const ts = Number(timestamp);
  if (!Number.isInteger(ts)) return "bad timestamp";
  if (Math.abs(now - ts) > TIMESTAMP_WINDOW_SECONDS) return "stale timestamp";
  if (!/^[0-9a-f]{64}$/.test(signature ?? "")) return "bad signature";
  const expected = await hmacHex(key, `${ts}.${await sha256Hex(body)}`);
  return timingSafeEqual(expected, signature) ? null : "bad signature";
}

const text = (max) => z.string().max(max);
const count = z.number().int().min(0).max(1e9);

/// The shape a report must have. Anything outside it is refused, and the
/// stored report is the parsed value, never the raw body.
export const Report = z.object({
  issue: text(4000).trim().min(1),
  previousId: text(48).optional(),
  app: z.object({
    version: text(32),
    build: text(32).optional(),
    macos: text(64).optional(),
    chip: text(96).optional(),
    appleIntelligence: text(64).optional(),
    model: text(128).optional(),
  }).strict(),
  dictation: z.object({
    id: text(48),
    at: text(40).optional(),
    transcript: text(20000),
    postProcessed: text(20000).optional(),
    postProcessRequested: z.boolean(),
    edited: text(20000).optional(),
    durationMs: count.optional(),
    transcribeMs: count.optional(),
    postProcessMs: count.optional(),
    dictionaryFixes: count.optional(),
    appId: text(256).optional(),
    appName: text(256).optional(),
    windowTitle: text(512).optional(),
  }).strict(),
  settings: z.record(z.string().regex(/^[a-zA-Z]{1,40}$/), z.union([z.boolean(), z.number(), text(64)])),
  audio: z.string().optional(),
}).strict();

/// Throws with the path and reason of the first bad field.
export function validateReport(json) {
  const result = Report.safeParse(json);
  if (result.success) return result.data;
  const issue = result.error.issues[0];
  throw new Error(`${issue.path.join(".") || "body"}: ${issue.message}`);
}

/// The audio arrives base64 inside the JSON. Only AAC in an MPEG-4 container
/// is accepted, which is what the app writes.
export function decodeAudio(b64) {
  if (b64 === undefined || b64 === null) return null;
  if (typeof b64 !== "string" || b64.length > Math.ceil(MAX_AUDIO_BYTES / 3) * 4 + 4) throw new Error("audio too large");
  let bin;
  try {
    bin = atob(b64);
  } catch {
    throw new Error("bad audio");
  }
  const bytes = Uint8Array.from(bin, (c) => c.charCodeAt(0));
  if (bytes.length > MAX_AUDIO_BYTES) throw new Error("audio too large");
  if (bytes.length < 12 || String.fromCharCode(...bytes.subarray(4, 8)) !== "ftyp") throw new Error("bad audio");
  return bytes;
}

export function reportId(date, bodyHash) {
  return `${date.toISOString().slice(0, 10).replaceAll("-", "")}-${bodyHash.slice(0, 32)}`;
}

/// Ids are "YYYYMMDD-<32 hex>", so the object prefix follows from the id and
/// nothing has to be looked up to find a report.
export function objectPrefix(id) {
  const m = /^(\d{4})(\d{2})(\d{2})-([0-9a-f]{32})$/.exec(id ?? "");
  if (!m) return null;
  return `reports/${m[1]}-${m[2]}-${m[3]}/${id}`;
}

export function notification(report, id, hasAudio, origin) {
  const target = report.dictation.appName ? ` · ${report.dictation.appName}` : "";
  const title = `${report.app.version}${target}`.slice(0, 200);
  const heard = report.dictation.transcript;
  const typed = report.dictation.edited ?? report.dictation.postProcessed ?? heard;
  const lines = [report.issue, "", "```", heard, "```"];
  if (typed !== heard) lines.push("→", "```", typed, "```");
  lines.push(hasAudio ? "audio attached" : "no audio");
  return {
    title,
    message: lines.join("\n").slice(0, 16000),
    link: `${origin}/api/feedback/${id}`,
    occurred_at: Date.parse(report.dictation.at ?? "") || Date.now(),
  };
}

export function json(body, status = 200, headers = {}) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", ...headers } });
}

export async function handleFeedback(request, env, ctx) {
  const url = new URL(request.url);
  const rest = url.pathname.slice("/api/feedback".length);

  if (rest === "" || rest === "/") {
    if (request.method !== "POST") return json({ error: "method" }, 405, { Allow: "POST" });
    return postReport(request, env, ctx, url.origin);
  }
  const m = /^\/([0-9a-f-]+)(\/audio)?$/.exec(rest);
  if (!m) return json({ error: "not found" }, 404);
  if (request.method !== "GET") return json({ error: "method" }, 405, { Allow: "GET" });
  return getReport(request, env, m[1], Boolean(m[2]));
}

async function postReport(request, env, ctx, origin) {
  const length = Number(request.headers.get("Content-Length"));
  if (!length || length > MAX_BODY_BYTES) return json({ error: "too large" }, 413);
  const body = await request.arrayBuffer();
  if (body.byteLength > MAX_BODY_BYTES) return json({ error: "too large" }, 413);

  const reason = await verifySignature({
    keyId: request.headers.get("X-Key-Id"),
    timestamp: request.headers.get("X-Timestamp"),
    signature: request.headers.get("X-Signature"),
    body,
    keys: parseKeys(env.FEEDBACK_KEYS),
    now: Math.floor(Date.now() / 1000),
  });
  if (reason) return json({ error: reason }, 401);

  let report;
  let audio;
  try {
    const { audio: encoded, ...rest } = validateReport(JSON.parse(new TextDecoder().decode(body)));
    report = rest;
    audio = decodeAudio(encoded);
  } catch (e) {
    return json({ error: e.message }, 400);
  }

  const now = new Date();
  const id = reportId(now, await sha256Hex(body));
  const prefix = objectPrefix(id);
  const existing = await env.FEEDBACK.head(`${prefix}/report.json`);
  if (existing) return json({ id }, 200);

  const stored = { id, receivedAt: now.toISOString(), hasAudio: audio !== null, ...report };
  await env.FEEDBACK.put(`${prefix}/report.json`, JSON.stringify(stored), {
    httpMetadata: { contentType: "application/json" },
  });
  if (audio) {
    await env.FEEDBACK.put(`${prefix}/audio.m4a`, audio, { httpMetadata: { contentType: "audio/mp4" } });
  }
  ctx.waitUntil(notify(env, notification(report, id, audio !== null, origin)));
  return json({ id }, 201);
}

async function notify(env, payload) {
  if (!env.NOTIFI_KEY) return;
  try {
    const res = await fetch("https://notifi.it/send", {
      method: "POST",
      headers: { Authorization: `Bearer ${env.NOTIFI_KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    if (!res.ok) console.error(`notifi answered ${res.status}`);
  } catch (e) {
    console.error(`notifi failed: ${e.message}`);
  }
}

async function getReport(request, env, id, audio) {
  const token = env.FEEDBACK_READ_TOKEN;
  const auth = request.headers.get("Authorization") ?? "";
  if (!token || !timingSafeEqual(auth, `Bearer ${token}`)) {
    return json({ error: "unauthorized" }, 401, { "WWW-Authenticate": "Bearer" });
  }
  const prefix = objectPrefix(id);
  if (!prefix) return json({ error: "not found" }, 404);
  const object = await env.FEEDBACK.get(`${prefix}/${audio ? "audio.m4a" : "report.json"}`);
  if (!object) return json({ error: "not found" }, 404);
  return new Response(object.body, {
    headers: {
      "Content-Type": audio ? "audio/mp4" : "application/json",
      "Cache-Control": "no-store",
    },
  });
}
