import os
from datetime import datetime, timezone

from flask import Flask, jsonify


app = Flask(__name__)


@app.get("/")
def root() -> tuple:
    return (
        jsonify(
            {
                "service": os.getenv("K_SERVICE", "ai-agent-runtime"),
                "status": "placeholder-runtime",
                "message": "Minimal Cloud Run runtime is active.",
                "environment": {
                    "port": os.getenv("PORT", "8080"),
                    "revision": os.getenv("K_REVISION", "unknown"),
                    "configuration": os.getenv("K_CONFIGURATION", "unknown"),
                },
                "timestamp_utc": datetime.now(timezone.utc).isoformat(),
            }
        ),
        200,
    )


@app.get("/health")
def health() -> tuple:
    return jsonify({"ok": True, "status": "healthy"}), 200


if __name__ == "__main__":
    port = int(os.getenv("PORT", "8080"))
    app.run(host="0.0.0.0", port=port)
