"""Build the Russian OpenWrt APK from a hash-pinned official release payload.

Run inside tools/Dockerfile. The base contributes bundled databases/assets and
OpenWrt lifecycle scripts. All plugin sources and catalogs come from this repo.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
BASE_VERSION = "0.47.156"
VERSION = "0.47.156.1"
BASE_SHA256 = "1e4f330fc654e0270ac9cfa762af221335567d9b89388219890e8a7745b914ab"
BASE_URL = f"https://github.com/vernesong/OpenClash/releases/download/v{BASE_VERSION}/luci-app-openclash-{BASE_VERSION}.apk"
BUILD = ROOT / "build"
DIST = ROOT / "dist"
PACKAGE = ROOT / "luci-app-openclash"
BUILD.mkdir(exist_ok=True)
DIST.mkdir(exist_ok=True)
base = BUILD / f"upstream-{BASE_VERSION}.apk"
if not base.exists():
    urllib.request.urlretrieve(BASE_URL, base)
assert hashlib.sha256(base.read_bytes()).hexdigest() == BASE_SHA256, "Upstream APK hash mismatch"
metadata = json.loads(subprocess.check_output(["apk", "adbdump", "--format", "json", str(base)]))

# Container-local storage keeps Unix permissions independent of the host OS.
stage = Path("/tmp/openclash-ru-stage")
if stage.exists():
    shutil.rmtree(stage)
stage.mkdir()
subprocess.run(["apk", "extract", "--allow-untrusted", str(base)], cwd=stage, check=True)
for folder, target in ((PACKAGE / "root", stage), (PACKAGE / "luasrc", stage / "usr/lib/lua/luci")):
    for source in folder.rglob("*"):
        if not source.is_file():
            continue
        destination = target / source.relative_to(folder)
        destination.parent.mkdir(parents=True, exist_ok=True)
        old_mode = destination.stat().st_mode & 0o777 if destination.exists() else 0o644
        payload = source.read_bytes()
        if source.suffix in (".lua", ".sh", ".htm", ".js", ".css", ".json") or payload.startswith(b"#!"):
            payload = payload.replace(b"\r\n", b"\n")
        destination.write_bytes(payload)
        if payload.startswith(b"#!") or source.parent.name == "uci-defaults":
            old_mode = 0o755
        destination.chmod(old_mode)
(stage / "usr/lib/lua/luci/view/openclash/developer.htm").unlink(missing_ok=True)

compiler = Path("/tmp/openclash-ru-po2lmo")
compiler.mkdir(exist_ok=True)
subprocess.run(["gcc", "-O2", "-o", str(compiler / "po2lmo"), str(PACKAGE / "tools/po2lmo/src/po2lmo.c"), str(PACKAGE / "tools/po2lmo/src/template_lmo.c")], check=True)
for po in sorted((PACKAGE / "po").glob("*/*.po")):
    lmo = stage / "usr/lib/lua/luci/i18n" / (po.stem + ".lmo")
    subprocess.run([str(compiler / "po2lmo"), str(po), str(lmo)], check=True)
    lmo.chmod(0o644)
docs = stage / "usr/share/doc/openclash-ru"
docs.mkdir(parents=True, exist_ok=True)
shutil.copyfile(ROOT / "LICENSE", docs / "LICENSE")
shutil.copyfile(ROOT / "README.ru.md", docs / "README.ru.md")
for path in stage.rglob("*"):
    if path.is_dir():
        path.chmod(0o755)
    os.chown(path, 0, 0, follow_symlinks=False)
    os.utime(path, (0, 0), follow_symlinks=False)

output = DIST / f"luci-app-openclash-{VERSION}.apk"
command = ["apk", "mkpkg", "--compat", "2.99.0", "--files", str(stage), "--output", str(output)]
info = dict(metadata["info"])
info.update(version=VERSION, description="OpenClash — русский интерфейс LuCI", maintainer="vernesong; expert43-dev (Russian edition)")
for key in ("name", "version", "description", "arch", "origin", "maintainer", "depends", "provides", "tags"):
    value = info.get(key)
    if value is not None:
        command.extend(["--info", key + ":" + (" ".join(value) if isinstance(value, list) else str(value))])
for kind, script in metadata["scripts"].items():
    path = compiler / (kind + ".sh")
    path.write_text(script, encoding="utf-8")
    command.extend(["--script", kind + ":" + str(path)])
subprocess.run(command, check=True)
result = json.loads(subprocess.check_output(["apk", "adbdump", "--format", "json", str(output)]))
assert result["info"]["version"] == VERSION
assert result["info"]["arch"] == "noarch"
assert result["info"]["depends"] == metadata["info"]["depends"]
assert result["scripts"] == metadata["scripts"]
verify = Path("/tmp/openclash-ru-verify")
if verify.exists():
    shutil.rmtree(verify)
verify.mkdir()
subprocess.run(["apk", "extract", "--allow-untrusted", str(output)], cwd=verify, check=True)
for file in stage.rglob("*"):
    if file.is_file():
        extracted = verify / file.relative_to(stage)
        assert extracted.read_bytes() == file.read_bytes(), str(extracted)
        assert extracted.stat().st_mode & 0o777 == file.stat().st_mode & 0o777
assert not (verify / "usr/lib/lua/luci/view/openclash/developer.htm").exists()
digest = hashlib.sha256(output.read_bytes()).hexdigest()
(DIST / "SHA256SUMS").write_text(f"{digest}  {output.name}\n", encoding="utf-8")
(DIST / "build-report.json").write_text(json.dumps({"version": VERSION, "upstream_version": BASE_VERSION, "upstream_sha256": BASE_SHA256, "apk_sha256": digest, "size": output.stat().st_size, "dependencies_preserved": True, "lifecycle_scripts_preserved": True, "payload_roundtrip_verified": True}, indent=2) + "\n")
print(f"Built and verified {output.name}: {output.stat().st_size} bytes, SHA256 {digest}")

