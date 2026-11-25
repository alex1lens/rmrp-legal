import json
import sys
from pathlib import Path

def validate(data):
    if data.get("server") != "Тверской":
        raise ValueError("Wrong server")
    rows = data.get("articles")
    if not isinstance(rows, list) or not rows:
        raise ValueError("Empty database")
    seen = set()
    for row in rows:
        for key in ("id", "document", "number", "text", "source", "status"):
            if not isinstance(row.get(key), str) or not row[key].strip():
                raise ValueError(f"Missing {key}")
        if row["id"] in seen:
            raise ValueError("Duplicate article")
        seen.add(row["id"])
        if row["status"] != "active":
            raise ValueError("Non-active article")
        if not row["source"].startswith("https://"):
            raise ValueError("Invalid source")
        if not isinstance(row.get("sanctions"), list):
            raise ValueError("Missing sanctions field")
    return len(rows)

if __name__ == "__main__":
    print("Validated:", validate(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))))
