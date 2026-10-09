"""Local UI preview with documented example IPs, never a router status report."""
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path.endswith("/myip_check"):
            body = "\n".join(json.dumps({"service": service, "ip": "203.0.113.10", "country_code": "RU", "geo": ""}) for service in ("ipgeo", "mailru", "ipsb", "ipify")) + '\n{"complete":true}\n'
            kind = "application/x-ndjson"
        elif path.endswith("/website_check"):
            body = "\n".join(json.dumps({"domain": domain, "success": True, "response_time": ms}) for domain, ms in (("ya.ru", 12), ("vk.ru", 24), ("github.com", 75), ("www.youtube.com", 84))) + '\n{"complete":true}\n'
            kind = "application/x-ndjson"
        elif path.startswith("/luci-static/"):
            file = ROOT / "luci-app-openclash/root/www" / path.lstrip("/")
            if not file.is_file() or not file.resolve().is_relative_to((ROOT / "luci-app-openclash/root/www").resolve()):
                self.send_error(404)
                return
            body = file.read_bytes()
            kind = "text/css" if file.suffix == ".css" else "application/javascript"
        elif path == "/":
            body = (ROOT / "build/preview/myip.html").read_text(encoding="utf-8")
            body = body.replace('<script src=', '<script defer src=')
            body = body.replace("</head>", '''<link rel="stylesheet" href="/luci-static/resources/openclash/css/oc.css">
<style>body{background:#202a38;color:#eee;font:16px Arial;margin:40px}.cbi-section{border:0;max-width:1200px;margin:auto}h1{max-width:1200px;margin:0 auto 24px;font-size:20px}.myip-main-card{background:#202a38;border:1px solid #708090} .myip-card-item{background:#46515f}</style></head>''')
            body = body.replace("<fieldset", '<h1>OpenClash — проверка интерфейса (демонстрационные данные)</h1><fieldset', 1)
            kind = "text/html"
        else:
            self.send_error(404)
            return
        body = body.encode("utf-8") if isinstance(body, str) else body
        self.send_response(200)
        self.send_header("Content-Type", kind + "; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

print("Preview: http://127.0.0.1:8765/ (example data only)", flush=True)
HTTPServer(("127.0.0.1", 8765), Handler).serve_forever()
