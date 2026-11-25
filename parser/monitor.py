"""Monitor reviewed forum URLs. Never publish articles automatically."""
import hashlib
import json
import pathlib
import urllib.request
import urllib.parse
from html.parser import HTMLParser

ROOT = pathlib.Path(__file__).resolve().parent.parent

class Text(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []
    def handle_data(self, data):
        self.parts.append(data.strip())

def main():
    config = json.loads((ROOT / "parser/sources.json").read_text())
    report = []
    for source in config["sources"]:
        url = source["url"]
        parsed = urllib.parse.urlparse(url)
        if parsed.scheme != "https" or parsed.hostname != "forum.rmrp.ru":
            raise ValueError("Unexpected source URL")
        request = urllib.request.Request(url, headers={"User-Agent": "RMRP-Legal-SourceMonitor/1.0"})
        with urllib.request.urlopen(request, timeout=30) as response:
            if urllib.parse.urlparse(response.geturl()).hostname != "forum.rmrp.ru":
                raise ValueError("Unexpected redirect")
            raw = response.read(8_000_001)
        if len(raw) > 8_000_000:
            raise ValueError("Response too large")
        parser = Text()
        parser.feed(raw.decode("utf-8"))
        body = " ".join(parser.parts)
        if "Статья" not in body or len(body) < 5000:
            raise ValueError("Incomplete or blocked source")
        report.append({"document":source["document"],"url":url,"sha256":hashlib.sha256(raw).hexdigest(),"status":"review_required"})
    if not report:
        raise ValueError("No configured sources")
    (ROOT / "source-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print("Source checks completed; publication remains disabled.")

if __name__ == "__main__":
    main()
