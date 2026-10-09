"""Bootstrap the Russian catalog; saved translations are reviewed and built offline.

Only public upstream UI strings are sent to the translation service. Never run
this against router configurations, subscriptions, logs or credentials.
"""
import ast
import concurrent.futures
import json
import pathlib
import re
import time
import urllib.parse
import urllib.request

import polib

ROOT = pathlib.Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "luci-app-openclash"
CACHE = ROOT / "tools" / "translation-cache.json"
original = (PACKAGE / "po/zh-cn/openclash.zh-cn.po").read_text(encoding="utf-8")
# Upstream's po2lmo accepts a header without msgid/msgstr; polib requires gettext syntax.
po = polib.pofile(original[original.index('msgid '):], encoding="utf-8")
keys = dict.fromkeys(e.msgid for e in po if e.msgid)
for p in (PACKAGE / "luasrc").rglob("*"):
    if p.suffix not in (".htm", ".lua"):
        continue
    source = p.read_text(encoding="utf-8")
    for m in re.finditer(r"<%:([\s\S]*?)%>", source):
        keys[m[1].strip()] = None
    for m in re.finditer(r'\btranslate\(\s*("(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\')', source):
        try:
            keys[ast.literal_eval(m[1])] = None
        except (SyntaxError, ValueError):
            pass
keys = {key: None for key in keys if key.strip() and "Math.round(-popup" not in key}
cache = json.loads(CACHE.read_text(encoding="utf-8")) if CACHE.exists() else {}

# Preserve protocol names, machine options, URLs, markup and format placeholders.
technical = r"OpenClash|OpenWrt|Mihomo|Clash|MetaCubeXD|Metacubexd|Zashboard|yacd|DNS|DoH|DoT|UDP|TCP|HTTP\(S\)|HTTPS?|SOCKS5?|QUIC|TUN|IPv[46]|IP|CIDR|GEOIP|GeoIP|GeoSite|ASN|MMDB|YAML|JSON|Ruby|LightGBM|Fake-IP|fake-ip|redir-host|Dnsmasq|dnsmasq|iptables|nftables|DSCP|XUDP|TLS|SNI|REALITY|VLESS|VMess|Vmess|Trojan|Shadowsocks|Snell|WireGuard|Hysteria|Age|age|x25519|mlkem768-x25519|GitHub|YouTube|oixCloud|SS/SSR|BT/P2P|DIRECT|REJECT-DROP|REJECT|PASS|GLOBAL"
protect_re = re.compile(r"https?://[^\s<>]+|</?[^>]+>|%[0-9$.*+-]*[sdifu]|\$\{[^}]+\}|\b[a-z][a-z0-9]*[_-][a-z0-9_-]+\b|/(?:[\w.*-]+/)*[\w.*-]+|\b(?:" + technical + r")\b", re.I)
for key in keys:
    if protect_re.fullmatch(key) or re.fullmatch(r"[\d\W]+|(?:[A-Za-z0-9_-]+\.)+[A-Za-z]{2,}", key):
        cache[key] = key


def translate_batch(batch):
    tokens = []
    def shield(m):
        tokens.append(m[0])
        return f"ZXQ{len(tokens)-1:05d}QXZ"
    text = protect_re.sub(shield, batch[0]) if len(batch) == 1 else "\n".join(f"@@{i:06d}@@ " + protect_re.sub(shield, key).replace("\n", " ") for i, key in enumerate(batch))
    url = "https://translate.googleapis.com/translate_a/single?" + urllib.parse.urlencode({"client": "gtx", "sl": "en", "tl": "ru", "dt": "t", "q": text})
    for attempt in range(4):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "OpenClash-Russian-localization/1.0"})
            with urllib.request.urlopen(request, timeout=45) as response:
                result = json.load(response)
            output = "".join(x[0] for x in result[0] if x[0])
            if len(batch) == 1:
                for index, token in enumerate(tokens):
                    output = re.sub(r"ZXQ\s*" + f"{index:05d}" + r"\s*QXZ", lambda m, token=token: token, output, flags=re.I)
                if not output.strip() or re.search(r"ZXQ\s*\d+\s*QXZ", output, re.I):
                    raise ValueError("Invalid single translation")
                return {batch[0]: output}
            marks = list(re.finditer(r"@@\s*(\d{6})\s*@@\s*", output))
            if len(marks) != len(batch) or [int(m[1]) for m in marks] != list(range(len(batch))):
                raise ValueError("Translation batch boundaries changed")
            translated = {}
            for i, mark in enumerate(marks):
                value = output[mark.end():marks[i+1].start() if i+1 < len(marks) else len(output)].strip()
                for index, token in enumerate(tokens):
                    value = re.sub(r"ZXQ\s*" + f"{index:05d}" + r"\s*QXZ", lambda m, token=token: token, value, flags=re.I)
                if re.search(r"ZXQ\s*\d+\s*QXZ", value, re.I):
                    raise ValueError("Unrestored technical token")
                if not value:
                    raise ValueError("Empty translation for " + repr(batch[i]))
                translated[batch[i]] = value
            return translated
        except Exception:
            if attempt == 3:
                if len(batch) > 1:
                    merged = {}
                    for key in batch:
                        merged.update(translate_batch([key]))
                    return merged
                raise
            time.sleep(1 + attempt)


pending = [k for k in keys if k not in cache]
batches, batch, size = [], [], 0
for key in pending:
    if batch and (size + len(key) > 2600 or len(batch) >= 25):
        batches.append(batch)
        batch, size = [], 0
    batch.append(key)
    size += len(key) + 16
if batch:
    batches.append(batch)
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
    for result in pool.map(translate_batch, batches):
        cache.update(result)
        CACHE.write_text(json.dumps(cache, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"Translated {len(cache)}/{len(keys)} public strings", flush=True)

cache.update(json.loads((ROOT / "tools/russian_overrides.json").read_text(encoding="utf-8")))

target = polib.POFile()
target.metadata = {"Project-Id-Version": "OpenClash 0.47.156 Russian edition", "Language": "ru", "PO-Revision-Date": "2026-10-09 21:00+0300", "Last-Translator": "expert43-dev", "Language-Team": "Russian", "MIME-Version": "1.0", "Content-Type": "text/plain; charset=UTF-8", "Content-Transfer-Encoding": "8bit", "Plural-Forms": "nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);"}
for key in keys:
    target.append(polib.POEntry(msgid=key, msgstr=cache[key]))
destination = PACKAGE / "po/ru/openclash.ru.po"
destination.parent.mkdir(parents=True, exist_ok=True)
target.save(str(destination))
print(f"Saved {len(target)} entries to {destination}", flush=True)
