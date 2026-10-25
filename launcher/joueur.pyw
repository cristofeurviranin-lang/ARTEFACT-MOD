"""ARTEFACT V1 LAUNCHER (player): pick a client on the left, install or uninstall its mods."""

import os
import subprocess
import sys
import threading
import tkinter as tk
import urllib.error
import webbrowser
from tkinter import filedialog

import core
import ui

HOW_IT_WORKS = [
    "Pick a client on the left (IW8, Cold War, BO7, LUMEN...).",
    "Click Install on a mod: it's active in that client right away.",
    "Click Uninstall to remove it. You can reinstall it any time.",
    "Installed mods update on their own each time you open the launcher.",
]


def friendly_error(error):
    if isinstance(error, PermissionError):
        return "A file is in use. Close the game, then try again."
    if isinstance(error, (urllib.error.URLError, TimeoutError, ConnectionError)):
        return "No internet connection. Try again later."
    return "Something went wrong: %s" % error


class PlayerApp:
    def __init__(self, root, splash=True):
        self.root = root
        self.fonts = ui.setup_window(root, core.APP_NAME, 1140, 740, 940, 600)
        self.settings = core.load_settings()
        self.state = core.load_state()
        self.manifest = self.state.get("manifest") or {"mods": [], "clients": []}
        self.busy = False
        self.page = self.state.get("last_page", "iw8")
        self.page_frame = None
        # pages already built stay alive and are just brought to the front; rerender() rebuilds them
        self.pages = {}
        self.banner = None
        self.action_buttons = []
        self.nav = {}

        self.sidebar = tk.Frame(root, bg=ui.SIDEBAR, width=270)
        self.sidebar.pack(side="left", fill="y")
        self.sidebar.pack_propagate(False)
        tk.Frame(root, bg=ui.BORDER, width=1).pack(side="left", fill="y")

        right = tk.Frame(root, bg=ui.BG)
        right.pack(side="left", fill="both", expand=True)
        bottom = tk.Frame(right, bg=ui.BG, padx=36)
        bottom.pack(fill="x", side="bottom", pady=(8, 16))
        self.status = ui.StatusLine(bottom, self.fonts)
        self.status.pack(fill="x")
        self.main = tk.Frame(right, bg=ui.BG)
        self.main.pack(fill="both", expand=True)

        self.build_sidebar()
        self.show(self.page, animate=False)
        self.status.set("busy", "Checking for updates...")
        root.after(100, self.check_updates)
        if splash:
            ui.Splash(root, self.fonts, on_done=lambda: self.show(self.page))
            self.play_intro_sound()

    # ------------------------------------------------------------ data helpers

    def clients(self):
        return core.merge_clients(self.manifest.get("clients"))

    def client(self, client_id):
        return next((c for c in self.clients() if c["id"] == client_id), None)

    def client_mods(self, client_id):
        return [m for m in self.manifest.get("mods", []) if m.get("client") == client_id]

    def statuses(self, client):
        """{mod_id: status} for one client; empty when its folder isn't set."""
        folder = core.mods_folder(client, self.state)
        if not folder:
            return {}
        result = {}
        for mod in self.client_mods(client["id"]):
            try:
                result[mod["id"]] = core.mod_status(mod, folder)
            except (OSError, ValueError):
                result[mod["id"]] = "missing"
        return result

    def installed_count(self, client):
        return sum(1 for s in self.statuses(client).values() if s != "missing")

    def nav_subtitle(self, client):
        mods = self.client_mods(client["id"])
        if not mods:
            return "No mods yet"
        if not core.mods_folder(client, self.state):
            return "Folder not set"
        return "%d of %d installed" % (self.installed_count(client), len(mods))

    # ------------------------------------------------------------ sidebar

    def build_sidebar(self):
        for child in self.sidebar.winfo_children():
            child.destroy()
        self.nav = {}

        top = tk.Frame(self.sidebar, bg=ui.SIDEBAR, padx=24, pady=22)
        top.pack(fill="x")
        ui.Logo(top, self.fonts).pack(fill="x")

        tk.Label(self.sidebar, text="CLIENTS", bg=ui.SIDEBAR, fg=ui.FAINT, font=self.fonts.label, anchor="w",
                 padx=24).pack(fill="x", pady=(6, 8))
        for client in self.clients():
            item = ui.NavItem(self.sidebar, self.fonts, client["name"], self.nav_subtitle(client),
                              lambda c=client["id"]: self.show(c), client=client)
            item.pack(fill="x")
            self.nav[client["id"]] = item

        settings = ui.NavItem(self.sidebar, self.fonts, "Settings", "Folders and updates",
                              lambda: self.show("settings"), icon="⚙", color=ui.MUTED)
        settings.pack(fill="x", side="bottom", pady=(0, 14))
        self.nav["settings"] = settings
        discord = tk.Frame(self.sidebar, bg=ui.SIDEBAR, padx=22)
        discord.pack(fill="x", side="bottom", pady=(0, 12))
        ui.Button(discord, "Join the Discord", self.open_discord, self.fonts.button, height=38,
                  colors=(ui.DISCORD, None)).pack(fill="x")
        tk.Frame(self.sidebar, bg=ui.BORDER, height=1).pack(fill="x", side="bottom", pady=(0, 14))

        for key, item in self.nav.items():
            item.set_selected(key == self.page)

    # ------------------------------------------------------------ pages

    def show(self, page, animate=True):
        if page != "settings" and not self.client(page):
            page = "iw8"
        self.page = page
        self.state["last_page"] = page
        core.save_state(self.state)
        for key, item in self.nav.items():
            item.set_selected(key == page)

        if page in self.pages:
            frame, banner, buttons = self.pages[page]
            frame.tkraise()
            self.page_frame, self.action_buttons = frame, buttons
            if animate and banner:
                banner.play()
            return

        self.page_frame = tk.Frame(self.main, bg=ui.BG)
        self.action_buttons = []
        self.banner = None
        if page == "settings":
            reveal = self.build_settings(self.page_frame)
        else:
            reveal = self.build_client_page(self.page_frame, self.client(page), animate)
        ui.slide_in(self.page_frame)
        if animate:
            ui.reveal(reveal, delay=120)
        else:
            for widget, options in reveal:
                widget.pack(**options)
        self.pages[page] = (self.page_frame, self.banner, self.action_buttons)

    def rerender(self):
        for frame, _banner, _buttons in self.pages.values():
            frame.destroy()
        self.pages = {}
        self.build_sidebar()
        self.show(self.page, animate=False)

    def build_client_page(self, frame, client, animate):
        mods = self.client_mods(client["id"])
        folder = core.chosen_folder(client, self.state)
        if not mods:
            pill = "NO MODS YET"
        elif not folder:
            pill = "FOLDER NOT SET"
        else:
            pill = "%d / %d INSTALLED" % (self.installed_count(client), len(mods))
        banner = ui.Banner(frame, self.fonts, client, client["description"], pill)
        banner.pack(fill="x")
        self.banner = banner
        if animate:
            banner.play()

        content = tk.Frame(frame, bg=ui.BG, padx=36)
        content.pack(fill="both", expand=True, pady=(4, 0))
        c1, c2 = ui.client_colors(client)
        items = []

        outer, bar = ui.card(content, padding=14)
        if folder:
            tk.Label(bar, text="✓", bg=ui.PANEL, fg=ui.GREEN, font=self.fonts.h2).pack(side="left", padx=(2, 12))
            ui.Button(bar, "Change", lambda: self.choose_folder(client), self.fonts.button, height=34,
                      kind="secondary", width=96, glow=c1).pack(side="right")
            info = tk.Frame(bar, bg=ui.PANEL)
            info.pack(side="left", fill="x", expand=True)
            tk.Label(info, text="Installing to", bg=ui.PANEL, fg=ui.FAINT, font=self.fonts.tiny, anchor="w").pack(fill="x")
            tk.Label(info, text=ui.short_path(folder), bg=ui.PANEL, fg=ui.TEXT, font=self.fonts.small,
                     anchor="w").pack(fill="x")
        else:
            # button packed first so the text never squeezes it
            ui.Button(bar, "Choose folder", lambda: self.choose_folder(client), self.fonts.button, height=36,
                      width=140, colors=(c1, c2)).pack(side="right", padx=(12, 0))
            tk.Label(bar, text="!", bg=ui.PANEL, fg=ui.YELLOW, font=self.fonts.title).pack(side="left", padx=(4, 14))
            ui.wrap_label(tk.Label(bar, text="Choose %s so the launcher knows where to install mods."
                                   % client["folder_hint"], bg=ui.PANEL, fg=ui.TEXT, font=self.fonts.body,
                                   anchor="w", justify="left")).pack(side="left", fill="x", expand=True)
        items.append((outer, {"fill": "x", "pady": (0, 20)}))
        items.append((ui.section_label(content, "Available mods  (%d)" % len(mods), self.fonts),
                      {"fill": "x", "pady": (0, 10)}))

        if not mods:
            outer, box = ui.card(content, padding=26)
            tk.Label(box, text="No mods for %s yet" % client["name"], bg=ui.PANEL, fg=ui.TEXT,
                     font=self.fonts.h2).pack()
            tk.Label(box, text="They'll show up here as soon as they're published. Join the Discord for news.",
                     bg=ui.PANEL, fg=ui.MUTED, font=self.fonts.body).pack(pady=(4, 0))
            items.append((outer, {"fill": "x"}))
            return items

        statuses = self.statuses(client)
        order = {"update": 0, "installed": 1, "missing": 2}
        mods = sorted(mods, key=lambda m: (order.get(statuses.get(m["id"], "missing"), 3), m["title"].lower()))
        scroll = ui.ScrollFrame(content)
        items.append((scroll, {"fill": "both", "expand": True}))
        for mod in mods:
            card = self.mod_card(scroll.body, client, mod, statuses.get(mod["id"]), bool(folder))
            card.pack(fill="x", pady=(0, 10))
        return items

    def mod_card(self, parent, client, mod, status, has_folder):
        c1, c2 = ui.client_colors(client)
        outer, box = ui.card(parent, padding=18)

        actions = tk.Frame(box, bg=ui.PANEL)
        actions.pack(side="right", padx=(18, 0))
        texts = tk.Frame(box, bg=ui.PANEL)
        texts.pack(side="left", fill="x", expand=True)

        title_row = tk.Frame(texts, bg=ui.PANEL)
        title_row.pack(fill="x")
        tk.Label(title_row, text=mod["title"], bg=ui.PANEL, fg=ui.TEXT, font=self.fonts.h2).pack(side="left")
        if status == "installed":
            ui.chip(title_row, "INSTALLED", ui.GREEN, self.fonts).pack(side="left", padx=(10, 0))
        elif status == "update":
            ui.chip(title_row, "UPDATE AVAILABLE", c2 or c1, self.fonts).pack(side="left", padx=(10, 0))
        if mod.get("description"):
            ui.wrap_label(tk.Label(texts, text=mod["description"], bg=ui.PANEL, fg=ui.MUTED, font=self.fonts.body,
                                   anchor="w", justify="left")).pack(fill="x", pady=(4, 0))
        files = len(mod["files"])
        tk.Label(texts, text="Version %s  ·  %d file%s" % (mod.get("version", "?"), files, "s" if files > 1 else ""),
                 bg=ui.PANEL, fg=ui.FAINT, font=self.fonts.tiny, anchor="w").pack(fill="x", pady=(6, 0))

        enabled = has_folder and not self.busy
        buttons = []
        if status == "update":
            buttons.append(ui.Button(actions, "Update", None, self.fonts.button, height=38, width=134, colors=(c1, c2)))
            buttons[-1].command = lambda b=buttons[-1]: self.run_install(client, mod, b)
        if status in ("installed", "update"):
            buttons.append(ui.Button(actions, "Uninstall", None, self.fonts.button, height=38, kind="danger", width=134))
            buttons[-1].command = lambda b=buttons[-1]: self.run_uninstall(client, mod, b)
        else:
            buttons.append(ui.Button(actions, "Install", None, self.fonts.button, height=38, width=134, colors=(c1, c2)))
            buttons[-1].command = lambda b=buttons[-1]: self.run_install(client, mod, b)
        for index, button in enumerate(buttons):
            button.set_enabled(enabled)
            button.pack(pady=(0, 6) if index < len(buttons) - 1 else 0)
            self.action_buttons.append(button)

        ui.hover_glow(outer, c1)
        return outer

    def build_settings(self, frame):
        header = tk.Frame(frame, bg=ui.BG, padx=36, pady=30)
        header.pack(fill="x")
        tk.Label(header, text="SETTINGS", bg=ui.BG, fg=ui.TEXT, font=self.fonts.hero, anchor="w").pack(fill="x")
        sweep = tk.Canvas(header, height=6, bg=ui.BG, highlightthickness=0)
        sweep.pack(fill="x", pady=(2, 8))
        sweep.bind("<Configure>", lambda e: (sweep.delete("all"),
                                             ui.gradient_rounded(sweep, 0, 1, 110, 5, 2, *ui.BRAND)))
        tk.Label(header, text="Where each client's mods go, how updates work, and where to find us.", bg=ui.BG,
                 fg=ui.MUTED, font=self.fonts.body, anchor="w").pack(fill="x")

        scroll = ui.ScrollFrame(frame)
        scroll.pack(fill="both", expand=True, padx=36)
        body = scroll.body
        items = []

        items.append((ui.section_label(body, "Client folders", self.fonts), {"fill": "x", "pady": (0, 10)}))
        outer, box = ui.card(body, padding=8)
        clients = self.clients()
        for index, client in enumerate(clients):
            row = tk.Frame(box, bg=ui.PANEL, padx=10, pady=10)
            row.pack(fill="x")
            ui.client_badge(row, client).pack(side="left", padx=(0, 14))
            folder = core.chosen_folder(client, self.state)
            ui.Button(row, "Change" if folder else "Choose", lambda c=client: self.choose_folder(c), self.fonts.button,
                      height=34, kind="secondary", width=96, glow=ui.client_colors(client)[0]).pack(side="right")
            texts = tk.Frame(row, bg=ui.PANEL)
            texts.pack(side="left", fill="x", expand=True)
            tk.Label(texts, text=client["name"], bg=ui.PANEL, fg=ui.TEXT, font=self.fonts.nav, anchor="w").pack(fill="x")
            tk.Label(texts, text=ui.short_path(folder, 64) if folder else "Not set", bg=ui.PANEL,
                     fg=ui.MUTED if folder else ui.YELLOW, font=self.fonts.small, anchor="w").pack(fill="x")
            if index < len(clients) - 1:
                tk.Frame(box, bg=ui.BORDER, height=1).pack(fill="x", padx=10)
        items.append((outer, {"fill": "x"}))

        items.append((ui.section_label(body, "Updates", self.fonts), {"fill": "x", "pady": (24, 10)}))
        outer, box = ui.card(body)
        row = tk.Frame(box, bg=ui.PANEL)
        row.pack(fill="x")
        ui.Switch(row, self.state.get("auto_update", True), self.set_auto_update).pack(side="right")
        tk.Label(row, text="Keep installed mods up to date automatically", bg=ui.PANEL, fg=ui.TEXT,
                 font=self.fonts.body, anchor="w").pack(side="left", fill="x", expand=True)
        row = tk.Frame(box, bg=ui.PANEL)
        row.pack(fill="x", pady=(14, 0))
        ui.Switch(row, self.state.get("sound", True), self.set_sound).pack(side="right")
        tk.Label(row, text="Play the intro sound when the launcher opens", bg=ui.PANEL, fg=ui.TEXT,
                 font=self.fonts.body, anchor="w").pack(side="left", fill="x", expand=True)
        row = tk.Frame(box, bg=ui.PANEL)
        row.pack(fill="x", pady=(14, 0))
        self.check_button = ui.Button(row, "Check for updates", self.check_updates, self.fonts.button, height=34,
                                      kind="secondary", width=160)
        self.check_button.set_enabled(not self.busy)
        self.check_button.pack(side="right")
        version = self.manifest.get("version")
        tk.Label(row, text=("Mod list version %s" % version) if version else "Mod list not downloaded yet",
                 bg=ui.PANEL, fg=ui.FAINT, font=self.fonts.small, anchor="w").pack(side="left")
        items.append((outer, {"fill": "x"}))

        items.append((ui.section_label(body, "Community", self.fonts), {"fill": "x", "pady": (24, 10)}))
        outer, box = ui.card(body)
        ui.Button(box, "Join the Discord", self.open_discord, self.fonts.button, height=38, width=170,
                  colors=(ui.DISCORD, None)).pack(side="right")
        tk.Label(box, text="News, new mods and help on the ARTEFACT Discord.", bg=ui.PANEL, fg=ui.TEXT,
                 font=self.fonts.body, anchor="w").pack(side="left", fill="x", expand=True)
        items.append((outer, {"fill": "x"}))

        items.append((ui.section_label(body, "How it works", self.fonts), {"fill": "x", "pady": (24, 10)}))
        outer, box = ui.card(body)
        for number, step in enumerate(HOW_IT_WORKS, 1):
            line = tk.Frame(box, bg=ui.PANEL)
            line.pack(fill="x", pady=4)
            badge = tk.Canvas(line, width=22, height=22, bg=ui.PANEL, highlightthickness=0)
            badge.pack(side="left", anchor="n", padx=(0, 12))
            ui.gradient_rounded(badge, 0, 0, 22, 22, 6, *ui.BRAND)
            badge.create_text(11, 11, text=str(number), fill="#ffffff", font=self.fonts.label)
            ui.wrap_label(tk.Label(line, text=step, bg=ui.PANEL, fg=ui.TEXT, font=self.fonts.body, anchor="w",
                                   justify="left")).pack(side="left", fill="x", expand=True)
        items.append((outer, {"fill": "x", "pady": (0, 8)}))
        return items

    # ------------------------------------------------------------ actions

    def open_discord(self):
        webbrowser.open(core.DISCORD_URL)

    def set_auto_update(self, value):
        self.state["auto_update"] = value
        core.save_state(self.state)
        self.status.set("ok", "Automatic updates %s." % ("on" if value else "off"))

    def set_sound(self, value):
        self.state["sound"] = value
        core.save_state(self.state)
        self.status.set("ok", "Intro sound %s." % ("on" if value else "off"))
        if value:
            self.play_intro_sound()

    def play_intro_sound(self):
        """Plays assets/startup.wav without blocking; silently skipped if it's missing or there's no audio."""
        path = os.path.join(core.HERE, "assets", "startup.wav")
        if not self.state.get("sound", True) or not os.path.isfile(path):
            return
        try:
            import winsound
            winsound.PlaySound(path, winsound.SND_FILENAME | winsound.SND_ASYNC | winsound.SND_NODEFAULT)
        except (ImportError, RuntimeError):
            pass

    def choose_folder(self, client):
        path = filedialog.askdirectory(parent=self.root, title="Choose %s" % client["folder_hint"])
        if not path:
            return
        path = os.path.normpath(path)
        error = core.validate_folder(client, path)
        if error:
            self.status.set("error", error)
            return
        self.state["folders"][client["id"]] = path
        core.save_state(self.state)
        self.status.set("ok", "%s folder saved." % client["name"])
        self.rerender()

    def run_in_background(self, work, busy_text, button=None, busy_label=None):
        if self.busy:
            return
        self.busy = True
        self.status.set("busy", busy_text)
        for other in self.action_buttons:
            if other is not button:
                other.set_enabled(False)
        if button is not None and busy_label:
            button.set_text(busy_label)
            button.set_progress(0.0)

        def worker():
            try:
                result = ("ok", work())
            except Exception as error:
                result = ("error", friendly_error(error))
            self.root.after(0, self.finish, result)

        threading.Thread(target=worker, daemon=True).start()

    def finish(self, result):
        self.busy = False
        self.rerender()
        self.status.set(*result)

    def progress_to(self, button):
        def callback(done, total):
            if total and button is not None:
                self.root.after(0, lambda: button.winfo_exists() and button.set_progress(done / total))
        return callback

    def run_install(self, client, mod, button=None):
        def work():
            core.install_mod(mod, core.mods_folder(client, self.state), self.settings["update_url"],
                             self.progress_to(button))
            return "%s installed. It's active in %s now." % (mod["title"], client["name"])
        self.run_in_background(work, "Installing %s..." % mod["title"], button, "Installing...")

    def run_uninstall(self, client, mod, button=None):
        def work():
            core.uninstall_mod(mod, core.mods_folder(client, self.state))
            return "%s uninstalled from %s." % (mod["title"], client["name"])
        self.run_in_background(work, "Uninstalling %s..." % mod["title"], button, None)

    def check_updates(self):
        url = self.settings.get("update_url")
        if not url:
            self.status.set("warn", "This launcher has no update address. Ask for a new copy on the Discord.")
            return

        def work():
            manifest = core.fetch_manifest(url)
            # a new launcher comes first: it restarts, then handles the mods on its next start
            if core.update_launcher(manifest, url):
                self.root.after(1400, self.restart)
                return "New launcher version installed. Restarting..."
            self.manifest = manifest
            self.state["manifest"] = manifest
            core.save_state(self.state)
            updated = []
            if self.state.get("auto_update", True):
                for client in self.clients():
                    folder = core.mods_folder(client, self.state)
                    if not folder:
                        continue
                    for mod in self.client_mods(client["id"]):
                        if core.mod_status(mod, folder) == "update":
                            core.install_mod(mod, folder, url)
                            updated.append(mod["title"])
            if updated:
                return "Updated: %s." % ", ".join(updated)
            return "Everything is up to date."
        self.run_in_background(work, "Checking for updates...")

    def restart(self):
        subprocess.Popen([sys.executable, os.path.join(core.HERE, "joueur.pyw")], cwd=core.HERE)
        self.root.destroy()


def main():
    root = tk.Tk()
    PlayerApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
