// Serves the site from ./web, answers /download by streaming the latest
// release's DMG from GitHub under the name "type me it.dmg", and takes the
// app's feedback reports at /api/feedback (see feedback.mjs). The asset on
// GitHub is TypeMeIt.dmg: /releases/latest/download/ only resolves a fixed
// name, and GitHub replaces spaces in asset names with dots, so the name the
// visitor saves has to be set here, in the Content-Disposition header.
import { handleFeedback } from "./feedback.mjs";

const DMG = "https://github.com/typemeit/typemeit/releases/latest/download/TypeMeIt.dmg";

export default {
  async fetch(request, env, ctx) {
    const path = new URL(request.url).pathname;
    if (path.startsWith("/api/feedback")) return handleFeedback(request, env, ctx);
    if (path !== "/download") return env.ASSETS.fetch(request);
    const upstream = await fetch(DMG, { redirect: "follow" });
    if (!upstream.ok) return new Response("the download is not available right now", { status: 502 });
    const headers = new Headers({
      "Content-Type": "application/x-apple-diskimage",
      "Content-Disposition": 'attachment; filename="type me it.dmg"',
      "Cache-Control": "no-store",
    });
    const length = upstream.headers.get("Content-Length");
    if (length) headers.set("Content-Length", length);
    return new Response(upstream.body, { status: 200, headers });
  },
};
