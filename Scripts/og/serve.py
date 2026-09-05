# Serves the repo so render.html can pull web/puff.glsl.js, and accepts the
# rendered PNG back as a POST into the directory given as the first argument.
#
#   python3 Scripts/og/serve.py /tmp/out
import http.server, os, sys, urllib.parse
D = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(D, "..", ".."))
OUT = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else D
class H(http.server.SimpleHTTPRequestHandler):
    def do_POST(self):
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        name = os.path.basename(q.get('name', ['og.png'])[0])
        data = self.rfile.read(int(self.headers['Content-Length']))
        open(os.path.join(OUT, name), 'wb').write(data)
        self.send_response(200); self.end_headers(); self.wfile.write(f"{name} {len(data)}".encode())
    def log_message(self, *a): pass
os.chdir(ROOT)
http.server.HTTPServer(('127.0.0.1', 8792), H).serve_forever()
