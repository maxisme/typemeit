// Serves the site from ./web, and proxies the release assets so nothing the app
// or the site points at has to be a github.com URL.
//
//   /download                    the latest DMG, saved as "type me it.dmg"
//   /appcast.xml                 the Sparkle feed attached to the latest release
//   /download/<tag>/TypeMeIt.dmg the DMG for one release, which is what the
//                                appcast's enclosures point at
//
// The asset on GitHub is TypeMeIt.dmg: /releases/latest/download/ only resolves a
// fixed name, and GitHub replaces spaces in asset names with dots, so the name a
// visitor saves is set here, in the Content-Disposition header. Sparkle verifies
// the DMG against the EdDSA signature in the appcast, which covers the file's
// bytes and not where it was fetched from, so proxying changes nothing it checks.
const RELEASES = "https://github.com/maxisme/typemeit/releases";
const LATEST_DMG = `${RELEASES}/latest/download/TypeMeIt.dmg`;
const LATEST_APPCAST = `${RELEASES}/latest/download/appcast.xml`;

// A release tag as the release workflow publishes it. Anything else is a 404
// rather than a fetch, so the path cannot name an arbitrary GitHub asset.
const TAG = /^v\d+(\.\d+)*$/;

const YEAR = 31536000;

/// Streams `url` back to the caller, passing the range through so an interrupted
/// download resumes rather than starting again.
async function proxy(request, url, headers, cacheTtl) {
  const range = request.headers.get("Range");
  const upstream = await fetch(url, {
    method: request.method,
    headers: range ? { Range: range } : undefined,
    redirect: "follow",
    // Ranged requests are left uncached: the hit would be for one slice.
    cf: cacheTtl && !range ? { cacheEverything: true, cacheTtl } : undefined,
  });
  if (!upstream.ok) return new Response("the download is not available right now", { status: 502 });

  const out = new Headers(headers);
  for (const header of ["Content-Length", "Content-Range", "Accept-Ranges", "ETag", "Last-Modified"]) {
    const value = upstream.headers.get(header);
    if (value) out.set(header, value);
  }
  return new Response(upstream.body, { status: upstream.status, headers: out });
}

export default {
  async fetch(request, env) {
    const { pathname } = new URL(request.url);
    const asset = pathname === "/download" || pathname === "/appcast.xml" || pathname.startsWith("/download/");
    if (!asset) return env.ASSETS.fetch(request);
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("method not allowed", { status: 405, headers: { Allow: "GET, HEAD" } });
    }

    if (pathname === "/download") {
      // Whichever release is current, so it is never served from a cache.
      return proxy(request, LATEST_DMG, {
        "Content-Type": "application/x-apple-diskimage",
        "Content-Disposition": 'attachment; filename="type me it.dmg"',
        "Cache-Control": "no-store",
      });
    }

    if (pathname === "/appcast.xml") {
      // Sparkle checks hourly, and a release should reach those checks quickly,
      // so the feed is cached for minutes rather than not at all.
      return proxy(request, LATEST_APPCAST, {
        "Content-Type": "application/xml; charset=utf-8",
        "Cache-Control": "public, max-age=300",
      }, 300);
    }

    // A DMG under its own tag never changes, so it can be cached indefinitely.
    const tag = pathname.match(/^\/download\/([^/]+)\/TypeMeIt\.dmg$/)?.[1];
    if (!tag || !TAG.test(tag)) return new Response("not found", { status: 404 });
    return proxy(request, `${RELEASES}/download/${tag}/TypeMeIt.dmg`, {
      "Content-Type": "application/x-apple-diskimage",
      "Cache-Control": "public, max-age=31536000, immutable",
    }, YEAR);
  },
};
