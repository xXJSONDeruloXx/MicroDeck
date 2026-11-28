// Gamescope's focus protocol on a plain X server. Steam in -steamos3 mode publishes which apps should be
// on top in GAMESCOPECTRL_BASELAYER_APPID (and GAMESCOPECTRL_BASELAYER_WINDOW) and reads back which apps
// have windows from GAMESCOPE_FOCUSABLE_APPS / _WINDOWS and GAMESCOPE_FOCUSED_*. This daemon plays the
// gamescope side: it works out each window's app the way gamescope does, publishes the focusable lists and
// activates the window of the first app in Steam's base-layer list through the window manager.
// A game window bigger than the panel (old Linux games open 800x600 or 1280x720 windows) would be cut off, as it would not
// be under gamescope, which scales it: mdeck-fit scales the whole X screen to such a window while it has the focus.
#define _GNU_SOURCE
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/extensions/XRes.h>
#include <dirent.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <signal.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#define STEAM_APPID 769
#define MAXW 256

static Display *d;
static Window root;
static Atom a_client_list, a_active, a_steam_game, a_bigpicture, a_overlay, a_input_focus, a_wm_state, a_pid, a_base_appid, a_base_window,
    a_focusable_apps, a_focusable_windows, a_focused_app, a_focused_app_gfx, a_focused_window;
static int verbose;
static const char *fit_cmd = "/usr/local/bin/mdeck-fit";   // MDECK_FIT overrides it (the tests)
static int base_w, base_h;      // the panel's own logical size, read with the screen unscaled
static Window fitted;           // the game window the screen is currently scaled to, 0 if none
static int fitted_w, fitted_h;

static int x_error(Display *dpy, XErrorEvent *e) { (void)dpy; (void)e; return 0; }

static long *get_cardinals(Window w, Atom prop, Atom type, unsigned long *n) {
  Atom t; int f; unsigned long after; unsigned char *data = NULL;
  *n = 0;
  if (XGetWindowProperty(d, w, prop, 0, 4096, False, type, &t, &f, n, &after, &data) != Success || !data)
    return NULL;
  if (f != 32) { XFree(data); *n = 0; return NULL; }
  return (long *)data;
}

static unsigned long get_cardinal(Window w, Atom prop, unsigned long dflt) {
  unsigned long n; long *v = get_cardinals(w, prop, AnyPropertyType, &n);
  unsigned long r = n ? (unsigned long)v[0] : dflt;
  if (v) XFree(v);
  return r;
}

static int read_file(const char *path, char *buf, size_t len) {
  FILE *f = fopen(path, "r");
  if (!f) return -1;
  size_t n = fread(buf, 1, len - 1, f);
  fclose(f);
  buf[n] = 0;
  return (int)n;
}

// Gamescope's GetAppIdFromPid: the app-steam-app<N>-*.scope cgroup, else the nearest `reaper` ancestor
// started as `reaper SteamLaunch AppId=<N> ...`.
static unsigned long appid_from_pid(unsigned long pid) {
  char path[64], buf[4096];
  for (int depth = 0; pid > 1 && depth < 64; depth++) {
    unsigned long id;
    snprintf(path, sizeof path, "/proc/%lu/cgroup", pid);
    if (read_file(path, buf, sizeof buf) > 0) {
      char *scope = strstr(buf, "app-steam-app");
      if (scope && sscanf(scope, "app-steam-app%lu-", &id) == 1 && id) return id;
    }
    snprintf(path, sizeof path, "/proc/%lu/cmdline", pid);
    int n = read_file(path, buf, sizeof buf);
    const char *base = n > 0 ? strrchr(buf, '/') : NULL;
    if (n > 0 && !strcmp(base ? base + 1 : buf, "reaper")) {
      int launch = 0;
      for (int i = 0; i < n; i += (int)strlen(buf + i) + 1) {
        launch |= !strcmp(buf + i, "SteamLaunch");
        if (launch && sscanf(buf + i, "AppId=%lu", &id) == 1 && id) return id;
      }
    }
    snprintf(path, sizeof path, "/proc/%lu/stat", pid);
    if (read_file(path, buf, sizeof buf) <= 0) break;
    char *paren = strrchr(buf, ')');
    unsigned long ppid;
    if (!paren || sscanf(paren + 1, " %*c %lu", &ppid) != 1) break;
    pid = ppid;
  }
  return 0;
}

// Windows that never set _NET_WM_PID (SDL 1.2 games, such as the Linux x86 ones run under FEX): the X server knows which
// process owns the connection (XRes), and that process sits under the same `reaper SteamLaunch` as the game.
static unsigned long client_pid(Window w) {
  XResClientIdSpec spec = {.client = w, .mask = XRES_CLIENT_ID_PID_MASK};
  XResClientIdValue *ids = NULL; long n = 0; unsigned long pid = 0;
  if (XResQueryClientIds(d, 1, &spec, &n, &ids) != Success) return 0;
  for (long i = 0; i < n; i++)
    if (XResGetClientIdType(&ids[i]) == XRES_CLIENT_ID_PID) pid = (unsigned long)XResGetClientPid(&ids[i]);
  XResClientIdsDestroy(n, ids);
  return pid;
}

static struct { Window w; unsigned long pid, appid; } cache[MAXW];
static int ncache;

static unsigned long window_appid(Window w, unsigned long pid) {
  if (get_cardinal(w, a_bigpicture, 0)) return STEAM_APPID;
  unsigned long id = get_cardinal(w, a_steam_game, 0);  // authoritative when present, as in gamescope
  if (id) return id;
  for (int i = 0; i < ncache; i++)
    if (cache[i].w == w && cache[i].pid == pid) return cache[i].appid;
  id = pid ? appid_from_pid(pid) : 0;
  if (ncache == MAXW) ncache = 0;
  cache[ncache].w = w; cache[ncache].pid = pid; cache[ncache].appid = id; ncache++;
  return id;
}

struct win { Window w; unsigned long appid, pid; };

static void activate(Window w) {
  if (verbose) fprintf(stderr, "mdeck-focus: activating 0x%lx\n", w);
  XEvent ev = {0};
  ev.xclient.type = ClientMessage;
  ev.xclient.window = w;
  ev.xclient.message_type = a_active;
  ev.xclient.format = 32;
  ev.xclient.data.l[0] = 2;  // source: pager, so the WM does not apply focus-stealing prevention
  ev.xclient.data.l[1] = CurrentTime;
  XSendEvent(d, root, False, SubstructureRedirectMask | SubstructureNotifyMask, &ev);
  XRaiseWindow(d, w);
}

// Scale the X screen to the focused game window when it is bigger than the panel (old Linux games open 800x600 or 1280x720 windows),
// letterboxed. Smaller windows are not magnified this way: a RandR transform that magnifies makes Wine see a smaller monitor and shrink
// the game's window to match, and the fit and its undoing then chase each other (measured with Sonic Mania's 424x240 window).
// Changing the screen is a modeset that blanks the panel for a moment, so a change waits until the wanted size has held still for
// SETTLE_MS (games resize and recreate their window several times while starting or switching between windowed and fullscreen), and
// going back to the panel's size because the game's window vanished waits GRACE_MS: Wine unmaps a window and maps a new one to change
// its mode, and resetting in between would blank the panel twice.
#define SETTLE_MS 300
#define GRACE_MS 700
static int pending;             // a change is waiting for its delay: the main loop wakes sooner
static int want_w, want_h;      // what the last pass wanted (0 x 0: the panel's own size), for which window, and since when
static Window want_win;
static long want_since;

static long now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec * 1000L + ts.tv_nsec / 1000000L;
}

// With mdeck-scale installed the screen is never resized: the game window is named in MDECK_SCALE_WINDOW and mdeck-scale, started here
// only while there is something to scale (it takes about 45 MB), draws it scaled on the composite overlay. Without it (or with
// MDECK_FIT set, as the tests do) the whole X screen is resized with mdeck-fit as before.
static int use_scaler;
static const char *scale_cmd = "/usr/local/bin/mdeck-scale";
static Atom a_scale_win;
static pid_t scaler_pid;

static void run_scaler(void) {
  if (scaler_pid > 0 && kill(scaler_pid, 0) == 0) return;
  scaler_pid = fork();
  if (scaler_pid == 0) {
    if (verbose) execl(scale_cmd, scale_cmd, "-v", (char *)NULL);
    else execl(scale_cmd, scale_cmd, (char *)NULL);
    _exit(1);
  }
}

static void apply_fit(int w, int h, Window win) {
  char cmd[256];
  if (use_scaler) {
    if (w) {
      long v = (long)win;
      XChangeProperty(d, root, a_scale_win, XA_CARDINAL, 32, PropModeReplace, (unsigned char *)&v, 1);
      XFlush(d);
      run_scaler();
    } else {
      XDeleteProperty(d, root, a_scale_win);
      XFlush(d);
    }
    if (verbose) fprintf(stderr, "mdeck-focus: scaler %s\n", w ? "on" : "off");
    return;
  }
  if (w) snprintf(cmd, sizeof cmd, "%s %d %d", fit_cmd, w, h);
  else snprintf(cmd, sizeof cmd, "%s reset", fit_cmd);
  if (verbose) fprintf(stderr, "mdeck-focus: %s\n", cmd);
  if (system(cmd) != 0) fprintf(stderr, "mdeck-focus: %s failed\n", cmd);
}

static void fit_screen(struct win *pick) {
  XWindowAttributes wa;
  int w = 0, h = 0;                       // the size the screen should have: 0 x 0 is the panel's own
  int steam = pick && pick->appid == STEAM_APPID;
  if (pick && !steam && XGetWindowAttributes(d, pick->w, &wa)) {
    int bigger = wa.width > base_w || wa.height > base_h;
    // magnifying is only safe without a screen change (see above); tiny windows (dialogs, splash screens) are left alone
    int smaller = use_scaler && wa.width < base_w && wa.height < base_h && wa.width >= 240 && wa.height >= 160;
    if (bigger || smaller) { w = wa.width; h = wa.height; }
  }
  Window win = w ? pick->w : 0;
  if (w != want_w || h != want_h || win != want_win) {
    want_w = w; want_h = h; want_win = win; want_since = now_ms();
  }
  // the scaler costs a GL start (several seconds of CPU while a launch is already short of it): wait out the short-lived dialogs Wine opens
  long wait = w ? (use_scaler ? 1000 : SETTLE_MS) : (steam ? 0 : GRACE_MS);
  int applied = w ? (fitted == pick->w && fitted_w == w && fitted_h == h) : !fitted;
  if (applied) {
    pending = 0;
  } else if (now_ms() - want_since < wait) {
    pending = 1;                           // not yet: the main loop comes back
    return;
  } else {
    pending = 0;
    if (w) {
      if (!use_scaler) {
        // undecorated and at the origin, so the picture is the window and nothing else. (mdeck-scale draws the window's own pixmap, which
        // has no frame and does not depend on where the window is; and games react to being moved: Sonic Mania shrinks its window by a
        // third when it is moved, so the window is left alone.)
        Atom motif = XInternAtom(d, "_MOTIF_WM_HINTS", False);
        long hints[5] = {2, 0, 0, 0, 0};
        XChangeProperty(d, pick->w, motif, motif, 32, PropModeReplace, (unsigned char *)hints, 5);
        XMoveWindow(d, pick->w, 0, 0);
        XFlush(d);
      }
      if (use_scaler || !(fitted && fitted_w == w && fitted_h == h)) apply_fit(w, h, pick->w);   // a new window of the same size needs no modeset
      fitted = pick->w; fitted_w = w; fitted_h = h;
    } else {
      apply_fit(0, 0, 0);
      fitted = 0;
    }
  }
  if (w && fitted == pick->w && !use_scaler) {
    // Games centre their window on the screen they saw (SDL does it after it maps): put it back at the origin whenever it drifts
    int rx = 0, ry = 0; Window child;
    if (XTranslateCoordinates(d, pick->w, root, 0, 0, &rx, &ry, &child) && (rx != 0 || ry != 0)) {
      if (verbose) fprintf(stderr, "mdeck-focus: moving 0x%lx from %d,%d to the origin\n", pick->w, rx, ry);
      XMoveWindow(d, pick->w, 0, 0);
    }
  }
}

// While a game launches or runs, Steam's web helper (the Steam UI) is kept to one core: during a launch it used 150-240 % CPU of the 400 %
// the container setup and Wine need, and a launch took 117 and 110 s with it pinned against 128 and 131 s without. It gets every core
// back while Steam's menu is open (the UI has to be quick then) and when no game is running. MDECK_UI_PIN=0 turns this off.
static int pin_enabled = 1, pin_state = -1, ncpu = 4;
static long pin_checked;

static void set_web_affinity(int pin) {
  cpu_set_t set;
  CPU_ZERO(&set);
  if (pin) CPU_SET(ncpu - 1, &set);
  else for (int i = 0; i < ncpu && i < CPU_SETSIZE; i++) CPU_SET(i, &set);
  DIR *proc = opendir("/proc");
  if (!proc) return;
  struct dirent *e;
  while ((e = readdir(proc))) {
    int pid = atoi(e->d_name);
    char path[64], comm[32];
    if (pid <= 1) continue;
    snprintf(path, sizeof path, "/proc/%d/comm", pid);
    if (read_file(path, comm, sizeof comm) <= 0 || strncmp(comm, "steamwebhelper", 14)) continue;
    snprintf(path, sizeof path, "/proc/%d/task", pid);
    DIR *tasks = opendir(path);
    if (!tasks) continue;
    struct dirent *t;
    while ((t = readdir(tasks))) {
      int tid = atoi(t->d_name);
      if (tid > 0) sched_setaffinity(tid, sizeof set, &set);
    }
    closedir(tasks);
  }
  closedir(proc);
}

// Is a game being launched or running? (`reaper SteamLaunch AppId=<N>` exists from the moment Steam starts the launch, long before a window)
static int game_launching(void) {
  DIR *proc = opendir("/proc");
  if (!proc) return 0;
  struct dirent *e;
  int found = 0;
  while (!found && (e = readdir(proc))) {
    int pid = atoi(e->d_name);
    char path[64], buf[512];
    if (pid <= 1) continue;
    snprintf(path, sizeof path, "/proc/%d/cmdline", pid);
    int n = read_file(path, buf, sizeof buf);
    found = n > 0 && memmem(buf, n, "reaper", 6) && memmem(buf, n, "SteamLaunch", 11) && memmem(buf, n, "AppId=", 6);
  }
  closedir(proc);
  return found;
}

static void update_pin(int game_in_front, int menu_open) {
  if (!pin_enabled) return;
  long now = (long)time(NULL);
  if (now == pin_checked) return;   // at most once a second
  pin_checked = now;
  int want = !menu_open && (game_in_front || game_launching());
  if (want || want != pin_state) {  // while pinned, again every pass: new helper processes keep appearing
    set_web_affinity(want);
    if (verbose && want != pin_state) fprintf(stderr, "mdeck-focus: web helper %s\n", want ? "pinned to one core" : "released");
  }
  pin_state = want;
}

static void sync_focus(void) {
  unsigned long n;
  long *clients = get_cardinals(root, a_client_list, XA_WINDOW, &n);
  struct win wins[MAXW]; int nw = 0;
  Window overlay = 0; int overlay_input = 0;
  for (unsigned long i = 0; i < n && nw < MAXW; i++) {
    Window w = (Window)clients[i];
    XWindowAttributes wa;
    XSelectInput(d, w, PropertyChangeMask);
    // Wine minimizes a fullscreen game that loses focus; gamescope never iconifies, so a minimized client
    // stays focusable here and activating it restores it.
    int iconic = get_cardinal(w, a_wm_state, 0) == IconicState;
    if (!XGetWindowAttributes(d, w, &wa) || (wa.map_state != IsViewable && !iconic) || wa.class == InputOnly ||
        (wa.width <= 1 && wa.height <= 1))
      continue;
    // STEAM_OVERLAY windows (Steam's in-game menu) are never the base layer; gamescope draws them on top,
    // and they take input while STEAM_INPUT_FOCUS is set.
    if (get_cardinal(w, a_overlay, 0)) {
      int input = get_cardinal(w, a_input_focus, 0) != 0;
      if (!overlay || input) { overlay = w; overlay_input = input; }
      continue;
    }
    unsigned long pid = get_cardinal(w, a_pid, 0);
    if (!pid) pid = client_pid(w);
    unsigned long id = window_appid(w, pid);
    if (!id) continue;
    wins[nw++] = (struct win){w, id, pid};
  }
  if (clients) XFree(clients);

  long apps[MAXW], triples[MAXW * 3]; int na = 0;
  for (int i = 0; i < nw; i++) {
    int seen = 0;
    for (int j = 0; j < na; j++) seen |= apps[j] == (long)wins[i].appid;
    if (!seen) apps[na++] = (long)wins[i].appid;
    triples[i * 3] = (long)wins[i].w; triples[i * 3 + 1] = (long)wins[i].appid; triples[i * 3 + 2] = (long)wins[i].pid;
  }
  XChangeProperty(d, root, a_focusable_apps, XA_CARDINAL, 32, PropModeReplace, (unsigned char *)apps, na);
  XChangeProperty(d, root, a_focusable_windows, XA_CARDINAL, 32, PropModeReplace, (unsigned char *)triples, nw * 3);

  struct win *pick = NULL;
  unsigned long base_win = get_cardinal(root, a_base_window, 0);
  for (int i = 0; i < nw && base_win; i++) if (wins[i].w == base_win) pick = &wins[i];
  unsigned long nb;
  long *base = get_cardinals(root, a_base_appid, XA_CARDINAL, &nb);
  // _NET_CLIENT_LIST is in mapping order: the last match is the most recently mapped, gamescope's tie-break.
  for (unsigned long b = 0; b < nb && !pick; b++)
    for (int i = nw - 1; i >= 0 && !pick; i--)
      if ((long)wins[i].appid == base[b]) pick = &wins[i];
  if (base) XFree(base);
  // Like gamescope under Steam control: no match keeps the current focus.
  if (pick) {
    long app = (long)pick->appid, w = (long)pick->w;
    long input_app = overlay_input ? STEAM_APPID : app;
    XChangeProperty(d, root, a_focused_app, XA_CARDINAL, 32, PropModeReplace, (unsigned char *)&input_app, input_app != 0);
    XChangeProperty(d, root, a_focused_app_gfx, XA_CARDINAL, 32, PropModeReplace, (unsigned char *)&app, app != 0);
    XChangeProperty(d, root, a_focused_window, XA_CARDINAL, 32, PropModeReplace, (unsigned char *)&w, 1);
  }
  fit_screen(pick);
  update_pin(pick && pick->appid != STEAM_APPID, overlay && overlay_input);
  Window want = overlay && (overlay_input || !pick) ? overlay : pick ? pick->w : 0;
  if (want && (Window)get_cardinal(root, a_active, 0) != want) activate(want);
  if (overlay) XRaiseWindow(d, overlay);
  XFlush(d);
}

int main(int argc, char **argv) {
  verbose = argc > 1 && !strcmp(argv[1], "-v");
  if (getenv("MDECK_FIT")) fit_cmd = getenv("MDECK_FIT");
  if (getenv("MDECK_SCALE_CMD")) scale_cmd = getenv("MDECK_SCALE_CMD");
  use_scaler = !getenv("MDECK_FIT") && access(scale_cmd, X_OK) == 0;
  signal(SIGCHLD, SIG_IGN);
  pin_enabled = !getenv("MDECK_UI_PIN") || strcmp(getenv("MDECK_UI_PIN"), "0");
  ncpu = (int)sysconf(_SC_NPROCESSORS_ONLN);
  if (ncpu < 2) pin_enabled = 0;
  {  // a crashed run may have left the screen scaled; Xlib reads the screen size once, when it connects, so reset before that
    char cmd[256];
    snprintf(cmd, sizeof cmd, "%s reset", fit_cmd);
    if (system(cmd) != 0) fprintf(stderr, "mdeck-focus: %s failed\n", cmd);
  }
  if (!(d = XOpenDisplay(NULL))) { fprintf(stderr, "mdeck-focus: cannot open display\n"); return 1; }
  XSetErrorHandler(x_error);
  root = DefaultRootWindow(d);
  a_scale_win = XInternAtom(d, "MDECK_SCALE_WINDOW", False);
  XDeleteProperty(d, root, a_scale_win);   // a crashed run may have left a window named
  base_w = DisplayWidth(d, DefaultScreen(d)); base_h = DisplayHeight(d, DefaultScreen(d));
#define A(v, s) v = XInternAtom(d, s, False)
  A(a_client_list, "_NET_CLIENT_LIST"); A(a_active, "_NET_ACTIVE_WINDOW"); A(a_steam_game, "STEAM_GAME");
  A(a_bigpicture, "STEAM_BIGPICTURE"); A(a_overlay, "STEAM_OVERLAY"); A(a_input_focus, "STEAM_INPUT_FOCUS"); A(a_wm_state, "WM_STATE");
  A(a_pid, "_NET_WM_PID"); A(a_base_appid, "GAMESCOPECTRL_BASELAYER_APPID");
  A(a_base_window, "GAMESCOPECTRL_BASELAYER_WINDOW"); A(a_focusable_apps, "GAMESCOPE_FOCUSABLE_APPS");
  A(a_focusable_windows, "GAMESCOPE_FOCUSABLE_WINDOWS"); A(a_focused_app, "GAMESCOPE_FOCUSED_APP");
  A(a_focused_app_gfx, "GAMESCOPE_FOCUSED_APP_GFX"); A(a_focused_window, "GAMESCOPE_FOCUSED_WINDOW");
  XSelectInput(d, root, PropertyChangeMask | SubstructureNotifyMask);
  sync_focus();
  int fd = ConnectionNumber(d);
  for (;;) {
    int relevant = 0;
    while (XPending(d)) {
      XEvent ev;
      XNextEvent(d, &ev);
      if (ev.type == PropertyNotify) {
        Atom a = ev.xproperty.atom;
        relevant |= a == a_client_list || a == a_base_appid || a == a_base_window || a == a_active ||
                    a == a_overlay || a == a_input_focus || a == a_wm_state;
      } else if (ev.type == MapNotify || ev.type == UnmapNotify || ev.type == ConfigureNotify) {
        relevant = 1;
      }
    }
    if (relevant) sync_focus();
    fd_set fds; FD_ZERO(&fds); FD_SET(fd, &fds);
    struct timeval tv = {pending ? 0 : 2, pending ? 100000 : 0};
    // The periodic pass picks up windows whose size or class changed without a root-level event.
    if (select(fd + 1, &fds, NULL, NULL, &tv) == 0) sync_focus();
  }
}
