#pragma once

#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/extensions/Xrandr.h>
#include <X11/Xutil.h>
#include <cairo/cairo.h>
#include <cairo/cairo-xlib.h>
#include <pango/pangocairo.h>
#include <sqlite3.h>
#include <glib-object.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/select.h>
#include <ctype.h>


#define NIZAM_PANEL_FONT "Sans 10"


#define NIZAM_PANEL_ICON_PX 16
#define NIZAM_PANEL_ICON_SCALE 1
#define NIZAM_PANEL_ICON_CACHE_CAP 64

typedef enum {
    ICON_VARIANT_NORMAL = 0,
    ICON_VARIANT_HOVER = 1,
    ICON_VARIANT_ACTIVE = 2,
    ICON_VARIANT_DISABLED = 3,
} IconVariant;

#define MAX_WINDOWS 128
#define MAX_WORKSPACES 16

typedef enum {
    PANEL_TOP = 0,
    PANEL_BOTTOM = 1,
} PanelEdge;

typedef struct {
    int panel_enabled;
    PanelEdge position;
    int height;
    int padding;
    int monitor;
    int launcher_enabled;
    char launcher_cmd[256];
    char launcher_label[128];
    int taskbar_enabled;
    int clock_enabled;
    char clock_format[64];
    char clock_timezone[16];
} PanelSettings;

typedef struct {
    int x, y, w, h;
} Rect;

typedef struct {
    Window win;
    char title[256];
    int is_active;
    int skip_taskbar;
    cairo_surface_t *icon;
} ClientItem;

typedef struct {
    Window win;
    int desktop;
} WindowDesktop;


extern Display *dpy;
extern int screen;
extern Window root;
extern Window win;
extern cairo_surface_t *surface;
extern cairo_t *cr;
extern PangoLayout *layout_clock;
extern PangoLayout *layout_title;
extern PangoLayout *layout_status;

extern int panel_x;
extern int panel_y;
extern int panel_w;
extern int panel_h;

extern PanelSettings settings;
extern ClientItem clients[MAX_WINDOWS];
extern int client_count;
extern WindowDesktop window_desktops[MAX_WINDOWS];
extern int window_desktop_count;

extern Rect launcher_rect;
extern int launcher_label_w;
extern Rect task_rects[MAX_WINDOWS];
extern Rect task_icon_rects[MAX_WINDOWS];
extern Rect clock_rect;

extern Atom A_NET_CLIENT_LIST;
extern Atom A_NET_ACTIVE_WINDOW;
extern Atom A_NET_WM_NAME;
extern Atom A_UTF8_STRING;
extern Atom A_NET_WM_STATE;
extern Atom A_NET_WM_STATE_SKIP_TASKBAR;
extern Atom A_NET_WM_STATE_HIDDEN;
extern Atom A_WM_STATE;
extern Atom A_NET_WM_WINDOW_TYPE;
extern Atom A_NET_WM_WINDOW_TYPE_DOCK;
extern Atom A_NET_WM_WINDOW_TYPE_DESKTOP;
extern Atom A_NET_CURRENT_DESKTOP;
extern Atom A_NET_NUMBER_OF_DESKTOPS;
extern Atom A_NET_DESKTOP_NAMES;
extern Atom A_NET_WM_DESKTOP;
extern Atom A_NET_WM_STRUT_PARTIAL;
extern Atom A_NET_WM_STRUT;
extern Atom A_NET_WM_STATE_ABOVE;
extern Atom A_NET_WM_STATE_STICKY;


extern Atom A_NIZAM_PANEL_REDRAW;
extern Atom A_NET_DESKTOP_VIEWPORT;
extern Atom A_NET_DESKTOP_GEOMETRY;
extern Atom A_WIN_WORKSPACE;

extern int running;
extern time_t last_clock_tick;
extern char clock_text[128];

extern const char *color_bg;
extern const char *color_fg;
extern const char *color_active;
extern const char *color_active_text;


int clamp_int(int v, int lo, int hi);
unsigned long parse_color(Display *d, const char *hex);
int get_root_cardinal(Atom prop, unsigned long *out);
int point_in_rect(int x, int y, Rect r);

int debug_enabled(void);
void debug_log(const char *fmt, ...);

void send_active_window(Window w);
void set_current_desktop(int idx);
void iconify_window(Window w);

void draw_rect(cairo_t *c, Rect r, const char *hex, int fill);

typedef enum {
    PANEL_TEXT_CLOCK = 0,
    PANEL_TEXT_TITLE = 1,
    PANEL_TEXT_STATUS = 2,
} PanelTextRole;

void draw_text_role(PanelTextRole role,
                    const char *text,
                    int x,
                    int y,
                    int w,
                    int h,
                    const char *hex,
                    int bold,
                    int align_center);

static inline void draw_text(const char *text, int x, int y, int w, int h, const char *hex, int bold, int align_center) {
    draw_text_role(PANEL_TEXT_TITLE, text, x, y, w, h, hex, bold, align_center);
}

void draw_icon(cairo_surface_t *icon, int x, int y, int size);
void draw_icon_to(cairo_t *c, cairo_surface_t *icon, int x, int y, int size);
void draw_icon_tinted_to(cairo_t *c, cairo_surface_t *icon, int x, int y, int size, const char *hex);
void draw_triangle(int x, int y, int w, int h, int dir_left, const char *hex);


#define LAUNCHER_PAD 0
#define LAUNCHER_ICON_LEFT_PAD 5
#define LAUNCHER_ICON_GAP 6


void menu_draw(void);
int menu_handle_click(int x, int y);
int menu_handle_xevent(XEvent *ev);
void menu_poll_live_updates(void);

void clock_update_text(void);
void clock_draw(void);


void tasklist_update_clients(void);
void tasklist_update_active(void);
void tasklist_draw(void);
int tasklist_handle_click(int x, int y);


int window_has_state(Window w, Atom state_atom);
int window_is_type(Window w, Atom type_atom);
int get_window_desktop(Window w, unsigned long *out);
void get_window_title(Window w, char *out, size_t out_len);
void get_window_class(Window w, char *instance, size_t instance_len, char *klass, size_t klass_len);

cairo_surface_t *load_icon_from_name(const char *name, int size);
cairo_surface_t *load_window_icon(Window w, int size);
cairo_surface_t *load_window_icon_hint(Window w, int size);
int find_desktop_icon_for_class(const char *instance, const char *klass, char *out, size_t out_len);
