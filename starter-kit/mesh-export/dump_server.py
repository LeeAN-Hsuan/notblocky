# 接收 Roblox Studio POST 過來的網格資料，直接落地成檔案。
# ★ 這支的存在本身就是實驗的一部分：驗「Studio 能不能把資料送到本機」。
import http.server, os, sys

OUT = os.path.dirname(os.path.abspath(__file__))

class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(n)
        name = self.path.strip("/").replace("/", "_") or "unnamed"
        path = os.path.join(OUT, name + ".txt")
        # 同一個名字多次 POST ⇒ 追加，方便分批送
        with open(path, "ab") as f:
            f.write(body)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")
        print(f"[recv] {name}: +{n} bytes -> {os.path.getsize(path)} total", flush=True)

    def log_message(self, *a):
        pass

http.server.HTTPServer(("127.0.0.1", 5599), H).serve_forever()
