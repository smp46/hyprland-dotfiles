#!/usr/bin/env python3
import sys
import os
import subprocess
import json

def get_file_icon(path, is_dir):
    if is_dir:
        return "folder"
    ext = os.path.splitext(path)[1].lower().lstrip(".")
    if ext in ["jpg", "jpeg", "png", "gif", "webp", "svg", "bmp", "ico"]:
        return "image"
    if ext in ["mp4", "mkv", "avi", "mov", "webm", "flv"]:
        return "video_file"
    if ext in ["mp3", "wav", "flac", "ogg", "m4a", "opus", "aac"]:
        return "audio_file"
    if ext in ["pdf"]:
        return "picture_as_pdf"
    if ext in ["zip", "tar", "gz", "bz2", "xz", "7z", "rar", "zst"]:
        return "folder_zip"
    if ext in ["sh", "bash", "zsh", "fish", "py", "rs", "go", "js", "ts", "c", "cpp", "h", "hpp", "lua", "qml", "json", "yaml", "yml", "toml", "conf", "css", "html", "rasi"]:
        return "code"
    if ext in ["txt", "md", "org", "rst", "csv"]:
        return "article"
    if ext in ["doc", "docx", "odt", "rtf", "xls", "xlsx", "ods", "ppt", "pptx"]:
        return "description"
    return "description"

def search_files(query, max_results=15):
    query = query.strip()
    if not query:
        return []

    # Clean leading ~ or ~/
    if query.startswith("~/"):
        query = query[2:].strip()
    elif query.startswith("~"):
        query = query[1:].strip()
    elif query.startswith("/home/smp/"):
        query = query[len("/home/smp/"):].strip()
    elif query.startswith("/"):
        query = query[1:].strip()

    if not query:
        return []

    home = "/home/smp"
    results = []
    seen = set()

    ignore_patterns = [
        "/.cache/", "/.git/", "/node_modules/", "/.cargo/", "/go/pkg/",
        "/.gemini/", "/.rustup/", "/.var/app/", "/.local/share/Trash/",
        "/.local/state/nvim/", "/.local/state/nvim.bak/", "/undo/", "/__pycache__/",
        "/.venv/", "/venv/", "/.local/state/wireplumber/"
    ]

    # 1. Fast indexed search via plocate
    try:
        proc = subprocess.run(
            ["plocate", "-i", home, query],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=0.35
        )
        for line in proc.stdout.splitlines():
            p = line.strip()
            if not p or any(ig in p for ig in ignore_patterns):
                continue
            if p not in seen and os.path.exists(p):
                seen.add(p)
                results.append(p)
                if len(results) >= max_results * 2:
                    break
    except Exception:
        pass

    # 2. Fast live fallback/supplement via fd if plocate yielded few results
    if len(results) < max_results:
        try:
            fd_cmd = [
                "fd", "-H", "--max-results", str(max_results * 2),
                "-E", ".cache", "-E", ".git", "-E", "node_modules", "-E", ".cargo",
                "-E", "go", "-E", ".gemini", "-E", ".var", "-E", ".rustup",
                "-E", ".local/share/Trash", "-E", ".local/state/nvim",
                query, home
            ]
            proc = subprocess.run(
                fd_cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=0.5
            )
            for line in proc.stdout.splitlines():
                p = line.strip()
                if p not in seen and os.path.exists(p):
                    seen.add(p)
                    results.append(p)
                    if len(results) >= max_results * 2:
                        break
        except Exception:
            pass

    # Scoring and ranking
    q_lower = query.lower()

    def score(p):
        base = os.path.basename(p).lower()
        base_no_ext = os.path.splitext(base)[0]
        # Priority 0: Exact match
        if base == q_lower or base_no_ext == q_lower:
            rank = 0
        # Priority 1: Starts with query
        elif base.startswith(q_lower):
            rank = 1
        # Priority 2: Basename contains query
        elif q_lower in base:
            rank = 2
        # Priority 3: Path contains query
        else:
            rank = 3
        return (rank, len(p), p)

    results.sort(key=score)
    top_results = results[:max_results]

    items = []
    for p in top_results:
        is_dir = os.path.isdir(p)
        name = os.path.basename(p) or p
        parent_dir = os.path.dirname(p)
        if parent_dir.startswith(home):
            rel_dir = "~" + parent_dir[len(home):]
        else:
            rel_dir = parent_dir

        items.append({
            "name": name,
            "path": p,
            "dir": rel_dir,
            "isDir": is_dir,
            "icon": get_file_icon(p, is_dir),
            "ext": os.path.splitext(p)[1].lower().lstrip(".")
        })

    return items

def main():
    if len(sys.argv) < 2:
        print("[]")
        return
    query = sys.argv[1]
    max_res = 15
    if len(sys.argv) >= 3:
        try:
            max_res = int(sys.argv[2])
        except ValueError:
            pass
    items = search_files(query, max_res)
    print(json.dumps(items))

if __name__ == "__main__":
    main()
