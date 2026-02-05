
#include "panel_shared.h"

#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <dirent.h>
#include <sys/types.h>

#ifdef NIZAM_HAVE_LIBRSVG
#include <librsvg/rsvg.h>
#endif

#ifdef NIZAM_HAVE_GDKPIXBUF
#include <gdk-pixbuf/gdk-pixbuf.h>
#endif

Display *dpy;
int screen;
Window root;
Window win;
cairo_surface_t *surface;
cairo_t *cr;
PangoLayout *layout_clock;
PangoLayout *layout_title;
PangoLayout *layout_status;

static PangoFontDescription *panel_font_desc = NULL;


static volatile sig_atomic_t mem_debug_toggle_requested = 0;
static int mem_debug_enabled = 0;


static Pixmap back_pixmap = None;
static GC back_gc = None;


typedef struct {
    int in_use;
    char *name;
    int size;
    int scale;
    int variant;
    cairo_surface_t *surface;
    int prev;
    int next;
} IconCacheEntry;

typedef struct {
    IconCacheEntry entries[64];
    int head;
    int tail;
    int used;
    uint64_t hits;
    uint64_t misses;
    uint64_t evictions;
} IconCache;

static IconCache icon_cache;

static int icon_cache_debug_enabled(void) {
    static int inited = 0;
    static int enabled = 0;
    if (!inited) {
        const char *v = getenv("NIZAM_PANEL_DEBUG_ICON_CACHE");
        enabled = (v && *v && strcmp(v, "0") != 0);
        inited = 1;
    }
    return enabled;
}

static int sanitize_scale(int scale) {
    
    (void)scale;
    return NIZAM_PANEL_ICON_SCALE;
}

static char *normalize_icon_name(const char *s) {
    if (!s) return NULL;

    
    while (*s == ' ' || *s == '\t' || *s == '\n' || *s == '\r') s++;
    size_t n = strlen(s);
    while (n > 0) {
        char c = s[n - 1];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') n--;
        else break;
    }
    if (n == 0) return strdup("");

    
    char *out = malloc(n + 1);
    if (!out) return NULL;
    for (size_t i = 0; i < n; i++) {
        out[i] = (char)tolower((unsigned char)s[i]);
    }
    out[n] = '\0';

    
    if (!strchr(out, '/')) {
        size_t ln = strlen(out);
        if (ln > 4) {
            const char *tail = out + (ln - 4);
            if (strcmp(tail, ".png") == 0 || strcmp(tail, ".xpm") == 0 || strcmp(tail, ".svg") == 0) {
                out[ln - 4] = '\0';
            }
        }
    }
    return out;
}

int panel_x = 0;
int panel_y = 0;
int panel_w = 1024;
int panel_h = 34;

PanelSettings settings;
ClientItem clients[MAX_WINDOWS];
int client_count = 0;
WindowDesktop window_desktops[MAX_WINDOWS];
int window_desktop_count = 0;

Rect launcher_rect;
int launcher_label_w = 0;
Rect task_rects[MAX_WINDOWS];
Rect task_icon_rects[MAX_WINDOWS];
Rect clock_rect;
static Rect launcher_sep_rect = {0};
static Rect launcher_sep_soft_rect = {0};
static Rect clock_sep_rect = {0};
static Rect clock_sep_soft_rect = {0};

Atom A_NET_CLIENT_LIST;
Atom A_NET_ACTIVE_WINDOW;
Atom A_NET_WM_NAME;
Atom A_UTF8_STRING;
Atom A_NET_WM_STATE;
Atom A_NET_WM_STATE_SKIP_TASKBAR;
Atom A_NET_WM_STATE_HIDDEN;
Atom A_WM_STATE;
Atom A_NET_WM_WINDOW_TYPE;
Atom A_NET_WM_WINDOW_TYPE_DOCK;
Atom A_NET_WM_WINDOW_TYPE_DESKTOP;
Atom A_NET_DESKTOP_NAMES;
Atom A_NET_WM_DESKTOP;
Atom A_NET_WM_STRUT_PARTIAL;
Atom A_NET_WM_STRUT;
Atom A_NET_WM_STATE_ABOVE;
Atom A_NET_WM_STATE_STICKY;
Atom A_NIZAM_PANEL_REDRAW;

int running = 1;
time_t last_clock_tick = 0;
char clock_text[128] = {0};


const char *color_bg = "#353a3d";          
const char *color_fg = "#eeeeec";          
const char *color_active = "#4a5054";      
const char *color_active_text = "#eeeeec"; 
const char *color_sep = "#3d4347";         
const char *color_sep_soft = "#4a5054";    

int debug_enabled(void) {
    static int inited = 0;
    static int enabled = 0;
    if (!inited) {
        const char *v = getenv("NIZAM_PANEL_DEBUG");
        enabled = (v && *v && strcmp(v, "0") != 0);
        inited = 1;
    }
    return enabled;
}

static void on_sigusr1(int sig) {
    (void)sig;
    mem_debug_toggle_requested = 1;
}

static long read_rss_kb(void) {
    FILE *f = fopen("/proc/self/status", "r");
    if (!f) return -1;
    char line[256];
    long rss_kb = -1;
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "VmRSS:", 6) == 0) {
            
            char *p = line + 6;
            while (*p == ' ' || *p == '\t') p++;
            rss_kb = strtol(p, NULL, 10);
            break;
        }
    }
    fclose(f);
    return rss_kb;
}

static int icon_cache_used_count(void) {
    return icon_cache.used;
}

static int pango_layout_count(void) {
    int n = 0;
    if (layout_clock) n++;
    if (layout_title) n++;
    if (layout_status) n++;
    return n;
}

static void mem_debug_print_stats(const char *reason) {
    long rss_kb = read_rss_kb();
    fprintf(stderr,
            "nizam-panel[mem]: %s rss=%ldkB icon_cache=%d/64 hits=%llu misses=%llu evict=%llu pango_layouts=%d\n",
            reason ? reason : "stats",
            rss_kb,
            icon_cache_used_count(),
            (unsigned long long)icon_cache.hits,
            (unsigned long long)icon_cache.misses,
            (unsigned long long)icon_cache.evictions,
            pango_layout_count());
}

static int is_all_digits(const char *s) {
    if (!s || !*s) return 0;
    for (const char *p = s; *p; p++) {
        if (*p < '0' || *p > '9') return 0;
    }
    return 1;
}

static int read_proc_comm(pid_t pid, char *out, size_t out_sz) {
    if (!out || out_sz == 0) return 0;
    out[0] = '\0';
    char path[64];
    snprintf(path, sizeof(path), "/proc/%d/comm", (int)pid);
    FILE *f = fopen(path, "r");
    if (!f) return 0;
    if (!fgets(out, (int)out_sz, f)) {
        fclose(f);
        return 0;
    }
    fclose(f);
    size_t n = strlen(out);
    while (n > 0 && (out[n - 1] == '\n' || out[n - 1] == '\r')) {
        out[n - 1] = '\0';
        n--;
    }
    return out[0] != '\0';
}

static int find_nizam_panel_pids(pid_t *out, int max_out) {
    if (!out || max_out <= 0) return 0;
    int count = 0;
    DIR *d = opendir("/proc");
    if (!d) return 0;
    struct dirent *de;
    while ((de = readdir(d)) != NULL) {
        if (!is_all_digits(de->d_name)) continue;
        pid_t pid = (pid_t)atoi(de->d_name);
        if (pid <= 0) continue;
        char comm[64];
        if (!read_proc_comm(pid, comm, sizeof(comm))) continue;
        if (strcmp(comm, "nizam-panel") != 0) continue;
        out[count++] = pid;
        if (count >= max_out) break;
    }
    closedir(d);
    return count;
}

static int send_sigusr1(pid_t pid) {
    if (pid <= 0) return 0;
    if (kill(pid, SIGUSR1) == 0) return 1;
    return 0;
}

static void icon_cache_init(void) {
    memset(&icon_cache, 0, sizeof(icon_cache));
    icon_cache.head = -1;
    icon_cache.tail = -1;
    for (int i = 0; i < (int)(sizeof(icon_cache.entries) / sizeof(icon_cache.entries[0])); i++) {
        icon_cache.entries[i].prev = -1;
        icon_cache.entries[i].next = -1;
    }
}

static void icon_cache_unlink(int idx) {
    IconCacheEntry *e = &icon_cache.entries[idx];
    if (e->prev != -1) icon_cache.entries[e->prev].next = e->next;
    if (e->next != -1) icon_cache.entries[e->next].prev = e->prev;
    if (icon_cache.head == idx) icon_cache.head = e->next;
    if (icon_cache.tail == idx) icon_cache.tail = e->prev;
    e->prev = -1;
    e->next = -1;
}

static void icon_cache_link_head(int idx) {
    IconCacheEntry *e = &icon_cache.entries[idx];
    e->prev = -1;
    e->next = icon_cache.head;
    if (icon_cache.head != -1) icon_cache.entries[icon_cache.head].prev = idx;
    icon_cache.head = idx;
    if (icon_cache.tail == -1) icon_cache.tail = idx;
}

static void icon_cache_touch(int idx) {
    if (idx == icon_cache.head) return;
    icon_cache_unlink(idx);
    icon_cache_link_head(idx);
}

static void icon_cache_evict_tail(void) {
    int idx = icon_cache.tail;
    if (idx == -1) return;
    IconCacheEntry *e = &icon_cache.entries[idx];
    icon_cache_unlink(idx);
    if (e->surface) {
        cairo_surface_destroy(e->surface);
        e->surface = NULL;
    }
    free(e->name);
    e->name = NULL;
    e->size = 0;
    e->scale = 0;
    e->in_use = 0;
    icon_cache.used--;
    icon_cache.evictions++;
    if (mem_debug_enabled) mem_debug_print_stats("icon_cache_evict");
}

static void icon_cache_destroy_all(void) {
    for (int i = 0; i < (int)(sizeof(icon_cache.entries) / sizeof(icon_cache.entries[0])); i++) {
        IconCacheEntry *e = &icon_cache.entries[i];
        if (!e->in_use) continue;
        if (e->surface) cairo_surface_destroy(e->surface);
        free(e->name);
        e->name = NULL;
        e->surface = NULL;
        e->in_use = 0;
    }
    icon_cache.head = -1;
    icon_cache.tail = -1;
    icon_cache.used = 0;
}

static cairo_surface_t *icon_cache_lookup(const char *name, int size, int scale, IconVariant variant) {
    if (!name || !*name) return NULL;
    
    if (strchr(name, '/')) return NULL;

    char *norm = normalize_icon_name(name);
    if (!norm) return NULL;
    scale = sanitize_scale(scale);

    for (int i = 0; i < (int)(sizeof(icon_cache.entries) / sizeof(icon_cache.entries[0])); i++) {
        IconCacheEntry *e = &icon_cache.entries[i];
        if (!e->in_use) continue;
        if (e->size != size || e->scale != scale || e->variant != (int)variant) continue;
        if (strcmp(e->name, norm) != 0) continue;
        icon_cache.hits++;
        icon_cache_touch(i);
        free(norm);
        return cairo_surface_reference(e->surface);
    }
    icon_cache.misses++;
    free(norm);
    return NULL;
}

static int icon_cache_insert(const char *name, int size, int scale, IconVariant variant, cairo_surface_t *surf) {
    if (!name || !*name || !surf) return 0;
    if (strchr(name, '/')) return 0;
    scale = sanitize_scale(scale);

    char *norm = normalize_icon_name(name);
    if (!norm) return 0;

    
    int free_idx = -1;
    for (int i = 0; i < (int)(sizeof(icon_cache.entries) / sizeof(icon_cache.entries[0])); i++) {
        if (!icon_cache.entries[i].in_use) { free_idx = i; break; }
    }
    if (free_idx == -1) {
        icon_cache_evict_tail();
        for (int i = 0; i < (int)(sizeof(icon_cache.entries) / sizeof(icon_cache.entries[0])); i++) {
            if (!icon_cache.entries[i].in_use) { free_idx = i; break; }
        }
    }
    if (free_idx == -1) {
        free(norm);
        return 0;
    }

    IconCacheEntry *e = &icon_cache.entries[free_idx];
    e->name = norm;
    if (!e->name) {
        
        e->in_use = 0;
        e->surface = NULL;
        e->size = 0;
        e->scale = 0;
        e->variant = 0;
        e->prev = -1;
        e->next = -1;
        return 0;
    }

    e->in_use = 1;
    e->size = size;
    e->scale = scale;
    e->variant = (int)variant;
    e->surface = surf;
    e->prev = -1;
    e->next = -1;
    icon_cache_link_head(free_idx);
    icon_cache.used++;
    if (mem_debug_enabled) mem_debug_print_stats("icon_cache_insert");
    return 1;
}

static int nizam_x11_error_handler(Display *display, XErrorEvent *error) {
    (void)display;
    if (!error) return 0;

    
    
    
    if (error->error_code == BadWindow || error->error_code == BadDrawable) {
        debug_log("nizam-panel: XError ignored (code=%d req=%d minor=%d resource=0x%lx)\n",
                  error->error_code,
                  error->request_code,
                  error->minor_code,
                  error->resourceid);
        return 0;
    }

    char text[256] = {0};
    XGetErrorText(dpy ? dpy : display, error->error_code, text, (int)sizeof(text));
    fprintf(stderr,
            "nizam-panel: XError: %s (code=%d req=%d minor=%d resource=0x%lx)\n",
            text,
            error->error_code,
            error->request_code,
            error->minor_code,
            error->resourceid);
    return 0;
}

static int nizam_x11_io_error_handler(Display *display) {
    (void)display;
    fprintf(stderr, "nizam-panel: XIOError: lost X server connection\n");
    
    _exit(1);
}

void debug_log(const char *fmt, ...) {
    if (!debug_enabled()) return;
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
}

int clamp_int(int v, int lo, int hi) {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

unsigned long parse_color(Display *d, const char *hex);

static void load_settings(PanelSettings *s) {
    memset(s, 0, sizeof(*s));
    s->panel_enabled = 1;
    s->position = PANEL_BOTTOM;
    s->height = 34;
    s->padding = 8;
    s->monitor = 0;
    s->launcher_enabled = 1;
    s->launcher_cmd[0] = '\0';
    strcpy(s->launcher_label, "Applications");
    s->taskbar_enabled = 1;
    s->clock_enabled = 1;
    strcpy(s->clock_format, "%H:%M");
    strcpy(s->clock_timezone, "local");
}

unsigned long parse_color(Display *d, const char *hex) {
    XColor color;
    Colormap cmap = DefaultColormap(d, screen);
    if (XParseColor(d, cmap, hex, &color) && XAllocColor(d, cmap, &color)) {
        return color.pixel;
    }
    return BlackPixel(d, screen);
}

static void setup_atoms(void) {
    A_NET_CLIENT_LIST = XInternAtom(dpy, "_NET_CLIENT_LIST", False);
    A_NET_ACTIVE_WINDOW = XInternAtom(dpy, "_NET_ACTIVE_WINDOW", False);
    A_NET_WM_NAME = XInternAtom(dpy, "_NET_WM_NAME", False);
    A_UTF8_STRING = XInternAtom(dpy, "UTF8_STRING", False);
    A_NET_WM_STATE = XInternAtom(dpy, "_NET_WM_STATE", False);
    A_NET_WM_STATE_SKIP_TASKBAR = XInternAtom(dpy, "_NET_WM_STATE_SKIP_TASKBAR", False);
    A_NET_WM_STATE_HIDDEN = XInternAtom(dpy, "_NET_WM_STATE_HIDDEN", False);
    A_WM_STATE = XInternAtom(dpy, "WM_STATE", False);
    A_NET_WM_WINDOW_TYPE = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE", False);
    A_NET_WM_WINDOW_TYPE_DOCK = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE_DOCK", False);
    A_NET_WM_WINDOW_TYPE_DESKTOP = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE_DESKTOP", False);
    A_NET_DESKTOP_NAMES = XInternAtom(dpy, "_NET_DESKTOP_NAMES", False);
    A_NET_WM_DESKTOP = XInternAtom(dpy, "_NET_WM_DESKTOP", False);
    A_NET_WM_STRUT_PARTIAL = XInternAtom(dpy, "_NET_WM_STRUT_PARTIAL", False);
    A_NET_WM_STRUT = XInternAtom(dpy, "_NET_WM_STRUT", False);
    A_NET_WM_STATE_ABOVE = XInternAtom(dpy, "_NET_WM_STATE_ABOVE", False);
    A_NET_WM_STATE_STICKY = XInternAtom(dpy, "_NET_WM_STATE_STICKY", False);

    A_NIZAM_PANEL_REDRAW = XInternAtom(dpy, "_NIZAM_PANEL_REDRAW", False);
}

static int get_monitor_geometry(int idx, int *x, int *y, int *w, int *h) {
    int n = 0;
    XRRMonitorInfo *mons = XRRGetMonitors(dpy, root, True, &n);
    if (mons && n > 0) {
        if (idx < 0 || idx >= n) idx = 0;
        *x = mons[idx].x;
        *y = mons[idx].y;
        *w = mons[idx].width;
        *h = mons[idx].height;
        XRRFreeMonitors(mons);
        return 1;
    }
    if (mons) XRRFreeMonitors(mons);
    *x = 0;
    *y = 0;
    *w = DisplayWidth(dpy, screen);
    *h = DisplayHeight(dpy, screen);
    return 0;
}

static void update_clock_text(void) {
    clock_update_text();
}

static int64_t now_realtime_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (int64_t)ts.tv_sec * 1000 + (int64_t)(ts.tv_nsec / 1000000);
}

static int64_t next_clock_deadline_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    int64_t now_ms = (int64_t)ts.tv_sec * 1000 + (int64_t)(ts.tv_nsec / 1000000);

    
    
    
    int64_t next_sec = (int64_t)ts.tv_sec + 1;
    int64_t next_ms = next_sec * 1000;
    int64_t diff = next_ms - now_ms;
    if (diff < 1) diff = 1;
    return now_ms + diff;
}

static PangoLayout *layout_for_role(PanelTextRole role) {
    switch (role) {
        case PANEL_TEXT_CLOCK: return layout_clock;
        case PANEL_TEXT_STATUS: return layout_status;
        case PANEL_TEXT_TITLE:
        default:
            return layout_title;
    }
}

void send_active_window(Window w) {
    XEvent ev;
    memset(&ev, 0, sizeof(ev));
    ev.xclient.type = ClientMessage;
    ev.xclient.window = w;
    ev.xclient.message_type = A_NET_ACTIVE_WINDOW;
    ev.xclient.format = 32;
    ev.xclient.data.l[0] = 1;
    ev.xclient.data.l[1] = CurrentTime;
    ev.xclient.data.l[2] = 0;
    ev.xclient.data.l[3] = 0;
    ev.xclient.data.l[4] = 0;
    XSendEvent(dpy, root, False, SubstructureRedirectMask | SubstructureNotifyMask, &ev);
}


int get_root_cardinal(Atom prop, unsigned long *out) {
    Atom type;
    int fmt;
    unsigned long nitems, bytes;
    unsigned char *data = NULL;
    if (XGetWindowProperty(dpy, root, prop, 0, 1, False, AnyPropertyType, &type, &fmt, &nitems, &bytes, &data) != Success) {
        return 0;
    }
    int ok = 0;
    if (data && nitems == 1 && (fmt == 32 || fmt == 16 || fmt == 8)) {
        *out = *((unsigned long *)data);
        ok = 1;
    }
    if (data) XFree(data);
    return ok;
}

int window_has_state(Window w, Atom state_atom) {
    Atom type;
    int fmt;
    unsigned long nitems, bytes;
    unsigned char *data = NULL;
    if (XGetWindowProperty(dpy, w, A_NET_WM_STATE, 0, 1024, False, XA_ATOM, &type, &fmt, &nitems, &bytes, &data) != Success) {
        return 0;
    }
    int found = 0;
    if (data && type == XA_ATOM) {
        Atom *atoms = (Atom *)data;
        for (unsigned long i = 0; i < nitems; i++) {
            if (atoms[i] == state_atom) { found = 1; break; }
        }
    }
    if (data) XFree(data);
    return found;
}

int window_is_type(Window w, Atom type_atom) {
    Atom type;
    int fmt;
    unsigned long nitems, bytes;
    unsigned char *data = NULL;
    if (XGetWindowProperty(dpy, w, A_NET_WM_WINDOW_TYPE, 0, 16, False, XA_ATOM, &type, &fmt, &nitems, &bytes, &data) != Success) {
        return 0;
    }
    int found = 0;
    if (data && type == XA_ATOM) {
        Atom *atoms = (Atom *)data;
        for (unsigned long i = 0; i < nitems; i++) {
            if (atoms[i] == type_atom) { found = 1; break; }
        }
    }
    if (data) XFree(data);
    return found;
}

int get_window_desktop(Window w, unsigned long *out) {
    Atom type;
    int fmt;
    unsigned long nitems, bytes;
    unsigned char *data = NULL;
    if (XGetWindowProperty(dpy, w, A_NET_WM_DESKTOP, 0, 1, False, XA_CARDINAL, &type, &fmt, &nitems, &bytes, &data) != Success) {
        return 0;
    }
    if (!data || nitems < 1 || type != XA_CARDINAL || fmt != 32) {
        if (data) XFree(data);
        return 0;
    }
    *out = *((unsigned long *)data);
    XFree(data);
    return 1;
}

void get_window_title(Window w, char *out, size_t out_len) {
    out[0] = '\0';
    Atom type;
    int fmt;
    unsigned long nitems, bytes;
    unsigned char *data = NULL;
    if (XGetWindowProperty(dpy, w, A_NET_WM_NAME, 0, 1024, False, A_UTF8_STRING, &type, &fmt, &nitems, &bytes, &data) == Success) {
        if (data) {
            strncpy(out, (char *)data, out_len - 1);
            out[out_len - 1] = '\0';
            XFree(data);
            for (size_t i = 0; i < out_len; i++) {
                if (out[i] == '\n' || out[i] == '\r') out[i] = ' ';
                if (out[i] == '\0') break;
            }
            return;
        }
    }
    XTextProperty prop;
    if (XGetWMName(dpy, w, &prop) && prop.value) {
        strncpy(out, (char *)prop.value, out_len - 1);
        out[out_len - 1] = '\0';
        XFree(prop.value);
        for (size_t i = 0; i < out_len; i++) {
            if (out[i] == '\n' || out[i] == '\r') out[i] = ' ';
            if (out[i] == '\0') break;
        }
    }
}

void get_window_class(Window w, char *instance, size_t instance_len, char *klass, size_t klass_len) {
    instance[0] = '\0';
    klass[0] = '\0';
    XClassHint hint;
    if (XGetClassHint(dpy, w, &hint)) {
        if (hint.res_name) {
            strncpy(instance, hint.res_name, instance_len - 1);
            instance[instance_len - 1] = '\0';
        }
        if (hint.res_class) {
            strncpy(klass, hint.res_class, klass_len - 1);
            klass[klass_len - 1] = '\0';
        }
        if (hint.res_name) XFree(hint.res_name);
        if (hint.res_class) XFree(hint.res_class);
    }
}

static int file_exists(const char *path) {
    struct stat st;
    return (stat(path, &st) == 0);
}

static int dir_exists(const char *path) {
    struct stat st;
    if (!path || path[0] == '\0') return 0;
    if (stat(path, &st) != 0) return 0;
    return S_ISDIR(st.st_mode);
}

static void path_parent_inplace(char *path) {
    if (!path) return;
    size_t n = strlen(path);
    if (n == 0) return;
    
    while (n > 1 && path[n - 1] == '/') {
        path[n - 1] = '\0';
        n--;
    }
    char *slash = strrchr(path, '/');
    if (!slash) {
        path[0] = '\0';
        return;
    }
    if (slash == path) {
        
        path[1] = '\0';
        return;
    }
    *slash = '\0';
}

static int build_common_icons_path(char *dst, size_t dst_sz, const char *base) {
    if (!dst || dst_sz == 0 || !base) return 0;
    const char *suffix = "/nizam-common/icons";
    size_t blen = strlen(base);
    size_t slen = strlen(suffix);
    if (blen + slen + 1 > dst_sz) {
        dst[0] = '\0';
        return 0;
    }
    memcpy(dst, base, blen);
    memcpy(dst + blen, suffix, slen);
    dst[blen + slen] = '\0';
    return 1;
}

static cairo_surface_t *load_icon_from_path(const char *path) {
    if (!path || path[0] == '\0') return NULL;
    if (!file_exists(path)) return NULL;

#ifdef NIZAM_HAVE_GDKPIXBUF
    GError *err = NULL;
    GdkPixbuf *pb = gdk_pixbuf_new_from_file(path, &err);
    if (!pb) {
        if (err) g_error_free(err);
        return NULL;
    }

    int w = gdk_pixbuf_get_width(pb);
    int h = gdk_pixbuf_get_height(pb);
    if (w <= 0 || h <= 0) {
        g_object_unref(pb);
        return NULL;
    }

    cairo_surface_t *surf = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w, h);
    if (cairo_surface_status(surf) != CAIRO_STATUS_SUCCESS) {
        cairo_surface_destroy(surf);
        g_object_unref(pb);
        return NULL;
    }

    unsigned char *dst = cairo_image_surface_get_data(surf);
    int dst_stride = cairo_image_surface_get_stride(surf);

    const unsigned char *src = gdk_pixbuf_get_pixels(pb);
    int src_stride = gdk_pixbuf_get_rowstride(pb);
    int nchan = gdk_pixbuf_get_n_channels(pb);
    int has_alpha = gdk_pixbuf_get_has_alpha(pb);

    
    for (int y = 0; y < h; y++) {
        const unsigned char *srow = src + y * src_stride;
        unsigned char *drow = dst + y * dst_stride;
        for (int x = 0; x < w; x++) {
            const unsigned char *sp = srow + x * nchan;
            unsigned char r = sp[0];
            unsigned char g = sp[1];
            unsigned char b = sp[2];
            unsigned char a = has_alpha ? sp[3] : 0xff;

            unsigned char *dp = drow + x * 4;
            dp[0] = (unsigned char)((b * a) / 255);
            dp[1] = (unsigned char)((g * a) / 255);
            dp[2] = (unsigned char)((r * a) / 255);
            dp[3] = a;
        }
    }

    cairo_surface_mark_dirty(surf);
    g_object_unref(pb);
    return surf;
#else
    cairo_surface_t *surf = cairo_image_surface_create_from_png(path);
    if (cairo_surface_status(surf) != CAIRO_STATUS_SUCCESS) {
        cairo_surface_destroy(surf);
        return NULL;
    }
    return surf;
#endif
}

static int ends_with(const char *s, const char *suffix) {
    if (!s || !suffix) return 0;
    size_t ls = strlen(s), lf = strlen(suffix);
    if (ls < lf) return 0;
    return strcmp(s + (ls - lf), suffix) == 0;
}

static cairo_surface_t *try_icon_path_raster(const char *root, const char *theme, int sz, const char *name, const char *ext_with_dot) {
    if (!root || !theme || !name || !ext_with_dot) return NULL;
    
    const char *dirs[] = {
        "apps",
        "categories",
        "places",
        "actions",
        "status",
        "devices",
        "mimetypes",
        "emblems",
    };
    for (size_t d = 0; d < sizeof(dirs) / sizeof(dirs[0]); d++) {
        
        size_t need = strlen(root) + 1 + strlen(theme) + 1 + 10 + 1 + strlen(dirs[d]) + 1 + strlen(name) + strlen(ext_with_dot) + 1;
        char *p = malloc(need);
        if (!p) return NULL;
        snprintf(p, need, "%s/%s/%dx%d/%s/%s%s", root, theme, sz, sz, dirs[d], name, ext_with_dot);
        cairo_surface_t *surf = load_icon_from_path(p);
        free(p);
        if (surf) return surf;
    }
    return NULL;
}

#ifdef NIZAM_HAVE_LIBRSVG
static cairo_surface_t *load_svg_icon_from_path(const char *path, int size);

static cairo_surface_t *try_icon_path_svg(const char *root, const char *theme, const char *name, int size) {
    if (!root || !theme || !name) return NULL;
    const char *size_dirs[] = {"scalable", "symbolic"};
    
    const char *icon_dirs[] = {
        "apps",
        "categories",
        "places",
        "actions",
        "status",
        "devices",
        "mimetypes",
        "emblems",
    };

    char name_symbolic[512];
    name_symbolic[0] = '\0';
    if (!ends_with(name, "-symbolic")) {
        snprintf(name_symbolic, sizeof(name_symbolic), "%s-symbolic", name);
    }

    for (size_t sd = 0; sd < sizeof(size_dirs) / sizeof(size_dirs[0]); sd++) {
        for (size_t d = 0; d < sizeof(icon_dirs) / sizeof(icon_dirs[0]); d++) {
            const char *candidates[2];
            size_t cand_count = 0;
            candidates[cand_count++] = name;
            if (name_symbolic[0]) candidates[cand_count++] = name_symbolic;

            for (size_t c = 0; c < cand_count; c++) {
                
                size_t need = strlen(root) + 1 + strlen(theme) + 1 + strlen(size_dirs[sd]) + 1 + strlen(icon_dirs[d]) + 1 + strlen(candidates[c]) + 4 + 1;
                char *p = malloc(need);
                if (!p) return NULL;
                snprintf(p, need, "%s/%s/%s/%s/%s.svg", root, theme, size_dirs[sd], icon_dirs[d], candidates[c]);
                cairo_surface_t *surf = load_svg_icon_from_path(p, size);
                free(p);
                if (surf) return surf;
            }
        }
    }
    return NULL;
}
#endif

#ifdef NIZAM_HAVE_LIBRSVG
static cairo_surface_t *load_svg_icon_from_path(const char *path, int size) {
    if (!path || path[0] == '\0') return NULL;
    if (!file_exists(path)) return NULL;

    GError *err = NULL;
    RsvgHandle *h = rsvg_handle_new_from_file(path, &err);
    if (!h) {
        if (err) g_error_free(err);
        return NULL;
    }

    cairo_surface_t *surf = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, size, size);
    if (cairo_surface_status(surf) != CAIRO_STATUS_SUCCESS) {
        cairo_surface_destroy(surf);
        g_object_unref(h);
        return NULL;
    }
    cairo_t *c = cairo_create(surf);
    cairo_set_source_rgba(c, 0, 0, 0, 0);
    cairo_paint(c);

#if LIBRSVG_CHECK_VERSION(2, 52, 0)
    
    RsvgRectangle viewport;
    viewport.x = 0;
    viewport.y = 0;
    viewport.width = (double)size;
    viewport.height = (double)size;

    GError *render_err = NULL;
    if (!rsvg_handle_render_document(h, c, &viewport, &render_err)) {
        if (render_err) g_error_free(render_err);
        cairo_destroy(c);
        cairo_surface_destroy(surf);
        g_object_unref(h);
        return NULL;
    }
#else
    
    RsvgDimensionData dim;
    rsvg_handle_get_dimensions(h, &dim);
    double iw = (dim.width > 0) ? (double)dim.width : (double)size;
    double ih = (dim.height > 0) ? (double)dim.height : (double)size;
    double scale = (iw > ih) ? ((double)size / iw) : ((double)size / ih);
    if (scale <= 0.0) scale = 1.0;

    cairo_scale(c, scale, scale);
    if (!rsvg_handle_render_cairo(h, c)) {
        cairo_destroy(c);
        cairo_surface_destroy(surf);
        g_object_unref(h);
        return NULL;
    }
#endif
    cairo_destroy(c);
    g_object_unref(h);
    return surf;
}
#endif

static int read_desktop_icon(const char *path, char *out, size_t out_len) {
    FILE *f = fopen(path, "r");
    if (!f) return 0;
    char line[512];
    int in_entry = 0;
    while (fgets(line, sizeof(line), f)) {
        if (line[0] == '[') {
            in_entry = (strncmp(line, "[Desktop Entry]", 15) == 0);
            continue;
        }
        if (!in_entry) continue;
        if (strncmp(line, "Icon=", 5) == 0) {
            char *val = line + 5;
            while (*val == ' ' || *val == '\t') val++;
            char *end = val + strlen(val);
            while (end > val && (end[-1] == '\n' || end[-1] == '\r')) end--;
            size_t len = (size_t)(end - val);
            if (len >= out_len) len = out_len - 1;
            memcpy(out, val, len);
            out[len] = '\0';
            fclose(f);
            return 1;
        }
    }
    fclose(f);
    return 0;
}

int find_desktop_icon_for_class(const char *instance, const char *klass, char *out, size_t out_len) {
    const char *home = getenv("HOME");
    char path[512];
    const char *names[4];
    char inst_lower[128], class_lower[128];
    size_t i = 0;
    if (instance && instance[0]) names[i++] = instance;
    if (klass && klass[0]) names[i++] = klass;
    if (instance && instance[0]) {
        snprintf(inst_lower, sizeof(inst_lower), "%s", instance);
        for (char *p = inst_lower; *p; p++) *p = (char)tolower(*p);
        names[i++] = inst_lower;
    }
    if (klass && klass[0]) {
        snprintf(class_lower, sizeof(class_lower), "%s", klass);
        for (char *p = class_lower; *p; p++) *p = (char)tolower(*p);
        names[i++] = class_lower;
    }
    for (size_t n = 0; n < i; n++) {
        if (home) {
            snprintf(path, sizeof(path), "%s/.local/share/applications/%s.desktop", home, names[n]);
            if (read_desktop_icon(path, out, out_len)) return 1;
        }
        snprintf(path, sizeof(path), "/usr/share/applications/%s.desktop", names[n]);
        if (read_desktop_icon(path, out, out_len)) return 1;
    }
    return 0;
}

static cairo_surface_t *load_icon_from_name_uncached(const char *name, int size) {
    if (!name || name[0] == '\0') return NULL;
    if (strchr(name, '/')) {
        
#ifdef NIZAM_HAVE_LIBRSVG
        if (ends_with(name, ".svg")) {
            cairo_surface_t *s = load_svg_icon_from_path(name, size);
            if (s) return s;
        }
#endif
        cairo_surface_t *s = load_icon_from_path(name);
        if (s) return s;

        
        if (!ends_with(name, ".png") && !ends_with(name, ".xpm") && !ends_with(name, ".svg")) {
            char path[1024];
            snprintf(path, sizeof(path), "%s.png", name);
            s = load_icon_from_path(path);
            if (s) return s;
            snprintf(path, sizeof(path), "%s.xpm", name);
            s = load_icon_from_path(path);
            if (s) return s;
#ifdef NIZAM_HAVE_LIBRSVG
            snprintf(path, sizeof(path), "%s.svg", name);
            s = load_svg_icon_from_path(path, size);
            if (s) return s;
#endif
        }
        return NULL;
    }

    
    
    char norm_name[512];
    const char *lookup = name;
    if (!strchr(name, '/') && (ends_with(name, ".png") || ends_with(name, ".xpm") || ends_with(name, ".svg"))) {
        size_t ln = strlen(name);
        if (ln > 4 && ln < sizeof(norm_name)) {
            memcpy(norm_name, name, ln - 4);
            norm_name[ln - 4] = '\0';
            lookup = norm_name;
        }
    }

    const char *home = getenv("HOME");
    const char *themes[] = {"hicolor", "Adwaita", "AdwaitaLegacy"};
    const int sizes[] = {16, 22, 24, 32, 48, 64, 96, 128, 256};
    char path[1024];

    
    
    char common_icons_root[1024];
    common_icons_root[0] = '\0';
    const char *common_dir = getenv("NIZAM_COMMON_DIR");
    if (common_dir && *common_dir) {
        snprintf(common_icons_root, sizeof(common_icons_root), "%s/icons", common_dir);
        if (!dir_exists(common_icons_root)) common_icons_root[0] = '\0';
    }

    char exe_icons_root[1024];
    exe_icons_root[0] = '\0';
    {
        char exe_path[1024];
        ssize_t n = readlink("/proc/self/exe", exe_path, (sizeof(exe_path) - 1));
        if (n > 0) {
            exe_path[n] = '\0';
            
            
            path_parent_inplace(exe_path);
            for (int up = 0; up < 8; up++) {
                if (!build_common_icons_path(exe_icons_root, sizeof(exe_icons_root), exe_path)) {
                    exe_icons_root[0] = '\0';
                    break;
                }
                if (dir_exists(exe_icons_root)) break;
                exe_icons_root[0] = '\0';
                path_parent_inplace(exe_path);
                if (exe_path[0] == '\0') break;
            }
        }
    }

    char cwd_icons_root[1024];
    cwd_icons_root[0] = '\0';
    {
        char cwd[1024];
        if (getcwd(cwd, sizeof(cwd))) {
            build_common_icons_path(cwd_icons_root, sizeof(cwd_icons_root), cwd);
            if (!dir_exists(cwd_icons_root)) cwd_icons_root[0] = '\0';
        }
    }

    
    char fp_user[1024];
    fp_user[0] = '\0';
    if (home) snprintf(fp_user, sizeof(fp_user), "%s/.local/share/flatpak/exports/share/icons", home);
    const char *icon_roots[] = {
        common_icons_root[0] ? common_icons_root : NULL,
        exe_icons_root[0] ? exe_icons_root : NULL,
        cwd_icons_root[0] ? cwd_icons_root : NULL,
        home ? "~/.local/share/icons" : NULL, 
        home ? "~/.icons" : NULL,             
        fp_user[0] ? fp_user : NULL,
        "/var/lib/flatpak/exports/share/icons",
        "/usr/local/share/icons",
        "/usr/share/icons",
    };

    char home_icons[1024];
    char home_doticons[1024];
    home_icons[0] = '\0';
    home_doticons[0] = '\0';
    if (home) {
        snprintf(home_icons, sizeof(home_icons), "%s/.local/share/icons", home);
        snprintf(home_doticons, sizeof(home_doticons), "%s/.icons", home);
    }

    for (size_t t = 0; t < sizeof(themes)/sizeof(themes[0]); t++) {
        for (size_t r = 0; r < sizeof(icon_roots)/sizeof(icon_roots[0]); r++) {
            const char *root = icon_roots[r];
            if (!root) continue;
            if (strcmp(root, "~/.local/share/icons") == 0) root = home_icons;
            if (strcmp(root, "~/.icons") == 0) root = home_doticons;

            for (size_t s = 0; s < sizeof(sizes)/sizeof(sizes[0]); s++) {
                cairo_surface_t *surf = try_icon_path_raster(root, themes[t], sizes[s], lookup, ".png");
                if (surf) return surf;
                surf = try_icon_path_raster(root, themes[t], sizes[s], lookup, ".xpm");
                if (surf) return surf;
            }
        }
    }

#ifdef NIZAM_HAVE_LIBRSVG
    
    for (size_t t = 0; t < sizeof(themes)/sizeof(themes[0]); t++) {
        for (size_t r = 0; r < sizeof(icon_roots)/sizeof(icon_roots[0]); r++) {
            const char *root = icon_roots[r];
            if (!root) continue;
            if (strcmp(root, "~/.local/share/icons") == 0) root = home_icons;
            if (strcmp(root, "~/.icons") == 0) root = home_doticons;

            cairo_surface_t *surf = try_icon_path_svg(root, themes[t], lookup, size);
            if (surf) return surf;
        }
    }
    
    snprintf(path, sizeof(path), "/usr/share/icons/hicolor/scalable/apps/%s.svg", lookup);
    cairo_surface_t *surf_svg = load_svg_icon_from_path(path, size);
    if (surf_svg) return surf_svg;
#endif
    snprintf(path, sizeof(path), "/usr/share/pixmaps/%s.png", lookup);
    cairo_surface_t *surf = load_icon_from_path(path);
    if (surf) return surf;
    snprintf(path, sizeof(path), "/usr/share/pixmaps/%s.xpm", lookup);
    surf = load_icon_from_path(path);
    if (surf) return surf;

#ifdef NIZAM_HAVE_LIBRSVG
    snprintf(path, sizeof(path), "/usr/share/pixmaps/%s.svg", lookup);
    surf = load_svg_icon_from_path(path, size);
    if (surf) return surf;
#endif

    return NULL;
}

cairo_surface_t *load_icon_from_name(const char *name, int size) {
    
    (void)size;
    const int size_px = NIZAM_PANEL_ICON_PX;
    const int scale = NIZAM_PANEL_ICON_SCALE;
    const IconVariant variant = ICON_VARIANT_NORMAL;

    cairo_surface_t *cached = icon_cache_lookup(name, size_px, scale, variant);
    if (cached) return cached;

    int px = size_px * scale;
    if (px < 1) px = 1;
    cairo_surface_t *surf = load_icon_from_name_uncached(name, px);
    if (!surf) return NULL;

    
    
    if (icon_cache_insert(name, size_px, scale, variant, surf)) {
        return cairo_surface_reference(surf);
    }
    return surf;
}

cairo_surface_t *load_window_icon(Window w, int size) {
    Atom A_NET_WM_ICON = XInternAtom(dpy, "_NET_WM_ICON", False);
    Atom type;
    int fmt;
    unsigned long nitems, bytes;
    unsigned char *data = NULL;
    if (XGetWindowProperty(dpy, w, A_NET_WM_ICON, 0, 1048576, False, XA_CARDINAL,
                           &type, &fmt, &nitems, &bytes, &data) != Success) {
        return NULL;
    }
    if (!data || type != XA_CARDINAL || fmt != 32 || nitems < 2) {
        if (data) XFree(data);
        return NULL;
    }

    unsigned long *icons = (unsigned long *)data;
    unsigned long best_w = 0, best_h = 0;
    unsigned long best_score = 0;
    unsigned long *best = NULL;
    unsigned long idx = 0;
    while (idx + 1 < nitems) {
        unsigned long w0 = icons[idx++];
        unsigned long h0 = icons[idx++];
        if (w0 == 0 || h0 == 0) break;
        if (idx + w0 * h0 > nitems) break;
        unsigned long score = (unsigned long)labs((long)w0 - size) + (unsigned long)labs((long)h0 - size);
        if (!best || score < best_score) {
            best = &icons[idx];
            best_w = w0;
            best_h = h0;
            best_score = score;
        }
        idx += w0 * h0;
    }
    if (!best) {
        XFree(data);
        return NULL;
    }

    cairo_surface_t *surf = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, (int)best_w, (int)best_h);
    unsigned char *dst = cairo_image_surface_get_data(surf);
    int stride = cairo_image_surface_get_stride(surf);
    for (unsigned long y = 0; y < best_h; y++) {
        for (unsigned long x = 0; x < best_w; x++) {
            unsigned long argb = best[y * best_w + x];
            unsigned char a = (argb >> 24) & 0xff;
            unsigned char r = (argb >> 16) & 0xff;
            unsigned char g = (argb >> 8) & 0xff;
            unsigned char b = (argb) & 0xff;
            unsigned char *p = dst + y * stride + x * 4;
            p[0] = (unsigned char)((b * a) / 255);
            p[1] = (unsigned char)((g * a) / 255);
            p[2] = (unsigned char)((r * a) / 255);
            p[3] = a;
        }
    }
    cairo_surface_mark_dirty(surf);
    XFree(data);
    return surf;
}

cairo_surface_t *load_window_icon_hint(Window w, int size) {
    XWMHints *hints = XGetWMHints(dpy, w);
    if (!hints) return NULL;
    if (!(hints->flags & IconPixmapHint) || hints->icon_pixmap == None) {
        XFree(hints);
        return NULL;
    }
    Pixmap pix = hints->icon_pixmap;
    XFree(hints);

    XWindowAttributes attr;
    if (!XGetWindowAttributes(dpy, root, &attr)) return NULL;

    XImage *img = XGetImage(dpy, pix, 0, 0, (unsigned int)size, (unsigned int)size, AllPlanes, ZPixmap);
    if (!img) return NULL;

    cairo_surface_t *surf = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, size, size);
    unsigned char *dst = cairo_image_surface_get_data(surf);
    int stride = cairo_image_surface_get_stride(surf);
    for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
            unsigned long pixel = XGetPixel(img, x, y);
            unsigned char r = (pixel >> 16) & 0xff;
            unsigned char g = (pixel >> 8) & 0xff;
            unsigned char b = (pixel) & 0xff;
            unsigned char *p = dst + y * stride + x * 4;
            p[0] = b;
            p[1] = g;
            p[2] = r;
            p[3] = 0xff;
        }
    }
    cairo_surface_mark_dirty(surf);
    XDestroyImage(img);
    return surf;
}

static int64_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + (int64_t)(ts.tv_nsec / 1000000);
}

static void update_clients(int force) {
    static int64_t last_ms = 0;
    int64_t now = now_ms();
    if (!force && (now - last_ms) < 80) {
        return;
    }
    last_ms = now;
    tasklist_update_clients();
}

void iconify_window(Window w) {
    if (XIconifyWindow(dpy, w, screen)) {
        return;
    }
    XEvent ev;
    memset(&ev, 0, sizeof(ev));
    ev.xclient.type = ClientMessage;
    ev.xclient.window = w;
    ev.xclient.message_type = A_NET_WM_STATE;
    ev.xclient.format = 32;
    ev.xclient.data.l[0] = 1; 
    ev.xclient.data.l[1] = A_NET_WM_STATE_HIDDEN;
    ev.xclient.data.l[2] = 0;
    ev.xclient.data.l[3] = 0;
    ev.xclient.data.l[4] = 0;
    XSendEvent(dpy, root, False, SubstructureRedirectMask | SubstructureNotifyMask, &ev);
}

static void update_layout(void) {
    int mx = 0, my = 0, mw = DisplayWidth(dpy, screen), mh = DisplayHeight(dpy, screen);
    get_monitor_geometry(settings.monitor, &mx, &my, &mw, &mh);

    panel_w = mw;
    panel_h = clamp_int(settings.height, 16, 128);
    panel_x = mx;
    if (settings.position == PANEL_BOTTOM) {
        panel_y = my + mh - panel_h;
    } else {
        panel_y = my;
    }

    XMoveResizeWindow(dpy, win, panel_x, panel_y, panel_w, panel_h);

    int x = settings.padding;
    int y = settings.padding;
    int h = panel_h - settings.padding * 2;
    const int sep_gap = 0;
    const int sep_inset = 9;

    
    update_clock_text();
    PangoLayout *ly_clock = layout_for_role(PANEL_TEXT_CLOCK);
    pango_layout_set_width(ly_clock, -1);
    pango_layout_set_text(ly_clock, clock_text, -1);
    int tw = 0, th = 0;
    pango_layout_get_pixel_size(ly_clock, &tw, &th);
    int clock_w = tw + 16;
    clock_rect.w = clock_w;
    clock_rect.h = h;
    clock_rect.x = panel_w - settings.padding - clock_w;
    clock_rect.y = y;

    clock_sep_rect.w = 0;
    clock_sep_rect.h = 0;
    clock_sep_rect.x = 0;
    clock_sep_rect.y = 0;
    clock_sep_soft_rect.w = 0;
    clock_sep_soft_rect.h = 0;
    clock_sep_soft_rect.x = 0;
    clock_sep_soft_rect.y = 0;
    if (settings.clock_enabled) {
        clock_sep_rect.w = 1;
        clock_sep_rect.h = h - sep_inset * 2;
        if (clock_sep_rect.h < 0) clock_sep_rect.h = 0;
        clock_sep_rect.x = clock_rect.x - sep_gap - clock_sep_rect.w;
        clock_sep_rect.y = y + sep_inset;
        clock_sep_soft_rect.w = 1;
        clock_sep_soft_rect.h = clock_sep_rect.h;
        clock_sep_soft_rect.x = clock_sep_rect.x + 1;
        clock_sep_soft_rect.y = clock_sep_rect.y;
    }

    int ws_start = settings.clock_enabled ? (clock_sep_rect.x - sep_gap) : clock_rect.x;

    
    launcher_label_w = 0;
    if (settings.launcher_enabled) {
        launcher_rect.x = x;
        launcher_rect.y = y;
        launcher_rect.h = h;
        launcher_rect.w = h;
        if (settings.launcher_label[0] != '\0') {
            PangoLayout *ly_status = layout_for_role(PANEL_TEXT_STATUS);
            pango_layout_set_width(ly_status, -1);
            pango_layout_set_text(ly_status, settings.launcher_label, -1);
            int lw = 0, lh = 0;
            pango_layout_get_pixel_size(ly_status, &lw, &lh);
            launcher_label_w = lw;
            int icon_sz = NIZAM_PANEL_ICON_PX;
            int icon_x = launcher_rect.x + LAUNCHER_PAD + LAUNCHER_ICON_LEFT_PAD;
            int text_start = icon_x + icon_sz + LAUNCHER_ICON_GAP;
            const int label_right_pad = 8;
            launcher_rect.w = (text_start - launcher_rect.x) + launcher_label_w + label_right_pad;
        }
        x += launcher_rect.w + sep_gap;
        launcher_sep_rect.x = x;
        launcher_sep_rect.y = y + sep_inset;
        launcher_sep_rect.w = 1;
        launcher_sep_rect.h = h - sep_inset * 2;
        if (launcher_sep_rect.h < 0) launcher_sep_rect.h = 0;
        launcher_sep_soft_rect.w = 1;
        launcher_sep_soft_rect.h = launcher_sep_rect.h;
        launcher_sep_soft_rect.x = launcher_sep_rect.x + 1;
        launcher_sep_soft_rect.y = launcher_sep_rect.y;
        x += launcher_sep_rect.w + sep_gap;
    } else {
        launcher_rect.w = launcher_rect.h = 0;
        launcher_sep_rect.w = launcher_sep_rect.h = 0;
        launcher_sep_soft_rect.w = launcher_sep_soft_rect.h = 0;
    }

    
    int task_x = x;
    int task_w = ws_start - 8 - task_x;
    if (!settings.taskbar_enabled) task_w = 0;

    int per = (client_count > 0) ? task_w / client_count : 0;
    if (per < 80) per = 80;
    if (per > 220) per = 220;
    int max_buttons = (per > 0) ? task_w / per : 0;
    if (max_buttons > client_count) max_buttons = client_count;

    for (int i = 0; i < client_count; i++) {
        if (i >= max_buttons) {
            task_rects[i].w = 0;
            continue;
        }
        task_rects[i].x = task_x;
        task_rects[i].y = y;
        task_rects[i].w = per - 4;
        task_rects[i].h = h;
        task_x += per;
        task_icon_rects[i].x = task_rects[i].x + 6;
        task_icon_rects[i].y = task_rects[i].y + (h - NIZAM_PANEL_ICON_PX) / 2;
        task_icon_rects[i].w = NIZAM_PANEL_ICON_PX;
        task_icon_rects[i].h = NIZAM_PANEL_ICON_PX;
    }
}

void draw_rect(cairo_t *c, Rect r, const char *hex, int fill) {
    unsigned long pixel = parse_color(dpy, hex);
    XColor xc;
    xc.pixel = pixel;
    XQueryColor(dpy, DefaultColormap(dpy, screen), &xc);
    double rr = xc.red / 65535.0;
    double gg = xc.green / 65535.0;
    double bb = xc.blue / 65535.0;
    cairo_set_source_rgb(c, rr, gg, bb);
    cairo_rectangle(c, r.x, r.y, r.w, r.h);
    if (fill) cairo_fill(c);
    else cairo_stroke(c);
}

void draw_text_role(PanelTextRole role,
                    const char *text,
                    int x,
                    int y,
                    int w,
                    int h,
                    const char *hex,
                    int bold,
                    int align_center) {
    PangoLayout *ly = layout_for_role(role);
    if (!ly) return;
    (void)bold;

    pango_layout_set_text(ly, text, -1);
    pango_layout_set_width(ly, w * PANGO_SCALE);
    pango_layout_set_height(ly, -1);
    pango_layout_set_single_paragraph_mode(ly, TRUE);
    pango_layout_set_ellipsize(ly, PANGO_ELLIPSIZE_END);
    if (align_center) pango_layout_set_alignment(ly, PANGO_ALIGN_CENTER);
    else pango_layout_set_alignment(ly, PANGO_ALIGN_LEFT);

    unsigned long pixel = parse_color(dpy, hex);
    XColor xc;
    xc.pixel = pixel;
    XQueryColor(dpy, DefaultColormap(dpy, screen), &xc);
    double rr = xc.red / 65535.0;
    double gg = xc.green / 65535.0;
    double bb = xc.blue / 65535.0;
    cairo_set_source_rgb(cr, rr, gg, bb);
    int tw = 0, th = 0;
    pango_layout_get_pixel_size(ly, &tw, &th);
    int dy = y + (h - th) / 2;
    if (dy < y) dy = y;
    cairo_move_to(cr, x, dy);
    pango_cairo_show_layout(cr, ly);
}

void draw_icon(cairo_surface_t *icon, int x, int y, int size) {
    draw_icon_to(cr, icon, x, y, size);
}

void draw_icon_to(cairo_t *c, cairo_surface_t *icon, int x, int y, int size) {
    if (!c || !icon) return;
    int iw = cairo_image_surface_get_width(icon);
    int ih = cairo_image_surface_get_height(icon);
    if (iw <= 0 || ih <= 0) return;
    double sx = (double)size / (double)iw;
    double sy = (double)size / (double)ih;
    cairo_save(c);
    cairo_translate(c, x, y);
    cairo_scale(c, sx, sy);
    cairo_set_source_surface(c, icon, 0, 0);
    cairo_paint(c);
    cairo_restore(c);
}

void draw_icon_tinted_to(cairo_t *c, cairo_surface_t *icon, int x, int y, int size, const char *hex) {
    if (!c || !icon || !hex) return;
    int iw = cairo_image_surface_get_width(icon);
    int ih = cairo_image_surface_get_height(icon);
    if (iw <= 0 || ih <= 0) return;
    double sx = (double)size / (double)iw;
    double sy = (double)size / (double)ih;

    unsigned long pixel = parse_color(dpy, hex);
    XColor xc;
    xc.pixel = pixel;
    XQueryColor(dpy, DefaultColormap(dpy, screen), &xc);
    double rr = xc.red / 65535.0;
    double gg = xc.green / 65535.0;
    double bb = xc.blue / 65535.0;

    cairo_save(c);
    cairo_translate(c, x, y);
    cairo_scale(c, sx, sy);
    cairo_set_source_rgb(c, rr, gg, bb);
    cairo_mask_surface(c, icon, 0, 0);
    cairo_restore(c);
}


void draw_triangle(int x, int y, int w, int h, int dir_left, const char *hex) {
    unsigned long pixel = parse_color(dpy, hex);
    XColor xc;
    xc.pixel = pixel;
    XQueryColor(dpy, DefaultColormap(dpy, screen), &xc);
    double rr = xc.red / 65535.0;
    double gg = xc.green / 65535.0;
    double bb = xc.blue / 65535.0;
    cairo_set_source_rgb(cr, rr, gg, bb);
    
    int size = (w < h ? w : h);
    size = (int)(size * 0.35);
    if (size < 6) size = 6;
    if (size > w - 2) size = w - 2;
    if (size > h - 2) size = h - 2;

    int midx = x + w / 2;
    int midy = y + h / 2;
    int half = size / 2;
    int left = midx - half;
    int right = midx + half;
    int top = midy - half;
    int bot = midy + half;

    if (dir_left) {
        cairo_move_to(cr, left, midy);
        cairo_line_to(cr, right, top);
        cairo_line_to(cr, right, bot);
    } else {
        cairo_move_to(cr, right, midy);
        cairo_line_to(cr, left, top);
        cairo_line_to(cr, left, bot);
    }
    cairo_close_path(cr);
    cairo_fill(cr);
}

static void redraw(void) {
    if (!surface) return;

    
    Rect full = {0, 0, panel_w, panel_h};
    draw_rect(cr, full, color_bg, 1);

    menu_draw();
    
    tasklist_draw();
    clock_draw();
    if (launcher_sep_rect.w > 0) draw_rect(cr, launcher_sep_rect, color_sep, 1);
    if (launcher_sep_soft_rect.w > 0) draw_rect(cr, launcher_sep_soft_rect, color_sep_soft, 1);
    if (clock_sep_rect.w > 0) draw_rect(cr, clock_sep_rect, color_sep, 1);
    if (clock_sep_soft_rect.w > 0) draw_rect(cr, clock_sep_soft_rect, color_sep_soft, 1);

    cairo_surface_flush(surface);

    if (back_pixmap != None) {
        XCopyArea(dpy, back_pixmap, win, back_gc, 0, 0, (unsigned int)panel_w, (unsigned int)panel_h, 0, 0);
    }
    XFlush(dpy);
}

static void redraw_clock_only(void) {
    if (!surface || !settings.clock_enabled) return;

    cairo_save(cr);
    cairo_rectangle(cr, clock_rect.x, clock_rect.y, clock_rect.w, clock_rect.h);
    cairo_clip(cr);

    draw_rect(cr, clock_rect, color_bg, 1);
    clock_draw();

    cairo_restore(cr);
    cairo_surface_flush(surface);

    if (back_pixmap != None) {
        XCopyArea(dpy,
                  back_pixmap,
                  win,
                  back_gc,
                  clock_rect.x,
                  clock_rect.y,
                  (unsigned int)clock_rect.w,
                  (unsigned int)clock_rect.h,
                  clock_rect.x,
                  clock_rect.y);
    }
    XFlush(dpy);
    if (mem_debug_enabled) mem_debug_print_stats("clock_redraw");
}

static void recreate_backbuffer(void) {
    
    if (layout_clock) { g_object_unref(layout_clock); layout_clock = NULL; }
    if (layout_title) { g_object_unref(layout_title); layout_title = NULL; }
    if (layout_status) { g_object_unref(layout_status); layout_status = NULL; }
    if (cr) {
        cairo_destroy(cr);
        cr = NULL;
    }
    if (surface) {
        cairo_surface_destroy(surface);
        surface = NULL;
    }
    if (back_pixmap != None) {
        XFreePixmap(dpy, back_pixmap);
        back_pixmap = None;
    }

    int depth = DefaultDepth(dpy, screen);
    back_pixmap = XCreatePixmap(dpy, win, (unsigned int)panel_w, (unsigned int)panel_h, (unsigned int)depth);
    if (back_pixmap == None) {
        surface = cairo_xlib_surface_create(dpy, win, DefaultVisual(dpy, screen), panel_w, panel_h);
    } else {
        surface = cairo_xlib_surface_create(dpy, back_pixmap, DefaultVisual(dpy, screen), panel_w, panel_h);
    }
    cr = cairo_create(surface);
    layout_clock = pango_cairo_create_layout(cr);
    layout_title = pango_cairo_create_layout(cr);
    layout_status = pango_cairo_create_layout(cr);

    if (!panel_font_desc) panel_font_desc = pango_font_description_from_string(NIZAM_PANEL_FONT);
    if (panel_font_desc) {
        pango_layout_set_font_description(layout_clock, panel_font_desc);
        pango_layout_set_font_description(layout_title, panel_font_desc);
        pango_layout_set_font_description(layout_status, panel_font_desc);
    }

    
}

static void update_struts(void) {
    unsigned long strut[12] = {0};
    if (settings.position == PANEL_TOP) {
        strut[2] = panel_h; 
        strut[8] = panel_x;
        strut[9] = panel_x + panel_w - 1;
    } else {
        strut[3] = panel_h; 
        strut[10] = panel_x;
        strut[11] = panel_x + panel_w - 1;
    }
    XChangeProperty(dpy, win, A_NET_WM_STRUT_PARTIAL, XA_CARDINAL, 32, PropModeReplace,
                    (unsigned char*)strut, 12);
    XChangeProperty(dpy, win, A_NET_WM_STRUT, XA_CARDINAL, 32, PropModeReplace,
                    (unsigned char*)strut, 4);
}

int point_in_rect(int x, int y, Rect r) {
    return x >= r.x && x <= r.x + r.w && y >= r.y && y <= r.y + r.h;
}

static void handle_click(int x, int y) {
    if (menu_handle_click(x, y)) return;
    
    (void)tasklist_handle_click(x, y);
}

static void init_window(void) {
    int mx = 0, my = 0, mw = DisplayWidth(dpy, screen), mh = DisplayHeight(dpy, screen);
    get_monitor_geometry(settings.monitor, &mx, &my, &mw, &mh);

    panel_w = mw;
    panel_h = clamp_int(settings.height, 16, 128);
    panel_x = mx;
    panel_y = (settings.position == PANEL_BOTTOM) ? (my + mh - panel_h) : my;

    win = XCreateSimpleWindow(dpy, root, panel_x, panel_y, panel_w, panel_h, 0,
                              BlackPixel(dpy, screen), parse_color(dpy, color_bg));
    XSetWindowBackgroundPixmap(dpy, win, None);
    XSelectInput(dpy, win, ExposureMask | ButtonPressMask | StructureNotifyMask | PropertyChangeMask | VisibilityChangeMask);
    XSelectInput(dpy, root, PropertyChangeMask | SubstructureNotifyMask);

    Atom type_dock = A_NET_WM_WINDOW_TYPE_DOCK;
    XChangeProperty(dpy, win, A_NET_WM_WINDOW_TYPE, XA_ATOM, 32, PropModeReplace,
                    (unsigned char*)&type_dock, 1);

    Atom states[2] = {A_NET_WM_STATE_ABOVE, A_NET_WM_STATE_STICKY};
    XChangeProperty(dpy, win, A_NET_WM_STATE, XA_ATOM, 32, PropModeReplace,
                    (unsigned char*)states, 2);

    XMapRaised(dpy, win);

    if (back_gc) {
        XFreeGC(dpy, back_gc);
        back_gc = None;
    }
    back_gc = XCreateGC(dpy, win, 0, NULL);

    recreate_backbuffer();

    update_struts();
}

static void cleanup(void) {
    if (layout_clock) g_object_unref(layout_clock);
    if (layout_title) g_object_unref(layout_title);
    if (layout_status) g_object_unref(layout_status);
    if (panel_font_desc) {
        pango_font_description_free(panel_font_desc);
        panel_font_desc = NULL;
    }
    icon_cache_destroy_all();
    if (cr) cairo_destroy(cr);
    if (surface) cairo_surface_destroy(surface);
    if (back_pixmap != None) XFreePixmap(dpy, back_pixmap);
    if (back_gc) XFreeGC(dpy, back_gc);
    if (dpy) XCloseDisplay(dpy);
}

int main(int argc, char **argv) {
    
    
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--debug-stats") == 0 || strcmp(argv[i], "--mem-stats") == 0) {
            pid_t pids[32];
            int n = find_nizam_panel_pids(pids, (int)(sizeof(pids) / sizeof(pids[0])));
            int sent = 0;
            for (int k = 0; k < n; k++) {
                if (send_sigusr1(pids[k])) sent++;
            }
            if (sent <= 0) {
                fprintf(stderr, "nizam-panel: no running instance found (cannot toggle stats)\n");
                return 1;
            }
            fprintf(stderr, "nizam-panel: toggled stats on %d instance(s)\n", sent);
            return 0;
        }
        if (strcmp(argv[i], "--pid") == 0 && (i + 1) < argc) {
            pid_t pid = (pid_t)atoi(argv[i + 1]);
            if (!send_sigusr1(pid)) {
                fprintf(stderr, "nizam-panel: failed to signal pid %d\n", (int)pid);
                return 1;
            }
            fprintf(stderr, "nizam-panel: toggled stats on pid %d\n", (int)pid);
            return 0;
        }
    }

    dpy = XOpenDisplay(NULL);
    if (!dpy) {
        fprintf(stderr, "nizam-panel: cannot open display\n");
        return 1;
    }

    XSetErrorHandler(nizam_x11_error_handler);
    XSetIOErrorHandler(nizam_x11_io_error_handler);

    screen = DefaultScreen(dpy);
    root = RootWindow(dpy, screen);

    
    icon_cache_init();
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = on_sigusr1;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_RESTART;
    sigaction(SIGUSR1, &sa, NULL);

    setup_atoms();
    load_settings(&settings);
    if (!settings.panel_enabled) {
        fprintf(stderr, "nizam-panel: disabled by config\n");
        cleanup();
        return 0;
    }

    init_window();
    update_clients(1);
    update_layout();
    redraw();

    int xfd = ConnectionNumber(dpy);
    char last_clock[128];
    last_clock[0] = '\0';
    int64_t next_clock_ms = next_clock_deadline_ms();
    int64_t last_rt_ms = now_realtime_ms();
    int64_t next_icon_cache_log_ms = now_ms() + 30000;
    while (running) {
        int need_redraw = 0;
        int need_layout = 0;
        int need_clock_only = 0;

        if (mem_debug_toggle_requested) {
            mem_debug_toggle_requested = 0;
            mem_debug_enabled = !mem_debug_enabled;
            mem_debug_print_stats(mem_debug_enabled ? "enabled" : "disabled");
        }

        if (icon_cache_debug_enabled()) {
            int64_t mnow = now_ms();
            if (mnow >= next_icon_cache_log_ms) {
                fprintf(stderr,
                        "nizam-panel: icon-cache size=%d/%d hits=%llu misses=%llu evictions=%llu icon_px=%d scale=%d\n",
                        icon_cache.used,
                        NIZAM_PANEL_ICON_CACHE_CAP,
                        (unsigned long long)icon_cache.hits,
                        (unsigned long long)icon_cache.misses,
                        (unsigned long long)icon_cache.evictions,
                        NIZAM_PANEL_ICON_PX,
                        NIZAM_PANEL_ICON_SCALE);
                next_icon_cache_log_ms = mnow + 30000;
            }
        }

        
        
        int64_t now_ms_rt = now_realtime_ms();
        if (now_ms_rt + 1500 < last_rt_ms) {
            
            
            next_clock_ms = now_ms_rt;
        }
        last_rt_ms = now_ms_rt;
        if (settings.clock_enabled && now_ms_rt >= next_clock_ms) {
            strncpy(last_clock, clock_text, sizeof(last_clock) - 1);
            last_clock[sizeof(last_clock) - 1] = '\0';
            update_clock_text();

            if (strcmp(last_clock, clock_text) != 0) {
                
                PangoLayout *ly_clock = layout_for_role(PANEL_TEXT_CLOCK);
                pango_layout_set_width(ly_clock, -1);
                pango_layout_set_text(ly_clock, last_clock, -1);
                int old_tw = 0, old_th = 0;
                pango_layout_get_pixel_size(ly_clock, &old_tw, &old_th);
                pango_layout_set_text(ly_clock, clock_text, -1);
                int new_tw = 0, new_th = 0;
                pango_layout_get_pixel_size(ly_clock, &new_tw, &new_th);

                int old_clock_w = old_tw + 16;
                int new_clock_w = new_tw + 16;
                if (old_clock_w != new_clock_w) {
                    need_layout = 1;
                    need_redraw = 1;
                } else {
                    need_clock_only = 1;
                }
            }
            next_clock_ms = next_clock_deadline_ms();
        }


        fd_set fds;
        FD_ZERO(&fds);
        FD_SET(xfd, &fds);
        struct timeval tv;
        
        int64_t timeout_ms = 250;
        if (settings.clock_enabled) {
            int64_t now2 = now_realtime_ms();
            int64_t diff = next_clock_ms - now2;
            if (diff < 0) diff = 0;
            timeout_ms = diff;
        }
        if (timeout_ms > 60000) timeout_ms = 60000;
        tv.tv_sec = (int)(timeout_ms / 1000);
        tv.tv_usec = (int)((timeout_ms % 1000) * 1000);
        int r = select(xfd + 1, &fds, NULL, NULL, &tv);
        if (r > 0 && FD_ISSET(xfd, &fds)) {
            while (XPending(dpy)) {
                XEvent ev;
                XNextEvent(dpy, &ev);

                
                if (menu_handle_xevent(&ev)) {
                    continue;
                }

                if (ev.type == Expose) {
                    if (ev.xexpose.window == win) need_redraw = 1;
                } else if (ev.type == VisibilityNotify) {
                    if (ev.xvisibility.window == win) need_redraw = 1;
                } else if (ev.type == ClientMessage) {
                    if (ev.xclient.message_type == A_NIZAM_PANEL_REDRAW) {
                        need_redraw = 1;
                    }
                } else if (ev.type == ConfigureNotify) {
                    if (ev.xconfigure.window == win) {
                        panel_w = ev.xconfigure.width;
                        panel_h = ev.xconfigure.height;

                        
                        recreate_backbuffer();
                        need_layout = 1;
                        update_struts();
                    }
                } else if (ev.type == ButtonPress) {
                    handle_click(ev.xbutton.x, ev.xbutton.y);
                } else if (ev.type == PropertyNotify) {
                    if (ev.xproperty.window == root) {
                        if (ev.xproperty.atom == A_NET_CLIENT_LIST) {
                            update_clients(0);
                            need_layout = 1;
                            need_redraw = 1;
                        } else if (ev.xproperty.atom == A_NET_ACTIVE_WINDOW) {
                            tasklist_update_active();
                            need_redraw = 1;
                        }
                    } else {
                        
                    }
                } else if (ev.type == MapNotify || ev.type == UnmapNotify || ev.type == DestroyNotify) {
                    update_clients(0);
                    need_layout = 1;
                    need_redraw = 1;
                }
            }
        }

        if (need_layout) update_layout();
        
        menu_poll_live_updates();
        if (need_redraw) redraw();
        else if (need_clock_only) redraw_clock_only();
    }

    cleanup();
    return 0;
}
