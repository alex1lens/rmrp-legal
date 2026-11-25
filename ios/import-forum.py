import concurrent.futures
import json
import pathlib
import re
import urllib.request
from html.parser import HTMLParser

import sys

root = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parent / "RMRPLegal-iOS"
destination = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else None
source = root / "Sources" / "RMRPLegal"
registry = json.loads((source / "Registry.json").read_text(encoding="utf-8"))
supplemental = json.loads((source / "Supplemental.json").read_text(encoding="utf-8"))
category = ["Законы", "УК", "КоАП", "ПК", "УПК"]
void = set("area base br col embed hr img input link meta param source track wbr".split())
blocks = set("br hr div p li ul ol blockquote pre tr td h1 h2 h3 h4 h5 h6".split())


class Post(HTMLParser):
    def __init__(self):
        super().__init__()
        self.stack = []
        self.started = False
        self.done = False
        self.parts = []

    def handle_starttag(self, tag, attrs):
        if self.done:
            return
        classes = dict(attrs).get("class", "").split()
        if not self.started:
            if tag == "div" and "bbWrapper" in classes:
                self.started = True
                self.stack.append((tag, False))
            return
        skipped = any(x[1] for x in self.stack) or tag in {"script", "style", "button", "s", "del", "strike"} or bool(set(classes) & {"postToc", "js-expandLink", "bbCodeBlock-expandLink", "u-anchorTarget"})
        if not skipped and tag in blocks:
            self.parts.append("\n")
        if tag not in void:
            self.stack.append((tag, skipped))

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag not in void:
            self.handle_endtag(tag)

    def handle_endtag(self, tag):
        if not self.started or self.done or tag in void:
            return
        for index in range(len(self.stack) - 1, -1, -1):
            if self.stack[index][0] == tag:
                if not self.stack[index][1] and tag in blocks:
                    self.parts.append("\n")
                del self.stack[index:]
                self.done = not self.stack
                return

    def handle_data(self, data):
        if self.started and not self.done and not any(x[1] for x in self.stack):
            self.parts.append(data)


heading = re.compile(r"(?im)^\s*стать[яи]\s+(\d+(?:[.\-–]\d+)*)(?:\.(?!\d))?[ \t]*[:.]?[ \t]*([^\n]*)")
rule_heading = re.compile(r"(?im)^[ \t]*(\d+(?:\.\d+)+)\.?[ \t]*()(?=[ \t\S]*$)")
section = re.compile(r"(?im)^(?:раздел|глава|часть)\s+(?:[IVXLCDM]+|\d+)\s*[.\-:]")
signature = re.compile(r"(?im)^\s*(?:Президент Российской Федерации|Москва, Кремль)\s*(?:$|\n)")
sanction = re.compile(r"(?i)\b(?:наказыва(?:ется|ются)|влеч[её]т|влекут|штраф\s+(?:в размере|от)|административный штраф|назначается наказание)\b")


def parse(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=22) as response:
        if not response.geturl().startswith("https://forum.rmrp.ru/"):
            raise ValueError("unexpected redirect")
        parser = Post()
        html = response.read().decode("utf-8")
        if post := re.search(r"/post-(\d+)$", url):
            marker = re.search(r'<article\b[^>]*\bid=["\']js-post-' + post[1] + r'["\']', html)
            if not marker:
                raise ValueError(f"missing post: {url}")
            html = html[marker.start():]
        parser.feed(html)
    raw = "".join(parser.parts).replace("\u200b", "").replace("\xa0", " ")
    clean = "\n".join(re.sub(r"[ \t]+", " ", line).strip() for line in raw.splitlines())
    clean = re.sub(r"\n{3,}", "\n\n", clean).strip()
    if len(clean) < 25 or not parser.done:
        raise ValueError(f"incomplete document: {url}")
    return clean


def prepare(item):
    i, law = item
    url = law["url"]
    full = parse(url)
    if law["id"] == "58190":
        full += "\n\n" + parse(law["attachments"][0])
    matches = list((rule_heading if law.get("category") in ("Правила", "Уставы") and not heading.search(full) else heading).finditer(full))
    rows = []
    seen = {}
    doc = law["title"]
    group = law.get("category") or (category[i] if i < len(category) else "Законы")

    def row(number, title, body, suffix, penalty=""):
        return dict(id=f'forum-{law["id"]}-{suffix}', category=group, document=doc, number=number,
                    title=title, body=body, penalty=penalty, url=url, tags="официальный текст")

    rows.append(row("", "Полный текст акта", full, "full"))
    for index, match in enumerate(matches):
        number, title = match.group(1), match.group(2).strip()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(full)
        body = full[match.end():end].strip()
        if boundary := section.search(body):
            body = body[:boundary.start()].strip()
        if boundary := signature.search(body):
            body = body[:boundary.start()].strip()
        if not body or re.match(r"(?i)^(?:утратил[аои]? силу|отменен[ао]?)\b", title or body):
            continue
        parts = []
        latest_part = ""
        for line in body.splitlines():
            if part := re.match(r"^(\d+(?:[.\-]\d+)+)\.", line):
                latest_part = part.group(1)
            if group in ("УК", "КоАП") and sanction.search(line):
                parts.append(f"{latest_part} · {line}" if latest_part and not line.startswith(latest_part) else line)
            if group == "Правила":
                parts.extend(re.findall(r"\[([^\[\]]+)\]", line))
        seen[number] = seen.get(number, 0) + 1
        rows.append(row(number, title, body, f"{number}-{seen[number]}", "\n".join(dict.fromkeys(parts))))
    return rows


def optional(item):
    try:
        return prepare(item)
    except (OSError, ValueError) as error:
        print("Unavailable:", item[1]["url"], error)
        if destination and destination.exists():
            previous = json.loads(destination.read_text(encoding="utf-8"))
            prefix = f'forum-{item[1]["id"]}-'
            return [row for row in previous if row["id"].startswith(prefix)]
        return []

with concurrent.futures.ThreadPoolExecutor(max_workers=7) as pool:
    chunks = list(pool.map(prepare, enumerate(registry)))
    extra = list(pool.map(optional, enumerate(supplemental, start=len(registry))))
articles = [record for chunk in chunks + extra for record in chunk]
assert len(chunks) == 31 and len({r["id"] for r in articles}) == len(articles)
assert sum(bool(r["penalty"]) for r in articles if r["category"] == "УК") >= 40
assert sum(bool(r["penalty"]) for r in articles if r["category"] == "КоАП") >= 25
output = destination or source / "articles.json"
output.parent.mkdir(parents=True, exist_ok=True)
temp = output.with_suffix(".tmp")
temp.write_text(json.dumps(articles, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
temp.replace(output)
for chunk in chunks + [x for x in extra if x]:
    print(chunk[0]["id"], len(chunk)-1, sum(bool(r["penalty"]) for r in chunk))
print("TOTAL", len(articles))

