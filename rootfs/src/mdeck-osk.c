/* On-screen keyboard for desktop mode, driven from the pad: a window that draws the keys and takes navigation words on stdin
 * (up, down, left, right, press, shift, backspace, close). It never takes the focus (override-redirect) and does not type itself:
 * it prints "key <linux key code> ..." lines (modifiers first) and mdeck-desktop-pad sends them through uinput. */
#include <X11/Xlib.h>
#include <X11/Xft/Xft.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define SHIFT 42
#define CTRL 29
#define ALT 56

struct key { const char *label, *shifted; int code; float w; };

#define K(l, s, c) { l, s, c, 1.0f }
#define KW(l, s, c, w) { l, s, c, w }
static const struct key row0[] = { K("Esc", "Esc", 1), K("1", "!", 2), K("2", "@", 3), K("3", "#", 4), K("4", "$", 5), K("5", "%", 6),
  K("6", "^", 7), K("7", "&", 8), K("8", "*", 9), K("9", "(", 10), K("0", ")", 11), K("-", "_", 12), K("=", "+", 13), KW("Bksp", "Bksp", 14, 1.5f), {0} };
static const struct key row1[] = { KW("Tab", "Tab", 15, 1.5f), K("q", "Q", 16), K("w", "W", 17), K("e", "E", 18), K("r", "R", 19), K("t", "T", 20),
  K("y", "Y", 21), K("u", "U", 22), K("i", "I", 23), K("o", "O", 24), K("p", "P", 25), K("[", "{", 26), K("]", "}", 27), K("\\", "|", 43), {0} };
static const struct key row2[] = { K("a", "A", 30), K("s", "S", 31), K("d", "D", 32), K("f", "F", 33), K("g", "G", 34), K("h", "H", 35),
  K("j", "J", 36), K("k", "K", 37), K("l", "L", 38), K(";", ":", 39), K("'", "\"", 40), KW("Enter", "Enter", 28, 2.0f), {0} };
static const struct key row3[] = { KW("Shift", "Shift", SHIFT, 2.0f), K("z", "Z", 44), K("x", "X", 45), K("c", "C", 46), K("v", "V", 47), K("b", "B", 48),
  K("n", "N", 49), K("m", "M", 50), K(",", "<", 51), K(".", ">", 52), K("/", "?", 53), K("`", "~", 41), {0} };
static const struct key row4[] = { KW("Ctrl", "Ctrl", CTRL, 1.5f), KW("Alt", "Alt", ALT, 1.5f), KW("Space", "Space", 57, 5.0f), K("<", "<", 105),
  K("v", "v", 108), K("^", "^", 103), K(">", ">", 106), KW("Hide", "Hide", -1, 1.5f), {0} };
static const struct key *rows[] = { row0, row1, row2, row3, row4 };
#define NROWS 5

static int is_mod(int code) { return code == SHIFT || code == CTRL || code == ALT; }

int main(void)
{
    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) return 1;
    int scr = DefaultScreen(dpy);
    int sw = DisplayWidth(dpy, scr), sh = DisplayHeight(dpy, scr);
    int kh = sh / 12 < 30 ? 30 : sh / 12, gap = 3;
    int h = NROWS * (kh + gap) + gap;
    XSetWindowAttributes attr = { .override_redirect = True, .background_pixel = 0x202428 };
    Window win = XCreateWindow(dpy, RootWindow(dpy, scr), 0, sh - h, sw, h, 0, CopyFromParent, InputOutput, CopyFromParent,
                               CWOverrideRedirect | CWBackPixel, &attr);
    XSelectInput(dpy, win, ExposureMask);
    XMapRaised(dpy, win);
    XftFont *font = XftFontOpen(dpy, scr, XFT_FAMILY, XftTypeString, "DejaVu Sans", XFT_PIXEL_SIZE, XftTypeDouble, (double)(kh * 5 / 11), NULL);
    XftDraw *draw = XftDrawCreate(dpy, win, DefaultVisual(dpy, scr), DefaultColormap(dpy, scr));
    XftColor fg, sel;
    XftColorAllocName(dpy, DefaultVisual(dpy, scr), DefaultColormap(dpy, scr), "#f0f0f0", &fg);
    XftColorAllocName(dpy, DefaultVisual(dpy, scr), DefaultColormap(dpy, scr), "#101010", &sel);
    GC gc = XCreateGC(dpy, win, 0, NULL);
    unsigned long normal = 0x40464d, hot = 0xf0b030, latched = 0x3a7bd5;

    int row = 2, col = 0, mods[3] = { 0, 0, 0 };
    char buf[64];
    int len = 0;
    for (;;) {
        int widths_sum[NROWS];
        for (int r = 0; r < NROWS; r++) {
            float total = 0;
            for (const struct key *k = rows[r]; k->label; k++) total += k->w;
            widths_sum[r] = (int)(total * 1000);
        }
        for (int r = 0; r < NROWS; r++) {
            float unit = (sw - gap) / (widths_sum[r] / 1000.0f);
            float x = gap / 2.0f;
            int c = 0;
            for (const struct key *k = rows[r]; k->label; k++, c++) {
                int kw = (int)(k->w * unit) - gap;
                int shifted = mods[0];
                int on = (r == row && c == col);
                unsigned long color = on ? hot : (is_mod(k->code) && mods[k->code == SHIFT ? 0 : k->code == CTRL ? 1 : 2]) ? latched : normal;
                XSetForeground(dpy, gc, color);
                XFillRectangle(dpy, win, gc, (int)x, gap + r * (kh + gap), kw, kh);
                const char *text = shifted ? k->shifted : k->label;
                XGlyphInfo ext;
                XftTextExtentsUtf8(dpy, font, (const FcChar8 *)text, strlen(text), &ext);
                XftDrawStringUtf8(draw, on ? &sel : &fg, font, (int)x + (kw - ext.xOff) / 2, gap + r * (kh + gap) + (kh + font->ascent - font->descent) / 2,
                                  (const FcChar8 *)text, strlen(text));
                x += k->w * unit;
            }
        }
        XFlush(dpy);

        struct pollfd pf[2] = { { STDIN_FILENO, POLLIN, 0 }, { ConnectionNumber(dpy), POLLIN, 0 } };
        poll(pf, 2, -1);
        while (XPending(dpy)) { XEvent ev; XNextEvent(dpy, &ev); }
        if (pf[0].revents & (POLLHUP | POLLERR)) break;
        if (!(pf[0].revents & POLLIN)) continue;
        int n = read(STDIN_FILENO, buf + len, sizeof buf - len - 1);
        if (n <= 0) break;
        len += n;
        char *nl;
        buf[len] = 0;
        while ((nl = strchr(buf, '\n'))) {
            *nl = 0;
            int ncols = 0;
            for (const struct key *k = rows[row]; k->label; k++) ncols++;
            if (!strcmp(buf, "left")) col = (col + ncols - 1) % ncols;
            else if (!strcmp(buf, "right")) col = (col + 1) % ncols;
            else if (!strcmp(buf, "up") || !strcmp(buf, "down")) {
                float x = 0;
                int c = 0;
                for (const struct key *k = rows[row]; c < col; k++, c++) x += k->w;
                x += rows[row][col].w / 2;
                row = (row + (buf[0] == 'u' ? NROWS - 1 : 1)) % NROWS;
                float acc = 0;
                c = 0;
                for (const struct key *k = rows[row]; k->label; k++, c++) {
                    if (x < acc + k->w) break;
                    acc += k->w;
                }
                for (ncols = 0; rows[row][ncols].label; ncols++) ;
                col = c < ncols ? c : ncols - 1;
            } else if (!strcmp(buf, "close")) {
                return 0;
            } else if (!strcmp(buf, "shift")) {
                mods[0] = !mods[0];
            } else if (!strcmp(buf, "backspace")) {
                printf("key 14\n");
                fflush(stdout);
            } else if (!strcmp(buf, "press")) {
                const struct key *k = &rows[row][col];
                if (k->code == -1) return 0;
                if (is_mod(k->code)) {
                    int i = k->code == SHIFT ? 0 : k->code == CTRL ? 1 : 2;
                    mods[i] = !mods[i];
                } else {
                    printf("key");
                    if (mods[0]) printf(" %d", SHIFT);
                    if (mods[1]) printf(" %d", CTRL);
                    if (mods[2]) printf(" %d", ALT);
                    printf(" %d\n", k->code);
                    fflush(stdout);
                    mods[0] = mods[1] = mods[2] = 0;
                }
            }
            memmove(buf, nl + 1, len - (nl + 1 - buf) + 1);
            len -= nl + 1 - buf;
        }
    }
    return 0;
}
