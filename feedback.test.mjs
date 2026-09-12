// node --test feedback.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  decodeAudio, handleFeedback, hmacHex, notification, objectPrefix, parseKeys, reportId, sha256Hex,
  validateReport, verifySignature,
} from "./feedback.mjs";

const KEY = "0b".repeat(32);
const KEYS = parseKeys(`1:${KEY}`);
const encoder = new TextEncoder();

function report(extra = {}) {
  return {
    issue: "it typed the wrong word",
    app: { version: "0.6.0", build: "12", macos: "26.0", chip: "Apple M3" },
    dictation: { id: "A1", at: "2026-09-12T10:00:00Z", transcript: "hello there", postProcessed: "Hello there", postProcessRequested: true, appName: "Slack" },
    settings: { postProcessingEnabled: true, historyLimit: 500 },
    ...extra,
  };
}

async function signed(body, { now = Math.floor(Date.now() / 1000), keyId = "1", key = KEY } = {}) {
  const bytes = encoder.encode(body);
  const signature = await hmacHex(key, `${now}.${await sha256Hex(bytes)}`);
  return { bytes, headers: { "X-Key-Id": keyId, "X-Timestamp": String(now), "X-Signature": signature } };
}

class Bucket {
  objects = new Map();
  async head(key) { return this.objects.has(key) ? {} : null; }
  async get(key) { return this.objects.has(key) ? { body: this.objects.get(key) } : null; }
  async put(key, value) { this.objects.set(key, value); }
}

function env(bucket = new Bucket(), extra = {}) {
  return { FEEDBACK: bucket, FEEDBACK_KEYS: `1:${KEY}`, FEEDBACK_READ_TOKEN: "readme", ...extra };
}

function post(body, headers) {
  return new Request("https://typeme.it/api/feedback", {
    method: "POST", body, headers: { ...headers, "Content-Length": String(body.byteLength) },
  });
}

const ctx = { waitUntil() {} };

test("a signed report is stored and gets an id derived from its body", async () => {
  const body = JSON.stringify(report());
  const { bytes, headers } = await signed(body);
  const bucket = new Bucket();
  const res = await handleFeedback(post(bytes, headers), env(bucket), ctx);
  assert.equal(res.status, 201);
  const { id } = await res.json();
  assert.equal(id, reportId(new Date(), await sha256Hex(bytes)));
  const stored = JSON.parse(bucket.objects.get(`${objectPrefix(id)}/report.json`));
  assert.equal(stored.issue, "it typed the wrong word");
  assert.equal(stored.hasAudio, false);
});

test("the same bytes again are answered with the same id and no second write", async () => {
  const body = JSON.stringify(report());
  const { bytes, headers } = await signed(body);
  const bucket = new Bucket();
  await handleFeedback(post(bytes, headers), env(bucket), ctx);
  let notified = 0;
  const first = await handleFeedback(post(bytes, headers), env(bucket), { waitUntil() { notified++; } });
  assert.equal(first.status, 200);
  assert.equal(notified, 0);
  assert.equal(bucket.objects.size, 1);
});

test("a bad signature, wrong key id or stale timestamp is refused", async () => {
  const body = encoder.encode(JSON.stringify(report()));
  const now = 1_000_000;
  assert.equal(await verifySignature({ keyId: "1", timestamp: String(now), signature: "00".repeat(32), body, keys: KEYS, now }), "bad signature");
  assert.equal(await verifySignature({ keyId: "2", timestamp: String(now), signature: "00".repeat(32), body, keys: KEYS, now }), "unknown key");
  const { headers } = await signed(JSON.stringify(report()), { now: now - 301 });
  assert.equal(await verifySignature({ keyId: "1", timestamp: headers["X-Timestamp"], signature: headers["X-Signature"], body, keys: KEYS, now }), "stale timestamp");
  const ok = await signed(JSON.stringify(report()), { now });
  assert.equal(await verifySignature({ keyId: "1", timestamp: ok.headers["X-Timestamp"], signature: ok.headers["X-Signature"], body, keys: KEYS, now }), null);
});

test("an unsigned post is a 401", async () => {
  const bytes = encoder.encode(JSON.stringify(report()));
  const res = await handleFeedback(post(bytes, {}), env(), ctx);
  assert.equal(res.status, 401);
});

test("an oversized body is refused before it is read", async () => {
  const req = new Request("https://typeme.it/api/feedback", { method: "POST", body: "x", headers: { "Content-Length": String(4 * 1024 * 1024) } });
  const res = await handleFeedback(req, env(), ctx);
  assert.equal(res.status, 413);
});

test("validation keeps the known shape and rejects the rest", () => {
  assert.throws(() => validateReport(report({ issue: "   " })), { message: "issue: Too small: expected string to have >=1 characters" });
  assert.throws(() => validateReport(report({ issue: "x".repeat(4001) })), { message: "issue: Too big: expected string to have <=4000 characters" });
  assert.throws(() => validateReport(report({ settings: { "bad key!": true } })), { message: "settings.bad key!: Invalid key in record" });
  assert.throws(() => validateReport(report({ settings: { nested: {} } })), { message: "settings.nested: Invalid input" });
  assert.throws(() => validateReport(report({ dictation: { id: "A1" } })), { message: "dictation.transcript: Invalid input: expected string, received undefined" });
  assert.throws(() => validateReport(report({ extra: "dropped" })), { message: 'body: Unrecognized key: "extra"' });
  const out = validateReport(report({ issue: "  trimmed  " }));
  assert.equal(out.issue, "trimmed");
  assert.equal(out.dictation.appName, "Slack");
});

test("audio must be an MPEG-4 file under the cap", () => {
  const m4a = new Uint8Array(16);
  m4a.set([0x66, 0x74, 0x79, 0x70], 4);
  assert.equal(decodeAudio(btoa(String.fromCharCode(...m4a))).length, 16);
  assert.throws(() => decodeAudio(btoa("not an mp4 file at all")), /bad audio/);
  assert.throws(() => decodeAudio("!!!"), /bad audio/);
  assert.throws(() => decodeAudio("A".repeat(3 * 1024 * 1024)), /audio too large/);
  assert.equal(decodeAudio(undefined), null);
});

test("ids map to a dated prefix", () => {
  const id = reportId(new Date("2026-09-12T23:59:00Z"), "ab".repeat(32));
  assert.equal(id, `20260912-${"ab".repeat(16)}`);
  assert.equal(objectPrefix(id), `reports/2026-09-12/${id}`);
  assert.equal(objectPrefix("../etc"), null);
});

test("the notification carries the issue, both texts and a read link", () => {
  const n = notification(validateReport(report()), "20260912-" + "ab".repeat(16), true, "https://typeme.it");
  assert.equal(n.title, "0.6.0 · Slack");
  assert.equal(n.link, "https://typeme.it/api/feedback/20260912-" + "ab".repeat(16));
  assert.equal(n.message, "it typed the wrong word\n\n```\nhello there\n```\n→\n```\nHello there\n```\naudio attached");
  assert.equal(n.occurred_at, Date.parse("2026-09-12T10:00:00Z"));
});

test("reading a report needs the bearer token", async () => {
  const body = JSON.stringify(report());
  const { bytes, headers } = await signed(body);
  const bucket = new Bucket();
  const { id } = await (await handleFeedback(post(bytes, headers), env(bucket), ctx)).json();
  const url = `https://typeme.it/api/feedback/${id}`;
  assert.equal((await handleFeedback(new Request(url), env(bucket), ctx)).status, 401);
  const ok = await handleFeedback(new Request(url, { headers: { Authorization: "Bearer readme" } }), env(bucket), ctx);
  assert.equal(ok.status, 200);
  assert.equal(JSON.parse(await ok.text()).id, id);
  const audio = await handleFeedback(new Request(`${url}/audio`, { headers: { Authorization: "Bearer readme" } }), env(bucket), ctx);
  assert.equal(audio.status, 404);
});
