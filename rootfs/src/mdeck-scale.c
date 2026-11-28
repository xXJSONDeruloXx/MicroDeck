// Gamescope's scaling on a plain X server. mdeck-focus names the game window that does not match the panel in the root property
// MDECK_SCALE_WINDOW (it is deleted when there is none); this draws that window scaled to the panel, letterboxed, on the composite
// overlay window with the GPU (GLX texture-from-pixmap), and Steam's overlay windows (STEAM_OVERLAY, the in-game menu) on top, unscaled.
// The X screen is never resized, so a game never sees its display change (a RandR transform made Wine shrink or regrow the game's
// window and flickered the panel). With no scaling needed nothing is redirected or drawn and this process sleeps.
// MDECK_SCALE_FILTER=nearest picks hard pixels; the default is linear.
#define GL_GLEXT_PROTOTYPES
#include <GL/gl.h>
#include <GL/glx.h>
#include <GL/glxext.h>
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/extensions/Xcomposite.h>
#include <X11/extensions/Xdamage.h>
#include <X11/extensions/Xfixes.h>
#include <X11/extensions/shape.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAXL 4

struct layer {
  Window w;
  Pixmap px;
  GLXPixmap gp;
  GLuint tex;
  Damage dmg;
  int width, height, flip, alpha;
};

static Display *d;
static Window root, cow;
static Atom a_target, a_overlay, a_client_list, a_filter, a_scaler;
static int sw, sh, verbose, damage_base;
static GLXContext ctx;
static GLXWindow gwin;
static GLXFBConfig win_cfg;
static GLuint prog, vbo;
static GLint u_rect, u_screen, u_flip, u_alpha;
static int filter = GL_LINEAR;
static struct layer game, overlays[MAXL];
static int active;
static PFNGLXBINDTEXIMAGEEXTPROC bind_tex;
static PFNGLXRELEASETEXIMAGEEXTPROC release_tex;
static PFNGLXSWAPINTERVALEXTPROC swap_interval;

static int x_error(Display *dpy, XErrorEvent *e) { (void)dpy; (void)e; return 0; }

static unsigned long cardinal(Window w, Atom prop) {
  Atom t; int f; unsigned long n, after, v = 0; unsigned char *data = NULL;
  if (XGetWindowProperty(d, w, prop, 0, 1, False, AnyPropertyType, &t, &f, &n, &after, &data) == Success && data) {
    if (n && f == 32) v = *(unsigned long *)data;
    XFree(data);
  }
  return v;
}

// Steam writes gamescope's scaling choices (its Quick Access menu) on the root window: GAMESCOPE_NEW_SCALING_FILTER (0 linear, 1 nearest,
// 2 FSR, 3 NIS, 4 pixel) and GAMESCOPE_NEW_SCALING_SCALER (0 auto, 1 integer, 2 fit, 3 fill, 4 stretch). FSR and NIS are drawn linear.
static int root_cardinal(Atom prop, unsigned long *v) {
  Atom t; int f; unsigned long n = 0, after; unsigned char *data = NULL; int have = 0;
  if (XGetWindowProperty(d, root, prop, 0, 1, False, AnyPropertyType, &t, &f, &n, &after, &data) == Success && data) {
    if (n && f == 32) { *v = *(unsigned long *)data; have = 1; }
    XFree(data);
  }
  return have;
}

static GLuint compile(GLenum type, const char *src) {
  GLuint s = glCreateShader(type);
  glShaderSource(s, 1, &src, NULL);
  glCompileShader(s);
  GLint ok = 0;
  glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
  if (!ok) { char log[512]; glGetShaderInfoLog(s, sizeof log, NULL, log); fprintf(stderr, "mdeck-scale: shader: %s\n", log); exit(1); }
  return s;
}

static void gl_init(void) {
  const char *vs = "#version 120\nattribute vec2 pos; uniform vec4 rect; uniform vec2 screen; uniform float flip; varying vec2 uv;\n"
                   "void main() { vec2 p = rect.xy + pos * rect.zw; gl_Position = vec4(p.x / screen.x * 2.0 - 1.0, 1.0 - p.y / screen.y * 2.0, 0.0, 1.0);\n"
                   "uv = vec2(pos.x, flip > 0.5 ? 1.0 - pos.y : pos.y); }\n";
  const char *fs = "#version 120\nuniform sampler2D tex; uniform float alpha; varying vec2 uv;\n"
                   "void main() { vec4 c = texture2D(tex, uv); gl_FragColor = alpha > 0.5 ? c : vec4(c.rgb, 1.0); }\n";
  prog = glCreateProgram();
  glAttachShader(prog, compile(GL_VERTEX_SHADER, vs));
  glAttachShader(prog, compile(GL_FRAGMENT_SHADER, fs));
  glBindAttribLocation(prog, 0, "pos");
  glLinkProgram(prog);
  u_rect = glGetUniformLocation(prog, "rect"); u_screen = glGetUniformLocation(prog, "screen"); u_flip = glGetUniformLocation(prog, "flip"); u_alpha = glGetUniformLocation(prog, "alpha");
  static const float quad[8] = {0, 0, 1, 0, 0, 1, 1, 1};
  glGenBuffers(1, &vbo);
  glBindBuffer(GL_ARRAY_BUFFER, vbo);
  glBufferData(GL_ARRAY_BUFFER, sizeof quad, quad, GL_STATIC_DRAW);
}

// The framebuffer configuration that can bind a window's pixmap as a texture, for the window's own visual.
static GLXFBConfig pixmap_config(VisualID vis, int alpha, int *flip) {
  int n = 0;
  GLXFBConfig *cfgs = glXGetFBConfigs(d, DefaultScreen(d), &n), found = NULL;
  for (int i = 0; i < n && !found; i++) {
    int id = 0, rgb = 0, type = 0;
    glXGetFBConfigAttrib(d, cfgs[i], GLX_VISUAL_ID, &id);
    glXGetFBConfigAttrib(d, cfgs[i], alpha ? GLX_BIND_TO_TEXTURE_RGBA_EXT : GLX_BIND_TO_TEXTURE_RGB_EXT, &rgb);
    glXGetFBConfigAttrib(d, cfgs[i], GLX_DRAWABLE_TYPE, &type);
    if ((VisualID)id == vis && rgb && (type & GLX_PIXMAP_BIT)) {
      found = cfgs[i];
      int inv = 0;
      glXGetFBConfigAttrib(d, found, GLX_Y_INVERTED_EXT, &inv);
      *flip = inv ? 0 : 1;
    }
  }
  if (cfgs) XFree(cfgs);
  return found;
}

static void layer_drop_pixmap(struct layer *l) {
  if (l->gp) { glXDestroyPixmap(d, l->gp); l->gp = 0; }
  if (l->px) { XFreePixmap(d, l->px); l->px = 0; }
}

// (Re)name the window's backing pixmap, which changes whenever the window is resized or remapped.
static int layer_bind(struct layer *l) {
  XWindowAttributes wa;
  layer_drop_pixmap(l);
  if (!XGetWindowAttributes(d, l->w, &wa) || wa.map_state != IsViewable) return 0;
  l->alpha = wa.depth == 32;   // Steam's windows have an alpha channel: its menu is translucent over the game
  GLXFBConfig cfg = pixmap_config(XVisualIDFromVisual(wa.visual), l->alpha, &l->flip);
  if (!cfg) { if (verbose) fprintf(stderr, "mdeck-scale: no texture-from-pixmap config for window 0x%lx\n", l->w); return 0; }
  l->px = XCompositeNameWindowPixmap(d, l->w);
  int attrs[] = {GLX_TEXTURE_TARGET_EXT, GLX_TEXTURE_2D_EXT, GLX_TEXTURE_FORMAT_EXT, l->alpha ? GLX_TEXTURE_FORMAT_RGBA_EXT : GLX_TEXTURE_FORMAT_RGB_EXT, None};
  l->gp = glXCreatePixmap(d, cfg, l->px, attrs);
  l->width = wa.width; l->height = wa.height;
  if (!l->tex) glGenTextures(1, &l->tex);
  return l->gp != 0;
}

static void layer_start(struct layer *l, Window w) {
  memset(l, 0, sizeof *l);
  l->w = w;
  XCompositeRedirectWindow(d, w, CompositeRedirectManual);
  l->dmg = XDamageCreate(d, w, XDamageReportNonEmpty);
  XSelectInput(d, w, StructureNotifyMask);
  layer_bind(l);
}

static void layer_stop(struct layer *l) {
  if (!l->w) return;
  layer_drop_pixmap(l);
  if (l->tex) glDeleteTextures(1, &l->tex);
  if (l->dmg) XDamageDestroy(d, l->dmg);
  XCompositeUnredirectWindow(d, l->w, CompositeRedirectManual);
  XSelectInput(d, l->w, 0);
  memset(l, 0, sizeof *l);
}

static void layer_draw(struct layer *l, float x, float y, float w, float h, int fil) {
  if (!l->gp) return;
  glBindTexture(GL_TEXTURE_2D, l->tex);
  bind_tex(d, l->gp, GLX_FRONT_EXT, NULL);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, fil);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, fil);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glUniform4f(u_rect, x, y, w, h);
  glUniform1f(u_flip, (float)l->flip);
  glUniform1f(u_alpha, (float)l->alpha);
  if (l->alpha) { glEnable(GL_BLEND); glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA); }   // X's alpha is premultiplied
  else glDisable(GL_BLEND);
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
  release_tex(d, l->gp, GLX_FRONT_EXT);
}

static void paint(void) {
  if (verbose > 1) { int no = 0; for (int i = 0; i < MAXL; i++) no += overlays[i].w != 0; fprintf(stderr, "mdeck-scale: paint game=%d (%dx%d) overlays=%d\n", game.gp != 0, game.width, game.height, no); }
  glViewport(0, 0, sw, sh);
  glClearColor(0, 0, 0, 1);
  glClear(GL_COLOR_BUFFER_BIT);
  glUseProgram(prog);
  glUniform2f(u_screen, (float)sw, (float)sh);
  glBindBuffer(GL_ARRAY_BUFFER, vbo);
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0);
  if (game.gp) {
    unsigned long scaler = 0, fil = 0;
    root_cardinal(a_scaler, &scaler);
    int have_filter = root_cardinal(a_filter, &fil);
    float sx = (float)sw / game.width, sy = (float)sh / game.height;
    float fit = sx < sy ? sx : sy, fill = sx > sy ? sx : sy, s = fit, w, h;
    if (scaler == 3) s = fill;
    else if (scaler == 1) { s = (float)(int)fit; if (s < 1) s = fit; }
    if (scaler == 4) { w = (float)sw; h = (float)sh; } else { w = game.width * s; h = game.height * s; }
    layer_draw(&game, (sw - w) / 2, (sh - h) / 2, w, h, have_filter ? (fil == 1 || fil == 4 ? GL_NEAREST : GL_LINEAR) : filter);
  }
  for (int i = 0; i < MAXL; i++) {
    if (!overlays[i].w) continue;
    XWindowAttributes wa;
    if (XGetWindowAttributes(d, overlays[i].w, &wa) && wa.map_state == IsViewable) {
      int x = 0, y = 0; Window child;
      XTranslateCoordinates(d, overlays[i].w, root, 0, 0, &x, &y, &child);   // wa.x is relative to the window manager's frame
      layer_draw(&overlays[i], x, y, wa.width, wa.height, GL_LINEAR);
    }
  }
  glXSwapBuffers(d, gwin);
}

static void sync_overlays(void) {
  Window seen[MAXL] = {0};
  Atom t; int f; unsigned long n = 0, after; unsigned char *data = NULL;
  // the window manager's client list: the real windows, not the frames it puts them in
  if (XGetWindowProperty(d, root, a_client_list, 0, 4096, False, XA_WINDOW, &t, &f, &n, &after, &data) != Success || !data || f != 32) { if (data) XFree(data); return; }
  Window *kids = (Window *)data;
  for (unsigned long i = 0; i < n; i++) {
    if (kids[i] == cow || kids[i] == game.w || !cardinal(kids[i], a_overlay)) continue;
    XWindowAttributes wa;
    if (!XGetWindowAttributes(d, kids[i], &wa) || wa.map_state != IsViewable || wa.class == InputOnly) continue;
    for (int j = 0; j < MAXL; j++) if (!seen[j]) { seen[j] = kids[i]; break; }
  }
  XFree(data);
  for (int i = 0; i < MAXL; i++) {          // drop the ones that went away, start the new ones
    int keep = 0;
    for (int j = 0; j < MAXL; j++) keep |= overlays[i].w && overlays[i].w == seen[j];
    if (overlays[i].w && !keep) layer_stop(&overlays[i]);
  }
  for (int j = 0; j < MAXL && seen[j]; j++) {
    int have = 0, slot = -1;
    for (int i = 0; i < MAXL; i++) { have |= overlays[i].w == seen[j]; if (!overlays[i].w && slot < 0) slot = i; }
    if (!have && slot >= 0) layer_start(&overlays[slot], seen[j]);
  }
}

static void stop(void) {
  if (!active) return;
  for (int i = 0; i < MAXL; i++) layer_stop(&overlays[i]);
  layer_stop(&game);
  glXMakeCurrent(d, None, NULL);
  if (gwin) glXDestroyWindow(d, gwin);
  if (ctx) glXDestroyContext(d, ctx);
  gwin = 0; ctx = NULL;
  XCompositeReleaseOverlayWindow(d, root);
  cow = 0; active = 0;
  XFlush(d);
  if (verbose) fprintf(stderr, "mdeck-scale: off\n");
}

static void start(Window target) {
  if (active && game.w == target) return;
  stop();
  cow = XCompositeGetOverlayWindow(d, root);
  XserverRegion none = XFixesCreateRegion(d, NULL, 0);
  XFixesSetWindowShapeRegion(d, cow, ShapeInput, 0, 0, none);   // clicks and touches go through to the windows below
  XFixesDestroyRegion(d, none);
  XWindowAttributes wa;
  XGetWindowAttributes(d, cow, &wa);
  VisualID vis = XVisualIDFromVisual(wa.visual);
  int n = 0, found = 0;
  GLXFBConfig *cfgs = glXGetFBConfigs(d, DefaultScreen(d), &n);
  for (int i = 0; i < n && !found; i++) {
    int id = 0, type = 0, dbl = 0;
    glXGetFBConfigAttrib(d, cfgs[i], GLX_VISUAL_ID, &id);
    glXGetFBConfigAttrib(d, cfgs[i], GLX_DRAWABLE_TYPE, &type);
    glXGetFBConfigAttrib(d, cfgs[i], GLX_DOUBLEBUFFER, &dbl);
    if ((VisualID)id == vis && (type & GLX_WINDOW_BIT) && dbl) { win_cfg = cfgs[i]; found = 1; }
  }
  if (cfgs) XFree(cfgs);
  if (!found) { fprintf(stderr, "mdeck-scale: no double-buffered GLX config for the overlay window\n"); XCompositeReleaseOverlayWindow(d, root); cow = 0; return; }
  ctx = glXCreateNewContext(d, win_cfg, GLX_RGBA_TYPE, NULL, True);
  gwin = glXCreateWindow(d, win_cfg, cow, NULL);
  if (!ctx || !gwin || !glXMakeCurrent(d, gwin, ctx)) { fprintf(stderr, "mdeck-scale: cannot make the GL context current\n"); stop(); return; }
  if (!prog) gl_init();
  if (swap_interval) swap_interval(d, gwin, 1);
  active = 1;
  layer_start(&game, target);
  sync_overlays();
  if (verbose) fprintf(stderr, "mdeck-scale: on for 0x%lx (%dx%d on %dx%d)\n", target, game.width, game.height, sw, sh);
  paint();
}

int main(int argc, char **argv) {
  verbose = argc > 1 && !strcmp(argv[1], "-v") ? 1 : argc > 1 && !strcmp(argv[1], "-vv") ? 2 : 0;
  if (getenv("MDECK_SCALE_FILTER") && !strcmp(getenv("MDECK_SCALE_FILTER"), "nearest")) filter = GL_NEAREST;
  if (!(d = XOpenDisplay(NULL))) { fprintf(stderr, "mdeck-scale: cannot open display\n"); return 1; }
  XSetErrorHandler(x_error);
  root = DefaultRootWindow(d);
  sw = DisplayWidth(d, DefaultScreen(d)); sh = DisplayHeight(d, DefaultScreen(d));
  int ev, er, cmaj = 0, cmin = 0;
  if (!XCompositeQueryExtension(d, &ev, &er) || !XDamageQueryExtension(d, &damage_base, &er) || !XFixesQueryExtension(d, &ev, &er)) {
    fprintf(stderr, "mdeck-scale: the X server lacks Composite, Damage or XFixes\n"); return 1;
  }
  XCompositeQueryVersion(d, &cmaj, &cmin);
  bind_tex = (PFNGLXBINDTEXIMAGEEXTPROC)glXGetProcAddress((const GLubyte *)"glXBindTexImageEXT");
  release_tex = (PFNGLXRELEASETEXIMAGEEXTPROC)glXGetProcAddress((const GLubyte *)"glXReleaseTexImageEXT");
  swap_interval = (PFNGLXSWAPINTERVALEXTPROC)glXGetProcAddress((const GLubyte *)"glXSwapIntervalEXT");
  if (!bind_tex || !release_tex) { fprintf(stderr, "mdeck-scale: GLX_EXT_texture_from_pixmap is missing\n"); return 1; }
  a_target = XInternAtom(d, "MDECK_SCALE_WINDOW", False);
  a_overlay = XInternAtom(d, "STEAM_OVERLAY", False);
  a_client_list = XInternAtom(d, "_NET_CLIENT_LIST", False);
  a_filter = XInternAtom(d, "GAMESCOPE_NEW_SCALING_FILTER", False);
  a_scaler = XInternAtom(d, "GAMESCOPE_NEW_SCALING_SCALER", False);
  XSelectInput(d, root, PropertyChangeMask | SubstructureNotifyMask);
  int dirty = 0;
  for (;;) {
    Window want = (Window)cardinal(root, a_target);
    if (want && (!active || game.w != want)) start(want);
    else if (!want && active) {
      stop();
      // mdeck-focus starts this process only while a game needs scaling; nothing to scale any more: give the memory back
      // (unless the window was named again while stopping)
      if (!cardinal(root, a_target)) return 0;
    } else if (!want && !active) {
      return 0;
    }
    while (XPending(d)) {
      XEvent e;
      XNextEvent(d, &e);
      if (e.type == damage_base + XDamageNotify) {
        XDamageNotifyEvent *de = (XDamageNotifyEvent *)&e;
        XDamageSubtract(d, de->damage, None, None);
        dirty = 1;
      } else if (e.type == ConfigureNotify || e.type == MapNotify || e.type == UnmapNotify) {
        Window w = e.type == ConfigureNotify ? e.xconfigure.window : e.type == MapNotify ? e.xmap.window : e.xunmap.window;
        if (active && w == game.w) layer_bind(&game);
        for (int i = 0; i < MAXL; i++) if (overlays[i].w == w) layer_bind(&overlays[i]);
        if (active) sync_overlays();
        dirty = 1;
      } else if (e.type == PropertyNotify && e.xproperty.window == root && active) {
        sync_overlays();
        dirty = 1;   // also when Steam changes the scaling filter or mode
      }
    }
    if (active && dirty) { paint(); dirty = 0; }
    struct pollfd pf = {ConnectionNumber(d), POLLIN, 0};
    // idle (nothing is scaled) it only wakes for X events; scaling, a slow pass also finds overlay windows that appeared
    poll(&pf, 1, active ? 1000 : -1);
    if (active && !XPending(d)) { sync_overlays(); dirty = 1; }
  }
}
