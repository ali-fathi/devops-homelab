from flask import Flask, jsonify
import os

app = Flask(__name__)


@app.route("/")
def index():
    return jsonify({
        "app": "homelab-api",
        "status": "ok",
        "version": os.environ.get("APP_VERSION", "dev")
    })


@app.route("/healthz")
def healthz():
    return jsonify({
        "status": "healthy"
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
