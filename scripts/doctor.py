#!/usr/bin/env python3
import json
import os
import pathlib
import plistlib
import queue
import subprocess
import sys
import threading

def codex_candidates():
    home = pathlib.Path.home()
    candidates = []
    for root in (pathlib.Path("/Applications"), home / "Applications"):
        for app in ("ChatGPT.app", "Codex.app"):
            candidates.append(root / app / "Contents/Resources/codex")
        try:
            for app in root.glob("*.app"):
                try:
                    with (app / "Contents/Info.plist").open("rb") as stream:
                        bundle_id = plistlib.load(stream).get("CFBundleIdentifier", "").lower()
                    if bundle_id in {"com.openai.codex", "com.openai.chat", "com.openai.chatgpt"}:
                        candidates.append(app / "Contents/Resources/codex")
                except (OSError, plistlib.InvalidFileException):
                    pass
        except OSError:
            pass
    candidates += [
        home / ".local/bin/codex",
        home / ".codex/bin/codex",
        pathlib.Path("/opt/homebrew/bin/codex"),
        pathlib.Path("/usr/local/bin/codex"),
    ]
    candidates += [pathlib.Path(directory) / "codex" for directory in os.environ.get("PATH", "").split(":") if directory]
    return list(dict.fromkeys(candidates))

def find_codex():
    return next((p for p in codex_candidates() if p.is_file() and os.access(p, os.X_OK)), None)

class ResponseReader:
    def __init__(self, stream):
        self.items = queue.Queue()
        self.thread = threading.Thread(target=self._read, args=(stream,), daemon=True)
        self.thread.start()

    def _read(self, stream):
        try:
            for line in stream:
                self.items.put(json.loads(line))
        except Exception as exc:
            self.items.put(exc)

    def response(self, request_id, timeout=15):
        while True:
            try:
                item = self.items.get(timeout=timeout)
            except queue.Empty:
                raise RuntimeError(f"request {request_id} timed out")
            if isinstance(item, Exception):
                raise item
            if item.get("id") == request_id:
                return item

def rpc_check(executable):
    process = subprocess.Popen([str(executable), "app-server", "--stdio"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    reader = ResponseReader(process.stdout)
    def send(obj):
        process.stdin.write(json.dumps(obj, separators=(",", ":")) + "\n"); process.stdin.flush()
    try:
        send({"id": 1, "method": "initialize", "params": {"clientInfo": {"name": "cody-overlay-doctor", "title": "Doctor", "version": "1"}, "capabilities": {"experimentalApi": True}}})
        initialized = reader.response(1)
        if "result" not in initialized:
            raise RuntimeError(initialized.get("error", {}).get("message", "initialize response missing"))
        send({"method": "initialized", "params": {}})
        send({"id": 2, "method": "account/rateLimits/read", "params": {}})
        result = reader.response(2)
        if "result" not in result:
            raise RuntimeError(result.get("error", {}).get("message", "rate-limit response missing"))
        return result["result"]
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()

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
    report = {"ok": False, "codex": None, "searchedCodexPaths": [str(p) for p in codex_candidates()], "appServer": False, "rateLimitFields": [], "rollout": None, "petPackage": False}
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
