#!/usr/bin/env python3

""" permissions: 755 root root """
""" location: /usr/local/bin """

from flask import Flask, request, redirect, Response, jsonify
import subprocess
import time
import os
import urllib.request

MOUNT_URL = "http://127.0.0.1:8000/fm.mp3"

app = Flask(__name__)

def set_env_and_restart(freq: str) -> None:
    body = f"FREQ={freq}\n"
    tmp = "/etc/default/fmradio.tmp"
    with open(tmp, "w") as f:
        f.write(body)
    os.replace(tmp, "/etc/default/fmradio")
    subprocess.run(["systemctl", "restart", "fmradio@active.service"], check=False)

def mount_is_up(timeout: float = 2.0) -> bool:
    try:
        req = urllib.request.Request(MOUNT_URL, method="GET", headers={"Range": "bytes=0-0"})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return getattr(r, "status", 200) in (200, 206)
    except Exception:
        return False

def wait_mount(timeout: float = 25.0, interval: float = 0.35) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if mount_is_up(timeout=2.0):
            return True
        time.sleep(interval)
    return False

@app.route("/fmtune", methods=["GET", "HEAD"])
@app.route("/fmtune/", methods=["GET", "HEAD"])
def fmtune():
    if request.method == "HEAD":
        return Response(status=200)

    freq = request.args.get("freq", "102.3")
    set_env_and_restart(freq)

    if wait_mount(timeout=25.0, interval=0.35):
        return redirect(MOUNT_URL, code=302)

    return Response("Tuner not ready", status=503, mimetype="text/plain")

@app.get("/fmstatus")
def fmstatus():
    svc = subprocess.run(["systemctl", "is-active", "fmradio@active.service"],
                         capture_output=True, text=True)
    return jsonify({
        "service": svc.stdout.strip(),
        "mount_up": mount_is_up(timeout=1.0),
        "mount_url": MOUNT_URL,
    })

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8081)
