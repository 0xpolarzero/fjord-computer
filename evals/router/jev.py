"""Minimal TypeSafe Jev client for the Router evals. The key is read from Lookout's Keychain item at runtime, never printed."""
import hashlib
import json
import os
import pathlib
import ssl
import subprocess
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

ENDPOINT = "https://api.typesafe.ai/v1/systemone"
CACHE = pathlib.Path(__file__).parent / "cache"
_key = None
# python.org's Python ships without CA certificates; macOS has its own bundle.
_TLS = ssl.create_default_context(cafile="/etc/ssl/cert.pem" if os.path.exists("/etc/ssl/cert.pem") else None)


def key():
    global _key
    if _key is None:
        _key = os.environ.get("TYPESAFE_API_KEY") or subprocess.run(
            ["security", "find-generic-password", "-s", "dev.polarzero.lookout", "-a", "typesafe-key", "-w"],
            capture_output=True, text=True, check=True).stdout.strip()
    return _key


def ask(state, questions, model="jev-latest", cache=True, sample=0):
    """One call. Cached on disk by request and sample index (a new index asks the same request again on purpose)."""
    body = {"model": model, "state": state, "questions": questions}
    raw = json.dumps(body, sort_keys=True)
    digest = hashlib.sha256((raw + f"#{sample}").encode()).hexdigest()
    path = CACHE / digest[:2] / f"{digest}.json"
    if cache and path.exists():
        try:
            return json.loads(path.read_text())
        except json.JSONDecodeError:
            pass
    out = None
    for attempt in range(6):
        req = urllib.request.Request(ENDPOINT, data=raw.encode(), method="POST", headers={
            "Authorization": f"Bearer {key()}", "Content-Type": "application/json"})
        t0 = time.time()
        try:
            with urllib.request.urlopen(req, timeout=30, context=_TLS) as r:
                out = json.loads(r.read())
            out["_latency"] = time.time() - t0
            break
        except urllib.error.HTTPError as e:
            if e.code in (429, 529, 503) and attempt < 5:
                time.sleep(2 ** attempt)
                continue
            raise RuntimeError(f"HTTP {e.code}: {e.read()[:300]!r}")
        except (urllib.error.URLError, TimeoutError):
            if attempt < 5:
                time.sleep(2 ** attempt)
                continue
            raise
    if cache:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(f".{os.getpid()}.{threading.get_ident()}.tmp")
        tmp.write_text(json.dumps(out))
        os.replace(tmp, path)
    return out


def ask_many(calls, workers=8):
    """calls: list of (state, questions) or (state, questions, kwargs). Answers in order."""
    with ThreadPoolExecutor(workers) as pool:
        return list(pool.map(lambda c: ask(c[0], c[1], **(c[2] if len(c) > 2 else {})), calls))
