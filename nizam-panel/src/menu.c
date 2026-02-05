#include "panel_shared.h"

#include <X11/keysym.h>
#include <fcntl.h>
#include <sqlite3.h>
#include <sys/stat.h>
#include <unistd.h>

typedef struct {
    char name[128];
    char exec[512];
    char icon[256];
    char category[64];
    cairo_surface_t *icon_surf;
} AppEntry;

typedef struct {
    Rect rect;              
    char label[128];
    AppEntry *app;
    cairo_surface_t *icon_surf; 
} MenuItem;

typedef struct {
    char name[64];
    int start;
    int count;
} CategoryGroup;

static Window cat_win = None;
static Window sub_win = None;
static cairo_surface_t *cat_surface = NULL;
static cairo_surface_t *sub_surface = NULL;
static cairo_t *cat_cr = NULL;
static cairo_t *sub_cr = NULL;
static PangoLayout *cat_layout = NULL;
static PangoLayout *sub_layout = NULL;
static int apps_visible = 0;
static int64_t live_reload_last_ms = 0;
static int64_t live_last_db_stamp = -1;

static int get_nizam_db_path(char *out, size_t out_sz);
static int sqlite_column_exists(sqlite3 *db, const char *table, const char *column);

static int64_t live_now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + (int64_t)ts.tv_nsec / 1000000;
}

static int64_t fetch_desktop_entries_stamp(void) {
    char db_path[1024];
    if (!get_nizam_db_path(db_path, sizeof(db_path))) return -1;

    sqlite3 *db = NULL;
    if (sqlite3_open_v2(db_path, &db, SQLITE_OPEN_READWRITE, NULL) != SQLITE_OK) {
        if (db) sqlite3_close(db);
        return -1;
    }

    sqlite3_busy_timeout(db, 2000);
    (void)sqlite3_exec(db, "PRAGMA query_only=ON;", NULL, NULL, NULL);

    int has_deleted = sqlite_column_exists(db, "desktop_entries", "deleted");
    const char *where_deleted = has_deleted ? " WHERE coalesce(deleted,0)=0" : "";

    char sql[256];
    snprintf(sql, sizeof(sql),
             "SELECT "
             "coalesce(max(updated_at),0), "
             "coalesce(sum(enabled),0) "
             "FROM desktop_entries%s",
             where_deleted);

    sqlite3_stmt *st = NULL;
    int64_t stamp = -1;
    if (sqlite3_prepare_v2(db, sql, -1, &st, NULL) == SQLITE_OK && st) {
        if (sqlite3_step(st) == SQLITE_ROW) {
            int64_t max_ts = sqlite3_column_int64(st, 0);
            int64_t enabled_sum = sqlite3_column_int64(st, 1);
            stamp = (max_ts << 1) ^ enabled_sum;
        }
        sqlite3_finalize(st);
    }

    sqlite3_close(db);
    return stamp;
}

static PangoFontDescription *menu_font_desc = NULL;

static int cat_w = 220;
static int cat_h = 240;
static int cat_scroll = 0;
static int cat_content_h = 0;
static int cat_hover = -1;

static int sub_w = 360;
static int sub_h = 300;
static int sub_scroll = 0;
static int sub_content_h = 0;
static int sub_hover = -1;

static int active_category = 0;


static const int TOP_TOOLS_COUNT = 4;
static const int TOP_TOOLS_GAP_PX = 8;
static AppEntry top_tools[4];

static AppEntry *apps = NULL;
static int apps_count = 0;
static CategoryGroup *cats = NULL;
static int cat_count = 0;
static MenuItem *cat_items = NULL;
static int cat_item_count = 0;
static MenuItem *sub_items = NULL;
static int sub_item_count = 0;

static const char *MENU_DIM = "#c0c5c9";
static const char *MENU_BORDER = "#1c1f21";
static const char *MENU_BG = "#2e3436";

#ifndef NIZAM_PANEL_VERSION
#define NIZAM_PANEL_VERSION "0.1.0"
#endif

static const int CAT_FOOTER_PX = 48;
static const int CAT_FOOTER_PAD_TOP_PX = 10;

static const int SUBMENU_GAP_PX = 1;
static const int PANEL_MENU_GAP_PX = 2;

static int ends_with_lit(const char *s, const char *suffix);
static int dir_exists(const char *path);
static int find_common_icons_root(char *out, size_t out_sz);

static int compute_submenu_width(void) {
    
    if (sub_win == None || !sub_cr || !sub_items || sub_item_count <= 0) {
        return sub_w;
    }

    int has_icon = 0;
    for (int i = 0; i < sub_item_count; i++) {
        if (sub_items[i].app && sub_items[i].app->icon_surf) {
            has_icon = 1;
            break;
        }
    }

    int text_x = has_icon ? 28 : 8;
    const int right_pad = 10; 
    const int min_w = 140;
    int max_w = DisplayWidth(dpy, screen) - 8;
    if (max_w < min_w) max_w = min_w;

    int max_text = 0;
    PangoLayout *ly = pango_cairo_create_layout(sub_cr);
    if (!menu_font_desc) menu_font_desc = pango_font_description_from_string(NIZAM_PANEL_FONT);
    if (menu_font_desc) pango_layout_set_font_description(ly, menu_font_desc);

    for (int i = 0; i < sub_item_count; i++) {
        pango_layout_set_width(ly, -1);
        pango_layout_set_ellipsize(ly, PANGO_ELLIPSIZE_NONE);
        pango_layout_set_text(ly, sub_items[i].label, -1);
        int tw = 0, th = 0;
        pango_layout_get_pixel_size(ly, &tw, &th);
        if (tw > max_text) max_text = tw;
    }

    g_object_unref(ly);

    int w = text_x + max_text + right_pad;
    if (w < min_w) w = min_w;
    if (w > max_w) w = max_w;
    return w;
}
static int sqlite_column_exists(sqlite3 *db, const char *table, const char *column) {
    sqlite3_stmt *stmt = NULL;
    char sql[256];
    snprintf(sql, sizeof(sql), "PRAGMA table_info(%s)", table);
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return 0;
    }

    int found = 0;
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        const unsigned char *name = sqlite3_column_text(stmt, 1);
        if (name && strcmp((const char *)name, column) == 0) {
            found = 1;
            break;
        }
    }
    sqlite3_finalize(stmt);
    return found;
}

static void draw_menu_border(cairo_t *c, int w, int h, const char *hex) {
    if (!c || w <= 0 || h <= 0) return;
    unsigned long pixel = parse_color(dpy, hex);
    XColor xc;
    xc.pixel = pixel;
    XQueryColor(dpy, DefaultColormap(dpy, screen), &xc);
    cairo_set_source_rgb(c, xc.red / 65535.0, xc.green / 65535.0, xc.blue / 65535.0);
    cairo_set_antialias(c, CAIRO_ANTIALIAS_NONE);
    cairo_set_line_width(c, 1.0);
    cairo_rectangle(c, 0.5, 0.5, (double)w - 1.0, (double)h - 1.0);
    cairo_stroke(c);
}

static cairo_surface_t *load_menu_icon_prefer_symbolic(const char *name, int size) {
    if (!name || name[0] == '\0') return NULL;
    (void)size;
    const int icon_px = NIZAM_PANEL_ICON_PX;
    
    if (strchr(name, '/')) return load_icon_from_name(name, icon_px);

    
    if (!ends_with_lit(name, "-symbolic")) {
        char sym[512];
        snprintf(sym, sizeof(sym), "%s-symbolic", name);
        cairo_surface_t *s = load_icon_from_name(sym, icon_px);
        if (s) return s;
    }

    return load_icon_from_name(name, icon_px);
}

static void draw_menu_triangle(cairo_t *c, int x, int y, int w, int h, int dir_left, const char *hex) {
    if (!c || w <= 0 || h <= 0) return;
    unsigned long pixel = parse_color(dpy, hex);
    XColor xc;
    xc.pixel = pixel;
    XQueryColor(dpy, DefaultColormap(dpy, screen), &xc);
    cairo_set_source_rgb(c, xc.red / 65535.0, xc.green / 65535.0, xc.blue / 65535.0);

    cairo_new_path(c);
    if (dir_left) {
        cairo_move_to(c, x + w, y);
        cairo_line_to(c, x, y + h / 2);
        cairo_line_to(c, x + w, y + h);
    } else {
        cairo_move_to(c, x, y);
        cairo_line_to(c, x + w, y + h / 2);
        cairo_line_to(c, x, y + h);
    }
    cairo_close_path(c);
    cairo_fill(c);
}

static void sub_close_only(void) {
    sub_hover = -1;
    sub_scroll = 0;
    sub_content_h = 0;

    if (sub_layout) {
        g_object_unref(sub_layout);
        sub_layout = NULL;
    }
    if (sub_cr) {
        cairo_destroy(sub_cr);
        sub_cr = NULL;
    }
    if (sub_surface) {
        cairo_surface_destroy(sub_surface);
        sub_surface = NULL;
    }
    if (sub_win != None) {
        XDestroyWindow(dpy, sub_win);
        sub_win = None;
    }
}

static int dir_exists(const char *path) {
    struct stat st;
    if (!path || path[0] == '\0') return 0;
    if (stat(path, &st) != 0) return 0;
    return S_ISDIR(st.st_mode);
}

static int find_common_icons_root(char *out, size_t out_sz) {
    if (!out || out_sz == 0) return 0;
    out[0] = '\0';
    const char *common_dir = getenv("NIZAM_COMMON_DIR");
    if (common_dir && *common_dir) {
        snprintf(out, out_sz, "%s/icons", common_dir);
        if (dir_exists(out)) return 1;
        out[0] = '\0';
    }
    char cwd[1024];
    if (getcwd(cwd, sizeof(cwd))) {
        snprintf(out, out_sz, "%s/nizam-common/icons", cwd);
        if (dir_exists(out)) return 1;
        out[0] = '\0';
    }
    return 0;
}

static void str_trim(char *s) {
    if (!s) return;
    size_t n = strlen(s);
    while (n > 0 && (s[n - 1] == '\n' || s[n - 1] == '\r' || s[n - 1] == ' ' || s[n - 1] == '\t')) {
        s[n - 1] = '\0';
        n--;
    }
    size_t i = 0;
    while (s[i] == ' ' || s[i] == '\t') i++;
    if (i > 0) memmove(s, s + i, strlen(s + i) + 1);
}

static void sanitize_exec(const char *in, char *out, size_t out_len) {
    
    if (!out || out_len == 0) return;
    out[0] = '\0';
    if (!in) return;

    size_t j = 0;
    for (size_t i = 0; in[i] != '\0' && j + 1 < out_len; i++) {
        if (in[i] == '%') {
            if (in[i + 1] != '\0') i++; 
            continue;
        }
        out[j++] = in[i];
    }
    out[j] = '\0';
    str_trim(out);
}

static const char *map_category_token(const char *tok) {
    if (!tok || tok[0] == '\0') return NULL;

    
    if (!strcasecmp(tok, "Development") || !strcasecmp(tok, "IDE") || !strcasecmp(tok, "Programming") ||
        !strcasecmp(tok, "Debugger") || !strcasecmp(tok, "Profiling") || !strcasecmp(tok, "RevisionControl") ||
        !strcasecmp(tok, "Translation")) {
        return "Development";
    }

    
    if (!strcasecmp(tok, "Game") || !strcasecmp(tok, "Games")) {
        return "Games";
    }

    
    if (!strcasecmp(tok, "Graphics") || !strcasecmp(tok, "2DGraphics") || !strcasecmp(tok, "3DGraphics") ||
        !strcasecmp(tok, "Photography") || !strcasecmp(tok, "RasterGraphics") || !strcasecmp(tok, "VectorGraphics")) {
        return "Graphics";
    }

    
    if (!strcasecmp(tok, "AudioVideo") || !strcasecmp(tok, "Audio") || !strcasecmp(tok, "Video") ||
        !strcasecmp(tok, "Player") || !strcasecmp(tok, "Recorder") || !strcasecmp(tok, "Music") ||
        !strcasecmp(tok, "TV")) {
        return "Multimedia";
    }

    
    if (!strcasecmp(tok, "Education") || !strcasecmp(tok, "Science") || !strcasecmp(tok, "Math") ||
        !strcasecmp(tok, "Astronomy") || !strcasecmp(tok, "Biology") || !strcasecmp(tok, "Chemistry") ||
        !strcasecmp(tok, "Physics") || !strcasecmp(tok, "Geography") || !strcasecmp(tok, "History") ||
        !strcasecmp(tok, "Office") || !strcasecmp(tok, "WordProcessor") || !strcasecmp(tok, "Spreadsheet") ||
        !strcasecmp(tok, "Presentation")) {
        return "Office";
    }

    
    if (!strcasecmp(tok, "Utility") || !strcasecmp(tok, "Utilities") || !strcasecmp(tok, "Accessories")) {
        return "Utilities";
    }

    
    if (!strcasecmp(tok, "System") || !strcasecmp(tok, "Settings") || !strcasecmp(tok, "Preferences") ||
        !strcasecmp(tok, "Monitor") || !strcasecmp(tok, "Security") || !strcasecmp(tok, "PackageManager")) {
        return "System";
    }

    
    if (!strcasecmp(tok, "Network") || !strcasecmp(tok, "WebBrowser") || !strcasecmp(tok, "Email") ||
        !strcasecmp(tok, "Chat") || !strcasecmp(tok, "IRCClient") || !strcasecmp(tok, "FileTransfer") ||
        !strcasecmp(tok, "P2P") || !strcasecmp(tok, "InstantMessaging") || !strcasecmp(tok, "RemoteAccess")) {
        return "Network";
    }

    return NULL;
}

static void pick_category_mapped(char *out, size_t out_len, const char *cats) {
    if (!out || out_len == 0) return;
    out[0] = '\0';

    if (!cats || cats[0] == '\0') {
        strncpy(out, "System", out_len - 1);
        return;
    }

    
    const char *p = cats;
    while (*p) {
        while (*p == ' ' || *p == '\t' || *p == ';') p++;
        if (!*p) break;

        const char *start = p;
        while (*p && *p != ';') p++;
        const char *end = p;
        while (end > start && (end[-1] == ' ' || end[-1] == '\t')) end--;
        size_t n = (size_t)(end - start);
        if (n > 0) {
            char token[64];
            if (n >= sizeof(token)) n = sizeof(token) - 1;
            memcpy(token, start, n);
            token[n] = '\0';
            const char *mapped = map_category_token(token);
            if (mapped) {
                strncpy(out, mapped, out_len - 1);
                return;
            }
        }
        if (*p == ';') p++;
    }

    strncpy(out, "System", out_len - 1);
}

static int ends_with_lit(const char *s, const char *suffix) {
    if (!s || !suffix) return 0;
    size_t ls = strlen(s);
    size_t lf = strlen(suffix);
    if (ls < lf) return 0;
    return strcmp(s + (ls - lf), suffix) == 0;
}

static cairo_surface_t *load_category_icon(const char *name, int size) {
    const char *base = (name && name[0]) ? name : "nizam-system";
    if (debug_enabled()) {
        debug_log("nizam-panel: category icon: name='%s'\n", base);
    }
    char root[1024];
    if (find_common_icons_root(root, sizeof(root))) {
        char path[1200];
        snprintf(path, sizeof(path), "%s/hicolor/scalable/categories/%s.svg", root, base);
        cairo_surface_t *s = load_icon_from_name(path, size);
        if (s) return s;
    }
    return load_icon_from_name(base, size);
}

static const char *category_display_name(const char *cat) {
    if (!cat || cat[0] == '\0') return "System";
    if (!strcasecmp(cat, "Development")) return "Development";
    if (!strcasecmp(cat, "Games")) return "Games";
    if (!strcasecmp(cat, "Graphics")) return "Graphics";
    if (!strcasecmp(cat, "Multimedia")) return "Multimedia";
    if (!strcasecmp(cat, "Office")) return "Learning";
    if (!strcasecmp(cat, "System")) return "System";
    if (!strcasecmp(cat, "Network")) return "Network";
    if (!strcasecmp(cat, "Utilities")) return "Accessories";
    return "System";
}

static const char *category_icon_name(const char *cat) {
    
    if (!cat || cat[0] == '\0') return "nizam-system";
    if (!strcasecmp(cat, "Development")) return "nizam-development";
    if (!strcasecmp(cat, "Games")) return "nizam-games";
    if (!strcasecmp(cat, "Graphics")) return "nizam-graphics";
    if (!strcasecmp(cat, "Multimedia")) return "nizam-multimedia";
    if (!strcasecmp(cat, "Office")) return "nizam-learning";
    if (!strcasecmp(cat, "System")) return "nizam-system";
    if (!strcasecmp(cat, "Network")) return "nizam-network";
    if (!strcasecmp(cat, "Utilities")) return "nizam-accessories";
    return "nizam-system";
}

static void apps_free(void) {
    
    for (int i = 0; i < TOP_TOOLS_COUNT; i++) {
        if (top_tools[i].icon_surf) {
            cairo_surface_destroy(top_tools[i].icon_surf);
            top_tools[i].icon_surf = NULL;
        }
    }
    if (cat_items) {
        for (int i = 0; i < cat_item_count; i++) {
            if (cat_items[i].icon_surf) {
                cairo_surface_destroy(cat_items[i].icon_surf);
                cat_items[i].icon_surf = NULL;
            }
        }
        free(cat_items);
        cat_items = NULL;
        cat_item_count = 0;
    }
    if (sub_items) {
        free(sub_items);
        sub_items = NULL;
        sub_item_count = 0;
    }
    if (cats) {
        free(cats);
        cats = NULL;
        cat_count = 0;
    }
    if (apps) {
        for (int i = 0; i < apps_count; i++) {
            if (apps[i].icon_surf) cairo_surface_destroy(apps[i].icon_surf);
        }
        free(apps);
        apps = NULL;
        apps_count = 0;
    }
    cat_scroll = 0;
    cat_content_h = 0;
    cat_hover = -1;
    sub_scroll = 0;
    sub_content_h = 0;
    sub_hover = -1;
    active_category = 0;
}

static void init_top_tools(void) {
    memset(top_tools, 0, sizeof(top_tools));

    
    strncpy(top_tools[0].name, "Terminal", sizeof(top_tools[0].name) - 1);
    strncpy(top_tools[0].exec, "nizam-terminal", sizeof(top_tools[0].exec) - 1);
    strncpy(top_tools[0].icon, "utilities-terminal-symbolic", sizeof(top_tools[0].icon) - 1);

    strncpy(top_tools[1].name, "Explorer", sizeof(top_tools[1].name) - 1);
    strncpy(top_tools[1].exec, "nizam-explorer", sizeof(top_tools[1].exec) - 1);
    strncpy(top_tools[1].icon, "system-file-manager-symbolic", sizeof(top_tools[1].icon) - 1);

    strncpy(top_tools[2].name, "Text", sizeof(top_tools[2].name) - 1);
    strncpy(top_tools[2].exec, "nizam-text", sizeof(top_tools[2].exec) - 1);
    strncpy(top_tools[2].icon, "accessories-text-editor-symbolic", sizeof(top_tools[2].icon) - 1);

    strncpy(top_tools[3].name, "Settings", sizeof(top_tools[3].name) - 1);
    strncpy(top_tools[3].exec, "nizam-settings", sizeof(top_tools[3].exec) - 1);
    strncpy(top_tools[3].icon, "preferences-system-symbolic", sizeof(top_tools[3].icon) - 1);

    for (int i = 0; i < TOP_TOOLS_COUNT; i++) {
        top_tools[i].icon_surf = load_menu_icon_prefer_symbolic(top_tools[i].icon, NIZAM_PANEL_ICON_PX);
        if (!top_tools[i].icon_surf) {
            top_tools[i].icon_surf = load_menu_icon_prefer_symbolic("nizam", NIZAM_PANEL_ICON_PX);
        }
    }
}

static int cat_item_is_tool(int idx) {
    return idx >= 0 && idx < TOP_TOOLS_COUNT;
}

static int cat_item_to_category_idx(int idx) {
    int ci = idx - TOP_TOOLS_COUNT;
    if (ci < 0 || ci >= cat_count) return -1;
    return ci;
}

static int is_allowed_category_bucket(const char *cat) {
    if (!cat || cat[0] == '\0') return 0;
    if (!strcasecmp(cat, "Development")) return 1;
    if (!strcasecmp(cat, "Games")) return 1;
    if (!strcasecmp(cat, "Graphics")) return 1;
    if (!strcasecmp(cat, "Multimedia")) return 1;
    if (!strcasecmp(cat, "Office")) return 1;
    if (!strcasecmp(cat, "System")) return 1;
    if (!strcasecmp(cat, "Network")) return 1;
    if (!strcasecmp(cat, "Utilities")) return 1;
    return 0;
}

static int get_nizam_db_path(char *out, size_t out_sz) {
    if (!out || out_sz == 0) return 0;
    out[0] = '\0';

    const char *env = getenv("NIZAM_DB");
    if (env && *env) {
        snprintf(out, out_sz, "%s", env);
        return 1;
    }

    const char *xdg = getenv("XDG_CONFIG_HOME");
    if (xdg && *xdg) {
        snprintf(out, out_sz, "%s/nizam/nizam.db", xdg);
        return 1;
    }

    const char *home = getenv("HOME");
    if (!home || !*home) return 0;
    snprintf(out, out_sz, "%s/.config/nizam/nizam.db", home);
    return 1;
}

static void scan_apps_from_sqlite(void) {
    char db_path[1024];
    if (!get_nizam_db_path(db_path, sizeof(db_path))) return;

    sqlite3 *db = NULL;
    
    
    if (sqlite3_open_v2(db_path, &db, SQLITE_OPEN_READWRITE, NULL) != SQLITE_OK) {
        if (db) sqlite3_close(db);
        return;
    }

    sqlite3_busy_timeout(db, 2000);
    (void)sqlite3_exec(db, "PRAGMA query_only=ON;", NULL, NULL, NULL);

    int has_user_name = sqlite_column_exists(db, "desktop_entries", "user_name");
    int has_user_exec = sqlite_column_exists(db, "desktop_entries", "user_exec");
    int has_deleted = sqlite_column_exists(db, "desktop_entries", "deleted");

    char sql_buf[512];
    const char *where_deleted = has_deleted ? " AND coalesce(deleted,0)=0" : "";
    if (has_user_name || has_user_exec) {
        snprintf(sql_buf, sizeof(sql_buf),
                 "SELECT filename, "
                 "coalesce(user_name, name) as name, "
                 "coalesce(user_exec, exec) as exec, "
                 "icon, category, categories "
                 "FROM desktop_entries "
                 "WHERE enabled=1%s "
                 "ORDER BY category, lower(coalesce(user_name, name))",
                 where_deleted);
    } else {
        snprintf(sql_buf, sizeof(sql_buf),
                 "SELECT filename, name, exec, icon, category, categories "
                 "FROM desktop_entries "
                 "WHERE enabled=1%s "
                 "ORDER BY category, lower(name)",
                 where_deleted);
    }

    sqlite3_stmt *st = NULL;
    if (sqlite3_prepare_v2(db, sql_buf, -1, &st, NULL) != SQLITE_OK) {
        sqlite3_close(db);
        return;
    }

    while (sqlite3_step(st) == SQLITE_ROW) {
        const char *name = (const char *)sqlite3_column_text(st, 1);
        const char *exec = (const char *)sqlite3_column_text(st, 2);
        const char *icon = (const char *)sqlite3_column_text(st, 3);
        const char *cat = (const char *)sqlite3_column_text(st, 4);
        const char *cats = (const char *)sqlite3_column_text(st, 5);

        if (!name || !*name || !exec || !*exec) continue;

        AppEntry e;
        memset(&e, 0, sizeof(e));
        strncpy(e.name, name, sizeof(e.name) - 1);

        char exec_clean[512];
        sanitize_exec(exec, exec_clean, sizeof(exec_clean));
        strncpy(e.exec, exec_clean, sizeof(e.exec) - 1);

        if (icon && *icon) strncpy(e.icon, icon, sizeof(e.icon) - 1);

        if (cat && *cat && is_allowed_category_bucket(cat)) {
            strncpy(e.category, cat, sizeof(e.category) - 1);
        } else {
            
            pick_category_mapped(e.category, sizeof(e.category), cats ? cats : "");
        }

        e.icon_surf = NULL;

        AppEntry *n = realloc(apps, sizeof(AppEntry) * (apps_count + 1));
        if (!n) break;
        apps = n;
        apps[apps_count++] = e;
    }

    sqlite3_finalize(st);
    sqlite3_close(db);
}

static int app_cmp2(const void *a, const void *b) {
    const AppEntry *aa = (const AppEntry *)a;
    const AppEntry *bb = (const AppEntry *)b;
    int ic = strcasecmp(aa->category, bb->category);
    if (ic != 0) return ic;
    return strcasecmp(aa->name, bb->name);
}

static void build_categories(void) {
    if (cats) {
        free(cats);
        cats = NULL;
        cat_count = 0;
    }
    if (!apps || apps_count <= 0) return;

    qsort(apps, apps_count, sizeof(AppEntry), app_cmp2);

    
    for (int i = 0; i < apps_count; i++) {
        if (apps[i].icon[0] == '\0') continue;
        if (apps[i].icon_surf) continue;
        
        apps[i].icon_surf = load_menu_icon_prefer_symbolic(apps[i].icon, NIZAM_PANEL_ICON_PX);
        if (!apps[i].icon_surf) {
            apps[i].icon_surf = load_menu_icon_prefer_symbolic("nizam-app-generic", NIZAM_PANEL_ICON_PX);
        }
    }

    const char *last = NULL;
    for (int i = 0; i < apps_count; i++) {
        if (!last || strcmp(last, apps[i].category) != 0) {
            CategoryGroup *n = realloc(cats, sizeof(CategoryGroup) * (cat_count + 1));
            if (!n) break;
            cats = n;
            CategoryGroup *cg = &cats[cat_count++];
            memset(cg, 0, sizeof(*cg));
            strncpy(cg->name, apps[i].category, sizeof(cg->name) - 1);
            cg->start = i;
            cg->count = 1;
            last = apps[i].category;
        } else {
            cats[cat_count - 1].count++;
        }
    }
}

static void build_category_items(void) {
    if (cat_items) {
        for (int i = 0; i < cat_item_count; i++) {
            if (cat_items[i].icon_surf) {
                cairo_surface_destroy(cat_items[i].icon_surf);
                cat_items[i].icon_surf = NULL;
            }
        }
        free(cat_items);
        cat_items = NULL;
        cat_item_count = 0;
    }

    const int pad = 0;
    const int row_h = 30;
    int y = pad;

    
    for (int i = 0; i < TOP_TOOLS_COUNT; i++) {
        if (top_tools[i].icon_surf) {
            cairo_surface_destroy(top_tools[i].icon_surf);
            top_tools[i].icon_surf = NULL;
        }
    }
    init_top_tools();

    int extra_rows = (cat_count <= 0) ? 1 : cat_count;
    cat_items = calloc((size_t)(TOP_TOOLS_COUNT + extra_rows), sizeof(MenuItem));
    if (!cat_items) return;
    cat_item_count = TOP_TOOLS_COUNT + extra_rows;

    
    for (int i = 0; i < TOP_TOOLS_COUNT; i++) {
        strncpy(cat_items[i].label, top_tools[i].name, sizeof(cat_items[i].label) - 1);
        cat_items[i].app = &top_tools[i];
        cat_items[i].icon_surf = NULL;
        cat_items[i].rect = (Rect){pad, y, cat_w - pad * 2, row_h};
        y += row_h;
    }

    
    y += TOP_TOOLS_GAP_PX;

    if (cat_count <= 0) {
        int idx = TOP_TOOLS_COUNT;
        strncpy(cat_items[idx].label, "No applications found", sizeof(cat_items[idx].label) - 1);
        cat_items[idx].rect = (Rect){pad, y, cat_w - pad * 2, row_h};
        cat_items[idx].app = NULL;
        cat_items[idx].icon_surf = NULL;
        cat_content_h = y + row_h + pad;
        return;
    }

    for (int i = 0; i < cat_count; i++) {
        int idx = TOP_TOOLS_COUNT + i;
        const char *label = category_display_name(cats[i].name);
        strncpy(cat_items[idx].label, label, sizeof(cat_items[idx].label) - 1);
        cat_items[idx].app = NULL;
        const char *primary = category_icon_name(cats[i].name);
        cat_items[idx].icon_surf = load_category_icon(primary, NIZAM_PANEL_ICON_PX);
        if (!cat_items[idx].icon_surf) {
            cat_items[idx].icon_surf = load_category_icon("nizam-system", NIZAM_PANEL_ICON_PX);
        }
        cat_items[idx].rect = (Rect){pad, y, cat_w - pad * 2, row_h};
        y += row_h;
    }
    cat_content_h = y + pad;
}

static void build_sub_items_for(int cat_idx) {
    if (sub_items) {
        free(sub_items);
        sub_items = NULL;
        sub_item_count = 0;
    }

    const int pad = 0;
    const int row_h = 30;
    int y = pad;

    if (cat_idx < 0 || cat_idx >= cat_count) {
        sub_items = calloc(1, sizeof(MenuItem));
        if (sub_items) {
            sub_item_count = 1;
            strncpy(sub_items[0].label, "(empty)", sizeof(sub_items[0].label) - 1);
            sub_items[0].rect = (Rect){pad, y, sub_w - pad * 2, row_h};
            sub_content_h = y + row_h + pad;
        }
        return;
    }

    int start = cats[cat_idx].start;
    int count = cats[cat_idx].count;
    if (count <= 0) {
        sub_items = calloc(1, sizeof(MenuItem));
        if (sub_items) {
            sub_item_count = 1;
            strncpy(sub_items[0].label, "(empty)", sizeof(sub_items[0].label) - 1);
            sub_items[0].rect = (Rect){pad, y, sub_w - pad * 2, row_h};
            sub_content_h = y + row_h + pad;
        }
        return;
    }

    sub_items = calloc((size_t)count, sizeof(MenuItem));
    if (!sub_items) return;
    sub_item_count = count;
    for (int i = 0; i < count; i++) {
        AppEntry *a = &apps[start + i];
        sub_items[i].app = a;
        strncpy(sub_items[i].label, a->name, sizeof(sub_items[i].label) - 1);
        sub_items[i].rect = (Rect){pad, y, sub_w - pad * 2, row_h};
        y += row_h;
    }
    sub_content_h = y + pad;
}

static void apps_spawn(const char *cmd) {
    if (!cmd || cmd[0] == '\0') return;
    pid_t pid = fork();
    if (pid == 0) {
        
        setsid();
        int fd = open("/dev/null", O_RDWR);
        if (fd >= 0) {
            dup2(fd, STDIN_FILENO);
            dup2(fd, STDOUT_FILENO);
            dup2(fd, STDERR_FILENO);
            if (fd > STDERR_FILENO) close(fd);
        }
        execl("/bin/sh", "sh", "-lc", cmd, (char *)NULL);
        _exit(127);
    }
}

static void draw_menu_list(cairo_t *c, PangoLayout **layout_ptr,
                           int ww, int hh,
                           MenuItem *list, int count,
                           int scroll, int hover,
                           int draw_icons,
                           int draw_sub_arrow,
                           int bold_labels,
                           int reserved_bottom_px,
                           const char *footer_text) {
    if (!c) return;
    Rect full = {0, 0, ww, hh};
    draw_rect(c, full, MENU_BG, 1);
    draw_menu_border(c, ww, hh, MENU_BORDER);

    cairo_save(c);
    int view_h = hh;
    if (reserved_bottom_px > 0 && reserved_bottom_px < hh) {
        view_h = hh - reserved_bottom_px;
    }

    cairo_rectangle(c, 0, 0, ww, view_h);
    cairo_clip(c);

    const int pad = 0;

    for (int i = 0; i < count; i++) {
        int y = list[i].rect.y - scroll;
        int h = list[i].rect.h;
        if (y + h < 0 || y > view_h) continue;

        Rect r = list[i].rect;
        r.y = y;

        int is_hover = (i == hover);
        if (is_hover) draw_rect(c, r, color_active, 1);

        const char *fg = is_hover ? color_active_text : color_fg;
        if (count == 1 && list[i].app == NULL && strcmp(list[i].label, "No applications found") == 0) {
            fg = is_hover ? color_active_text : MENU_DIM;
        }

        
        int text_x = r.x + 8;
        if (draw_icons) {
            cairo_surface_t *isurf = NULL;
            if (list[i].app && list[i].app->icon_surf) isurf = list[i].app->icon_surf;
            else if (list[i].icon_surf) isurf = list[i].icon_surf;
            if (isurf) {
                int ix = r.x + 6;
                int iy = r.y + (r.h - 22) / 2;
                
                
                if (list[i].app && ends_with_lit(list[i].app->icon, "-symbolic")) {
                    draw_icon_tinted_to(c, isurf, ix, iy, 22, fg);
                } else {
                    draw_icon_to(c, isurf, ix, iy, 22);
                }
            }
            text_x = r.x + 32;
        }

        if (!*layout_ptr) {
            *layout_ptr = pango_cairo_create_layout(c);
            if (!menu_font_desc) menu_font_desc = pango_font_description_from_string(NIZAM_PANEL_FONT);
            if (menu_font_desc) pango_layout_set_font_description(*layout_ptr, menu_font_desc);
        }
        pango_layout_set_text(*layout_ptr, list[i].label, -1);
        (void)bold_labels;
        pango_layout_set_width(*layout_ptr, (ww - text_x - pad) * PANGO_SCALE);
        pango_layout_set_ellipsize(*layout_ptr, PANGO_ELLIPSIZE_END);

        unsigned long pixel = parse_color(dpy, fg);
        XColor xc;
        xc.pixel = pixel;
        XQueryColor(dpy, DefaultColormap(dpy, screen), &xc);
        cairo_set_source_rgb(c, xc.red / 65535.0, xc.green / 65535.0, xc.blue / 65535.0);

        int tw = 0, th = 0;
        pango_layout_get_pixel_size(*layout_ptr, &tw, &th);
        int dy = r.y + (r.h - th) / 2;
        if (dy < r.y) dy = r.y;
        cairo_move_to(c, text_x, dy);
        pango_cairo_show_layout(c, *layout_ptr);

        if (draw_sub_arrow) {
            
            
            if (list[i].app == NULL && list[i].label[0] != '\0') {
                int tri_w = 7;
                int tri_h = 9;
                int ax = r.x + r.w - tri_w - 10;
                int ay = r.y + (r.h - tri_h) / 2;
                const char *arrow = is_hover ? color_active_text : MENU_DIM;
                draw_menu_triangle(c, ax, ay, tri_w, tri_h, 0, arrow);
            }
        }
    }

    cairo_restore(c);

    if (footer_text && footer_text[0] != '\0' && reserved_bottom_px > 0 && reserved_bottom_px < hh) {
        int top = hh - reserved_bottom_px;
        int sep_y = top + CAT_FOOTER_PAD_TOP_PX;
        if (sep_y < top) sep_y = top;
        if (sep_y > hh - 2) sep_y = hh - 2;

        
        unsigned long pixel = parse_color(dpy, MENU_BORDER);
        XColor xc;
        xc.pixel = pixel;
        XQueryColor(dpy, DefaultColormap(dpy, screen), &xc);
        cairo_set_source_rgb(c, xc.red / 65535.0, xc.green / 65535.0, xc.blue / 65535.0);
        cairo_set_antialias(c, CAIRO_ANTIALIAS_NONE);
        cairo_set_line_width(c, 1.0);
        cairo_move_to(c, 0.0, sep_y + 0.5);
        cairo_line_to(c, (double)ww, sep_y + 0.5);
        cairo_stroke(c);

        
        PangoLayout *f = pango_cairo_create_layout(c);
        PangoFontDescription *fd = pango_font_description_from_string("Sans 9");
        if (fd) {
            pango_layout_set_font_description(f, fd);
            pango_font_description_free(fd);
        }
        pango_layout_set_width(f, (ww - 16) * PANGO_SCALE);
        pango_layout_set_ellipsize(f, PANGO_ELLIPSIZE_END);
        pango_layout_set_alignment(f, PANGO_ALIGN_CENTER);
        pango_layout_set_text(f, footer_text, -1);

        pixel = parse_color(dpy, MENU_DIM);
        xc.pixel = pixel;
        XQueryColor(dpy, DefaultColormap(dpy, screen), &xc);
        cairo_set_source_rgb(c, xc.red / 65535.0, xc.green / 65535.0, xc.blue / 65535.0);

        int tw = 0, th = 0;
        pango_layout_get_pixel_size(f, &tw, &th);
        int text_area_top = sep_y + 1;
        int text_area_h = hh - text_area_top;
        if (text_area_h < 1) text_area_h = 1;
        int y = text_area_top + (text_area_h - th) / 2;
        if (y < text_area_top + 2) y = text_area_top + 2;
        cairo_move_to(c, 8, y);
        pango_cairo_show_layout(c, f);
        g_object_unref(f);
    }
}

static void cat_redraw(void) {
    if (!apps_visible || !cat_surface || !cat_cr) return;
    cairo_xlib_surface_set_size(cat_surface, cat_w, cat_h);
    char footer[256];
    snprintf(footer, sizeof(footer), "Nizam version %s", NIZAM_PANEL_VERSION);
    draw_menu_list(cat_cr, &cat_layout, cat_w, cat_h,
                  cat_items, cat_item_count,
                  cat_scroll, cat_hover,
                  1, (cat_count > 0), 1,
                  CAT_FOOTER_PX, footer);
    cairo_surface_flush(cat_surface);
    XFlush(dpy);
}

static void sub_redraw(void) {
    if (!apps_visible || cat_count <= 0) return;
    if (!sub_surface || !sub_cr) return;
    cairo_xlib_surface_set_size(sub_surface, sub_w, sub_h);
    draw_menu_list(sub_cr, &sub_layout, sub_w, sub_h,
                  sub_items, sub_item_count,
                  sub_scroll, sub_hover,
                  1, 0, 0,
                  0, NULL);
    cairo_surface_flush(sub_surface);
    XFlush(dpy);
}

static void apps_close(void) {
    if (!apps_visible) return;
    apps_visible = 0;
    cat_hover = -1;
    sub_hover = -1;
    XUngrabPointer(dpy, CurrentTime);
    XUngrabKeyboard(dpy, CurrentTime);
    if (cat_layout) {
        g_object_unref(cat_layout);
        cat_layout = NULL;
    }
    if (sub_layout) {
        g_object_unref(sub_layout);
        sub_layout = NULL;
    }
    if (cat_cr) {
        cairo_destroy(cat_cr);
        cat_cr = NULL;
    }
    if (sub_cr) {
        cairo_destroy(sub_cr);
        sub_cr = NULL;
    }
    if (cat_surface) {
        cairo_surface_destroy(cat_surface);
        cat_surface = NULL;
    }
    if (sub_surface) {
        cairo_surface_destroy(sub_surface);
        sub_surface = NULL;
    }
    if (sub_win != None) {
        XDestroyWindow(dpy, sub_win);
        sub_win = None;
    }
    if (cat_win != None) {
        XDestroyWindow(dpy, cat_win);
        cat_win = None;
    }
    apps_free();
}

static int clamp_menu_y_gap(int y, int h, int gap_px) {
    
    if (settings.position == PANEL_BOTTOM) {
        
        int max_allowed = panel_y - gap_px - h;
        if (y > max_allowed) y = max_allowed;
    } else {
        
        int min_allowed = panel_y + panel_h + gap_px;
        if (y < min_allowed) y = min_allowed;
    }

    int maxy = DisplayHeight(dpy, screen) - h;
    if (maxy < 0) maxy = 0;
    if (y < 0) y = 0;
    if (y > maxy) y = maxy;
    return y;
}

static void position_submenu(int cat_x, int cat_y) {
    if (cat_count <= 0 || sub_win == None) return;

    int row_y = 0;
    int item_idx = TOP_TOOLS_COUNT + active_category;
    if (cat_items && item_idx >= 0 && item_idx < cat_item_count) {
        row_y = cat_items[item_idx].rect.y - cat_scroll;
    }
    int sx;
    
    if (cat_x + cat_w + sub_w <= DisplayWidth(dpy, screen)) {
        sx = cat_x + cat_w + SUBMENU_GAP_PX;
    } else {
        sx = cat_x - sub_w - SUBMENU_GAP_PX;
    }
    if (sx < 0) sx = 0;
    if (sx + sub_w > DisplayWidth(dpy, screen)) sx = DisplayWidth(dpy, screen) - sub_w;

    int sy = clamp_menu_y_gap(cat_y + row_y, sub_h, PANEL_MENU_GAP_PX);
    XMoveResizeWindow(dpy, sub_win, sx, sy, (unsigned int)sub_w, (unsigned int)sub_h);
    if (sub_surface) {
        cairo_xlib_surface_set_size(sub_surface, sub_w, sub_h);
    }
}

static void apps_open(void) {
    apps_close();

    apps_free();

    
    scan_apps_from_sqlite();
    live_reload_last_ms = live_now_ms();
    live_last_db_stamp = fetch_desktop_entries_stamp();

    if (apps_count > 0) {
        build_categories();
    }
    build_category_items();
    active_category = 0;

    
    
    const int screen_h = DisplayHeight(dpy, screen);
    const int edge_margin = 6;
    int max_h;
    if (settings.position == PANEL_BOTTOM) {
        max_h = panel_y - PANEL_MENU_GAP_PX - edge_margin;
    } else {
        max_h = screen_h - (panel_y + panel_h + PANEL_MENU_GAP_PX) - edge_margin;
    }
    if (max_h < 1) max_h = 1;

    int min_h = 120;
    if (min_h > max_h) min_h = max_h;

    int desired_cat_h = cat_content_h;
    desired_cat_h += CAT_FOOTER_PX;
    if (desired_cat_h < min_h) desired_cat_h = min_h;
    if (desired_cat_h > max_h) desired_cat_h = max_h;
    cat_h = desired_cat_h;

    

    int cat_x = panel_x + launcher_rect.x;
    int cat_y;
    if (settings.position == PANEL_BOTTOM) cat_y = panel_y - cat_h - PANEL_MENU_GAP_PX;
    else cat_y = panel_y + panel_h + PANEL_MENU_GAP_PX;
    cat_y = clamp_menu_y_gap(cat_y, cat_h, PANEL_MENU_GAP_PX);

    if (debug_enabled()) {
        int gap_px;
        if (settings.position == PANEL_BOTTOM) gap_px = panel_y - (cat_y + cat_h);
        else gap_px = cat_y - (panel_y + panel_h);
        debug_log("nizam-panel: menu gap=%dpx (want=%d) panel_y=%d panel_h=%d cat_y=%d cat_h=%d\n",
              gap_px, PANEL_MENU_GAP_PX, panel_y, panel_h, cat_y, cat_h);
    }
    if (cat_x + cat_w > DisplayWidth(dpy, screen)) cat_x = DisplayWidth(dpy, screen) - cat_w;
    if (cat_x < 0) cat_x = 0;

    XSetWindowAttributes attrs;
    memset(&attrs, 0, sizeof(attrs));
    attrs.override_redirect = True;

    cat_win = XCreateWindow(
        dpy, root,
        cat_x, cat_y,
        (unsigned int)cat_w,
        (unsigned int)cat_h,
        0,
        CopyFromParent,
        InputOutput,
        CopyFromParent,
        CWOverrideRedirect,
        &attrs);

    XSelectInput(dpy, cat_win,
                 ExposureMask | ButtonPressMask | ButtonReleaseMask |
                     PointerMotionMask | LeaveWindowMask | KeyPressMask);

    
    Atom A_TYPE = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE", False);
    Atom A_POPUP = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE_POPUP_MENU", False);
    if (A_TYPE != None && A_POPUP != None) {
        XChangeProperty(dpy, cat_win, A_TYPE, XA_ATOM, 32, PropModeReplace, (unsigned char *)&A_POPUP, 1);
    }

    XMapRaised(dpy, cat_win);
    cat_surface = cairo_xlib_surface_create(dpy, cat_win, DefaultVisual(dpy, screen), cat_w, cat_h);
    cat_cr = cairo_create(cat_surface);

    

    
    
    
    
    
    XGrabPointer(dpy, cat_win, False,
                 ButtonPressMask | ButtonReleaseMask | PointerMotionMask,
                 GrabModeSync, GrabModeAsync, None, None, CurrentTime);
    
    XAllowEvents(dpy, AsyncPointer, CurrentTime);

    apps_visible = 1;
    cat_redraw();
}

void menu_poll_live_updates(void) {
    if (!apps_visible) return;

    
    
    
    
    int64_t now = live_now_ms();
    if (live_reload_last_ms != 0 && (now - live_reload_last_ms) < 500) {
        return;
    }
    live_reload_last_ms = now;

    
    int64_t stamp = fetch_desktop_entries_stamp();
    if (stamp != -1 && stamp == live_last_db_stamp) {
        return;
    }
    live_last_db_stamp = stamp;

    
    
    if (sub_layout) {
        g_object_unref(sub_layout);
        sub_layout = NULL;
    }
    if (sub_cr) {
        cairo_destroy(sub_cr);
        sub_cr = NULL;
    }
    if (sub_surface) {
        cairo_surface_destroy(sub_surface);
        sub_surface = NULL;
    }
    if (sub_win != None) {
        XDestroyWindow(dpy, sub_win);
        sub_win = None;
    }

    apps_free();
    scan_apps_from_sqlite();
    if (apps_count > 0) {
        build_categories();
    }
    build_category_items();
    if (active_category < 0) active_category = 0;
    if (active_category >= cat_count) active_category = 0;
    cat_scroll = 0;
    sub_scroll = 0;

    cat_redraw();
}

static void allow_pointer_async(XEvent *ev) {
    if (!ev) return;
    Time t = CurrentTime;
    if (ev->type == MotionNotify) t = ev->xmotion.time;
    else if (ev->type == ButtonPress) t = ev->xbutton.time;
    else if (ev->type == ButtonRelease) t = ev->xbutton.time;
    XAllowEvents(dpy, AsyncPointer, t);
}

static int root_xy_in_window(Window win, int root_x, int root_y, int *out_x, int *out_y) {
    if (win == None) return 0;
    Window dummy;
    int wx = 0, wy = 0;
    unsigned int ww = 0, hh = 0, bw = 0, depth = 0;
    if (!XGetGeometry(dpy, win, &dummy, &wx, &wy, &ww, &hh, &bw, &depth)) return 0;
    if (root_x < wx || root_y < wy) return 0;
    if (root_x >= wx + (int)ww || root_y >= wy + (int)hh) return 0;
    if (out_x) *out_x = root_x - wx;
    if (out_y) *out_y = root_y - wy;
    return 1;
}

static int item_at(MenuItem *list, int count, int scroll, int x, int y, int view_h) {
    if (view_h > 0 && y >= view_h) return -1;
    int cy = y + scroll;
    for (int i = 0; i < count; i++) {
        Rect r = list[i].rect;
        if (x >= r.x && x <= r.x + r.w && cy >= r.y && cy <= r.y + r.h) return i;
    }
    return -1;
}

static void scroll_by(int *scroll, int content_h, int view_h, int delta) {
    int max_scroll = content_h - view_h;
    if (max_scroll < 0) max_scroll = 0;
    *scroll += delta;
    if (*scroll < 0) *scroll = 0;
    if (*scroll > max_scroll) *scroll = max_scroll;
}

void menu_draw(void) {
    if (!settings.launcher_enabled) return;

    int pad = LAUNCHER_PAD;
    const int icon_left_pad = LAUNCHER_ICON_LEFT_PAD;
    int icon_sz = NIZAM_PANEL_ICON_PX;

    int icon_x = launcher_rect.x + pad + icon_left_pad;
    int icon_y = launcher_rect.y + (launcher_rect.h - icon_sz) / 2;
    int gap = LAUNCHER_ICON_GAP;
    cairo_surface_t *app_icon = load_icon_from_name("nizam", icon_sz);
    if (app_icon) {
        draw_icon_tinted_to(cr, app_icon, icon_x, icon_y, icon_sz, color_fg);
        cairo_surface_destroy(app_icon);
    } else {
        draw_text_role(PANEL_TEXT_STATUS, "≡", launcher_rect.x, launcher_rect.y, launcher_rect.h, launcher_rect.h, color_fg, 1, 1);
    }
    draw_text_role(PANEL_TEXT_STATUS, settings.launcher_label,
              icon_x + icon_sz + gap,
              launcher_rect.y,
              launcher_label_w,
              launcher_rect.h,
              color_fg,
              0,
              0);
}

int menu_handle_click(int x, int y) {
    if (!settings.launcher_enabled) return 0;
    if (!point_in_rect(x, y, launcher_rect)) return 0;
    if (apps_visible) apps_close();
    else apps_open();
    return 1;
}

int menu_handle_xevent(XEvent *ev) {
    if (!apps_visible) return 0;

    if (cat_win == None) return 0;
    int on_cat = (ev->xany.window == cat_win);
    int on_sub = (sub_win != None && ev->xany.window == sub_win);

    
    
    
    int px = 0, py = 0;
    if (ev->type == MotionNotify || ev->type == ButtonPress || ev->type == ButtonRelease) {
        int root_x = 0, root_y = 0;
        if (ev->type == MotionNotify) {
            root_x = ev->xmotion.x_root;
            root_y = ev->xmotion.y_root;
        } else {
            root_x = ev->xbutton.x_root;
            root_y = ev->xbutton.y_root;
        }

        int lx = 0, ly = 0;
        if (root_xy_in_window(cat_win, root_x, root_y, &lx, &ly)) {
            on_cat = 1;
            on_sub = 0;
            px = lx;
            py = ly;
        } else if (sub_win != None && root_xy_in_window(sub_win, root_x, root_y, &lx, &ly)) {
            on_sub = 1;
            on_cat = 0;
            px = lx;
            py = ly;
        } else {
            on_cat = 0;
            on_sub = 0;
        }
    }

    
    if (ev->type == ButtonPress && !on_cat && !on_sub) {
        
        XAllowEvents(dpy, ReplayPointer, ev->xbutton.time);
        apps_close();
        return 1;
    }

    
    
    
    if (ev->type == ButtonRelease) {
        allow_pointer_async(ev);
        
        return (on_cat || on_sub) ? 1 : 0;
    }

    
    if ((ev->type == MotionNotify || ev->type == ButtonRelease) && !on_cat && !on_sub) {
        if (ev->type == MotionNotify || ev->type == ButtonRelease) allow_pointer_async(ev);
        return 0;
    }

    if (!on_cat && !on_sub) {
        
        return 0;
    }

    if (ev->type == Expose) {
        if (on_cat) cat_redraw();
        else sub_redraw();
        return 1;
    }
    if (ev->type == LeaveNotify) {
        if (on_cat) {
            if (cat_hover != -1) {
                cat_hover = -1;
                cat_redraw();
            }
        } else {
            if (sub_hover != -1) {
                sub_hover = -1;
                sub_redraw();
            }
        }
        return 1;
    }
    if (ev->type == MotionNotify) {
        if (on_cat) {
            
            if (sub_hover != -1) {
                sub_hover = -1;
                if (sub_win != None) sub_redraw();
            }
            int idx = item_at(cat_items, cat_item_count, cat_scroll,
                              px, py,
                              cat_h - CAT_FOOTER_PX);
            if (idx != cat_hover) {
                cat_hover = idx;
                cat_redraw();
            }

            
            int cat_idx = cat_item_to_category_idx(idx);
            if (sub_win != None && cat_count > 0 && cat_idx >= 0 && active_category != cat_idx) {
                active_category = cat_idx;
                sub_scroll = 0;
                sub_hover = -1;
                build_sub_items_for(active_category);

                
                sub_h = sub_content_h;

                
                sub_w = compute_submenu_width();
                XResizeWindow(dpy, sub_win, (unsigned int)sub_w, (unsigned int)sub_h);
                if (sub_surface) cairo_xlib_surface_set_size(sub_surface, sub_w, sub_h);

                Window dummy;
                int wx, wy;
                unsigned int ww, hh, bw, depth;
                if (XGetGeometry(dpy, cat_win, &dummy, &wx, &wy, &ww, &hh, &bw, &depth)) {
                    position_submenu(wx, wy);
                }
                sub_redraw();
            }
        } else {
            
            if (cat_hover != -1) {
                cat_hover = -1;
                cat_redraw();
            }
            int idx = item_at(sub_items, sub_item_count, sub_scroll,
                              px, py,
                              sub_h);
            if (idx != sub_hover) {
                sub_hover = idx;
                sub_redraw();
            }
        }
        allow_pointer_async(ev);
        return 1;
    }
    if (ev->type == ButtonPress) {
        
        if (ev->xbutton.button == Button4) {
            if (on_cat) {
                scroll_by(&cat_scroll, cat_content_h, cat_h - CAT_FOOTER_PX, -52);
                cat_redraw();
            } else {
                scroll_by(&sub_scroll, sub_content_h, sub_h, -52);
                sub_redraw();
            }
            allow_pointer_async(ev);
            return 1;
        }
        if (ev->xbutton.button == Button5) {
            if (on_cat) {
                scroll_by(&cat_scroll, cat_content_h, cat_h - CAT_FOOTER_PX, 52);
                cat_redraw();
                
                if (sub_win != None) {
                    int cat_x = 0, cat_y = 0;
                    Window dummy;
                    int wx, wy;
                    unsigned int ww, hh, bw, depth;
                    if (XGetGeometry(dpy, cat_win, &dummy, &wx, &wy, &ww, &hh, &bw, &depth)) {
                        cat_x = wx;
                        cat_y = wy;
                        position_submenu(cat_x, cat_y);
                    }
                }
            } else {
                scroll_by(&sub_scroll, sub_content_h, sub_h, 52);
                sub_redraw();
            }
            allow_pointer_async(ev);
            return 1;
        }

        if (ev->xbutton.button != Button1) {
            allow_pointer_async(ev);
            return 1;
        }

        if (on_cat) {
            
            int idx = item_at(cat_items, cat_item_count, cat_scroll,
                              px, py,
                              cat_h - CAT_FOOTER_PX);
            if (idx < 0 || idx >= cat_item_count) {
                allow_pointer_async(ev);
                return 1;
            }

            
            if (cat_item_is_tool(idx) && cat_items[idx].app) {
                char cmd[512];
                strncpy(cmd, cat_items[idx].app->exec, sizeof(cmd) - 1);
                cmd[sizeof(cmd) - 1] = '\0';
                allow_pointer_async(ev);
                apps_close();
                if (cmd[0] != '\0') apps_spawn(cmd);
                return 1;
            }

            int cat_idx = cat_item_to_category_idx(idx);
            if (cat_idx < 0) {
                allow_pointer_async(ev);
                return 1;
            }

            
            if (sub_win != None && active_category == cat_idx) {
                sub_close_only();
                cat_redraw();
                allow_pointer_async(ev);
                return 1;
            }

            active_category = cat_idx;
            sub_scroll = 0;
            sub_hover = -1;
            build_sub_items_for(active_category);

            
            sub_h = sub_content_h;

            Window dummy;
            int cat_x = 0, cat_y = 0;
            unsigned int ww, hh, bw, depth;
            if (XGetGeometry(dpy, cat_win, &dummy, &cat_x, &cat_y, &ww, &hh, &bw, &depth)) {
                
                if (sub_win == None) {
                    XSetWindowAttributes attrs;
                    memset(&attrs, 0, sizeof(attrs));
                    attrs.override_redirect = True;

                    int sub_x;
                    if (cat_x + cat_w + sub_w <= DisplayWidth(dpy, screen)) sub_x = cat_x + cat_w + SUBMENU_GAP_PX;
                    else sub_x = cat_x - sub_w - SUBMENU_GAP_PX;
                    if (sub_x < 0) sub_x = 0;
                    if (sub_x + sub_w > DisplayWidth(dpy, screen)) sub_x = DisplayWidth(dpy, screen) - sub_w;
                    int sub_y = clamp_menu_y_gap(cat_y, sub_h, PANEL_MENU_GAP_PX);

                    sub_win = XCreateWindow(
                        dpy, root,
                        sub_x, sub_y,
                        (unsigned int)sub_w,
                        (unsigned int)sub_h,
                        0,
                        CopyFromParent,
                        InputOutput,
                        CopyFromParent,
                        CWOverrideRedirect,
                        &attrs);
                    XSelectInput(dpy, sub_win,
                                 ExposureMask | ButtonPressMask | ButtonReleaseMask |
                                     PointerMotionMask | LeaveWindowMask | KeyPressMask);

                    Atom A_TYPE = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE", False);
                    Atom A_POPUP = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE_POPUP_MENU", False);
                    if (A_TYPE != None && A_POPUP != None) {
                        XChangeProperty(dpy, sub_win, A_TYPE, XA_ATOM, 32, PropModeReplace, (unsigned char *)&A_POPUP, 1);
                    }

                    XMapRaised(dpy, sub_win);
                    sub_surface = cairo_xlib_surface_create(dpy, sub_win, DefaultVisual(dpy, screen), sub_w, sub_h);
                    sub_cr = cairo_create(sub_surface);
                }

                
                sub_w = compute_submenu_width();
                XResizeWindow(dpy, sub_win, (unsigned int)sub_w, (unsigned int)sub_h);
                if (sub_surface) cairo_xlib_surface_set_size(sub_surface, sub_w, sub_h);

                position_submenu(cat_x, cat_y);
            }

            cat_redraw();
            sub_redraw();
            allow_pointer_async(ev);
            return 1;
        }

        int idx = item_at(sub_items, sub_item_count, sub_scroll,
                          px, py,
                          sub_h);
        if (idx < 0 || idx >= sub_item_count) {
            allow_pointer_async(ev);
            apps_close();
            return 1;
        }
        if (!sub_items[idx].app) {
            allow_pointer_async(ev);
            apps_close();
            return 1;
        }

        char cmd[512];
        strncpy(cmd, sub_items[idx].app->exec, sizeof(cmd) - 1);
        cmd[sizeof(cmd) - 1] = '\0';
        allow_pointer_async(ev);
        apps_close();
        if (cmd[0] != '\0') apps_spawn(cmd);
        return 1;
    }
    if (ev->type == KeyPress) {
        KeySym ks = XLookupKeysym(&ev->xkey, 0);
        if (ks == XK_Escape) {
            apps_close();
        }
        return 1;
    }
    return 1;
}
