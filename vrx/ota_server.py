#!/usr/bin/python3

from flask import Flask, request, send_file, Response, redirect, url_for
import os
import subprocess
import argparse
import time

# ─── Config ─────────────────────────────────────────────────────────────
APP_DIR = '/srv/fpv_server'
STATIC_DIR = os.path.join(APP_DIR, 'static')
os.makedirs(STATIC_DIR, exist_ok=True)

DEFAULT_BW_LIMIT = 128  # in KB/s

# ─── Flask Setup ────────────────────────────────────────────────────────
app = Flask(__name__)
fetch_logs = []

@app.route('/')
def index():
    files = sorted(f for f in os.listdir(STATIC_DIR) if f.endswith('.tgz'))
    links = [f'<a href="/{f}">{f}</a>' for f in files]

    return f"""
    <h2>Available FPV Firmware Files</h2>
    {'<br>'.join(links)}

    <hr>
    <h3>Fetch New Firmware</h3>
    <form method="post" action="/fetch">
        Board keyword (optional): <input type="text" name="keyword">
        <input type="submit" value="Fetch latest">
    </form>
    <br>
    <a href="/fetch-status">View last fetch log</a>
    """

@app.route('/fetch-status')
def fetch_status():
    return "<pre>" + "\n".join(fetch_logs[-50:]) + "</pre>"

@app.route('/fetch', methods=['POST'])
def fetch():
    keyword = request.form.get('keyword', '').strip()
    fetch_logs.clear()
    run_fetch(keyword)
    return redirect(url_for('index'))

@app.route('/<path:filename>')
def serve_file(filename):
    filepath = os.path.join(STATIC_DIR, filename)
    if not os.path.isfile(filepath):
        return "File not found", 404
    return throttle_file_send(filepath, bw_limit_kbps=app.config.get("bw_limit_kbps", DEFAULT_BW_LIMIT))

# ─── Throttled File Sender ──────────────────────────────────────────────
def throttle_file_send(path, bw_limit_kbps):
    chunk_size = 1024  # bytes
    delay = chunk_size / (bw_limit_kbps * 1024.0)

    def generate():
        with open(path, 'rb') as f:
            while True:
                chunk = f.read(chunk_size)
                if not chunk:
                    break
                yield chunk
                time.sleep(delay)

    return Response(generate(), mimetype='application/octet-stream')

# ─── Firmware Fetching ──────────────────────────────────────────────────
def run_fetch(keyword):
    api_url = "https://api.github.com/repos/OpenIPC/builder/releases/latest"

    try:
        output = subprocess.check_output(['curl', '-s', api_url], text=True)
    except subprocess.CalledProcessError:
        fetch_logs.append("Failed to contact GitHub API.")
        return

    urls = []
    for line in output.splitlines():
        if '"browser_download_url"' in line and 'fpv' in line and '.tgz' in line:
            url = line.split('"')[3]
            if not keyword or keyword in url:
                urls.append(url)

    if not urls:
        fetch_logs.append("No matching firmware found.")
        return

    for url in urls:
        filename = os.path.basename(url)
        dest = os.path.join(STATIC_DIR, filename)
        fetch_logs.append(f"Downloading: {filename}")
        try:
            subprocess.run(['wget', '-O', dest, url], check=True)
            fetch_logs.append(f"Success: {filename}")
        except subprocess.CalledProcessError:
            fetch_logs.append(f"Failed: {filename}")

# ─── Entrypoint ─────────────────────────────────────────────────────────
if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="FPV Firmware Flask Server")
    parser.add_argument('--bw-limit', type=int, default=DEFAULT_BW_LIMIT,
                        help='Limit served download bandwidth in KB/s (default: 1024)')
    args = parser.parse_args()

    app.config["bw_limit_kbps"] = args.bw_limit
    print(f"[INFO] Serving firmware with bandwidth limit: {args.bw_limit} KB/s")
    app.run(host='0.0.0.0', port=81)
