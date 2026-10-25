#!/usr/bin/env python3
import sys
import os
import subprocess
import json

HOME = os.path.expanduser("~")

FD_EXCLUDES = [
    ".cache", ".git", "node_modules", ".cargo", "go", ".gemini", ".var", ".rustup",
    ".local/share/Trash", ".local/state", ".local/share/Steam", ".local/share/containers",
    ".local/share/flatpak", ".local/share/nvim", ".local/share/nvim.bak",
    ".local/share/Anki2", ".local/share/AnkiProgramFiles", ".local/share/firefoxpwa",
    ".local/share/nvm", ".local/share/uv", ".local/lib",
    ".cabal", ".ghcup", ".minecraft", ".docker", ".android", ".dotnet", ".java", ".npm",
    ".cursor", ".copilot", ".claude", ".mozilla", ".thunderbird", ".zoom",
    ".gradle", ".m2", ".ivy2", ".sbt", ".wine", ".vscode", ".nvm", ".oh-my-zsh",
    "google-chrome", "google-chrome-canary", "google-chrome-headless", "BeeperTexts",
    "CurseForge", "Code", "Cursor", "balenaEtcher",
    "__pycache__", ".venv", "venv", "target", "dist", "build",
    "gdrive", "VMs", "migration_backup", "ii-original-dots-backup", "recup_dir.*"
]

IGNORE_SUBSTRINGS = [
    "/.cache/", "/.git/", "/node_modules/", "/.cargo/", "/go/pkg/",
    "/.gemini/", "/.rustup/", "/.var/app/", "/.local/share/Trash/",
    "/.local/state/", "/.local/share/Steam/", "/.local/share/nvim",
    "/.local/share/Anki", "/.local/share/firefoxpwa/", "/.local/share/nvm/",
    "/.local/share/uv/", "/.cabal/", "/.ghcup/", "/.minecraft/", "/.docker/",
    "/.android/", "/.dotnet/", "/.java/", "/.npm/", "/.cursor/", "/.copilot/",
    "/.claude/", "/.mozilla/", "/.wine/", "/.vscode/", "/.nvm/", "/.oh-my-zsh/",
    "/google-chrome", "/BeeperTexts/", "/CurseForge/", "/.config/Code/",
    "/.config/Cursor/", "/__pycache__/", "/.venv/", "/venv/", "/gdrive/",
    "/VMs/", "/migration_backup/", "/ii-original-dots-backup/", "/recup_dir."
]

PRIORITY_DIRS = [
    "Desktop", "Documents", "Downloads", "Uni", "Pictures", "Videos",
    "Music", "Books", "hyprland-dotfiles", ".config"
]

def get_file_icon(path, is_dir):
    if is_dir:
        return "folder"
    ext = os.path.splitext(path)[1].lower().lstrip(".")
    if ext in ("jpg", "jpeg", "png", "gif", "webp", "svg", "bmp", "ico"):
        return "image"
    if ext in ("mp4", "mkv", "avi", "mov", "webm", "flv"):
        return "video_file"
    if ext in ("mp3", "wav", "flac", "ogg", "m4a", "opus", "aac"):
        return "audio_file"
    if ext == "pdf":
        return "picture_as_pdf"
    if ext in ("zip", "tar", "gz", "bz2", "xz", "7z", "rar", "zst"):
        return "folder_zip"
    if ext in ("sh", "bash", "zsh", "fish", "py", "rs", "go", "js", "ts", "c", "cpp", "h", "hpp", "lua", "qml", "json", "yaml", "yml", "toml", "conf", "css", "html", "rasi", "md"):
        return "code" if ext != "md" else "article"
    if ext in ("txt", "org", "rst", "csv"):
        return "article"
    return "description"

def format_item(p, is_dir=None):
    p = p.rstrip("/")
    if not p:
        p = "/"
    if is_dir is None:
        is_dir = os.path.isdir(p)
    name = os.path.basename(p) or p
    parent_dir = os.path.dirname(p)
    if parent_dir == HOME:
        rel_dir = "~"
    elif parent_dir.startswith(HOME + "/"):
        rel_dir = "~" + parent_dir[len(HOME):]
    else:
        rel_dir = parent_dir

    return {
        "name": name,
        "path": p,
        "dir": rel_dir,
        "isDir": is_dir,
        "icon": get_file_icon(p, is_dir),
        "ext": "" if is_dir else os.path.splitext(p)[1].lower().lstrip(".")
    }

def list_directory_entries(target_dir, prefix_filter="", max_results=15):
    try:
        entries = list(os.scandir(target_dir))
    except OSError:
        return []

    pf_lower = prefix_filter.lower()
    show_hidden = prefix_filter.startswith(".")

    matched = []
    for e in entries:
        name = e.name
        if not show_hidden and name.startswith(".") and name not in (".config", ".local"):
            continue
        if name in ("gdrive", "VMs", "migration_backup", "ii-original-dots-backup") and not pf_lower:
            continue
        if pf_lower and pf_lower not in name.lower():
            continue
        try:
            is_dir = e.is_dir()
        except OSError:
            is_dir = False
        matched.append((name, e.path, is_dir))

    def dir_score(item):
        name, path, is_dir = item
        n_lower = name.lower()
        if pf_lower:
            if n_lower == pf_lower:
                r = 0
            elif n_lower.startswith(pf_lower):
                r = 1
            else:
                r = 2
        else:
            if name in PRIORITY_DIRS:
                r = 0
            elif is_dir:
                r = 1
            else:
                r = 2
        return (r, not is_dir, n_lower)

    matched.sort(key=dir_score)
    return [format_item(p, is_dir) for _, p, is_dir in matched[:max_results]]

def search_files(raw_query, max_results=15):
    q = raw_query.strip()

    # Clean leading ~ or ~/
    if q in ("~", "~/"):
        q = ""
    elif q.startswith("~/"):
        q = q[2:].strip()
    elif q.startswith("~"):
        q = q[1:].strip()
    elif q.startswith(HOME + "/"):
        q = q[len(HOME) + 1:].strip()
    elif q == HOME:
        q = ""

    # 1. Empty query (user typed just `~` or `~/`): show top-level home folders/files immediately
    if not q:
        return list_directory_entries(HOME, "", max_results)

    # 2. Path navigation (e.g. `Downloads/`, `Downloads/foo`, `/etc/pacman`)
    if "/" in q:
        if raw_query.strip().startswith("/") and not raw_query.strip().startswith(HOME):
            full_target = "/" + q.lstrip("/")
        else:
            full_target = os.path.join(HOME, q.lstrip("/"))

        if q.endswith("/") or os.path.isdir(full_target):
            return list_directory_entries(full_target, "", max_results)
        parent = os.path.dirname(full_target)
        base_filter = os.path.basename(full_target)
        if os.path.isdir(parent):
            direct = list_directory_entries(parent, base_filter, max_results)
            if direct:
                return direct

    results = []
    seen = set()

    # First check direct matches in HOME for super fast feedback (especially 1-2 char queries)
    for item in list_directory_entries(HOME, q, max_results):
        p = item["path"]
        seen.add(p)
        results.append((p, item["isDir"]))

    # 3. Fast live search via fd with --one-file-system and smart excludes
    try:
        fd_cmd = ["fd", "-H", "-i", "--one-file-system", "--max-results", str(max_results * 4)]
        for ex in FD_EXCLUDES:
            fd_cmd.extend(["-E", ex])
        if "/" in q:
            fd_cmd.append("-p")
        fd_cmd.extend([q, HOME])

        proc = subprocess.run(
            fd_cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=0.35
        )
        for line in proc.stdout.splitlines():
            p_raw = line.strip()
            if not p_raw:
                continue
            is_dir = p_raw.endswith("/")
            p = p_raw.rstrip("/")
            if p not in seen:
                seen.add(p)
                results.append((p, is_dir))
                if len(results) >= max_results * 4:
                    break
    except Exception:
        pass

    # 4. Supplement with plocate -b (basename index) only if fd found nothing
    if len(results) == 0 and "/" not in q and len(q) >= 2:
        try:
            proc = subprocess.run(
                ["plocate", "-b", "-i", "-l", str(max_results * 4), q],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=0.25
            )
            for line in proc.stdout.splitlines():
                p = line.strip()
                if not p.startswith(HOME + "/") or any(ig in p for ig in IGNORE_SUBSTRINGS):
                    continue
                if p not in seen and os.path.exists(p):
                    seen.add(p)
                    results.append((p, os.path.isdir(p)))
                    if len(results) >= max_results * 4:
                        break
        except Exception:
            pass

    q_lower = q.lower()

    def score(entry):
        p, is_dir = entry
        base = os.path.basename(p).lower()
        base_no_ext = os.path.splitext(base)[0]
        rel = p[len(HOME) + 1:] if p.startswith(HOME + "/") else p
        depth = rel.count("/")
        top_dir = rel.split("/", 1)[0]
        in_priority = 0 if top_dir in PRIORITY_DIRS else 1

        if base == q_lower or base_no_ext == q_lower:
            rank = 0
        elif base.startswith(q_lower):
            rank = 1
        elif q_lower in base:
            rank = 2
        else:
            rank = 3
        return (rank, in_priority, depth, len(p), p)

    results.sort(key=score)
    return [format_item(p, is_dir) for p, is_dir in results[:max_results]]

def main():
    query = sys.argv[1] if len(sys.argv) >= 2 else ""
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

