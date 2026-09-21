from flask import Flask, request, jsonify
import json, base64, requests, datetime, os

app = Flask(__name__)

GITHUB_TOKEN = os.getenv("GITHUB_TOKEN", "")
GITHUB_USERNAME = "khantthuaun1813-dotcom"
GITHUB_REPO = "Khant"
GITHUB_FILE_PATH = "keylist.json"
GITHUB_BRANCH = "main"
GITHUB_API_URL = f"https://api.github.com/repos/{GITHUB_USERNAME}/{GITHUB_REPO}/contents/{GITHUB_FILE_PATH}"

def load_keys():
    try:
        headers = {"Authorization": f"token {GITHUB_TOKEN}",
                   "Accept": "application/vnd.github.v3+json"}
        r = requests.get(GITHUB_API_URL, headers=headers, timeout=10)
        if r.status_code == 200:
            content = base64.b64decode(r.json()["content"]).decode()
            return json.loads(content)
        return {}
    except:
        return {}

@app.route("/lua/check_vip_key.php", methods=["POST"])
def check_vip_key():
    try:
        key = (request.form.get("key") or "").strip().upper()
        hwid = (request.form.get("hwid") or "").strip()
        if not key:
            return jsonify({"status": False, "msg": "Missing key"})
        keys = load_keys()
        if key not in keys:
            return jsonify({"status": False, "msg": "Invalid key"})
        entry = keys[key]
        if not entry.get("active", True):
            return jsonify({"status": False, "msg": "Key banned"})
        try:
            expiry = datetime.datetime.fromisoformat(entry["expiry"])
            if datetime.datetime.now() > expiry:
                return jsonify({"status": False, "msg": "Key expired"})
        except:
            pass
        return jsonify({"status": True, "type": entry.get("type", "VIP")})
    except Exception as e:
        return jsonify({"status": False, "msg": str(e)})

@app.route("/", methods=["GET"])
def health():
    return jsonify({"status": "ok"})

if __name__ == "__main__":
    port = int(os.getenv("PORT", 5000))
    app.run(host="0.0.0.0", port=port)
