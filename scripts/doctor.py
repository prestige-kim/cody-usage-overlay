#!/usr/bin/env python3
import json
import os
import pathlib
import subprocess
import sys
import threading

CODEX_CANDIDATES = [
    pathlib.Path("/Applications/ChatGPT.app/Contents/Resources/codex"),
    pathlib.Path(os.popen("command -v codex 2>/dev/null").read().strip()),
]

def find_codex():
    return next((p for p in CODEX_CANDIDATES if str(p) and p.is_file() and os.access(p, os.X_OK)), None)

def rpc_check(executable):
    process = subprocess.Popen([str(executable), "app-server", "--stdio"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    def send(obj):
        process.stdin.write(json.dumps(obj, separators=(",", ":")) + "\n"); process.stdin.flush()
    send({"id": 1, "method": "initialize", "params": {"clientInfo": {"name": "cody-overlay-doctor", "title": "Doctor", "version": "1"}, "capabilities": {"experimentalApi": True}}})
    initialized = None
    for _ in range(20):
        line = process.stdout.readline()
        if not line: break
        item = json.loads(line)
        if item.get("id") == 1:
            initialized = item
            break
    if not initialized or "result" not in initialized:
        process.terminate()
        detail = (initialized or {}).get("error", {}).get("message")
        if not detail and process.stderr:
            detail = process.stderr.read().strip().splitlines()[-1:] or None
            if isinstance(detail, list): detail = detail[0] if detail else None
        raise RuntimeError(detail or "initialize response missing")
    send({"method": "initialized", "params": {}})
    send({"id": 2, "method": "account/rateLimits/read", "params": {}})
    result = None
    for _ in range(20):
        line = process.stdout.readline()
        if not line: break
        item = json.loads(line)
        if item.get("id") == 2:
            result = item
            break
    process.terminate()
    if not result or "result" not in result:
        raise RuntimeError((result or {}).get("error", {}).get("message", "rate-limit response missing"))
    return result["result"]

def rollout_check():
    root = pathlib.Path.home() / ".codex" / "sessions"
    candidates = []
    for file in root.rglob("*.jsonl"):
        try:
            with file.open() as stream: meta = json.loads(stream.readline()).get("payload", {})
            if meta.get("originator") == "Codex Desktop" and meta.get("source") == "vscode":
                candidates.append(file)
        except Exception:
            pass
    return max(candidates, key=lambda p: p.stat().st_mtime) if candidates else None

def main():
    report = {"ok": False, "codex": None, "appServer": False, "rateLimitFields": [], "rollout": None, "petPackage": False}
    executable = find_codex()
    if not executable:
        print(json.dumps(report, ensure_ascii=False, indent=2)); return 1
    report["codex"] = str(executable)
    try:
        rate = rpc_check(executable)
        report["appServer"] = True
        report["rateLimitFields"] = sorted(rate.keys())
    except Exception as exc:
        report["error"] = str(exc)
    rollout = rollout_check()
    report["rollout"] = str(rollout) if rollout else None
    report["petPackage"] = (pathlib.Path.home() / ".codex/pets/cody/pet.json").is_file()
    report["ok"] = report["appServer"] and rollout is not None
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["ok"] else 1

if __name__ == "__main__": sys.exit(main())
