# serve_config.py

from flask import Flask, request, send_file
import os
import logging
from datetime import datetime

# Configure logging to show INFO-level messages with timestamp and formatting  
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)

# CORRECTED: Use __name__ (double underscores)
app = Flask(__name__)

# Base and config directory paths
# CORRECTED: Use __file__ (double underscores)
this_dir = os.path.dirname(__file__)
# This line assumes Dockerfile places configs in /app/config_files/
CONFIG_DIR = os.path.join(this_dir, "config_files")

@app.route("/cooker_config.json")
def serve_cooker_config():
    config_path = os.path.join(CONFIG_DIR, "cooker_config.json")
    if not os.path.exists(config_path):
        app.logger.error(f"File not found: {config_path}")
        return "Config file not found", 404
    return send_file(config_path, mimetype="application/json")

@app.route("/eiot_config.json")
def serve_eiot_config():
    config_path = os.path.join(CONFIG_DIR, "eiot_config.json")
    if not os.path.exists(config_path):
        app.logger.error(f"File not found: {config_path}")
        return "Config file not found", 404
    return send_file(config_path, mimetype="application/json")

@app.route("/pico_iot_config.json")
def serve_pico_iot_config():
    config_path = os.path.join(CONFIG_DIR, "pico_iot_config.json")
    if not os.path.exists(config_path):
        app.logger.error(f"File not found: {config_path}")
        return "Config file not found", 404
    return send_file(config_path, mimetype="application/json")

# Add a simple test endpoint that's easy to check
@app.route("/ping")
def ping():
    app.logger.info(f"Ping request from IP: {request.remote_addr}")
    return "pong", 200

# CORRECTED: Use __name__ and "__main__" (double underscores)
if __name__ == "__main__":
    # This block is mainly for direct execution (python serve_config.py)
    # Gunicorn uses the 'app' object directly.
    app.logger.info("Flask development server starting on 0.0.0.0:5000")
    app.run(host="0.0.0.0", port=5000)