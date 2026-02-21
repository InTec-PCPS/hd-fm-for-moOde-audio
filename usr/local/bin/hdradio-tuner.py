#!/usr/bin/env python3
""" permissions: 755 root root """
""" location: /usr/local/bin """


from flask import Flask, request, redirect, jsonify, Response
import subprocess
import time
import os
import urllib.request
import urllib.error

MOUNT_URL = "http://127.0.0.1:8000/hd.mp3"

app = Flask(__name__)

def set_env_and_restart(freq, prog):
    body = f"FREQ={freq}\nPROG={prog}\n"
    tmp = "/etc/default/hdradio.tmp"
    with open(tmp, "w") as f:
        f.write(body)
    os.replace(tmp, "/etc/default/hdradio")
    subprocess.run(["systemctl", "restart", "hdradio@active.service"], check=False)

def mount_is_up(timeout=1.0):
    try:
        req = urllib.request.Request(MOUNT_URL)
        req.add_header("Range", "bytes=0-0")
        with urllib.request.urlopen(req, timeout=timeout) as r:
            status = getattr(r, "status", 200)
            return status in (200, 206)
    except Exception:
        return False

def wait_until_mount(timeout=15.0, interval=0.25):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if mount_is_up(timeout=1.0):
            return True
        time.sleep(interval)
    return False

@app.route("/tune", methods=["GET", "HEAD"])
@app.route("/tune/", methods=["GET", "HEAD"])
def tune():
    if request.method == "HEAD":
        return ("", 200) if mount_is_up(timeout=1.0) else ("", 503)

    freq = request.args.get("freq", "97.1")
    prog = request.args.get("prog", "0")

    set_env_and_restart(freq, prog)

    if wait_until_mount(timeout=15.0, interval=0.25):
        return redirect(MOUNT_URL, code=302)

    return Response("Tuner not ready", status=503, mimetype="text/plain")

@app.route("/status", methods=["GET"])
def status():
    return jsonify({
        "mount_up": mount_is_up(timeout=1.0)
    })

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8080)
