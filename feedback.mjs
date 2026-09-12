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

const encoder = new TextEncoder();

export const TIMESTAMP_WINDOW_SECONDS = 5 * 60;
export const MAX_BODY_BYTES = 3 * 1024 * 1024;
export const MAX_AUDIO_BYTES = 2 * 1024 * 1024;

const LIMITS = {
  issue: 4000,
  transcript: 20000,
  text: 20000,
  version: 32,
  build: 32,
  macos: 64,
  chip: 96,
  app: 256,
  window: 512,
};

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

function str(value, max, required = false) {
  if (value === undefined || value === null) {
    if (required) throw new Error("missing field");
    return undefined;
  }
  if (typeof value !== "string" || value.length > max) throw new Error("bad field");
  return value;
}

function int(value) {
  if (value === undefined || value === null) return undefined;
  if (!Number.isInteger(value) || value < 0 || value > 1e9) throw new Error("bad field");
  return value;
}

function bool(value) {
  if (typeof value !== "boolean") throw new Error("bad field");
  return value;
}

/// Picks the fields the endpoint knows out of the parsed body, throwing on
/// anything outside its shape. The stored report is this, never the raw body.
export function validateReport(json) {
  if (typeof json !== "object" || json === null || Array.isArray(json)) throw new Error("bad body");
  const settings = json.settings;
  if (typeof settings !== "object" || settings === null || Array.isArray(settings)) throw new Error("bad settings");
  for (const [k, v] of Object.entries(settings)) {
    if (!/^[a-zA-Z]{1,40}$/.test(k)) throw new Error("bad settings");
    if (!["boolean", "number", "string"].includes(typeof v) || String(v).length > 64) throw new Error("bad settings");
  }
  const d = json.dictation;
  if (typeof d !== "object" || d === null) throw new Error("bad dictation");
  const out = {
    issue: str(json.issue, LIMITS.issue, true).trim(),
    previousId: str(json.previousId, 48),
    app: {
      version: str(json.app?.version, LIMITS.version, true),
      build: str(json.app?.build, LIMITS.build),
      macos: str(json.app?.macos, LIMITS.macos),
      chip: str(json.app?.chip, LIMITS.chip),
      appleIntelligence: str(json.app?.appleIntelligence, 64),
      model: str(json.app?.model, 128),
    },
    dictation: {
      id: str(d.id, 48, true),
      at: str(d.at, 40),
      transcript: str(d.transcript, LIMITS.transcript, true),
      postProcessed: str(d.postProcessed, LIMITS.text),
      postProcessRequested: bool(d.postProcessRequested),
      edited: str(d.edited, LIMITS.text),
      durationMs: int(d.durationMs),
      transcribeMs: int(d.transcribeMs),
      postProcessMs: int(d.postProcessMs),
      dictionaryFixes: int(d.dictionaryFixes),
      appId: str(d.appId, LIMITS.app),
      appName: str(d.appName, LIMITS.app),
      windowTitle: str(d.windowTitle, LIMITS.window),
    },
    settings,
  };
  if (!out.issue) throw new Error("empty issue");
  return out;
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
    const parsed = JSON.parse(new TextDecoder().decode(body));
    report = validateReport(parsed);
    audio = decodeAudio(parsed.audio);
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
