"""ARTEFACT theme: dark palette, animated widgets and transitions (plain tkinter, no extra install)."""

import math
import os
import time
import tkinter as tk
import tkinter.font as tkfont

BG = "#0d0f13"
SIDEBAR = "#090b0e"
PANEL = "#14171d"
PANEL_HOVER = "#1a1e26"
BORDER = "#232832"
TEXT = "#eef0f3"
MUTED = "#8b93a1"
FAINT = "#5c6370"
GREEN = "#3ddc84"
YELLOW = "#f5c542"
RED = "#ff5c5c"
SWITCH_OFF = "#353b47"
DISABLED_BG = "#20242c"
DISABLED_TEXT = "#5f6672"
DISCORD = "#5865f2"

# brand: the BO7-style blue to orange sweep
BRAND = ("#2f8cff", "#ff7a1a")
ACCENT = BRAND[1]
ACCENT_TEXT = "#14100c"

ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets")


# ---------------------------------------------------------------- colours

def hex_rgb(color):
    color = color.lstrip("#")
    return tuple(int(color[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    """Blend two #rrggbb colours, t=0 gives a, t=1 gives b."""
    ra, ga, ba = hex_rgb(a)
    rb, gb, bb = hex_rgb(b)
    t = max(0.0, min(1.0, t))
    return "#%02x%02x%02x" % (round(ra + (rb - ra) * t), round(ga + (gb - ga) * t), round(ba + (bb - ba) * t))


def is_light(color):
    r, g, b = hex_rgb(color)
    return (0.299 * r + 0.587 * g + 0.114 * b) / 255 > 0.6


def text_on(color):
    return "#101216" if is_light(color) else "#ffffff"


def client_colors(client):
    """(main colour, second colour or None) for a client dict."""
    return client.get("color", ACCENT), client.get("color2")


# ---------------------------------------------------------------- animation

def ease_out(t):
    return 1 - (1 - t) ** 3


def ease_in_out(t):
    return 4 * t * t * t if t < 0.5 else 1 - (-2 * t + 2) ** 3 / 2


def tween(widget, duration, step, done=None, ease=ease_out):
    """Calls step(eased 0..1) about 60 times a second for duration ms; stops quietly if the widget dies."""
    start = time.perf_counter()
    # timers live on the window, so a page destroyed mid-animation doesn't leave dangling Tcl callbacks
    clock = widget.winfo_toplevel()

    def tick():
        try:
            if not widget.winfo_exists():
                return
            t = min(1.0, (time.perf_counter() - start) * 1000 / duration)
            step(ease(t))
            if t < 1:
                clock.after(15, tick)
            elif done:
                done()
        except tk.TclError:
            pass

    tick()


class Tweened:
    """A value that animates towards a target; newer animations cancel older ones."""

    def __init__(self, widget, value, on_change, duration=150):
        self.widget = widget
        self.value = value
        self.on_change = on_change
        self.duration = duration
        self.token = 0

    def to(self, target):
        self.token += 1
        token, start = self.token, self.value

        def step(t):
            if token == self.token:
                self.value = start + (target - start) * t
                self.on_change()

        tween(self.widget, self.duration, step)


def descendants(widget):
    yield widget
    for child in widget.winfo_children():
        yield from descendants(child)


def pointer_inside(widget):
    x, y = widget.winfo_pointerxy()
    left, top = widget.winfo_rootx(), widget.winfo_rooty()
    return left <= x < left + widget.winfo_width() and top <= y < top + widget.winfo_height()


def hover_glow(outer, color):
    """Animates a card's border towards color while the mouse is over it (children included)."""
    glow = Tweened(outer, 0.0, lambda: outer.configure(bg=mix(BORDER, color, glow.value * 0.75)), 180)

    def leave(event):
        if not pointer_inside(outer):
            glow.to(0.0)

    for widget in descendants(outer):
        widget.bind("<Enter>", lambda e: glow.to(1.0), add="+")
        widget.bind("<Leave>", leave, add="+")


def reveal(items, delay=0, step=60, rise=18):
    """Packs widgets one after another, each sliding up into place. items: [(widget, pack kwargs)]."""
    for index, (widget, options) in enumerate(items):
        top, bottom = options.get("pady", (0, 0))

        def show(widget=widget, options=options, top=top, bottom=bottom):
            try:
                widget.pack(**dict(options, pady=(top + rise, bottom)))
                tween(widget, 280, lambda t: widget.pack_configure(pady=(top + rise * (1 - t), bottom)))
            except tk.TclError:
                pass

        widget.after(delay + index * step, show)


def slide_in(frame, distance=36, duration=320):
    """Places a page frame in its parent and slides it in from the right."""
    frame.place(x=distance, y=0, relwidth=1, relheight=1)
    tween(frame, duration, lambda t: frame.place_configure(x=round(distance * (1 - t))))


# ---------------------------------------------------------------- fonts and window

class Fonts:
    def __init__(self, root):
        families = set(tkfont.families(root))
        display = "Bahnschrift" if "Bahnschrift" in families else "Segoe UI"
        body = "Segoe UI" if "Segoe UI" in families else "TkDefaultFont"
        semibold = "Segoe UI Semibold" if "Segoe UI Semibold" in families else body
        self.display = display
        self.logo = (display, 22, "bold")
        self.logo_sub = (display, 9, "bold")
        self.hero = (display, 32, "bold")
        self.title = (display, 18, "bold")
        self.h2 = (semibold, 13)
        self.button = (semibold, 11)
        self.button_big = (display, 15, "bold")
        self.nav = (semibold, 11)
        self.label = (display, 10, "bold")
        self.body = (body, 11)
        self.small = (body, 10)
        self.tiny = (body, 9)
        self.badge = (display, 9, "bold")
        self.mono = ("Consolas", 11)


def setup_window(root, title, width, height, min_width=None, min_height=None):
    root.title(title)
    root.configure(bg=BG)
    x = max(0, (root.winfo_screenwidth() - width) // 2)
    y = max(0, (root.winfo_screenheight() - height) // 3)
    root.geometry("%dx%d+%d+%d" % (width, height, x, y))
    root.minsize(min_width or width - 120, min_height or height - 120)
    # dark title bar on Windows 10/11 (ignored elsewhere)
    try:
        import ctypes
        root.update_idletasks()
        hwnd = ctypes.windll.user32.GetParent(root.winfo_id())
        value = ctypes.c_int(1)
        ctypes.windll.dwmapi.DwmSetWindowAttribute(hwnd, 20, ctypes.byref(value), ctypes.sizeof(value))
    except Exception:
        pass
    return Fonts(root)


def load_image(name):
    """PhotoImage from assets/, or None when the file is missing."""
    path = os.path.join(ASSETS, name)
    if not os.path.isfile(path):
        return None
    try:
        return tk.PhotoImage(file=path)
    except tk.TclError:
        return None


# ---------------------------------------------------------------- drawing helpers

def short_path(path, limit=78):
    """Keeps the start and the end of a long path."""
    if len(path) <= limit:
        return path
    keep = (limit - 3) // 2
    return path[:keep] + "..." + path[-keep:]


def wrap_label(label):
    """Makes a label re-wrap its text to its own width."""
    label.bind("<Configure>", lambda e: label.configure(wraplength=max(e.width - 4, 60)), add="+")
    return label


def rounded_rect(canvas, x1, y1, x2, y2, radius, **kwargs):
    r = min(radius, (x2 - x1) / 2, (y2 - y1) / 2)
    points = [
        x1 + r, y1, x2 - r, y1, x2, y1, x2, y1 + r,
        x2, y2 - r, x2, y2, x2 - r, y2, x1 + r, y2,
        x1, y2, x1, y2 - r, x1, y1 + r, x1, y1,
    ]
    return canvas.create_polygon(points, smooth=True, **kwargs)


def gradient_rounded(canvas, x1, y1, x2, y2, radius, c1, c2=None, upto=None):
    """Rounded shape filled column by column (left c1 to right c2); upto clips it at that x."""
    width = int(x2 - x1)
    r = min(radius, width / 2, (y2 - y1) / 2)
    for i in range(width):
        x = x1 + i
        if upto is not None and x > upto:
            break
        if i < r:
            dy = r - math.sqrt(max(r * r - (r - i) ** 2, 0))
        elif i > width - r:
            dy = r - math.sqrt(max(r * r - (i - (width - r)) ** 2, 0))
        else:
            dy = 0
        color = mix(c1, c2, i / max(width - 1, 1)) if c2 else c1
        canvas.create_line(x, y1 + dy, x, y2 - dy, fill=color)


# ---------------------------------------------------------------- widgets

class Button(tk.Canvas):
    """Rounded animated button.

    kind: primary (filled with colors, gradient when two), secondary (outlined, border glows on hover),
    danger (outlined, turns red), ghost (text only).
    """

    def __init__(self, parent, text, command, font, height=40, kind="primary", width=None, colors=None, glow=None):
        super().__init__(parent, height=height, bg=parent.cget("bg"), highlightthickness=0, bd=0, cursor="hand2")
        if width:
            self.configure(width=width)
        self.text = text
        self.command = command
        self.font = font
        self.kind = kind
        self.colors = colors or BRAND
        self.glow = glow or MUTED
        self.enabled = True
        self.pressed = False
        self.progress = None
        self.hover = Tweened(self, 0.0, self.draw, 140)
        self.bind("<Configure>", lambda e: self.draw())
        self.bind("<Enter>", lambda e: self.hover.to(1.0))
        self.bind("<Leave>", lambda e: (self.hover.to(0.0), self._press(False)))
        self.bind("<ButtonPress-1>", lambda e: self._press(True))
        self.bind("<ButtonRelease-1>", self._release)

    def _press(self, pressed):
        self.pressed = pressed
        self.draw()

    def _release(self, event):
        inside = 0 <= event.x <= self.winfo_width() and 0 <= event.y <= self.winfo_height()
        self._press(False)
        if inside and self.enabled and self.command:
            self.command()

    def draw(self):
        self.delete("all")
        w, h = self.winfo_width(), self.winfo_height()
        if w < 4:
            return
        hv = self.hover.value if self.enabled else 0.0
        y_shift = 1 if self.pressed else 0

        if self.kind == "ghost":
            color = DISABLED_TEXT if not self.enabled else mix(MUTED, TEXT, hv)
            self.create_text(w / 2, h / 2 + y_shift, text=self.text, fill=color, font=self.font)
            return

        if self.kind == "primary":
            c1, c2 = self.colors
            if not self.enabled and self.progress is None:
                rounded_rect(self, 1, 1, w - 1, h - 1, 9, fill=DISABLED_BG, outline=DISABLED_BG)
                self.create_text(w / 2, h / 2, text=self.text, fill=DISABLED_TEXT, font=self.font)
                return
            lift = 0.14 * hv - (0.12 if self.pressed else 0)
            a = mix(c1, "#ffffff", lift) if lift >= 0 else mix(c1, "#000000", -lift)
            b = (mix(c2, "#ffffff", lift) if lift >= 0 else mix(c2, "#000000", -lift)) if c2 else None
            if self.progress is not None:
                gradient_rounded(self, 1, 1, w - 1, h - 1, 9, mix(a, BG, 0.65), mix(b, BG, 0.65) if b else None)
                gradient_rounded(self, 1, 1, w - 1, h - 1, 9, a, b, upto=1 + (w - 2) * self.progress)
            elif b:
                gradient_rounded(self, 1, 1, w - 1, h - 1, 9, a, b)
            else:
                rounded_rect(self, 1, 1, w - 1, h - 1, 9, fill=a, outline=a)
            self.create_text(w / 2, h / 2 + y_shift, text=self.text, fill=text_on(c1), font=self.font)
            return

        if not self.enabled:
            fill, outline, text = PANEL, BORDER, DISABLED_TEXT
        elif self.kind == "danger":
            fill = mix(PANEL, "#2a1517", hv)
            outline = mix(BORDER, RED, hv)
            text = mix(TEXT, RED, hv)
        else:
            fill = mix(PANEL, PANEL_HOVER, hv)
            outline = mix(BORDER, self.glow, hv * 0.8)
            text = TEXT
        rounded_rect(self, 1, 1, w - 1, h - 1, 9, fill=fill, outline=outline)
        self.create_text(w / 2, h / 2 + y_shift, text=self.text, fill=text, font=self.font)

    def set_enabled(self, enabled):
        self.enabled = enabled
        self.configure(cursor="hand2" if enabled else "arrow")
        self.draw()

    def set_text(self, text):
        self.text = text
        self.draw()

    def set_progress(self, fraction):
        self.progress = fraction
        self.draw()


class Switch(tk.Canvas):
    """On/off switch whose knob slides. on_change(value) is called after a click."""

    W, H = 46, 26

    def __init__(self, parent, value, on_change, color=GREEN):
        super().__init__(parent, width=self.W, height=self.H, bg=parent.cget("bg"),
                         highlightthickness=0, bd=0, cursor="hand2")
        self.value = value
        self.color = color
        self.on_change = on_change
        self.pos = Tweened(self, 1.0 if value else 0.0, self.draw, 180)
        self.bind("<Button-1>", self._click)
        self.draw()

    def draw(self):
        self.delete("all")
        p = self.pos.value
        color = mix(SWITCH_OFF, self.color, p)
        rounded_rect(self, 1, 1, self.W - 1, self.H - 1, 13, fill=color, outline=color)
        x = 13 + (self.W - 27) * p
        self.create_oval(x - 9, 4, x + 9, self.H - 4, fill="#ffffff", outline="")

    def _click(self, event):
        self.set(not self.value)
        self.on_change(self.value)

    def set(self, value):
        self.value = value
        self.pos.to(1.0 if value else 0.0)


class StatusLine(tk.Frame):
    """Coloured dot + text: ok (green), busy (pulsing orange), warn (yellow), error (red)."""

    COLORS = {"ok": GREEN, "busy": ACCENT, "warn": YELLOW, "error": RED}

    def __init__(self, parent, fonts):
        super().__init__(parent, bg=parent.cget("bg"))
        self.dot = tk.Canvas(self, width=14, height=14, bg=self.cget("bg"), highlightthickness=0)
        self.dot.pack(side="left", padx=(0, 8))
        self.label = wrap_label(tk.Label(self, text="", bg=self.cget("bg"), fg=MUTED, font=fonts.small,
                                         anchor="w", justify="left"))
        self.label.pack(side="left", fill="x", expand=True)
        self.kind = "ok"
        self.phase = 0.0
        self.timer = None
        self.bind("<Destroy>", lambda e: self.timer and self.after_cancel(self.timer))
        self._pulse()

    def _pulse(self):
        try:
            self.dot.delete("all")
            color = self.COLORS[self.kind]
            if self.kind == "busy":
                self.phase = (self.phase + 0.08) % (2 * math.pi)
                halo = (math.sin(self.phase) + 1) / 2
                r = 4 + 3 * halo
                self.dot.create_oval(7 - r, 7 - r, 7 + r, 7 + r, fill=mix(BG, color, 0.35), outline="")
            self.dot.create_oval(3, 3, 11, 11, fill=color, outline="")
            self.timer = self.after(30 if self.kind == "busy" else 250, self._pulse)
        except tk.TclError:
            pass

    def set(self, kind, text):
        self.kind = kind
        self.label.configure(text=text, fg=TEXT if kind in ("ok", "busy") else self.COLORS[kind])


def chip(parent, text, color, fonts):
    """Small tinted pill: bg is a dark tint of color, text in color."""
    return tk.Label(parent, text=text, bg=mix(PANEL, color, 0.16), fg=color, font=fonts.badge, padx=9, pady=3)


def client_badge(parent, client, size=40):
    """The client's thumbnail, or a rounded square with its short name when there's no image."""
    image = load_image("%s_thumb.png" % client["id"])
    canvas = tk.Canvas(parent, width=size, height=size, bg=parent.cget("bg"), highlightthickness=0, bd=0)
    if image and size == 40:
        canvas.create_image(size / 2, size / 2, image=image)
        canvas.image = image
    else:
        c1, c2 = client_colors(client)
        gradient_rounded(canvas, 1, 1, size - 1, size - 1, 9, c1, c2)
        canvas.create_text(size / 2, size / 2, text=client.get("short", "?"), fill=text_on(c1),
                           font=("Bahnschrift", 10 if size < 50 else 13, "bold"))
    return canvas


class NavItem(tk.Frame):
    """Sidebar entry with thumbnail or icon; background eases on hover, coloured bar when selected."""

    def __init__(self, parent, fonts, title, subtitle, command, client=None, icon=None, color=ACCENT):
        super().__init__(parent, bg=SIDEBAR, cursor="hand2")
        self.command = command
        self.selected = False
        self.color = client_colors(client)[0] if client else color
        self.hover = Tweened(self, 0.0, self._paint, 140)
        self.bar = tk.Frame(self, bg=SIDEBAR, width=3)
        self.bar.pack(side="left", fill="y")
        self.inner = tk.Frame(self, bg=SIDEBAR, padx=16, pady=9)
        self.inner.pack(side="left", fill="x", expand=True)
        if client:
            client_badge(self.inner, client).pack(side="left", padx=(0, 12))
        elif icon:
            tk.Label(self.inner, text=icon, bg=SIDEBAR, fg=MUTED, font=("Segoe UI Symbol", 15), width=2).pack(
                side="left", padx=(0, 10))
        texts = tk.Frame(self.inner, bg=SIDEBAR)
        texts.pack(side="left", fill="x", expand=True)
        self.title = tk.Label(texts, text=title, bg=SIDEBAR, fg=TEXT, font=fonts.nav, anchor="w")
        self.title.pack(fill="x")
        self.subtitle = tk.Label(texts, text=subtitle, bg=SIDEBAR, fg=FAINT, font=fonts.tiny, anchor="w")
        if subtitle:
            self.subtitle.pack(fill="x")
        for widget in descendants(self):
            widget.bind("<Button-1>", lambda e: self.command())
            widget.bind("<Enter>", lambda e: self.hover.to(1.0))
            widget.bind("<Leave>", lambda e: None if pointer_inside(self) else self.hover.to(0.0))

    def _paint(self):
        base = mix(SIDEBAR, "#151922", 1.0 if self.selected else 0.0)
        bg = mix(base, PANEL_HOVER, self.hover.value * (0.4 if self.selected else 1.0))
        for widget in descendants(self.inner):
            widget.configure(bg=bg)
        self.bar.configure(bg=self.color if self.selected else bg)
        self.title.configure(fg=TEXT if self.selected or self.hover.value > 0.5 else mix(MUTED, TEXT, 0.6))

    def set_selected(self, selected):
        self.selected = selected
        self._paint()

    def set_subtitle(self, text):
        self.subtitle.configure(text=text)
        if text and not self.subtitle.winfo_ismapped():
            self.subtitle.pack(fill="x")


class Banner(tk.Canvas):
    """Client artwork across the top of a page, with its name; slides and fades in when played."""

    def __init__(self, parent, fonts, client, subtitle, pill=None, height=230):
        super().__init__(parent, height=height, bg=BG, highlightthickness=0, bd=0)
        self.fonts = fonts
        self.client = client
        self.subtitle = subtitle
        self.pill = pill
        self.image = load_image("%s_banner.png" % client["id"])
        self.t = 1.0
        self.bind("<Configure>", lambda e: self.draw())

    def play(self):
        self.t = 0.0
        tween(self, 700, self._step)

    def _step(self, t):
        self.t = t
        self.draw()

    def draw(self):
        self.delete("all")
        w, h = self.winfo_width(), self.winfo_height()
        if w < 10:
            return
        t = self.t
        c1, c2 = client_colors(self.client)
        if self.image:
            self.create_image(w / 2 + 40 * (1 - t), h / 2, image=self.image)
        else:
            # no artwork: dim diagonal sweep in the client's colours
            for i in range(0, w, 2):
                color = mix(mix(c1, BG, 0.78), mix(c2 or c1, BG, 0.86), i / w)
                self.create_line(i, 0, i, h, fill=color, width=2)
            for y in range(h - 70, h, 2):
                self.create_line(0, y, w, y, fill=mix(mix(c1, BG, 0.8), BG, (y - (h - 70)) / 70), width=2)

        fade = min(1.0, t * 1.4)
        x = 36 - 14 * (1 - t)
        name_y = h - 92
        self.create_text(x + 2, name_y + 2, text=self.client["name"].upper(), anchor="w", fill="#000000",
                         font=self.fonts.hero)
        self.create_text(x, name_y, text=self.client["name"].upper(), anchor="w", fill=mix(BG, "#ffffff", fade),
                         font=self.fonts.hero)
        line_w = 110 * ease_out(min(1.0, t * 1.2))
        if c2:
            gradient_rounded(self, x, name_y + 26, x + max(line_w, 2), name_y + 30, 2, c1, c2)
        else:
            self.create_rectangle(x, name_y + 26, x + line_w, name_y + 30, fill=c1, outline="")
        self.create_text(x, name_y + 52, text=self.subtitle, anchor="w", fill=mix(BG, "#c9ced6", fade),
                         font=self.fonts.body)
        if self.pill:
            font = self.fonts.badge
            pill_w = tkfont.Font(font=font).measure(self.pill) + 22
            px, py = w - 28 - pill_w, 24
            rounded_rect(self, px, py, px + pill_w, py + 26, 13, fill=mix(BG, c1, 0.25 * fade + 0.05),
                         outline=mix(BG, c1, 0.6 * fade))
            self.create_text(px + pill_w / 2, py + 13, text=self.pill, fill=mix(BG, "#ffffff", fade), font=font)


class Logo(tk.Canvas):
    """ARTEFACT wordmark with the brand sweep under it."""

    def __init__(self, parent, fonts, subtitle="V1 LAUNCHER"):
        super().__init__(parent, height=74, bg=parent.cget("bg"), highlightthickness=0, bd=0)
        self.fonts = fonts
        self.subtitle = subtitle
        self.bind("<Configure>", lambda e: self.draw())

    def draw(self):
        self.delete("all")
        self.create_text(0, 24, text="ARTEFACT", anchor="w", fill=TEXT, font=self.fonts.logo)
        gradient_rounded(self, 1, 44, 128, 47, 1, BRAND[0], BRAND[1])
        self.create_text(0, 62, text="  ".join(self.subtitle), anchor="w", fill=FAINT, font=self.fonts.logo_sub)


class Splash(tk.Canvas):
    """Startup animation over the whole window: wordmark types in, sweep grows, then it slides away."""

    def __init__(self, root, fonts, subtitle="V1 LAUNCHER", on_done=None):
        super().__init__(root, bg=BG, highlightthickness=0, bd=0)
        self.fonts = fonts
        self.subtitle = subtitle
        self.on_done = on_done
        self.place(x=0, y=0, relwidth=1, relheight=1)
        self.tk.call("raise", self._w)  # Canvas.lift() raises canvas items, not the widget
        self.big = (fonts.display, 46, "bold")
        tween(self, 1100, self._intro, self._hold, ease=lambda t: t)

    def _intro(self, t):
        self.delete("all")
        w, h = self.winfo_width(), self.winfo_height()
        word = "ARTEFACT"
        shown = word[:max(0, min(len(word), int(len(word) * min(1.0, t * 1.5)) + 1))]
        cx, cy = w / 2, h / 2 - 20
        full = tkfont.Font(font=self.big).measure(word)
        self.create_text(cx - full / 2, cy, text=shown, anchor="w", fill=TEXT, font=self.big)
        grow = ease_out(max(0.0, min(1.0, (t - 0.35) / 0.65)))
        half = full / 2 * grow
        if half > 2:
            gradient_rounded(self, cx - half, cy + 40, cx + half, cy + 44, 2, BRAND[0], BRAND[1])
        sub_t = max(0.0, min(1.0, (t - 0.55) / 0.45))
        self.create_text(cx, cy + 72, text="   ".join(self.subtitle), fill=mix(BG, MUTED, sub_t),
                         font=self.fonts.label)

    def _hold(self):
        self.after(250, lambda: tween(self, 420, self._leave, self._finish, ease=ease_in_out))

    def _leave(self, t):
        self.place_configure(y=-round(self.winfo_height() * t))

    def _finish(self):
        self.destroy()
        if self.on_done:
            self.on_done()


class ScrollFrame(tk.Frame):
    """Vertical scrolling area with smooth wheel scrolling; put content in .body."""

    def __init__(self, parent, bg=BG):
        super().__init__(parent, bg=bg)
        self.canvas = tk.Canvas(self, bg=bg, highlightthickness=0, bd=0)
        self.canvas.pack(side="left", fill="both", expand=True)
        self.body = tk.Frame(self.canvas, bg=bg)
        self.window = self.canvas.create_window(0, 0, window=self.body, anchor="nw")
        self.body.bind("<Configure>", lambda e: self.canvas.configure(scrollregion=self.canvas.bbox("all")))
        self.canvas.bind("<Configure>", lambda e: self.canvas.itemconfigure(self.window, width=e.width))
        self.canvas.bind("<Enter>", lambda e: self.canvas.bind_all("<MouseWheel>", self._wheel))
        self.canvas.bind("<Leave>", lambda e: self.canvas.unbind_all("<MouseWheel>"))
        self.scroll = Tweened(self.canvas, 0.0, lambda: self.canvas.yview_moveto(self.scroll.value), 160)

    def _wheel(self, event):
        total = self.body.winfo_height()
        view = self.canvas.winfo_height()
        if total <= view:
            return
        self.scroll.value = self.canvas.yview()[0]
        self.scroll.to(max(0.0, min(1 - view / total, self.scroll.value - event.delta / 120 * 110 / total)))


def card(parent, padding=18, bg=PANEL):
    """A panel with a thin border. Returns (outer, inner) frames; outer's bg is the border colour."""
    outer = tk.Frame(parent, bg=BORDER)
    inner = tk.Frame(outer, bg=bg, padx=padding, pady=padding)
    inner.pack(fill="both", expand=True, padx=1, pady=1)
    return outer, inner


def section_label(parent, text, fonts):
    return tk.Label(parent, text=text.upper(), bg=parent.cget("bg"), fg=FAINT, font=fonts.label, anchor="w")


def entry(parent, variable, fonts, color=ACCENT):
    """Text field whose border lights up while it has focus."""
    border = tk.Frame(parent, bg=BORDER)
    field = tk.Entry(border, textvariable=variable, bg=BG, fg=TEXT, insertbackground=TEXT, relief="flat",
                     font=fonts.body)
    field.pack(fill="x", padx=1, pady=1, ipady=7, ipadx=6)
    field.bind("<FocusIn>", lambda e: border.configure(bg=color), add="+")
    field.bind("<FocusOut>", lambda e: border.configure(bg=BORDER), add="+")
    return border


def dialog(root, fonts, title, build, width=460, close_text="Close"):
    """Dark modal window that drops in; build(frame, close) fills it."""
    top = tk.Toplevel(root)
    top.withdraw()
    top.title(title)
    top.configure(bg=BG)
    top.transient(root)
    top.resizable(False, False)
    frame = tk.Frame(top, bg=BG, padx=26, pady=24)
    frame.pack(fill="both", expand=True)
    tk.Label(frame, text=title, bg=BG, fg=TEXT, font=fonts.title, anchor="w").pack(fill="x", pady=(0, 14))
    build(frame, top.destroy)
    if close_text:
        Button(frame, close_text, top.destroy, fonts.button, height=38, kind="secondary").pack(fill="x", pady=(18, 0))
    top.update_idletasks()
    x = root.winfo_rootx() + (root.winfo_width() - width) // 2
    y = root.winfo_rooty() + 70
    height = top.winfo_reqheight()
    top.geometry("%dx%d+%d+%d" % (width, height, x, y - 20))
    try:
        top.attributes("-alpha", 0.0)
    except tk.TclError:
        pass
    top.deiconify()
    top.grab_set()

    def step(t):
        top.geometry("%dx%d+%d+%d" % (width, height, x, y - 20 + round(20 * t)))
        try:
            top.attributes("-alpha", t)
        except tk.TclError:
            pass

    tween(top, 220, step)
    return top
