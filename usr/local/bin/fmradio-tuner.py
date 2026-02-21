#!/usr/bin/env python3

""" permissions: 755 root root """

from flask import Flask, request, redirect, Response
import subprocess, time, urllib.request

MOUNT_URL = "http://127.0.0.1:8000/fm.mp3"
STATUS_URL = "http://127.0.0.1:8000/status-json.xsl"

app = Flask(__name__)

def set_env_and_restart(freq):
    body = f"FREQ={freq}\n"
    tmp = "/etc/default/fmradio.tmp"
    with open(tmp, "w") as f: f.write(body)
    import os
    os.replace(tmp, "/etc/default/fmradio")
    subprocess.run(["systemctl","restart","fmradio@active.service"], check=True)

def wait_mount(timeout=20.0, interval=0.4):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            req = urllib.request.Request(MOUNT_URL, method="GET", headers={"Range":"bytes=0-0"})
            with urllib.request.urlopen(req, timeout=2) as r:
                if r.status in (200,206):
                    return True
        except Exception:
            pass
        time.sleep(interval)
    return False

@app.route("/fmtune", methods=["GET","HEAD"])
def fmtune():
    freq = request.args.get("freq","102.3")
    set_env_and_restart(freq)
    if wait_mount():
        if request.method == "HEAD":
            return Response(status=204)
        return redirect(MOUNT_URL, code=302)
    return Response("Tuner not ready", status=503, mimetype="text/plain")

@app.get("/fmstatus")
def fmstatus():
    out = subprocess.run(["systemctl","is-active","fmradio@active.service"], capture_output=True, text=True)
    return {"service": out.stdout.strip(), "mount": MOUNT_URL}

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8081)   # different port from HD tuner