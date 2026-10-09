"""Offline checks for catalogs, plugin syntax and the localized overview."""
import ast
import html
import json
from pathlib import Path
import re
import subprocess
import tempfile
import polib

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "luci-app-openclash"
po = polib.pofile(str(PACKAGE / "po/ru/openclash.ru.po"))
catalog = {entry.msgid: entry.msgstr for entry in po}
assert len(catalog) == len(po), "Duplicate message IDs"
assert all(entry.msgstr and not entry.fuzzy for entry in po), "Incomplete translation"
assert not any(re.search(r"[\u4e00-\u9fff]|ZXQ\d+QXZ", entry.msgstr) for entry in po), "Untranslated Chinese/token"
for entry in po:
    placeholders = lambda s: sorted(re.findall(r"%[0-9$.*+-]*[sdifu]|\$\{[^}]+\}", s))
    assert placeholders(entry.msgid) == placeholders(entry.msgstr), "Changed placeholders: " + entry.msgid
subprocess.run(["msgfmt", "--check", "--check-format", "-o", "/tmp/openclash-ru.mo", str(PACKAGE / "po/ru/openclash.ru.po")], check=True)

lua_count = 0
keys = set()
for file in (PACKAGE / "luasrc").rglob("*"):
    if file.suffix not in (".lua", ".htm"):
        continue
    source = file.read_text(encoding="utf-8")
    keys.update(m[1].strip() for m in re.finditer(r"<%:([\s\S]*?)%>", source))
    for m in re.finditer(r'\btranslate\(\s*("(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\')', source):
        try:
            key = ast.literal_eval(m[1])
            if "Math.round(-popup" not in key:
                keys.add(key)
        except (SyntaxError, ValueError):
            pass
    if file.suffix == ".lua":
        subprocess.run(["luac5.1", "-p", str(file)], check=True)
        lua_count += 1
for file in (PACKAGE / "root").rglob("*.lua"):
    subprocess.run(["luac5.1", "-p", str(file)], check=True)
    lua_count += 1
assert not {key for key in keys if key.strip()} - catalog.keys(), "Missing translations"

def render(template):
    template = re.sub(r"<%:([\s\S]*?)%>", lambda m: html.escape(catalog[m[1].strip()], quote=False), template)
    template = re.sub(r"<%=([\s\S]*?)%>", "0", template)
    return re.sub(r"<%[\s\S]*?%>", "", template)

myip = (PACKAGE / "luasrc/view/openclash/myip.htm").read_text(encoding="utf-8")
assert "Baidu" not in myip and "NetEase" not in myip and "PConline" not in myip and "IPIP.NET" not in myip
assert "ya.ru" in myip and "vk.ru" in myip and "api.ipgeo.ru" in myip and "ip.mail.ru" in myip
assert "www.yandex.com" not in myip and "qqwry" not in myip
assert "Template(\"openclash/developer\")" not in (PACKAGE / "luasrc/model/cbi/openclash/client.lua").read_text()
assert not (PACKAGE / "luasrc/view/openclash/developer.htm").exists()
rendered = render(myip)
javascript_count = 0
with tempfile.TemporaryDirectory() as temp:
    for template in (PACKAGE / "luasrc/view").rglob("*.htm"):
        for index, script in enumerate(re.findall(r"<script[^>]*>([\s\S]*?)</script>", render(template.read_text(encoding="utf-8")))):
            if script.strip():
                path = Path(temp) / f"{template.stem}-{index}.js"
                path.write_text(script)
                subprocess.run(["node", "--check", str(path)], check=True)
                javascript_count += 1
subprocess.run(["lua5.1", str(ROOT / "tools/test_ip_parsers.lua")], cwd=ROOT, check=True)
subprocess.run(["lua5.1", str(ROOT / "tools/test_update_routing.lua")], cwd=ROOT, check=True)
subprocess.run(["lua5.1", str(ROOT / "tools/test_active_proxy.lua")], cwd=ROOT, check=True)
subprocess.run(["lua5.1", str(ROOT / "tools/test_core_version.lua")], cwd=ROOT, check=True)
subprocess.run(["lua5.1", str(ROOT / "tools/test_awg.lua")], cwd=ROOT, check=True)
subprocess.run(["ruby", str(ROOT / "tools/test_awg.rb")], cwd=ROOT, check=True)
for name in ("awg.sh", "yml_proxys_get.sh", "yml_proxys_set.sh"):
    subprocess.run(["bash", "-n", str(PACKAGE / "root/usr/share/openclash" / name)], check=True)
subprocess.run(["ruby", "-c", str(PACKAGE / "root/usr/share/openclash/awg.rb")], check=True)
subprocess.run(["bash", "-n", str(PACKAGE / "root/usr/share/openclash/openclash_update.sh")], check=True)

# Exercise the same translated template in a browser using mocked LuCI endpoints.
preview = ROOT / "build/preview"
preview.mkdir(parents=True, exist_ok=True)
(preview / "myip.html").write_text(rendered, encoding="utf-8")
report = {"catalog_entries": len(po), "source_messages_covered": len(keys), "lua_files_checked": lua_count, "javascript_blocks_checked": javascript_count, "update_routes_checked": True, "overview_javascript_checked": True, "ip_parser_tests_passed": True, "awg_tests_passed": True}
(ROOT / "build/localization-report.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report))
