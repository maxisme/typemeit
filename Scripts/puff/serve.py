# Serves the repo so render.html can pull web/puff.glsl.js, and accepts the
# rendered PNG back as a POST. A browser is the only thing here that can run the
# shader; this is how its pixels reach disk.
#
#   python3 Scripts/puff/serve.py
#   open http://127.0.0.1:8791/Scripts/puff/render.html?name=p1&size=520&exp=0.55&trail=0.5&flow=0.35&time=140
import http.server, os, urllib.parse
D = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(D, "..", ".."))
class H(http.server.SimpleHTTPRequestHandler):
    def do_POST(self):
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        name = os.path.basename(q.get('name', ['puff.png'])[0])
        data = self.rfile.read(int(self.headers['Content-Length']))
        open(os.path.join(D, name), 'wb').write(data)
        self.send_response(200); self.end_headers(); self.wfile.write(f"{name} {len(data)}".encode())
    def log_message(self, *a): pass
os.chdir(ROOT)
http.server.HTTPServer(('127.0.0.1', 8791), H).serve_forever()
