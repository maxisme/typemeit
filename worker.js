// Serves the site from ./web, and answers /download by streaming the latest
// release's DMG from GitHub under the name "type me it.dmg". The asset on GitHub
// is TypeMeIt.dmg: /releases/latest/download/ only resolves a fixed name, and
// GitHub replaces spaces in asset names with dots, so the name the visitor saves
// has to be set here, in the Content-Disposition header.
const DMG = "https://github.com/maxisme/typemeit/releases/latest/download/TypeMeIt.dmg";

export default {
  async fetch(request, env) {
    if (new URL(request.url).pathname !== "/download") return env.ASSETS.fetch(request);
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("method not allowed", { status: 405, headers: { Allow: "GET, HEAD" } });
    }

    // HEAD and Range go upstream rather than being answered here. GitHub's asset
    // storage handles both, a forwarded Range lets an interrupted download resume
    // instead of starting over, and HEAD lets a health check confirm the download
    // works without pulling the whole disk image every time it runs.
    const range = request.headers.get("Range");
    const upstream = await fetch(DMG, {
      method: request.method,
      redirect: "follow",
      headers: range ? { Range: range } : {},
    });
    if (!upstream.ok) return new Response("the download is not available right now", { status: 502 });

    const headers = new Headers({
      "Content-Type": "application/x-apple-diskimage",
      "Content-Disposition": 'attachment; filename="type me it.dmg"',
      "Cache-Control": "no-store",
      "Accept-Ranges": "bytes",
    });
    // Content-Range carries the answer to a Range request; without it a 206 is
    // unreadable. Both are copied only when upstream sent them.
    for (const header of ["Content-Length", "Content-Range"]) {
      const value = upstream.headers.get(header);
      if (value) headers.set(header, value);
    }
    return new Response(request.method === "HEAD" ? null : upstream.body, {
      status: upstream.status,
      headers,
    });
  },
};
