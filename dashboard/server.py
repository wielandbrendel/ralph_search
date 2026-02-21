#!/usr/bin/env python3
"""Ralph Search Dashboard — Live monitoring for iterative research."""

import argparse
import json
import os
import re
from datetime import datetime
from pathlib import Path

import markdown
import yaml
from flask import Flask, jsonify, render_template, abort

app = Flask(__name__)
app.config["DOSSIER_FOLDER"] = None


# =============================================================================
# Dossier Directory Detection
# =============================================================================

def detect_dossier_dir(folder: str) -> str | None:
    """Find the dossier subdirectory inside a search folder.

    Strategy mirrors ralph_search.sh: prefer 'dossiers/', else pick the
    subdirectory (excluding logs/ and docs/) with the most .md files.
    """
    folder = Path(folder)
    if not folder.is_dir():
        return None

    best_dir = None
    best_count = 0

    for d in sorted(folder.iterdir()):
        if not d.is_dir():
            continue
        name = d.name
        if name in ("logs", "docs", "dashboard") or "backup" in name.lower():
            continue

        if name == "dossiers":
            return str(d)

        count = len(list(d.glob("*.md")))
        if count > best_count:
            best_count = count
            best_dir = d

    if best_dir is None:
        # Fallback: first non-excluded directory
        for d in sorted(folder.iterdir()):
            if d.is_dir() and d.name not in ("logs", "docs", "dashboard") and "backup" not in d.name.lower():
                return str(d)

    return str(best_dir) if best_dir else None


# =============================================================================
# Dossier Parsing
# =============================================================================

def parse_yaml_frontmatter(content: str) -> tuple[dict | None, str]:
    """Extract YAML frontmatter from markdown content.

    Returns (metadata_dict, remaining_content) or (None, full_content).
    """
    if not content.startswith("---"):
        return None, content

    parts = content.split("---", 2)
    if len(parts) < 3:
        return None, content

    try:
        meta = yaml.safe_load(parts[1])
        if isinstance(meta, dict):
            return meta, parts[2]
    except yaml.YAMLError:
        pass

    return None, content


def parse_regex_fallback(content: str) -> dict:
    """Parse dossier metadata from markdown using regex.

    Handles legacy dossiers without YAML frontmatter (e.g. pizza oven dossiers).
    Extracts: name, date, priority_score, recommendation, summary, scores.
    """
    meta = {}

    # Extract name from title: # ... Dossier: Name
    m = re.search(r"^#\s+.*?Dossier:\s*(.+)$", content, re.MULTILINE)
    if m:
        meta["name"] = m.group(1).strip()

    # Extract date
    m = re.search(r"\*\*Research Date:\*\*\s*(\S+)", content)
    if m:
        meta["date"] = m.group(1).strip()

    # Extract priority score
    m = re.search(r"\*\*Priority Score:\*\*\s*(\d+)\s*/\s*10", content)
    if m:
        meta["priority_score"] = int(m.group(1))

    # Extract recommendation
    m = re.search(r"\*\*Recommendation:\*\*\s*(.+)", content)
    if m:
        meta["recommendation"] = m.group(1).strip()

    # Extract summary (first paragraph after ## Summary)
    m = re.search(r"##\s+Summary\s*\n+((?:(?!^---|\n##).)+)", content, re.MULTILINE | re.DOTALL)
    if m:
        meta["summary"] = m.group(1).strip()

    # Extract scores from assessment table
    # Matches rows like: | Criterion Name | 8/10 | Comment text |
    # Also handles bold OVERALL row: | **OVERALL** | **9/10** | **comment** |
    scores = []
    assessment_match = re.search(
        r"##\s+(?:Suitability )?Assessment\s*\n(.*?)(?:\n---|\n##|\Z)",
        content,
        re.DOTALL,
    )
    if assessment_match:
        table_text = assessment_match.group(1)
        # Parse line by line for robustness
        for line in table_text.split("\n"):
            line = line.strip()
            if not line.startswith("|"):
                continue
            # Split by | and filter empty parts
            cells = [c.strip() for c in line.split("|")]
            cells = [c for c in cells if c]  # remove empty from leading/trailing |
            if len(cells) < 3:
                continue
            # Extract score from second cell: "8/10" or "**8/10**"
            score_cell = cells[1].strip("* ")
            score_match = re.match(r"(\d+)\s*/\s*10", score_cell)
            if not score_match:
                continue
            criterion = cells[0].strip("* ").strip()
            score_val = int(score_match.group(1))
            comment = cells[2].strip("* ").strip()
            # Skip header row and separator
            if criterion.lower() in ("criterion", "score (0-10)", "---"):
                continue
            scores.append({"criterion": criterion, "score": score_val, "comment": comment})

    if scores:
        meta["scores"] = scores

    return meta


def parse_dossier(filepath: str) -> dict:
    """Parse a dossier .md file, returning metadata + raw content.

    Tries YAML frontmatter first, falls back to regex parsing.
    """
    path = Path(filepath)
    content = path.read_text(encoding="utf-8")

    yaml_meta, body = parse_yaml_frontmatter(content)

    if yaml_meta:
        meta = yaml_meta
        meta["_source"] = "yaml"
    else:
        meta = parse_regex_fallback(content)
        meta["_source"] = "regex"
        body = content

    # Ensure a name exists
    if "name" not in meta or not meta["name"]:
        meta["name"] = path.stem.replace("_", " ").title()

    meta["_filename"] = path.name
    meta["_body"] = body

    return meta


# =============================================================================
# Data Collection
# =============================================================================

def get_search_metadata(folder: str) -> dict:
    """Get high-level metadata about the search folder."""
    folder = Path(folder)
    info = {
        "folder_name": folder.name,
        "folder_path": str(folder),
    }

    # Read search title from prompt.md first line
    prompt_path = folder / "prompt.md"
    if prompt_path.exists():
        first_line = prompt_path.read_text(encoding="utf-8").split("\n", 1)[0]
        info["title"] = first_line.lstrip("# ").strip()
    else:
        info["title"] = folder.name

    # Count log files
    logs_dir = folder / "logs"
    if logs_dir.is_dir():
        log_files = sorted(logs_dir.glob("session_*.log"), reverse=True)
        info["session_count"] = len(log_files)
        if log_files:
            # Parse timestamp from filename: session_YYYYMMDD_HHMMSS.log
            latest = log_files[0].stem  # session_YYYYMMDD_HHMMSS
            ts = latest.replace("session_", "")
            try:
                info["last_session"] = datetime.strptime(ts, "%Y%m%d_%H%M%S").strftime(
                    "%Y-%m-%d %H:%M"
                )
            except ValueError:
                info["last_session"] = ts
    else:
        info["session_count"] = 0

    return info


def get_all_dossiers(folder: str) -> list[dict]:
    """Load and parse all dossiers in the search folder."""
    dossier_dir = detect_dossier_dir(folder)
    if not dossier_dir:
        return []

    dossiers = []
    for md_file in sorted(Path(dossier_dir).glob("*.md")):
        if md_file.name.startswith("DOSSIER_TEMPLATE") or md_file.name.startswith("_"):
            continue
        try:
            dossier = parse_dossier(str(md_file))
            dossiers.append(dossier)
        except Exception:
            continue

    # Sort by priority_score descending
    dossiers.sort(key=lambda d: d.get("priority_score", 0), reverse=True)
    return dossiers


def collect_all_criteria(dossiers: list[dict]) -> list[str]:
    """Collect unique criterion names across all dossiers, preserving order."""
    seen = set()
    criteria = []
    for d in dossiers:
        for s in d.get("scores", []):
            c = s["criterion"]
            if c.upper() != "OVERALL" and c not in seen:
                seen.add(c)
                criteria.append(c)
    return criteria


# =============================================================================
# Template Filters
# =============================================================================

def score_color(score: int | None) -> str:
    """Return an HSL color string for a 0-10 score (red -> green)."""
    if score is None:
        return "hsl(0, 0%, 75%)"
    score = max(0, min(10, score))
    hue = score * 12  # 0 = red (0), 10 = green (120)
    return f"hsl({hue}, 70%, 42%)"


def recommendation_class(rec: str | None) -> str:
    """Return a CSS class for the recommendation tier."""
    if not rec:
        return "rec-unknown"
    rec_lower = rec.lower()
    if "excellent" in rec_lower:
        return "rec-excellent"
    if "good" in rec_lower:
        return "rec-good"
    if "decent" in rec_lower:
        return "rec-decent"
    if "weak" in rec_lower:
        return "rec-weak"
    if "not suitable" in rec_lower:
        return "rec-unsuitable"
    return "rec-unknown"


app.jinja_env.filters["score_color"] = score_color
app.jinja_env.filters["recommendation_class"] = recommendation_class


# =============================================================================
# Routes
# =============================================================================

@app.route("/")
def overview():
    folder = app.config["DOSSIER_FOLDER"]
    meta = get_search_metadata(folder)
    dossiers = get_all_dossiers(folder)
    criteria = collect_all_criteria(dossiers)
    return render_template(
        "overview.html",
        meta=meta,
        dossiers=dossiers,
        criteria=criteria,
    )


@app.route("/dossier/<filename>")
def detail(filename: str):
    folder = app.config["DOSSIER_FOLDER"]
    dossier_dir = detect_dossier_dir(folder)
    if not dossier_dir:
        abort(404)

    filepath = Path(dossier_dir) / filename
    if not filepath.exists() or not filepath.suffix == ".md":
        abort(404)

    dossier = parse_dossier(str(filepath))

    # Render markdown body to HTML
    body_html = markdown.markdown(
        dossier["_body"],
        extensions=["tables", "fenced_code", "toc"],
    )

    return render_template(
        "detail.html",
        dossier=dossier,
        body_html=body_html,
        meta=get_search_metadata(folder),
    )


@app.route("/api/dossiers")
def api_dossiers():
    folder = app.config["DOSSIER_FOLDER"]
    meta = get_search_metadata(folder)
    dossiers = get_all_dossiers(folder)
    criteria = collect_all_criteria(dossiers)

    # Strip _body for API response (too large)
    dossiers_slim = []
    for d in dossiers:
        slim = {k: v for k, v in d.items() if k != "_body"}
        dossiers_slim.append(slim)

    return jsonify({
        "meta": meta,
        "dossiers": dossiers_slim,
        "criteria": criteria,
        "timestamp": datetime.now().isoformat(),
    })


# =============================================================================
# CLI
# =============================================================================

def main():
    parser = argparse.ArgumentParser(description="Ralph Search Dashboard")
    parser.add_argument("--folder", required=True, help="Path to the search folder")
    parser.add_argument("--port", type=int, default=8420, help="Port (default: 8420)")
    parser.add_argument("--host", default="0.0.0.0", help="Host (default: 0.0.0.0)")
    args = parser.parse_args()

    folder = os.path.abspath(args.folder)
    if not os.path.isdir(folder):
        print(f"Error: folder not found: {folder}")
        raise SystemExit(1)

    app.config["DOSSIER_FOLDER"] = folder

    dossier_dir = detect_dossier_dir(folder)
    dossier_count = len(list(Path(dossier_dir).glob("*.md"))) if dossier_dir else 0

    print(f"\n  Ralph Search Dashboard")
    print(f"  {'=' * 40}")
    print(f"  Folder:   {os.path.basename(folder)}")
    print(f"  Dossiers: {dossier_count}")
    print(f"  URL:      http://localhost:{args.port}")
    print(f"  {'=' * 40}\n")

    app.run(host=args.host, port=args.port, debug=False)


if __name__ == "__main__":
    main()
