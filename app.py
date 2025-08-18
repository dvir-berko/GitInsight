from flask import Flask, request, jsonify
import os, json, time
import requests

app = Flask(__name__)
DATA_FILE = os.environ.get("DATA_FILE", "insights.json")

GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "")
HEADERS = {
    "Accept": "application/vnd.github+json",
    **({"Authorization": f"Bearer {GITHUB_TOKEN}"} if GITHUB_TOKEN else {}),
}

# Ensure data file exists
if not os.path.exists(DATA_FILE):
    with open(DATA_FILE, "w") as f:
        json.dump({
            "repo": None,
            "branch": None,
            "updated_at": None,
            "summary": {"commits": 0, "additions": 0, "deletions": 0, "files_changed": 0},
            "commits": []
        }, f, indent=2)

def fetch_repo_insights(repo: str, branch: str = "main", limit: int = 10):
    base = f"https://api.github.com/repos/{repo}"
    commits_url = f"{base}/commits"

    r = requests.get(commits_url, params={"sha": branch, "per_page": limit}, headers=HEADERS, timeout=30)
    r.raise_for_status()
    commit_list = r.json()

    items = []
    add_sum = del_sum = files_sum = 0

    for c in commit_list:
        sha = c.get("sha")
        msg = (c.get("commit", {}).get("message") or "").split("\n")[0]
        author = c.get("commit", {}).get("author", {}).get("name")
        date = c.get("commit", {}).get("author", {}).get("date")

        # Fetch per-commit stats
        d = requests.get(f"{base}/commits/{sha}", headers=HEADERS, timeout=30)
        d.raise_for_status()
        det = d.json()
        stats = det.get("stats", {})
        additions = stats.get("additions", 0)
        deletions = stats.get("deletions", 0)
        files_changed = len(det.get("files", []) or [])

        add_sum += additions
        del_sum += deletions
        files_sum += files_changed

        items.append({
            "sha": sha,
            "message": msg,
            "author": author,
            "date": date,
            "additions": additions,
            "deletions": deletions,
            "files_changed": files_changed,
        })

    snapshot = {
        "repo": repo,
        "branch": branch,
        "updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "summary": {
            "commits": len(items),
            "additions": add_sum,
            "deletions": del_sum,
            "files_changed": files_sum,
        },
        "commits": items,
    }
    return snapshot

@app.route("/insights", methods=["GET", "POST"])
def insights():
    # GET supports optional live fetch via query params
    if request.method == "GET":
        repo = request.args.get("repo")
        branch = request.args.get("branch", "main")
        limit = int(request.args.get("limit", 10))
        refresh = request.args.get("refresh", "false").lower() in ("true", "1", "yes")

        if repo and refresh:
            try:
                snapshot = fetch_repo_insights(repo, branch, limit)
                with open(DATA_FILE, "w") as f:
                    json.dump(snapshot, f, indent=2)
                return jsonify(snapshot), 200
            except Exception as e:
                return jsonify({"error": str(e)}), 400

        # Otherwise return last saved snapshot
        try:
            with open(DATA_FILE, "r") as f:
                data = json.load(f)
            return jsonify(data), 200
        except Exception as e:
            return jsonify({"error": f"Failed to read {DATA_FILE}: {e}"}), 500

    # POST always does a fresh fetch and saves it
    try:
        body = request.get_json(force=True)
        repo = body.get("repo")
        if not repo or "/" not in repo:
            return jsonify({"error": "Provide 'repo' as 'owner/name'"}), 400
        branch = body.get("branch", "main")
        limit = int(body.get("limit", 10))

        snapshot = fetch_repo_insights(repo, branch, limit)
        with open(DATA_FILE, "w") as f:
            json.dump(snapshot, f, indent=2)
        return jsonify(snapshot), 201
    except Exception as e:
        return jsonify({"error": str(e)}), 400

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)