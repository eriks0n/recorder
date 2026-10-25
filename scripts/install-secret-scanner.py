#!/usr/bin/env python3
"""Install a pinned, checksum-verified scanner into ignored local build storage."""
import hashlib
import io
import os
from pathlib import Path
import platform
import ssl
import tarfile
import urllib.request

VERSION = "8.30.1"
ASSETS = {
    ("Darwin", "arm64"): ("darwin_arm64", "b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5"),
    ("Linux", "x86_64"): ("linux_x64", "551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb"),
}

def main():
    target = Path(__file__).resolve().parent.parent / ".build/security-tools/gitleaks"
    asset = ASSETS.get((platform.system(), platform.machine()))
    if not asset:
        raise SystemExit("Unsupported platform: install Gitleaks 8.30.1 manually and rerun setup.")
    name, expected = asset
    context = ssl.create_default_context(cafile="/etc/ssl/cert.pem") if Path("/etc/ssl/cert.pem").exists() else ssl.create_default_context()
    url = f"https://github.com/gitleaks/gitleaks/releases/download/v{VERSION}/gitleaks_{VERSION}_{name}.tar.gz"
    with urllib.request.urlopen(url, context=context, timeout=120) as response:
        data = response.read()
    if hashlib.sha256(data).hexdigest() != expected:
        raise SystemExit("Scanner checksum mismatch; nothing installed.")
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        member = archive.getmember("gitleaks")
        if not member.isfile():
            raise SystemExit("Invalid scanner archive.")
        binary = archive.extractfile(member).read()
    target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temporary = target.with_suffix(".tmp")
    try:
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o700)
        with os.fdopen(fd, "wb") as handle:
            handle.write(binary)
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)
    print(f"Installed verified Gitleaks {VERSION} in ignored .build/security-tools/.")

if __name__ == "__main__":
    main()
