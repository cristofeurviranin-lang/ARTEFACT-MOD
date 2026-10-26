"""Shared logic for the player launcher (joueur.pyw) and the admin tool (admin.pyw).

A *client* is a game client (IW8, Cold War, BO7, LUMEN...). Each one has a mods folder on the
player's PC. A *mod* belongs to one client and is a set of files dropped in that folder:
installing writes the files, uninstalling deletes them. Installed mods are active right away.

Files next to this script:
  settings.json   shipped to players, written by the admin tool: {"update_url": ...}
  state.json      local to each PC: client folders, auto-update, last manifest seen
  workspace/      admin only: workspace/<client>/<mod>/mod.json + the mod's files
  depot/          admin only: what gets pushed to GitHub (manifest.json + mods/)
"""

import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
import urllib.request
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
SETTINGS_PATH = os.path.join(HERE, "settings.json")
STATE_PATH = os.path.join(HERE, "state.json")
WORKSPACE = os.path.join(HERE, "workspace")
DEPOT = os.path.join(HERE, "depot")
DIST = os.path.join(HERE, "dist")
CUSTOM_CLIENTS_PATH = os.path.join(WORKSPACE, "clients.json")

TIMEOUT = 15
PLAYER_FILES = ["core.py", "ui.py", "joueur.pyw"]

# files a mod may contain: scripts and data only, never programs
ALLOWED_EXTENSIONS = {
    ".gsc", ".gsh", ".gscbin", ".gscc", ".csc", ".lua", ".luac", ".json", ".csv", ".txt", ".cfg", ".ini",
    ".str", ".ff", ".pak", ".xml", ".png", ".jpg", ".dds", ".wav", ".ogg", ".bik",
}
# what the first launchers accept: a mod with any other file goes to "mods_extra" in the
# manifest, which they never read (they would reject the whole manifest and never update)
LEGACY_EXTENSIONS = ALLOWED_EXTENSIONS - {".gscc"}
SAFE_PART = re.compile(r"^[A-Za-z0-9_\-. ]+$")
SAFE_ID = re.compile(r"^[a-z0-9_\-]+$")

# built-in clients; the manifest (and the admin's clients.json) can add more
# pick: "game" = the player chooses the game folder and mods go in mods_subdir,
#       "mods" = the player chooses the mods folder itself
BUILTIN_CLIENTS = [
    {"id": "iw8", "name": "IW8 Warzone", "short": "IW8", "color": "#3aa0ff",
     "description": "Modern Warfare 2019 and Warzone on IW8-Mod.",
     "pick": "game", "marker": "! Start MW2019.bat", "mods_subdir": ".iw8-mod/custom_scripts",
     "folder_hint": "your Modern Warfare game folder (the one with \"! Start MW2019.bat\")"},
    {"id": "coldwar", "name": "Cold War", "short": "CW", "color": "#f2f2f2",
     "description": "Black Ops Cold War client.",
     "pick": "mods", "folder_hint": "the folder where your Cold War client loads mods"},
    {"id": "bo7", "name": "Black Ops 7", "short": "BO7", "color": "#2f8cff", "color2": "#ff7a1a",
     "description": "Black Ops 7 client.",
     "pick": "mods", "folder_hint": "the folder where your BO7 client loads mods"},
    {"id": "lumen", "name": "LUMEN", "short": "LU", "color": "#ff3b3b",
     "description": "Modern Warfare III on the LUMEN client.",
     "pick": "mods", "folder_hint": "the folder where LUMEN loads mods"},
]

APP_NAME = "ARTEFACT V1 LAUNCHER"
DISCORD_URL = "https://discord.gg/EmMRBTQdvj"


# ---------------------------------------------------------------- json files

def read_json(path, default):
    data = dict(default)
    try:
        with open(path, "r", encoding="utf-8") as f:
            loaded = json.load(f)
        if isinstance(loaded, dict):
            data.update(loaded)
    except (OSError, ValueError):
        pass
    return data


def write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)


def load_settings():
    return read_json(SETTINGS_PATH, {"update_url": ""})


def save_settings(settings):
    write_json(SETTINGS_PATH, settings)


def load_state():
    state = read_json(STATE_PATH, {"folders": {}, "auto_update": True, "manifest": None})
    # launcher v1 kept the IW8 game folder as "game_dir"
    if state.get("game_dir") and "iw8" not in state["folders"]:
        state["folders"]["iw8"] = state["game_dir"]
    state.pop("game_dir", None)
    return state


def save_state(state):
    write_json(STATE_PATH, state)


# ---------------------------------------------------------------- clients and folders

def merge_clients(*lists):
    """Built-in clients first, then any new ones; later lists override fields of earlier ones."""
    merged = {}
    order = []
    for clients in (BUILTIN_CLIENTS,) + lists:
        for client in clients or []:
            cid = client.get("id", "")
            if not SAFE_ID.match(cid):
                continue
            if cid not in merged:
                order.append(cid)
                merged[cid] = {"pick": "mods", "short": cid[:3].upper(), "color": "#8b93a1",
                               "description": "", "folder_hint": "the folder where this client loads mods"}
            merged[cid].update(client)
    return [merged[cid] for cid in order]


def find_game_folder(marker):
    """For "game" clients: the launcher folder sits inside the game folder or next to it."""
    for base in (HERE, os.path.dirname(HERE)):
        if os.path.isfile(os.path.join(base, marker)):
            return base
        try:
            names = os.listdir(base)
        except OSError:
            continue
        for name in names:
            path = os.path.join(base, name)
            if os.path.isfile(os.path.join(path, marker)):
                return path
    return ""


def chosen_folder(client, state):
    """The folder the player picked (or that was auto-detected), or ""."""
    folder = state["folders"].get(client["id"], "")
    if client.get("pick") == "game":
        marker = client.get("marker", "")
        if not (folder and os.path.isfile(os.path.join(folder, marker))):
            folder = find_game_folder(marker) if marker else ""
    elif folder and not os.path.isdir(folder):
        folder = ""
    return folder


def validate_folder(client, path):
    """Returns an error message, or "" when the folder is fine for this client."""
    if not path or not os.path.isdir(path):
        return "This folder doesn't exist."
    if client.get("pick") == "game" and not os.path.isfile(os.path.join(path, client.get("marker", ""))):
        return "Wrong folder: it must contain \"%s\"." % client.get("marker", "")
    return ""


def mods_folder(client, state):
    folder = chosen_folder(client, state)
    if not folder:
        return ""
    if client.get("pick") == "game":
        return os.path.join(folder, *client.get("mods_subdir", "").split("/"))
    return folder


# ---------------------------------------------------------------- mod files

def safe_relpath(path):
    """Checks a relative path coming from a manifest; returns it with OS separators or raises."""
    parts = path.split("/")
    if not path or any(not SAFE_PART.match(p) or p in (".", "..") for p in parts):
        raise ValueError("unsafe file path: %r" % path)
    if os.path.splitext(path)[1].lower() not in ALLOWED_EXTENSIONS:
        raise ValueError("file type not allowed: %r" % path)
    return os.path.join(*parts)


_hash_cache = {}


def sha256_of(path):
    """File checksum, remembered until the file's size or modification time changes
    (the launcher checks every mod's files each time a page is shown)."""
    info = os.stat(path)
    key = (os.path.abspath(path), info.st_size, info.st_mtime_ns)
    if key not in _hash_cache:
        digest = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                digest.update(chunk)
        _hash_cache[key] = digest.hexdigest()
    return _hash_cache[key]


def mod_status(mod, folder):
    """"missing" (not installed), "installed" (up to date) or "update" (installed, files differ)."""
    present = 0
    up_to_date = True
    for entry in mod["files"]:
        path = os.path.join(folder, safe_relpath(entry["path"]))
        if os.path.exists(path):
            present += 1
            if sha256_of(path) != entry["sha256"]:
                up_to_date = False
        elif os.path.exists(path + ".disabled"):  # switched off by the old launcher
            present += 1
            up_to_date = False
        else:
            up_to_date = False
    if present == 0:
        # the old mods this one replaces are still active: offer it as their update
        return "update" if replaced_files(mod, folder) else "missing"
    return "installed" if up_to_date else "update"


def replaced_files(mod, folder):
    """Active files of older mods this mod replaces (e.g. three scripts merged into one)."""
    paths = [os.path.join(folder, safe_relpath(rel)) for rel in mod.get("replaces", [])]
    return [p for p in paths if os.path.exists(p)]


def remove_replaced(mod, folder):
    for rel in mod.get("replaces", []):
        target = os.path.join(folder, safe_relpath(rel))
        for path in (target, target + ".disabled"):
            if os.path.exists(path):
                os.remove(path)


# ---------------------------------------------------------------- network (player side)

def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "mod-launcher"})
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        return response.read()


def check_mod(mod):
    """Raises if one mod of the manifest is malformed or unsafe."""
    if not SAFE_ID.match(str(mod.get("id", ""))) or not SAFE_ID.match(str(mod.get("client", ""))):
        raise ValueError("invalid mod id")
    if not isinstance(mod.get("files"), list) or not mod["files"]:
        raise ValueError("mod %s has no files" % mod["id"])
    for entry in mod["files"]:
        safe_relpath(str(entry.get("path", "")))
        if not re.match(r"^[0-9a-f]{64}$", str(entry.get("sha256", ""))):
            raise ValueError("bad checksum in %s" % mod["id"])
    if not isinstance(mod.get("replaces", []), list):
        raise ValueError("bad replaces list in %s" % mod["id"])
    for rel in mod.get("replaces", []):
        safe_relpath(str(rel))


def check_manifest(manifest):
    """Raises if the manifest is malformed or a launcher file is unsafe. Mods are merged from "mods"
    and "mods_extra" (mods with files the first launchers reject: they only read "mods", so they
    can still update themselves); a mod this launcher cannot accept is left out, not the whole file."""
    if not isinstance(manifest, dict) or not isinstance(manifest.get("mods"), list):
        raise ValueError("invalid update file")
    extra = manifest.get("mods_extra", [])
    if not isinstance(extra, list):
        raise ValueError("invalid update file")
    accepted = []
    for mod in manifest["mods"] + extra:
        try:
            check_mod(mod)
        except (ValueError, TypeError, AttributeError):
            continue
        accepted.append(mod)
    manifest["mods"] = accepted
    manifest.pop("mods_extra", None)
    for entry in launcher_entries(manifest):
        safe_launcher_path(str(entry.get("path", "")))
        if not re.match(r"^[0-9a-f]{64}$", str(entry.get("sha256", ""))):
            raise ValueError("bad checksum in launcher files")
    return manifest


def fetch_manifest(url):
    return check_manifest(json.loads(fetch(url).decode("utf-8")))


def resolve_url(manifest_url, file_url):
    """File URLs in the manifest may be relative to the manifest itself."""
    if re.match(r"^[a-z]+://", file_url):
        return file_url
    return manifest_url.rsplit("/", 1)[0] + "/" + file_url


def install_mod(mod, folder, manifest_url, progress=lambda done, total: None):
    """Downloads every file of the mod into the client's mods folder (only the ones that changed)."""
    files = mod["files"]
    for index, entry in enumerate(files):
        progress(index, len(files))
        target = os.path.join(folder, safe_relpath(entry["path"]))
        if os.path.exists(target + ".disabled"):
            os.remove(target + ".disabled")
        if os.path.exists(target) and sha256_of(target) == entry["sha256"]:
            continue
        data = fetch(resolve_url(manifest_url, entry["url"]))
        if hashlib.sha256(data).hexdigest() != entry["sha256"]:
            raise ValueError("%s arrived damaged, try again later" % entry["path"])
        os.makedirs(os.path.dirname(target), exist_ok=True)
        # write next to the target then swap, so a failed download never leaves a half file
        handle, temp_path = tempfile.mkstemp(dir=os.path.dirname(target), suffix=".part")
        with os.fdopen(handle, "wb") as f:
            f.write(data)
        os.replace(temp_path, target)
    # only once the new files are in place, so a failed download never leaves the player with nothing
    remove_replaced(mod, folder)
    progress(len(files), len(files))


def uninstall_mod(mod, folder):
    for entry in mod["files"]:
        target = os.path.join(folder, safe_relpath(entry["path"]))
        for path in (target, target + ".disabled"):
            if os.path.exists(path):
                os.remove(path)
    remove_replaced(mod, folder)


# ---------------------------------------------------------------- launcher self-update

ASSET_NAME = re.compile(r"^[A-Za-z0-9_\-]+\.(png|wav)$")


def safe_launcher_path(path):
    """Only the player launcher's own files may be replaced: its three scripts, its artwork and sounds."""
    if path in PLAYER_FILES or (path.startswith("assets/") and ASSET_NAME.match(path[len("assets/"):])):
        return os.path.join(*path.split("/"))
    raise ValueError("unexpected launcher file: %r" % path)


def launcher_files():
    """Relative paths of everything that makes up the player launcher."""
    files = list(PLAYER_FILES)
    assets = os.path.join(HERE, "assets")
    if os.path.isdir(assets):
        files += ["assets/" + n for n in sorted(os.listdir(assets)) if ASSET_NAME.match(n)]
    return files


def launcher_entries(manifest):
    # "media" holds files the first launcher version (PNG only) would reject; it never reads that key
    launcher = manifest.get("launcher", {})
    return launcher.get("files", []) + launcher.get("media", [])


def is_admin_install():
    """The admin's own folder is the source of the launcher: it must never overwrite itself."""
    return os.path.exists(os.path.join(HERE, "admin.pyw"))


def update_launcher(manifest, manifest_url):
    """Replaces the launcher's files that differ from the published ones. Returns the paths replaced.

    Everything is downloaded and checked first, then written, so a failed download changes nothing.
    """
    if is_admin_install():
        return []
    downloads = []
    for entry in launcher_entries(manifest):
        target = os.path.join(HERE, safe_launcher_path(entry["path"]))
        if os.path.exists(target) and sha256_of(target) == entry["sha256"]:
            continue
        data = fetch(resolve_url(manifest_url, entry["url"]))
        if hashlib.sha256(data).hexdigest() != entry["sha256"]:
            raise ValueError("launcher update arrived damaged, try again later")
        downloads.append((entry["path"], target, data))
    for _path, target, data in downloads:
        os.makedirs(os.path.dirname(target), exist_ok=True)
        handle, temp_path = tempfile.mkstemp(dir=os.path.dirname(target), suffix=".part")
        with os.fdopen(handle, "wb") as f:
            f.write(data)
        os.replace(temp_path, target)
    return [path for path, _target, _data in downloads]


# ---------------------------------------------------------------- workspace (admin side)

def load_custom_clients():
    return read_json(CUSTOM_CLIENTS_PATH, {"clients": []})["clients"]


def save_custom_clients(clients):
    write_json(CUSTOM_CLIENTS_PATH, {"clients": clients})


def all_clients_admin():
    return merge_clients(load_custom_clients())


def slug(text):
    return re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")[:40]


def mod_dir(client_id, mod_id):
    return os.path.join(WORKSPACE, client_id, mod_id)


def workspace_mods(client_id):
    """[(mod_id, info, [relative file paths])] for one client."""
    base = os.path.join(WORKSPACE, client_id)
    result = []
    try:
        names = sorted(os.listdir(base))
    except OSError:
        return result
    for mod_id in names:
        folder = os.path.join(base, mod_id)
        if not os.path.isdir(folder) or not SAFE_ID.match(mod_id):
            continue
        info = read_json(os.path.join(folder, "mod.json"),
                         {"title": mod_id, "description": "", "published": True, "sync_from_game": False})
        files = []
        for root, _dirs, filenames in os.walk(folder):
            for name in filenames:
                if name == "mod.json":
                    continue
                files.append(os.path.relpath(os.path.join(root, name), folder).replace(os.sep, "/"))
        result.append((mod_id, info, sorted(files)))
    return result


def save_mod_info(client_id, mod_id, info):
    write_json(os.path.join(mod_dir(client_id, mod_id), "mod.json"), info)


def create_mod(client_id, title):
    mod_id = slug(title)
    if not mod_id:
        raise ValueError("give the mod a name")
    folder = mod_dir(client_id, mod_id)
    if os.path.exists(folder):
        raise ValueError("a mod with this name already exists")
    os.makedirs(folder)
    save_mod_info(client_id, mod_id, {"title": title, "description": "", "published": True})
    return mod_id


def sync_from_game(client, state):
    """IW8 mods flagged sync_from_game take the latest copy of their files from the admin's game."""
    folder = mods_folder(client, state)
    if not folder:
        return
    for mod_id, info, files in workspace_mods(client["id"]):
        if not info.get("sync_from_game"):
            continue
        for rel in files:
            source = os.path.join(folder, *rel.split("/"))
            if not os.path.exists(source):
                source += ".disabled"
            if os.path.exists(source):
                shutil.copyfile(source, os.path.join(mod_dir(client["id"], mod_id), *rel.split("/")))


def build_depot(state):
    """Writes depot/manifest.json and depot/mods/ from the workspace. Returns the manifest."""
    clients = all_clients_admin()
    for client in clients:
        sync_from_game(client, state)

    out = os.path.join(DEPOT, "mods")
    if os.path.isdir(out):
        shutil.rmtree(out)
    os.makedirs(out)

    mods = []
    for client in clients:
        for mod_id, info, files in workspace_mods(client["id"]):
            if not info.get("published", True) or not files:
                continue
            entries = []
            for rel in files:
                safe_relpath(rel)  # refuse to publish something players would reject
                source = os.path.join(mod_dir(client["id"], mod_id), *rel.split("/"))
                url = "mods/%s/%s/%s" % (client["id"], mod_id, rel)
                target = os.path.join(DEPOT, *url.split("/"))
                os.makedirs(os.path.dirname(target), exist_ok=True)
                shutil.copyfile(source, target)
                entries.append({"path": rel, "url": url, "sha256": sha256_of(source)})
            fingerprint = hashlib.sha256("".join(e["path"] + e["sha256"] for e in entries).encode()).hexdigest()
            mod = {"id": mod_id, "client": client["id"], "title": info.get("title", mod_id),
                   "description": info.get("description", ""), "version": fingerprint[:8], "files": entries}
            if info.get("replaces"):
                for rel in info["replaces"]:
                    safe_relpath(rel)
                mod["replaces"] = list(info["replaces"])
            mods.append(mod)

    # the player launcher itself, so players get interface changes without a new zip
    launcher = []
    out_launcher = os.path.join(DEPOT, "launcher")
    if os.path.isdir(out_launcher):
        shutil.rmtree(out_launcher)
    for rel in launcher_files():
        source = os.path.join(HERE, safe_launcher_path(rel))
        target = os.path.join(out_launcher, *rel.split("/"))
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copyfile(source, target)
        launcher.append({"path": rel, "url": "launcher/" + rel, "sha256": sha256_of(source)})
    launcher_version = hashlib.sha256("".join(e["path"] + e["sha256"] for e in launcher).encode()).hexdigest()[:8]
    media = [e for e in launcher if not e["path"].endswith(".png") and e["path"].startswith("assets/")]
    files = [e for e in launcher if e not in media]

    fingerprint = hashlib.sha256(("".join(m["client"] + m["id"] + m["version"] for m in mods) +
                                  launcher_version).encode()).hexdigest()
    legacy = [m for m in mods if all(os.path.splitext(e["path"])[1].lower() in LEGACY_EXTENSIONS for e in m["files"])]
    extra = [m for m in mods if m not in legacy]
    manifest = {"format": 2, "version": fingerprint[:8], "clients": load_custom_clients(), "mods": legacy,
                "mods_extra": extra, "launcher": {"version": launcher_version, "files": files, "media": media}}
    write_json(os.path.join(DEPOT, "manifest.json"), manifest)
    return manifest


def published_version():
    return read_json(os.path.join(DEPOT, "manifest.json"), {"version": ""})["version"]


def find_git():
    """git on PATH, or the copy bundled with GitHub Desktop."""
    found = shutil.which("git")
    if found:
        return found
    base = os.path.join(os.environ.get("LOCALAPPDATA", ""), "GitHubDesktop")
    try:
        apps = sorted(n for n in os.listdir(base) if n.startswith("app-"))
    except OSError:
        return None
    for app in reversed(apps):
        candidate = os.path.join(base, app, "resources", "app", "git", "cmd", "git.exe")
        if os.path.isfile(candidate):
            return candidate
    return None


def depot_is_repo():
    return os.path.isdir(os.path.join(DEPOT, ".git"))


def git_push(version):
    """Commits and pushes the depot. Returns (ok, message); message "manual" = do it in GitHub Desktop."""
    git = find_git()
    if not git or not depot_is_repo():
        return False, "manual"

    def run(*args):
        return subprocess.run([git, *args], cwd=DEPOT, capture_output=True, text=True,
                              timeout=120, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))

    run("add", "-A")
    commit = run("commit", "-m", "Update %s" % version)
    if commit.returncode != 0 and "nothing to commit" not in (commit.stdout + commit.stderr):
        return False, (commit.stderr or commit.stdout).strip()
    push = run("push")
    if push.returncode != 0:
        return False, (push.stderr or push.stdout).strip()
    return True, "ok"


def build_player_pack():
    """Zips everything a player needs. Returns the zip path."""
    folder_name = "ARTEFACT V1 Launcher"
    staging = os.path.join(DIST, folder_name)
    if os.path.isdir(staging):
        shutil.rmtree(staging)
    os.makedirs(staging)

    for name in PLAYER_FILES:
        shutil.copyfile(os.path.join(HERE, name), os.path.join(staging, name))
    assets = os.path.join(HERE, "assets")
    if os.path.isdir(assets):
        shutil.copytree(assets, os.path.join(staging, "assets"))
    write_json(os.path.join(staging, "settings.json"), {"update_url": load_settings()["update_url"]})

    with open(os.path.join(staging, "ARTEFACT Launcher.bat"), "w", encoding="ascii") as f:
        f.write('@echo off\r\ncd /d %~dp0\r\nstart "" pyw joueur.pyw\r\n')

    with open(os.path.join(staging, "README.txt"), "w", encoding="utf-8") as f:
        f.write(
            "ARTEFACT V1 LAUNCHER\n"
            "====================\n\n"
            "1. Put this folder next to your game folder.\n"
            "2. Double-click \"ARTEFACT Launcher.bat\" (Python must be installed).\n"
            "3. Pick a client on the left, then click Install on the mods you want.\n\n"
            "Installed mods are active in the game right away and update on their own.\n"
            "Discord: %s\n" % DISCORD_URL
        )

    zip_path = os.path.join(DIST, folder_name + ".zip")
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as archive:
        for root, _dirs, files in os.walk(staging):
            for name in files:
                path = os.path.join(root, name)
                archive.write(path, os.path.join(folder_name, os.path.relpath(path, staging)))
    return zip_path
