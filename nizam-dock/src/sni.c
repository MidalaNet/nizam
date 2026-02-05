#include "sni.h"

#include <cairo/cairo.h>
#include <dbus/dbus.h>
#include <dirent.h>
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include "xcb_app.h"

#define SNI_WATCHER_BUS "org.kde.StatusNotifierWatcher"
#define SNI_WATCHER_PATH "/StatusNotifierWatcher"
#define SNI_WATCHER_IFACE "org.kde.StatusNotifierWatcher"
#define SNI_ITEM_IFACE "org.kde.StatusNotifierItem"

struct nizam_dock_sni_item {
  char service[128];
  char owner[128];
  char path[256];
  char menu_path[256];
  cairo_surface_t *icon;
  unsigned char *icon_data;
  int icon_w;
  int icon_h;
  int has_activate;
  int has_secondary;
  int has_context;
  int has_xayatana_secondary;
  int item_is_menu;
  int introspected;
};

struct nizam_dock_sni {
  DBusConnection *conn;
  int fd;
  struct nizam_dock_sni_item *items;
  size_t count;
  size_t cap;
  int dirty;
};

static const char *sni_best_icon_path_in_dir(const char *base,
                                             const char *name,
                                             char *out,
                                             size_t out_size);

static int sni_has_suffix(const char *path, const char *suffix) {
  if (!path || !suffix) {
    return 0;
  }
  size_t plen = strlen(path);
  size_t slen = strlen(suffix);
  if (plen < slen) {
    return 0;
  }
  return strcmp(path + plen - slen, suffix) == 0;
}

static int nizam_dock_debug_enabled(void) {
  const char *env = getenv("NIZAM_DOCK_DEBUG");
  return env && *env && strcmp(env, "0") != 0;
}

static void nizam_dock_debug_log(const char *msg) {
  if (nizam_dock_debug_enabled()) {
    fprintf(stderr, "nizam-dock: %s\n", msg);
  }
}

static void nizam_dock_debug_log2(const char *prefix, const char *value) {
  if (nizam_dock_debug_enabled()) {
    fprintf(stderr, "nizam-dock: %s%s\n", prefix, value ? value : "(null)");
  }
}

static void nizam_dock_debug_log3(const char *prefix, const char *value, const char *suffix) {
  if (nizam_dock_debug_enabled()) {
    fprintf(stderr, "nizam-dock: %s%s%s\n", prefix, value ? value : "(null)",
            suffix ? suffix : "");
  }
}

static int sni_call_method(struct nizam_dock_sni *sni,
                           struct nizam_dock_sni_item *item,
                           const char *iface,
                           const char *method,
                           const char *path,
                           int x,
                           int y) {
  if (!sni || !item || !iface || !method || !path) {
    return 0;
  }
  DBusMessage *msg = dbus_message_new_method_call(
      item->service, path, iface, method);
  if (!msg) {
    return 0;
  }
  int32_t xi = x;
  int32_t yi = y;
  dbus_message_append_args(msg,
                           DBUS_TYPE_INT32, &xi,
                           DBUS_TYPE_INT32, &yi,
                           DBUS_TYPE_INVALID);
  DBusError err;
  dbus_error_init(&err);
  DBusMessage *reply = dbus_connection_send_with_reply_and_block(
      sni->conn, msg, 500, &err);
  dbus_message_unref(msg);
  if (!reply) {
    if (nizam_dock_debug_enabled()) {
      fprintf(stderr, "nizam-dock: sni method %s failed (%s %s): %s\n",
              method, iface, path, err.message ? err.message : "unknown");
    }
    dbus_error_free(&err);
    return 0;
  }
  dbus_message_unref(reply);
  dbus_connection_flush(sni->conn);
  if (strcmp(item->path, path) != 0) {
    snprintf(item->path, sizeof(item->path), "%s", path);
  }
  return 1;
}

static int sni_normalize_icon_name(const char *name, char *out, size_t out_size) {
  if (!name || !*name || !out || out_size == 0) {
    return 0;
  }
  while (*name == ' ' || *name == '\t' || *name == '\n' || *name == '\r') {
    ++name;
  }
  size_t len = 0;
  while (name[len] && name[len] != ' ' && name[len] != '\t' &&
         name[len] != '\n' && name[len] != '\r') {
    len++;
  }
  if (len == 0) {
    return 0;
  }
  if (len >= out_size) {
    len = out_size - 1;
  }
  memcpy(out, name, len);
  out[len] = '\0';
  return 1;
}

static int sni_lowercase(const char *in, char *out, size_t out_size) {
  if (!in || !out || out_size == 0) {
    return 0;
  }
  size_t len = strlen(in);
  if (len >= out_size) {
    len = out_size - 1;
  }
  int changed = 0;
  for (size_t i = 0; i < len; ++i) {
    char c = in[i];
    if (c >= 'A' && c <= 'Z') {
      out[i] = (char)(c - 'A' + 'a');
      changed = 1;
    } else {
      out[i] = c;
    }
  }
  out[len] = '\0';
  return changed;
}

static void sni_item_clear_icon(struct nizam_dock_sni_item *item) {
  if (item->icon) {
    cairo_surface_destroy(item->icon);
    item->icon = NULL;
  }
  free(item->icon_data);
  item->icon_data = NULL;
  item->icon_w = 0;
  item->icon_h = 0;
}

static void sni_item_clear_full(struct nizam_dock_sni_item *item) {
  sni_item_clear_icon(item);
  item->menu_path[0] = '\0';
  item->has_activate = 0;
  item->has_secondary = 0;
  item->has_context = 0;
  item->has_xayatana_secondary = 0;
  item->item_is_menu = 0;
  item->introspected = 0;
}

static void sni_set_dirty(struct nizam_dock_sni *sni) {
  if (sni) {
    sni->dirty = 1;
  }
}

static struct nizam_dock_sni_item *sni_find_by_owner(struct nizam_dock_sni *sni, const char *owner) {
  if (!sni || !owner) {
    return NULL;
  }
  for (size_t i = 0; i < sni->count; ++i) {
    if (strcmp(sni->items[i].owner, owner) == 0) {
      return &sni->items[i];
    }
  }
  return NULL;
}

static struct nizam_dock_sni_item *sni_find_by_service(struct nizam_dock_sni *sni, const char *service) {
  if (!sni || !service) {
    return NULL;
  }
  for (size_t i = 0; i < sni->count; ++i) {
    if (strcmp(sni->items[i].service, service) == 0) {
      return &sni->items[i];
    }
  }
  return NULL;
}

static void sni_remove_by_owner(struct nizam_dock_sni *sni, const char *owner) {
  if (!sni || !owner) {
    return;
  }
  for (size_t i = 0; i < sni->count; ++i) {
    if (strcmp(sni->items[i].owner, owner) == 0) {
      sni_item_clear_full(&sni->items[i]);
      sni->items[i] = sni->items[sni->count - 1];
      sni->count--;
      sni_set_dirty(sni);
      return;
    }
  }
}

static int sni_ensure_capacity(struct nizam_dock_sni *sni) {
  if (sni->count < sni->cap) {
    return 1;
  }
  size_t next = sni->cap == 0 ? 8 : sni->cap * 2;
  struct nizam_dock_sni_item *items = realloc(sni->items, next * sizeof(*items));
  if (!items) {
    return 0;
  }
  sni->items = items;
  sni->cap = next;
  return 1;
}

static int sni_is_dir(const char *path) {
  struct stat st;
  if (stat(path, &st) != 0) {
    return 0;
  }
  return S_ISDIR(st.st_mode);
}

static int sni_try_icon_file(const char *path) {
  if (!path || !*path) {
    return 0;
  }
  if (access(path, R_OK) != 0) {
    return 0;
  }
  return 1;
}

static int sni_run_rsvg_convert(const char *input, const char *output, int size) {
  char wbuf[16];
  char hbuf[16];
  snprintf(wbuf, sizeof(wbuf), "%d", size);
  snprintf(hbuf, sizeof(hbuf), "%d", size);
  pid_t pid = fork();
  if (pid == 0) {
    execlp("rsvg-convert", "rsvg-convert", "-w", wbuf, "-h", hbuf,
           "-o", output, input, (char *)NULL);
    _exit(127);
  }
  if (pid < 0) {
    return 0;
  }
  int status = 0;
  if (waitpid(pid, &status, 0) < 0) {
    return 0;
  }
  return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

static cairo_surface_t *sni_load_icon_surface(const char *path, unsigned char **out_data) {
  if (!path || !*path) {
    return NULL;
  }
  if (out_data) {
    *out_data = NULL;
  }
  GError *gerr = NULL;
  GdkPixbuf *pixbuf = gdk_pixbuf_new_from_file(path, &gerr);
  if (pixbuf) {
    int w = gdk_pixbuf_get_width(pixbuf);
    int h = gdk_pixbuf_get_height(pixbuf);
    int stride_src = gdk_pixbuf_get_rowstride(pixbuf);
    int channels = gdk_pixbuf_get_n_channels(pixbuf);
    int has_alpha = gdk_pixbuf_get_has_alpha(pixbuf);
    const guchar *src = gdk_pixbuf_get_pixels(pixbuf);
    int stride_dst = cairo_format_stride_for_width(CAIRO_FORMAT_ARGB32, w);
    unsigned char *dst = calloc(1, (size_t)stride_dst * (size_t)h);
    if (!dst) {
      g_object_unref(pixbuf);
      return NULL;
    }
    for (int y = 0; y < h; ++y) {
      const guchar *row = src + y * stride_src;
      unsigned char *out = dst + y * stride_dst;
      for (int x = 0; x < w; ++x) {
        unsigned char r = row[x * channels + 0];
        unsigned char g = row[x * channels + 1];
        unsigned char b = row[x * channels + 2];
        unsigned char a = has_alpha ? row[x * channels + 3] : 255;
        unsigned char pr = (unsigned char)((r * a + 127) / 255);
        unsigned char pg = (unsigned char)((g * a + 127) / 255);
        unsigned char pb = (unsigned char)((b * a + 127) / 255);
#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
        out[x * 4 + 0] = pb;
        out[x * 4 + 1] = pg;
        out[x * 4 + 2] = pr;
        out[x * 4 + 3] = a;
#else
        out[x * 4 + 0] = a;
        out[x * 4 + 1] = pr;
        out[x * 4 + 2] = pg;
        out[x * 4 + 3] = pb;
#endif
      }
    }
    g_object_unref(pixbuf);
    cairo_surface_t *surface = cairo_image_surface_create_for_data(
        dst, CAIRO_FORMAT_ARGB32, w, h, stride_dst);
    if (cairo_surface_status(surface) != CAIRO_STATUS_SUCCESS) {
      cairo_surface_destroy(surface);
      free(dst);
      return NULL;
    }
    if (out_data) {
      *out_data = dst;
    }
    return surface;
  }
  if (gerr) {
    nizam_dock_debug_log3("sni icon load error: ", path, gerr->message ? " " : "");
    if (gerr->message) {
      nizam_dock_debug_log2("sni icon load detail: ", gerr->message);
    }
    g_error_free(gerr);
  }
  if (sni_has_suffix(path, ".svg") || sni_has_suffix(path, ".svgz")) {
    char tmp[] = "/tmp/nizam-dock-svg-XXXXXX";
    int fd = mkstemp(tmp);
    if (fd < 0) {
      return NULL;
    }
    close(fd);
    char out[512];
    snprintf(out, sizeof(out), "%s.png", tmp);
    unlink(tmp);
    if (!sni_run_rsvg_convert(path, out, 64)) {
      unlink(out);
      return NULL;
    }
    cairo_surface_t *surface = cairo_image_surface_create_from_png(out);
    unlink(out);
    if (cairo_surface_status(surface) == CAIRO_STATUS_SUCCESS) {
      return surface;
    }
    cairo_surface_destroy(surface);
    return NULL;
  }
  return NULL;
}

static const char *sni_best_icon_path(const char *name, char *out, size_t out_size) {
  if (!name || !*name) {
    return NULL;
  }
  if (strchr(name, '/')) {
    if (sni_try_icon_file(name)) {
      snprintf(out, out_size, "%s", name);
      return out;
    }
    return NULL;
  }
  const char *suffixes[] = {".png", ".svg", ".svgz", ".xpm"};
  for (size_t i = 0; i < sizeof(suffixes) / sizeof(suffixes[0]); ++i) {
    snprintf(out, out_size, "%s%s", name, suffixes[i]);
    if (sni_try_icon_file(out)) {
      nizam_dock_debug_log2("sni icon path: ", out);
      return out;
    }
  }
  snprintf(out, out_size, "/usr/share/pixmaps/%s", name);
  if (sni_try_icon_file(out)) {
    nizam_dock_debug_log2("sni icon path: ", out);
    return out;
  }

  const char *xdg_home = getenv("XDG_DATA_HOME");
  char local_icons[256];
  if (!xdg_home || !*xdg_home) {
    const char *home = getenv("HOME");
    if (home && *home) {
      snprintf(local_icons, sizeof(local_icons), "%s/.local/share", home);
      xdg_home = local_icons;
    }
  }

  const char *xdg_dirs = getenv("XDG_DATA_DIRS");
  if (!xdg_dirs || !*xdg_dirs) {
    xdg_dirs = "/usr/local/share:/usr/share";
  }

  const char *dirs[8];
  size_t dir_count = 0;
  if (xdg_home && *xdg_home) {
    dirs[dir_count++] = xdg_home;
  }
  char *dirs_copy = strdup(xdg_dirs);
  if (!dirs_copy) {
    return NULL;
  }
  char *save = NULL;
  for (char *tok = strtok_r(dirs_copy, ":", &save);
       tok && dir_count < sizeof(dirs) / sizeof(dirs[0]);
       tok = strtok_r(NULL, ":", &save)) {
    dirs[dir_count++] = tok;
  }

  for (size_t i = 0; i < dir_count; ++i) {
    char icons_root[256];
    char pix_root[256];
    snprintf(icons_root, sizeof(icons_root), "%s/icons", dirs[i]);
    snprintf(pix_root, sizeof(pix_root), "%s/pixmaps", dirs[i]);

    if (sni_is_dir(icons_root)) {
      DIR *dir = opendir(icons_root);
      if (dir) {
        struct dirent *ent;
        while ((ent = readdir(dir)) != NULL) {
          if (ent->d_name[0] == '.') {
            continue;
          }
          char theme_path[512];
          snprintf(theme_path, sizeof(theme_path), "%s/%s", icons_root, ent->d_name);
          if (!sni_is_dir(theme_path)) {
            continue;
          }
          if (sni_best_icon_path_in_dir(theme_path, name, out, out_size)) {
            nizam_dock_debug_log2("sni icon path: ", out);
            closedir(dir);
            free(dirs_copy);
            return out;
          }
        }
        closedir(dir);
      }
    }

    if (sni_is_dir(pix_root)) {
      const char *pix_exts[] = {".png", ".svg", ".xpm"};
      for (size_t e = 0; e < sizeof(pix_exts) / sizeof(pix_exts[0]); ++e) {
        snprintf(out, out_size, "%s/%s%s", pix_root, name, pix_exts[e]);
        if (sni_try_icon_file(out)) {
          nizam_dock_debug_log2("sni icon path: ", out);
          free(dirs_copy);
          return out;
        }
      }
    }
  }

  free(dirs_copy);
  const char *fallback_exts[] = {".png", ".svg", ".xpm"};
  for (size_t e = 0; e < sizeof(fallback_exts) / sizeof(fallback_exts[0]); ++e) {
    snprintf(out, out_size, "/usr/share/pixmaps/%s%s", name, fallback_exts[e]);
    if (sni_try_icon_file(out)) {
      nizam_dock_debug_log2("sni icon path: ", out);
      return out;
    }
  }
  snprintf(out, out_size, "/usr/share/pixmaps/%s", name);
  if (sni_try_icon_file(out)) {
    nizam_dock_debug_log2("sni icon path: ", out);
    return out;
  }
  return NULL;
}

static cairo_user_data_key_t nizam_dock_icon_data_key;

const char *nizam_dock_resolve_icon_path(const char *name, char *out, size_t out_size) {
  return sni_best_icon_path(name, out, out_size);
}

cairo_surface_t *nizam_dock_load_icon_surface(const char *path) {
  unsigned char *data = NULL;
  cairo_surface_t *surface = sni_load_icon_surface(path, &data);
  if (!surface) {
    return NULL;
  }
  if (data) {
    cairo_surface_set_user_data(surface, &nizam_dock_icon_data_key, data, free);
  }
  return surface;
}

static const char *sni_best_icon_path_in_dir(const char *base,
                                             const char *name,
                                             char *out,
                                             size_t out_size) {
  if (!base || !*base || !name || !*name) {
    return NULL;
  }
  char hicolor[512];
  snprintf(hicolor, sizeof(hicolor), "%s/hicolor", base);
  if (sni_is_dir(hicolor)) {
    if (sni_best_icon_path_in_dir(hicolor, name, out, out_size)) {
      return out;
    }
  }
  const char *base_exts[] = {".png", ".svg", ".svgz", ".xpm"};
  for (size_t e = 0; e < sizeof(base_exts) / sizeof(base_exts[0]); ++e) {
    snprintf(out, out_size, "%s/%s%s", base, name, base_exts[e]);
    if (access(out, R_OK) == 0) {
      return out;
    }
  }
  snprintf(out, out_size, "%s/%s@2x.png", base, name);
  if (access(out, R_OK) == 0) {
    return out;
  }
  const char *scalable_exts[] = {".svg", ".svgz", ".png"};
  for (size_t e = 0; e < sizeof(scalable_exts) / sizeof(scalable_exts[0]); ++e) {
    snprintf(out, out_size, "%s/scalable/status/%s%s", base, name, scalable_exts[e]);
    if (access(out, R_OK) == 0) {
      return out;
    }
    snprintf(out, out_size, "%s/scalable/apps/%s%s", base, name, scalable_exts[e]);
    if (access(out, R_OK) == 0) {
      return out;
    }
  }
  const char *sizes[] = {
    "128x128",
    "64x64",
    "48x48",
    "32x32",
    "24x24",
    "16x16"
  };
  const char *groups[] = {"status", "apps"};
  for (size_t s = 0; s < sizeof(sizes) / sizeof(sizes[0]); ++s) {
    for (size_t g = 0; g < sizeof(groups) / sizeof(groups[0]); ++g) {
      const char *size_exts[] = {".png", ".svg", ".svgz", ".xpm", ".icon"};
      for (size_t e = 0; e < sizeof(size_exts) / sizeof(size_exts[0]); ++e) {
        snprintf(out, out_size, "%s/%s/%s/%s%s", base, sizes[s], groups[g], name, size_exts[e]);
        if (access(out, R_OK) == 0) {
          return out;
        }
      }
      snprintf(out, out_size, "%s/%s/%s/%s-symbolic.png", base, sizes[s], groups[g], name);
      if (access(out, R_OK) == 0) {
        return out;
      }
    }
  }
  snprintf(out, out_size, "%s/%s.png", base, name);
  if (access(out, R_OK) == 0) {
    return out;
  }
  return NULL;
}

static int sni_set_icon_surface(struct nizam_dock_sni_item *item,
                                cairo_surface_t *surface,
                                unsigned char *data,
                                int w, int h) {
  if (!item || !surface) {
    return 0;
  }
  sni_item_clear_icon(item);
  item->icon = surface;
  item->icon_data = data;
  item->icon_w = w;
  item->icon_h = h;
  return 1;
}

static int sni_fetch_icon_pixmap_prop(DBusConnection *conn,
                                      struct nizam_dock_sni_item *item,
                                      const char *prop) {
  if (!prop || !*prop) {
    return 0;
  }
  DBusMessage *msg = dbus_message_new_method_call(
      item->service, item->path,
      "org.freedesktop.DBus.Properties", "Get");
  if (!msg) {
    return 0;
  }
  const char *iface = SNI_ITEM_IFACE;
  dbus_message_append_args(msg,
                           DBUS_TYPE_STRING, &iface,
                           DBUS_TYPE_STRING, &prop,
                           DBUS_TYPE_INVALID);
  DBusError err;
  dbus_error_init(&err);
  DBusMessage *reply = dbus_connection_send_with_reply_and_block(conn, msg, 500, &err);
  dbus_message_unref(msg);
  if (!reply) {
    dbus_error_free(&err);
    return 0;
  }

  DBusMessageIter iter;
  dbus_message_iter_init(reply, &iter);
  if (dbus_message_iter_get_arg_type(&iter) != DBUS_TYPE_VARIANT) {
    dbus_message_unref(reply);
    return 0;
  }
  DBusMessageIter variant;
  dbus_message_iter_recurse(&iter, &variant);
  if (dbus_message_iter_get_arg_type(&variant) != DBUS_TYPE_ARRAY) {
    dbus_message_unref(reply);
    return 0;
  }

  DBusMessageIter array;
  dbus_message_iter_recurse(&variant, &array);
  int best_w = 0;
  int best_h = 0;
  unsigned char *best_data = NULL;
  int best_len = 0;

  while (dbus_message_iter_get_arg_type(&array) == DBUS_TYPE_STRUCT) {
    DBusMessageIter st;
    dbus_message_iter_recurse(&array, &st);
    int32_t w = 0;
    int32_t h = 0;
    dbus_message_iter_get_basic(&st, &w);
    dbus_message_iter_next(&st);
    dbus_message_iter_get_basic(&st, &h);
    dbus_message_iter_next(&st);
    if (dbus_message_iter_get_arg_type(&st) == DBUS_TYPE_ARRAY) {
      DBusMessageIter bytes;
      dbus_message_iter_recurse(&st, &bytes);
      unsigned char *data = NULL;
      int len = 0;
      dbus_message_iter_get_fixed_array(&bytes, &data, &len);
      if (data && len > 0 && w > 0 && h > 0) {
        if (w * h > best_w * best_h) {
          free(best_data);
          best_data = malloc((size_t)len);
          if (best_data) {
            memcpy(best_data, data, (size_t)len);
            best_w = w;
            best_h = h;
            best_len = len;
          }
        }
      }
    }
    dbus_message_iter_next(&array);
  }

  dbus_message_unref(reply);
  if (!best_data || best_w <= 0 || best_h <= 0) {
    free(best_data);
    return 0;
  }

  size_t expected = (size_t)best_w * (size_t)best_h * 4;
  if ((size_t)best_len < expected) {
    if (nizam_dock_debug_enabled()) {
      fprintf(stderr, "nizam-dock: sni pixmap size mismatch (%dx%d len=%d expected=%zu)\n",
              best_w, best_h, best_len, expected);
    }
    free(best_data);
    return 0;
  }

  
  
  int alpha0_nonzero = 0;
  int alpha3_nonzero = 0;
  {
    int sample = best_w * best_h;
    if (sample > 1024) {
      sample = 1024;
    }
    for (int i = 0; i < sample; ++i) {
      const unsigned char *px = best_data + (size_t)i * 4;
      if (px[0] != 0) {
        alpha0_nonzero++;
      }
      if (px[3] != 0) {
        alpha3_nonzero++;
      }
    }
  }
  int alpha_is_byte3 = (alpha0_nonzero < alpha3_nonzero / 4);
  if (alpha_is_byte3 && nizam_dock_debug_enabled()) {
    fprintf(stderr, "nizam-dock: sni pixmap detected RGBA-like data (%dx%d)\n", best_w, best_h);
  }

  int stride = cairo_format_stride_for_width(CAIRO_FORMAT_ARGB32, best_w);
  unsigned char *buf = calloc(1, (size_t)stride * (size_t)best_h);
  if (!buf) {
    free(best_data);
    return 0;
  }
  size_t row_bytes = (size_t)best_w * 4;
  for (int y = 0; y < best_h; ++y) {
    unsigned char *dst = buf + (size_t)y * (size_t)stride;
    unsigned char *src = best_data + (size_t)y * row_bytes;
    for (int x = 0; x < best_w; ++x) {
      unsigned char a = 0;
      unsigned char r = 0;
      unsigned char g = 0;
      unsigned char b = 0;
      if (alpha_is_byte3) {
        
        r = src[x * 4 + 0];
        g = src[x * 4 + 1];
        b = src[x * 4 + 2];
        a = src[x * 4 + 3];
      } else {
        
        a = src[x * 4 + 0];
        r = src[x * 4 + 1];
        g = src[x * 4 + 2];
        b = src[x * 4 + 3];
      }

      
      if (a != 255) {
        r = (unsigned char)(((unsigned)r * (unsigned)a + 127u) / 255u);
        g = (unsigned char)(((unsigned)g * (unsigned)a + 127u) / 255u);
        b = (unsigned char)(((unsigned)b * (unsigned)a + 127u) / 255u);
      }
#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
      dst[x * 4 + 0] = b;
      dst[x * 4 + 1] = g;
      dst[x * 4 + 2] = r;
      dst[x * 4 + 3] = a;
#else
      dst[x * 4 + 0] = a;
      dst[x * 4 + 1] = r;
      dst[x * 4 + 2] = g;
      dst[x * 4 + 3] = b;
#endif
    }
  }
  free(best_data);

  cairo_surface_t *surface = cairo_image_surface_create_for_data(
      buf, CAIRO_FORMAT_ARGB32, best_w, best_h, stride);
  if (cairo_surface_status(surface) != CAIRO_STATUS_SUCCESS) {
    cairo_surface_destroy(surface);
    free(buf);
    return 0;
  }
  return sni_set_icon_surface(item, surface, buf, best_w, best_h);
}

static int sni_fetch_icon_pixmap(DBusConnection *conn,
                                 struct nizam_dock_sni_item *item) {
  return sni_fetch_icon_pixmap_prop(conn, item, "IconPixmap");
}

static int sni_fetch_icon_name_prop(DBusConnection *conn,
                                    struct nizam_dock_sni_item *item,
                                    const char *prop) {
  if (!prop || !*prop) {
    return 0;
  }
  DBusMessage *msg = dbus_message_new_method_call(
      item->service, item->path,
      "org.freedesktop.DBus.Properties", "Get");
  if (!msg) {
    return 0;
  }
  const char *iface = SNI_ITEM_IFACE;
  dbus_message_append_args(msg,
                           DBUS_TYPE_STRING, &iface,
                           DBUS_TYPE_STRING, &prop,
                           DBUS_TYPE_INVALID);
  DBusError err;
  dbus_error_init(&err);
  DBusMessage *reply = dbus_connection_send_with_reply_and_block(conn, msg, 500, &err);
  dbus_message_unref(msg);
  if (!reply) {
    dbus_error_free(&err);
    return 0;
  }

  DBusMessageIter iter;
  dbus_message_iter_init(reply, &iter);
  if (dbus_message_iter_get_arg_type(&iter) != DBUS_TYPE_VARIANT) {
    dbus_message_unref(reply);
    return 0;
  }
  DBusMessageIter variant;
  dbus_message_iter_recurse(&iter, &variant);
  const char *name = NULL;
  if (dbus_message_iter_get_arg_type(&variant) == DBUS_TYPE_STRING) {
    dbus_message_iter_get_basic(&variant, &name);
  }
  dbus_message_unref(reply);
  if (!name || !*name) {
    return 0;
  }
  nizam_dock_debug_log2("sni icon name: ", name);

  char normalized[256];
  if (!sni_normalize_icon_name(name, normalized, sizeof(normalized))) {
    return 0;
  }
  if (strcmp(name, normalized) != 0) {
    nizam_dock_debug_log2("sni icon name normalized: ", normalized);
  }

  char path[512];
  DBusMessage *path_msg = dbus_message_new_method_call(
      item->service, item->path,
      "org.freedesktop.DBus.Properties", "Get");
  if (path_msg) {
    const char *path_prop = "IconThemePath";
    dbus_message_append_args(path_msg,
                             DBUS_TYPE_STRING, &iface,
                             DBUS_TYPE_STRING, &path_prop,
                             DBUS_TYPE_INVALID);
    DBusError err2;
    dbus_error_init(&err2);
    DBusMessage *path_reply = dbus_connection_send_with_reply_and_block(conn, path_msg, 200, &err2);
    dbus_message_unref(path_msg);
    if (path_reply) {
      DBusMessageIter it;
      dbus_message_iter_init(path_reply, &it);
      if (dbus_message_iter_get_arg_type(&it) == DBUS_TYPE_VARIANT) {
        DBusMessageIter var;
        dbus_message_iter_recurse(&it, &var);
        const char *theme_path = NULL;
        if (dbus_message_iter_get_arg_type(&var) == DBUS_TYPE_STRING) {
          dbus_message_iter_get_basic(&var, &theme_path);
        }
        if (theme_path && *theme_path) {
          nizam_dock_debug_log2("sni icon theme path: ", theme_path);
          if (sni_best_icon_path_in_dir(theme_path, normalized, path, sizeof(path))) {
            unsigned char *data = NULL;
            cairo_surface_t *surface = sni_load_icon_surface(path, &data);
            if (surface) {
              dbus_message_unref(path_reply);
              return sni_set_icon_surface(item, surface, data, 0, 0);
            }
          }
        }
      }
      dbus_message_unref(path_reply);
    }
    dbus_error_free(&err2);
  }

  if (!sni_best_icon_path(normalized, path, sizeof(path))) {
    char lower[256];
    if (sni_lowercase(normalized, lower, sizeof(lower))) {
      nizam_dock_debug_log2("sni icon name lowercase: ", lower);
      if (!sni_best_icon_path(lower, path, sizeof(path))) {
        return 0;
      }
    } else {
      return 0;
    }
  }
  unsigned char *data = NULL;
  cairo_surface_t *surface = sni_load_icon_surface(path, &data);
  if (!surface) {
    return 0;
  }
  return sni_set_icon_surface(item, surface, data, 0, 0);
}

static int sni_fetch_icon_name(DBusConnection *conn,
                               struct nizam_dock_sni_item *item) {
  return sni_fetch_icon_name_prop(conn, item, "IconName");
}

static void sni_fetch_menu_path(DBusConnection *conn, struct nizam_dock_sni_item *item) {
  if (!conn || !item) {
    return;
  }
  char prev[256];
  snprintf(prev, sizeof(prev), "%s", item->menu_path);
  {
    DBusMessage *msg = dbus_message_new_method_call(
        item->service, item->path,
        "org.freedesktop.DBus.Properties", "Get");
    if (msg) {
      const char *iface = SNI_ITEM_IFACE;
      const char *prop = "Menu";
      dbus_message_append_args(msg,
                               DBUS_TYPE_STRING, &iface,
                               DBUS_TYPE_STRING, &prop,
                               DBUS_TYPE_INVALID);
      DBusMessage *reply = dbus_connection_send_with_reply_and_block(conn, msg, 500, NULL);
      dbus_message_unref(msg);
      if (reply) {
        DBusMessageIter iter;
        dbus_message_iter_init(reply, &iter);
        if (dbus_message_iter_get_arg_type(&iter) == DBUS_TYPE_VARIANT) {
          DBusMessageIter var;
          dbus_message_iter_recurse(&iter, &var);
          int vtype = dbus_message_iter_get_arg_type(&var);
          const char *path = NULL;
          if (vtype == DBUS_TYPE_OBJECT_PATH || vtype == DBUS_TYPE_STRING) {
            dbus_message_iter_get_basic(&var, &path);
          }
          if (nizam_dock_debug_enabled()) {
            fprintf(stderr, "nizam-dock: sni prop Menu (Get) type=%c value=%s\n",
                    vtype ? vtype : '?', path ? path : "(null)");
          }
          if (path && *path && strcmp(path, "/") != 0) {
            snprintf(item->menu_path, sizeof(item->menu_path), "%s", path);
          }
        }
        dbus_message_unref(reply);
      }
    }
  }

  if (!item->menu_path[0]) {
    DBusMessage *msg = dbus_message_new_method_call(
        item->service, item->path,
        "org.freedesktop.DBus.Properties", "GetAll");
    if (!msg) {
      return;
    }
    const char *iface = SNI_ITEM_IFACE;
    dbus_message_append_args(msg, DBUS_TYPE_STRING, &iface, DBUS_TYPE_INVALID);
    DBusMessage *reply = dbus_connection_send_with_reply_and_block(conn, msg, 500, NULL);
    dbus_message_unref(msg);
    if (!reply) {
      return;
    }
    DBusMessageIter iter;
    dbus_message_iter_init(reply, &iter);
    if (dbus_message_iter_get_arg_type(&iter) == DBUS_TYPE_ARRAY) {
      DBusMessageIter array;
      dbus_message_iter_recurse(&iter, &array);
      while (dbus_message_iter_get_arg_type(&array) == DBUS_TYPE_DICT_ENTRY) {
        DBusMessageIter entry;
        dbus_message_iter_recurse(&array, &entry);
        const char *key = NULL;
        dbus_message_iter_get_basic(&entry, &key);
        dbus_message_iter_next(&entry);
        if (key && strcmp(key, "Menu") == 0 &&
            dbus_message_iter_get_arg_type(&entry) == DBUS_TYPE_VARIANT) {
          DBusMessageIter var;
          dbus_message_iter_recurse(&entry, &var);
          int vtype = dbus_message_iter_get_arg_type(&var);
          const char *path = NULL;
          if (vtype == DBUS_TYPE_OBJECT_PATH || vtype == DBUS_TYPE_STRING) {
            dbus_message_iter_get_basic(&var, &path);
          }
          if (nizam_dock_debug_enabled()) {
            fprintf(stderr, "nizam-dock: sni prop Menu (GetAll) type=%c value=%s\n",
                    vtype ? vtype : '?', path ? path : "(null)");
          }
          if (path && *path && strcmp(path, "/") != 0) {
            snprintf(item->menu_path, sizeof(item->menu_path), "%s", path);
            break;
          }
        }
        dbus_message_iter_next(&array);
      }
    }
    dbus_message_unref(reply);
  }

  if (!item->menu_path[0] && prev[0]) {
    snprintf(item->menu_path, sizeof(item->menu_path), "%s", prev);
  }
  if (item->menu_path[0] && nizam_dock_debug_enabled()) {
    fprintf(stderr, "nizam-dock: sni menu path: %s\n", item->menu_path);
  }
}

static int sni_path_has_sni(DBusConnection *conn, const char *service, const char *path) {
  if (!conn || !service || !path) {
    return 0;
  }
  DBusMessage *msg = dbus_message_new_method_call(
      service, path, "org.freedesktop.DBus.Properties", "GetAll");
  if (!msg) {
    return 0;
  }
  const char *iface = SNI_ITEM_IFACE;
  dbus_message_append_args(msg, DBUS_TYPE_STRING, &iface, DBUS_TYPE_INVALID);
  DBusMessage *reply = dbus_connection_send_with_reply_and_block(conn, msg, 500, NULL);
  dbus_message_unref(msg);
  if (!reply) {
    return 0;
  }
  int ok = dbus_message_get_type(reply) == DBUS_MESSAGE_TYPE_METHOD_RETURN;
  if (nizam_dock_debug_enabled()) {
    fprintf(stderr, "nizam-dock: sni path check %s -> %s\n",
            path, ok ? "yes" : "no");
  }
  dbus_message_unref(reply);
  return ok;
}

static int sni_introspect_first_child(DBusConnection *conn,
                                      const char *service,
                                      const char *base_path,
                                      char *out,
                                      size_t out_size) {
  if (!conn || !service || !base_path || !out || out_size == 0) {
    return 0;
  }
  DBusMessage *msg = dbus_message_new_method_call(
      service, base_path,
      "org.freedesktop.DBus.Introspectable", "Introspect");
  if (!msg) {
    return 0;
  }
  DBusMessage *reply = dbus_connection_send_with_reply_and_block(conn, msg, 500, NULL);
  dbus_message_unref(msg);
  if (!reply) {
    return 0;
  }
  const char *xml = NULL;
  int ok = 0;
  if (dbus_message_get_args(reply, NULL, DBUS_TYPE_STRING, &xml, DBUS_TYPE_INVALID) && xml) {
    const char *needle = "node name=\"";
    const char *pos = strstr(xml, needle);
    if (pos) {
      pos += strlen(needle);
      const char *end = strchr(pos, '"');
      if (end && end > pos) {
        size_t len = (size_t)(end - pos);
        if (len >= out_size) {
          len = out_size - 1;
        }
        memcpy(out, pos, len);
        out[len] = '\0';
        ok = 1;
      }
    }
  }
  dbus_message_unref(reply);
  return ok;
}

static void sni_discover_item_path(DBusConnection *conn, struct nizam_dock_sni_item *item) {
  if (!conn || !item) {
    return;
  }
  if (nizam_dock_debug_enabled()) {
    fprintf(stderr, "nizam-dock: sni discover path (service=%s) start=%s\n",
            item->service, item->path);
  }
  if (sni_path_has_sni(conn, item->service, item->path)) {
    return;
  }
  const char *kde_path = "/org/kde/StatusNotifierItem";
  if (sni_path_has_sni(conn, item->service, kde_path)) {
    snprintf(item->path, sizeof(item->path), "%s", kde_path);
    if (nizam_dock_debug_enabled()) {
      fprintf(stderr, "nizam-dock: sni item path: %s\n", item->path);
    }
    return;
  }
  const char *ayatana_base = "/org/ayatana/NotificationItem";
  char child[128];
  if (sni_introspect_first_child(conn, item->service, ayatana_base, child, sizeof(child))) {
    char path[192];
    snprintf(path, sizeof(path), "%s/%s", ayatana_base, child);
    if (sni_path_has_sni(conn, item->service, path)) {
      snprintf(item->path, sizeof(item->path), "%s", path);
      if (nizam_dock_debug_enabled()) {
        fprintf(stderr, "nizam-dock: sni item path: %s\n", item->path);
      }
      return;
    }
  }
}

static void sni_fetch_item_is_menu(DBusConnection *conn, struct nizam_dock_sni_item *item) {
  if (!conn || !item) {
    return;
  }
  DBusMessage *msg = dbus_message_new_method_call(
      item->service, item->path,
      "org.freedesktop.DBus.Properties", "Get");
  if (!msg) {
    return;
  }
  const char *iface = SNI_ITEM_IFACE;
  const char *prop = "ItemIsMenu";
  dbus_message_append_args(msg,
                           DBUS_TYPE_STRING, &iface,
                           DBUS_TYPE_STRING, &prop,
                           DBUS_TYPE_INVALID);
  DBusMessage *reply = dbus_connection_send_with_reply_and_block(conn, msg, 500, NULL);
  dbus_message_unref(msg);
  if (!reply) {
    return;
  }
  DBusMessageIter iter;
  dbus_message_iter_init(reply, &iter);
  if (dbus_message_iter_get_arg_type(&iter) != DBUS_TYPE_VARIANT) {
    dbus_message_unref(reply);
    return;
  }
  DBusMessageIter variant;
  dbus_message_iter_recurse(&iter, &variant);
  if (dbus_message_iter_get_arg_type(&variant) == DBUS_TYPE_BOOLEAN) {
    dbus_bool_t val = 0;
    dbus_message_iter_get_basic(&variant, &val);
    item->item_is_menu = val ? 1 : 0;
  }
  dbus_message_unref(reply);
}

static void sni_introspect_item(DBusConnection *conn, struct nizam_dock_sni_item *item) {
  if (!conn || !item || item->introspected) {
    return;
  }
  item->introspected = 1;
  DBusMessage *msg = dbus_message_new_method_call(
      item->service, item->path,
      "org.freedesktop.DBus.Introspectable", "Introspect");
  if (!msg) {
    return;
  }
  DBusMessage *reply = dbus_connection_send_with_reply_and_block(conn, msg, 500, NULL);
  dbus_message_unref(msg);
  if (!reply) {
    return;
  }
  const char *xml = NULL;
  if (dbus_message_get_args(reply, NULL, DBUS_TYPE_STRING, &xml, DBUS_TYPE_INVALID) && xml) {
    if (strstr(xml, "name=\"Activate\"")) {
      item->has_activate = 1;
    }
    if (strstr(xml, "name=\"SecondaryActivate\"")) {
      item->has_secondary = 1;
    }
    if (strstr(xml, "name=\"ContextMenu\"")) {
      item->has_context = 1;
    }
    if (strstr(xml, "name=\"XAyatanaSecondaryActivate\"")) {
      item->has_xayatana_secondary = 1;
    }
  }
  if (nizam_dock_debug_enabled()) {
    fprintf(stderr,
            "nizam-dock: sni caps service=%s path=%s act=%d sec=%d xaya=%d ctx=%d menu=%d\n",
            item->service, item->path,
            item->has_activate, item->has_secondary, item->has_xayatana_secondary,
            item->has_context, item->item_is_menu);
  }
  dbus_message_unref(reply);
}

static int sni_refresh_item(DBusConnection *conn, struct nizam_dock_sni_item *item) {
  if (!conn || !item) {
    return 0;
  }
  sni_discover_item_path(conn, item);
  sni_fetch_menu_path(conn, item);
  sni_fetch_item_is_menu(conn, item);
  sni_introspect_item(conn, item);
  if (sni_fetch_icon_pixmap(conn, item)) {
    nizam_dock_debug_log("sni icon: pixmap");
    return 1;
  }
  if (sni_fetch_icon_name(conn, item)) {
    nizam_dock_debug_log("sni icon: name");
    return 1;
  }
  if (sni_fetch_icon_pixmap_prop(conn, item, "AttentionIconPixmap")) {
    nizam_dock_debug_log("sni icon: attention pixmap");
    return 1;
  }
  if (sni_fetch_icon_name_prop(conn, item, "AttentionIconName")) {
    nizam_dock_debug_log("sni icon: attention name");
    return 1;
  }
  if (sni_fetch_icon_pixmap_prop(conn, item, "OverlayIconPixmap")) {
    nizam_dock_debug_log("sni icon: overlay pixmap");
    return 1;
  }
  if (sni_fetch_icon_name_prop(conn, item, "OverlayIconName")) {
    nizam_dock_debug_log("sni icon: overlay name");
    return 1;
  }
  nizam_dock_debug_log("sni icon: missing");
  return 0;
}

static const char *sni_get_owner(DBusConnection *conn, const char *service, char *out, size_t out_size) {
  if (!service || !*service) {
    return NULL;
  }
  if (service[0] == ':') {
    snprintf(out, out_size, "%s", service);
    return out;
  }
  DBusMessage *msg = dbus_message_new_method_call(
      "org.freedesktop.DBus", "/org/freedesktop/DBus",
      "org.freedesktop.DBus", "GetNameOwner");
  if (!msg) {
    return NULL;
  }
  dbus_message_append_args(msg, DBUS_TYPE_STRING, &service, DBUS_TYPE_INVALID);
  DBusError err;
  dbus_error_init(&err);
  DBusMessage *reply = dbus_connection_send_with_reply_and_block(conn, msg, 500, &err);
  dbus_message_unref(msg);
  if (!reply) {
    dbus_error_free(&err);
    return NULL;
  }
  const char *owner = NULL;
  if (!dbus_message_get_args(reply, &err, DBUS_TYPE_STRING, &owner, DBUS_TYPE_INVALID)) {
    dbus_message_unref(reply);
    dbus_error_free(&err);
    return NULL;
  }
  snprintf(out, out_size, "%s", owner);
  dbus_message_unref(reply);
  return out;
}

static void sni_emit_item_registered(DBusConnection *conn, const char *service) {
  DBusMessage *sig = dbus_message_new_signal(SNI_WATCHER_PATH, SNI_WATCHER_IFACE,
                                             "StatusNotifierItemRegistered");
  if (!sig) {
    return;
  }
  dbus_message_append_args(sig, DBUS_TYPE_STRING, &service, DBUS_TYPE_INVALID);
  dbus_connection_send(conn, sig, NULL);
  dbus_message_unref(sig);
}

static void sni_emit_host_registered(DBusConnection *conn) {
  DBusMessage *sig = dbus_message_new_signal(SNI_WATCHER_PATH, SNI_WATCHER_IFACE,
                                             "StatusNotifierHostRegistered");
  if (!sig) {
    return;
  }
  dbus_connection_send(conn, sig, NULL);
  dbus_message_unref(sig);
}

static DBusMessage *sni_reply_registered_items(DBusMessage *msg, struct nizam_dock_sni *sni) {
  DBusMessage *reply = dbus_message_new_method_return(msg);
  if (!reply) {
    return NULL;
  }
  DBusMessageIter iter;
  dbus_message_iter_init_append(reply, &iter);
  DBusMessageIter array;
  dbus_message_iter_open_container(&iter, DBUS_TYPE_ARRAY, "s", &array);
  for (size_t i = 0; i < sni->count; ++i) {
    const char *service = sni->items[i].service;
    dbus_message_iter_append_basic(&array, DBUS_TYPE_STRING, &service);
  }
  dbus_message_iter_close_container(&iter, &array);
  return reply;
}

static DBusMessage *sni_handle_properties_get(DBusMessage *msg, struct nizam_dock_sni *sni) {
  const char *iface = NULL;
  const char *prop = NULL;
  if (!dbus_message_get_args(msg, NULL,
                             DBUS_TYPE_STRING, &iface,
                             DBUS_TYPE_STRING, &prop,
                             DBUS_TYPE_INVALID)) {
    return NULL;
  }
  if (!iface || strcmp(iface, SNI_WATCHER_IFACE) != 0) {
    return NULL;
  }
  DBusMessage *reply = dbus_message_new_method_return(msg);
  if (!reply) {
    return NULL;
  }
  DBusMessageIter iter;
  dbus_message_iter_init_append(reply, &iter);
  DBusMessageIter variant;
  if (strcmp(prop, "IsStatusNotifierHostRegistered") == 0) {
    dbus_message_iter_open_container(&iter, DBUS_TYPE_VARIANT, "b", &variant);
    dbus_bool_t val = 1;
    dbus_message_iter_append_basic(&variant, DBUS_TYPE_BOOLEAN, &val);
  } else if (strcmp(prop, "ProtocolVersion") == 0) {
    dbus_message_iter_open_container(&iter, DBUS_TYPE_VARIANT, "i", &variant);
    int32_t val = 0;
    dbus_message_iter_append_basic(&variant, DBUS_TYPE_INT32, &val);
  } else if (strcmp(prop, "RegisteredStatusNotifierItems") == 0) {
    dbus_message_iter_open_container(&iter, DBUS_TYPE_VARIANT, "as", &variant);
    DBusMessageIter array;
    dbus_message_iter_open_container(&variant, DBUS_TYPE_ARRAY, "s", &array);
    for (size_t i = 0; i < sni->count; ++i) {
      const char *service = sni->items[i].service;
      dbus_message_iter_append_basic(&array, DBUS_TYPE_STRING, &service);
    }
    dbus_message_iter_close_container(&variant, &array);
  } else {
    dbus_message_unref(reply);
    return NULL;
  }
  dbus_message_iter_close_container(&iter, &variant);
  return reply;
}

static DBusMessage *sni_handle_properties_get_all(DBusMessage *msg, struct nizam_dock_sni *sni) {
  const char *iface = NULL;
  if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_STRING, &iface, DBUS_TYPE_INVALID)) {
    return NULL;
  }
  if (!iface || strcmp(iface, SNI_WATCHER_IFACE) != 0) {
    return NULL;
  }
  DBusMessage *reply = dbus_message_new_method_return(msg);
  if (!reply) {
    return NULL;
  }
  DBusMessageIter iter;
  dbus_message_iter_init_append(reply, &iter);
  DBusMessageIter dict;
  dbus_message_iter_open_container(&iter, DBUS_TYPE_ARRAY, "{sv}", &dict);

  DBusMessageIter entry;
  DBusMessageIter variant;
  const char *key = "IsStatusNotifierHostRegistered";
  dbus_message_iter_open_container(&dict, DBUS_TYPE_DICT_ENTRY, NULL, &entry);
  dbus_message_iter_append_basic(&entry, DBUS_TYPE_STRING, &key);
  dbus_message_iter_open_container(&entry, DBUS_TYPE_VARIANT, "b", &variant);
  dbus_bool_t host = 1;
  dbus_message_iter_append_basic(&variant, DBUS_TYPE_BOOLEAN, &host);
  dbus_message_iter_close_container(&entry, &variant);
  dbus_message_iter_close_container(&dict, &entry);

  key = "ProtocolVersion";
  dbus_message_iter_open_container(&dict, DBUS_TYPE_DICT_ENTRY, NULL, &entry);
  dbus_message_iter_append_basic(&entry, DBUS_TYPE_STRING, &key);
  dbus_message_iter_open_container(&entry, DBUS_TYPE_VARIANT, "i", &variant);
  int32_t ver = 0;
  dbus_message_iter_append_basic(&variant, DBUS_TYPE_INT32, &ver);
  dbus_message_iter_close_container(&entry, &variant);
  dbus_message_iter_close_container(&dict, &entry);

  key = "RegisteredStatusNotifierItems";
  dbus_message_iter_open_container(&dict, DBUS_TYPE_DICT_ENTRY, NULL, &entry);
  dbus_message_iter_append_basic(&entry, DBUS_TYPE_STRING, &key);
  dbus_message_iter_open_container(&entry, DBUS_TYPE_VARIANT, "as", &variant);
  DBusMessageIter array;
  dbus_message_iter_open_container(&variant, DBUS_TYPE_ARRAY, "s", &array);
  for (size_t i = 0; i < sni->count; ++i) {
    const char *service = sni->items[i].service;
    dbus_message_iter_append_basic(&array, DBUS_TYPE_STRING, &service);
  }
  dbus_message_iter_close_container(&variant, &array);
  dbus_message_iter_close_container(&entry, &variant);
  dbus_message_iter_close_container(&dict, &entry);

  dbus_message_iter_close_container(&iter, &dict);
  return reply;
}

static DBusHandlerResult sni_message_handler(DBusConnection *conn,
                                             DBusMessage *msg,
                                             void *user_data) {
  struct nizam_dock_app *app = user_data;
  struct nizam_dock_sni *sni = app ? app->sni : NULL;
  if (!sni) {
    return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
  }

  if (dbus_message_is_method_call(msg, SNI_WATCHER_IFACE, "RegisterStatusNotifierItem")) {
    const char *arg = NULL;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_STRING, &arg, DBUS_TYPE_INVALID)) {
      return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
    }
    const char *sender = dbus_message_get_sender(msg);
    if (!sender) {
      return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
    }
    char service[128] = "";
    char path[128] = "/StatusNotifierItem";
    if (arg && arg[0] == '/') {
      snprintf(service, sizeof(service), "%s", sender);
      snprintf(path, sizeof(path), "%s", arg);
    } else if (arg && *arg) {
      snprintf(service, sizeof(service), "%s", arg);
    } else {
      snprintf(service, sizeof(service), "%s", sender);
    }

    char owner[128] = "";
    if (!sni_get_owner(conn, service, owner, sizeof(owner))) {
      snprintf(owner, sizeof(owner), "%s", sender);
    }

    struct nizam_dock_sni_item *item = sni_find_by_service(sni, service);
    if (!item) {
      if (!sni_ensure_capacity(sni)) {
        return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
      }
      item = &sni->items[sni->count++];
      memset(item, 0, sizeof(*item));
      snprintf(item->service, sizeof(item->service), "%s", service);
    }
    snprintf(item->owner, sizeof(item->owner), "%s", owner);
    snprintf(item->path, sizeof(item->path), "%s", path);
    if (sni_refresh_item(conn, item)) {
      sni_set_dirty(sni);
    } else {
      if (nizam_dock_debug_enabled()) {
        fprintf(stderr, "nizam-dock: sni icon missing for %s (%s)\n",
                item->service, item->path);
      }
    }
    sni_emit_item_registered(conn, item->service);

    DBusMessage *reply = dbus_message_new_method_return(msg);
    if (reply) {
      dbus_connection_send(conn, reply, NULL);
      dbus_message_unref(reply);
    }
    return DBUS_HANDLER_RESULT_HANDLED;
  }

  if (dbus_message_is_method_call(msg, SNI_WATCHER_IFACE, "RegisterStatusNotifierHost")) {
    DBusMessage *reply = dbus_message_new_method_return(msg);
    if (reply) {
      dbus_connection_send(conn, reply, NULL);
      dbus_message_unref(reply);
    }
    return DBUS_HANDLER_RESULT_HANDLED;
  }

  if (dbus_message_is_method_call(msg, "org.freedesktop.DBus.Properties", "Get")) {
    DBusMessage *reply = sni_handle_properties_get(msg, sni);
    if (reply) {
      dbus_connection_send(conn, reply, NULL);
      dbus_message_unref(reply);
      return DBUS_HANDLER_RESULT_HANDLED;
    }
  }

  if (dbus_message_is_method_call(msg, "org.freedesktop.DBus.Properties", "GetAll")) {
    DBusMessage *reply = sni_handle_properties_get_all(msg, sni);
    if (reply) {
      dbus_connection_send(conn, reply, NULL);
      dbus_message_unref(reply);
      return DBUS_HANDLER_RESULT_HANDLED;
    }
  }

  if (dbus_message_is_method_call(msg, SNI_WATCHER_IFACE, "GetRegisteredStatusNotifierItems")) {
    DBusMessage *reply = sni_reply_registered_items(msg, sni);
    if (reply) {
      dbus_connection_send(conn, reply, NULL);
      dbus_message_unref(reply);
      return DBUS_HANDLER_RESULT_HANDLED;
    }
  }

  return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
}

static DBusHandlerResult sni_signal_filter(DBusConnection *conn,
                                           DBusMessage *msg,
                                           void *user_data) {
  struct nizam_dock_app *app = user_data;
  struct nizam_dock_sni *sni = app ? app->sni : NULL;
  if (!sni) {
    return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
  }

  if (dbus_message_is_signal(msg, "org.freedesktop.DBus", "NameOwnerChanged")) {
    const char *name = NULL;
    const char *old_owner = NULL;
    const char *new_owner = NULL;
    if (dbus_message_get_args(msg, NULL,
                              DBUS_TYPE_STRING, &name,
                              DBUS_TYPE_STRING, &old_owner,
                              DBUS_TYPE_STRING, &new_owner,
                              DBUS_TYPE_INVALID)) {
      if (old_owner && *old_owner && (!new_owner || !*new_owner)) {
        sni_remove_by_owner(sni, old_owner);
      }
    }
    return DBUS_HANDLER_RESULT_HANDLED;
  }

  if (dbus_message_is_signal(msg, SNI_ITEM_IFACE, "NewIcon") ||
      dbus_message_is_signal(msg, SNI_ITEM_IFACE, "NewAttentionIcon") ||
      dbus_message_is_signal(msg, SNI_ITEM_IFACE, "NewOverlayIcon") ||
      dbus_message_is_signal(msg, SNI_ITEM_IFACE, "NewStatus")) {
    const char *sender = dbus_message_get_sender(msg);
    struct nizam_dock_sni_item *item = sni_find_by_owner(sni, sender);
    if (item && sni_refresh_item(conn, item)) {
      sni_set_dirty(sni);
    }
    return DBUS_HANDLER_RESULT_HANDLED;
  }

  return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
}

int nizam_dock_sni_init(struct nizam_dock_app *app) {
  if (!app) {
    return -1;
  }
  DBusError err;
  dbus_error_init(&err);
  DBusConnection *conn = dbus_bus_get(DBUS_BUS_SESSION, &err);
  if (!conn) {
    dbus_error_free(&err);
    return -1;
  }
  dbus_connection_set_exit_on_disconnect(conn, 0);

  int request = dbus_bus_request_name(conn, SNI_WATCHER_BUS,
                                      DBUS_NAME_FLAG_REPLACE_EXISTING |
                                        DBUS_NAME_FLAG_DO_NOT_QUEUE,
                                      &err);
  if (request != DBUS_REQUEST_NAME_REPLY_PRIMARY_OWNER &&
      request != DBUS_REQUEST_NAME_REPLY_ALREADY_OWNER) {
    if (nizam_dock_debug_enabled()) {
      fprintf(stderr, "nizam-dock: sni watcher busy: %s\n",
              err.message ? err.message : "unknown error");
    }
    dbus_error_free(&err);
    return -1;
  }
  dbus_error_free(&err);

  struct nizam_dock_sni *sni = calloc(1, sizeof(*sni));
  if (!sni) {
    return -1;
  }
  sni->conn = conn;
  sni->fd = -1;
  if (!dbus_connection_get_unix_fd(conn, &sni->fd)) {
    sni->fd = -1;
    if (nizam_dock_debug_enabled()) {
      fprintf(stderr, "nizam-dock: sni no unix fd, polling fallback enabled\n");
    }
  } else if (nizam_dock_debug_enabled()) {
    fprintf(stderr, "nizam-dock: sni unix fd=%d\n", sni->fd);
  }

  static const DBusObjectPathVTable vtable = {
    .message_function = sni_message_handler
  };
  if (!dbus_connection_register_object_path(conn, SNI_WATCHER_PATH, &vtable, app)) {
    free(sni);
    return -1;
  }

  dbus_connection_add_filter(conn, sni_signal_filter, app, NULL);
  dbus_bus_add_match(conn,
                     "type='signal',sender='org.freedesktop.DBus',"
                     "interface='org.freedesktop.DBus',member='NameOwnerChanged'",
                     NULL);
  dbus_bus_add_match(conn,
                     "type='signal',interface='org.kde.StatusNotifierItem',member='NewIcon'",
                     NULL);
  dbus_bus_add_match(conn,
                     "type='signal',interface='org.kde.StatusNotifierItem',member='NewAttentionIcon'",
                     NULL);
  dbus_bus_add_match(conn,
                     "type='signal',interface='org.kde.StatusNotifierItem',member='NewOverlayIcon'",
                     NULL);
  dbus_bus_add_match(conn,
                     "type='signal',interface='org.kde.StatusNotifierItem',member='NewStatus'",
                     NULL);

  app->sni = sni;
  sni_emit_host_registered(conn);
  return 0;
}

void nizam_dock_sni_cleanup(struct nizam_dock_app *app) {
  if (!app || !app->sni) {
    return;
  }
  struct nizam_dock_sni *sni = app->sni;
  for (size_t i = 0; i < sni->count; ++i) {
    sni_item_clear_full(&sni->items[i]);
  }
  free(sni->items);
  sni->items = NULL;
  sni->count = 0;
  sni->cap = 0;
  app->sni = NULL;
  free(sni);
}

int nizam_dock_sni_get_fd(const struct nizam_dock_app *app) {
  if (!app || !app->sni) {
    return -1;
  }
  return app->sni->fd;
}

int nizam_dock_sni_process(struct nizam_dock_app *app) {
  if (!app || !app->sni) {
    return 0;
  }
  struct nizam_dock_sni *sni = app->sni;
  sni->dirty = 0;
  dbus_connection_read_write_dispatch(sni->conn, 0);
  while (dbus_connection_dispatch(sni->conn) == DBUS_DISPATCH_DATA_REMAINS) {
  }
  return sni->dirty;
}

size_t nizam_dock_sni_count(const struct nizam_dock_app *app) {
  if (!app || !app->sni) {
    return 0;
  }
  return app->sni->count;
}

cairo_surface_t *nizam_dock_sni_icon(const struct nizam_dock_app *app, size_t idx) {
  if (!app || !app->sni || idx >= app->sni->count) {
    return NULL;
  }
  return app->sni->items[idx].icon;
}

int nizam_dock_sni_activate(struct nizam_dock_app *app, size_t idx, int x, int y) {
  if (!app || !app->sni || idx >= app->sni->count) {
    return 0;
  }
  struct nizam_dock_sni_item *item = &app->sni->items[idx];
  return sni_call_method(app->sni, item, SNI_ITEM_IFACE, "Activate", item->path, x, y);
}

int nizam_dock_sni_secondary_activate(struct nizam_dock_app *app, size_t idx, int x, int y) {
  if (!app || !app->sni || idx >= app->sni->count) {
    return 0;
  }
  struct nizam_dock_sni_item *item = &app->sni->items[idx];
  int ok = sni_call_method(app->sni, item, SNI_ITEM_IFACE, "SecondaryActivate", item->path, x, y);
  if (nizam_dock_debug_enabled()) {
    fprintf(stderr, "nizam-dock: sni SecondaryActivate %s\n", ok ? "ok" : "failed");
  }
  return ok;
}

int nizam_dock_sni_xayatana_secondary(struct nizam_dock_app *app, size_t idx, uint32_t time) {
  if (!app || !app->sni || idx >= app->sni->count) {
    return 0;
  }
  struct nizam_dock_sni_item *item = &app->sni->items[idx];
  DBusMessage *msg = dbus_message_new_method_call(
      item->service, item->path, SNI_ITEM_IFACE, "XAyatanaSecondaryActivate");
  if (!msg) {
    return 0;
  }
  dbus_message_append_args(msg, DBUS_TYPE_UINT32, &time, DBUS_TYPE_INVALID);
  DBusMessage *reply = dbus_connection_send_with_reply_and_block(
      app->sni->conn, msg, 500, NULL);
  dbus_message_unref(msg);
  if (!reply) {
    if (nizam_dock_debug_enabled()) {
      fprintf(stderr, "nizam-dock: sni method XAyatanaSecondaryActivate failed (%s %s)\n",
              item->service, item->path);
    }
    return 0;
  }
  dbus_message_unref(reply);
  dbus_connection_flush(app->sni->conn);
  if (nizam_dock_debug_enabled()) {
    fprintf(stderr, "nizam-dock: sni XAyatanaSecondaryActivate ok\n");
  }
  return 1;
}

int nizam_dock_sni_scroll(struct nizam_dock_app *app, size_t idx, int delta, const char *orientation) {
  if (!app || !app->sni || idx >= app->sni->count) {
    return 0;
  }
  struct nizam_dock_sni_item *item = &app->sni->items[idx];
  DBusMessage *msg = dbus_message_new_method_call(
      item->service, item->path, SNI_ITEM_IFACE, "Scroll");
  if (!msg) {
    return 0;
  }
  dbus_message_append_args(msg,
                           DBUS_TYPE_INT32, &delta,
                           DBUS_TYPE_STRING, &orientation,
                           DBUS_TYPE_INVALID);
  DBusMessage *reply = dbus_connection_send_with_reply_and_block(
      app->sni->conn, msg, 500, NULL);
  dbus_message_unref(msg);
  if (!reply) {
    if (nizam_dock_debug_enabled()) {
      fprintf(stderr, "nizam-dock: sni method Scroll failed (%s %s)\n",
              item->service, item->path);
    }
    return 0;
  }
  dbus_message_unref(reply);
  dbus_connection_flush(app->sni->conn);
  return 1;
}

int nizam_dock_sni_context_menu(struct nizam_dock_app *app, size_t idx, int x, int y) {
  if (!app || !app->sni || idx >= app->sni->count) {
    return 0;
  }
  struct nizam_dock_sni_item *item = &app->sni->items[idx];
  return sni_call_method(app->sni, item, SNI_ITEM_IFACE, "ContextMenu", item->path, x, y);
}

int nizam_dock_sni_item_has_activate(const struct nizam_dock_app *app, size_t idx) {
  if (!app || !app->sni || idx >= app->sni->count) {
    return 0;
  }
  return app->sni->items[idx].has_activate;
}

int nizam_dock_sni_item_has_secondary(const struct nizam_dock_app *app, size_t idx) {
  if (!app || !app->sni || idx >= app->sni->count) {
    return 0;
  }
  return app->sni->items[idx].has_secondary;
}

int nizam_dock_sni_item_has_context(const struct nizam_dock_app *app, size_t idx) {
  if (!app || !app->sni || idx >= app->sni->count) {
    return 0;
  }
  return app->sni->items[idx].has_context;
}

int nizam_dock_sni_item_has_xayatana_secondary(const struct nizam_dock_app *app, size_t idx) {
  if (!app || !app->sni || idx >= app->sni->count) {
    return 0;
  }
  return app->sni->items[idx].has_xayatana_secondary;
}

int nizam_dock_sni_item_is_menu(const struct nizam_dock_app *app, size_t idx) {
  if (!app || !app->sni || idx >= app->sni->count) {
    return 0;
  }
  return app->sni->items[idx].item_is_menu;
}

int nizam_dock_sni_item_has_menu(const struct nizam_dock_app *app, size_t idx) {
  if (!app || !app->sni || idx >= app->sni->count) {
    return 0;
  }
  return app->sni->items[idx].menu_path[0] != '\0';
}

static int menu_builder_push(struct nizam_dock_menu_item **items,
                             size_t *count,
                             size_t *cap,
                             const struct nizam_dock_menu_item *item_in) {
  if (!items || !count || !cap || !item_in) {
    return 0;
  }
  if (*cap == 0) {
    *cap = 8;
    *items = calloc(*cap, sizeof(**items));
  } else if (*count >= *cap) {
    *cap *= 2;
    struct nizam_dock_menu_item *next = realloc(*items, *cap * sizeof(**items));
    if (!next) {
      return 0;
    }
    *items = next;
  }
  if (!*items) {
    return 0;
  }
  (*items)[(*count)++] = *item_in;
  return 1;
}

static void menu_parse_node(DBusMessageIter *node,
                            int level,
                            struct nizam_dock_menu_item **items,
                            size_t *count,
                            size_t *cap) {
  if (!node || level > 4) {
    return;
  }
  DBusMessageIter cur = *node;
  int32_t id = 0;
  dbus_message_iter_get_basic(&cur, &id);
  dbus_message_iter_next(&cur);
  struct nizam_dock_menu_item item_out = {0};
  item_out.id = id;
  item_out.enabled = 1;
  item_out.level = level;
  if (dbus_message_iter_get_arg_type(&cur) == DBUS_TYPE_ARRAY) {
    DBusMessageIter props_iter;
    dbus_message_iter_recurse(&cur, &props_iter);
    while (dbus_message_iter_get_arg_type(&props_iter) == DBUS_TYPE_DICT_ENTRY) {
      DBusMessageIter entry;
      dbus_message_iter_recurse(&props_iter, &entry);
      const char *key = NULL;
      dbus_message_iter_get_basic(&entry, &key);
      dbus_message_iter_next(&entry);
      if (dbus_message_iter_get_arg_type(&entry) == DBUS_TYPE_VARIANT) {
        DBusMessageIter var;
        dbus_message_iter_recurse(&entry, &var);
        if (key && strcmp(key, "label") == 0 &&
            dbus_message_iter_get_arg_type(&var) == DBUS_TYPE_STRING) {
          const char *label = NULL;
          dbus_message_iter_get_basic(&var, &label);
          if (label) {
            snprintf(item_out.label, sizeof(item_out.label), "%s", label);
          }
        } else if (key && strcmp(key, "enabled") == 0 &&
                   dbus_message_iter_get_arg_type(&var) == DBUS_TYPE_BOOLEAN) {
          dbus_bool_t enabled = 1;
          dbus_message_iter_get_basic(&var, &enabled);
          item_out.enabled = enabled ? 1 : 0;
        } else if (key && strcmp(key, "visible") == 0 &&
                   dbus_message_iter_get_arg_type(&var) == DBUS_TYPE_BOOLEAN) {
          dbus_bool_t visible = 1;
          dbus_message_iter_get_basic(&var, &visible);
          if (!visible) {
            item_out.enabled = 0;
            item_out.label[0] = '\0';
            item_out.separator = 1;
          }
        } else if (key && strcmp(key, "type") == 0 &&
                   dbus_message_iter_get_arg_type(&var) == DBUS_TYPE_STRING) {
          const char *type = NULL;
          dbus_message_iter_get_basic(&var, &type);
          if (type && strcmp(type, "separator") == 0) {
            item_out.separator = 1;
          }
        } else if (key && strcmp(key, "children-display") == 0 &&
                   dbus_message_iter_get_arg_type(&var) == DBUS_TYPE_STRING) {
          const char *display = NULL;
          dbus_message_iter_get_basic(&var, &display);
          if (display && strcmp(display, "submenu") == 0) {
            item_out.submenu = 1;
          }
        }
      }
      dbus_message_iter_next(&props_iter);
    }
  }
  dbus_message_iter_next(&cur);
  if (id != 0) {
    menu_builder_push(items, count, cap, &item_out);
  }
  if (dbus_message_iter_get_arg_type(&cur) == DBUS_TYPE_ARRAY) {
    DBusMessageIter kids;
    dbus_message_iter_recurse(&cur, &kids);
    while (dbus_message_iter_get_arg_type(&kids) == DBUS_TYPE_STRUCT ||
           dbus_message_iter_get_arg_type(&kids) == DBUS_TYPE_VARIANT) {
      DBusMessageIter child;
      if (dbus_message_iter_get_arg_type(&kids) == DBUS_TYPE_VARIANT) {
        DBusMessageIter var;
        dbus_message_iter_recurse(&kids, &var);
        if (dbus_message_iter_get_arg_type(&var) != DBUS_TYPE_STRUCT) {
          dbus_message_iter_next(&kids);
          continue;
        }
        dbus_message_iter_recurse(&var, &child);
      } else {
        dbus_message_iter_recurse(&kids, &child);
      }
      menu_parse_node(&child, level + 1, items, count, cap);
      dbus_message_iter_next(&kids);
    }
  }
}

int nizam_dock_sni_menu_fetch(struct nizam_dock_app *app, size_t idx,
                         struct nizam_dock_menu_item **items, size_t *count) {
  if (!app || !app->sni || idx >= app->sni->count || !items || !count) {
    return 0;
  }
  struct nizam_dock_sni_item *item = &app->sni->items[idx];
  if (!item->menu_path[0]) {
    sni_fetch_menu_path(app->sni->conn, item);
  }
  if (!item->menu_path[0]) {
    if (nizam_dock_debug_enabled()) {
      fprintf(stderr, "nizam-dock: sni menu missing (Menu path empty) service=%s path=%s\n",
              item->service, item->path);
    }
    return 0;
  }
  if (nizam_dock_debug_enabled()) {
    fprintf(stderr, "nizam-dock: sni menu fetch dest=%s path=%s iface=com.canonical.dbusmenu\n",
            item->service, item->menu_path);
  }
  {
    DBusMessage *abt = dbus_message_new_method_call(
        item->service, item->menu_path,
        "com.canonical.dbusmenu", "AboutToShow");
    if (abt) {
      int32_t root_id = 0;
      dbus_message_append_args(abt, DBUS_TYPE_INT32, &root_id, DBUS_TYPE_INVALID);
      DBusMessage *abt_reply = dbus_connection_send_with_reply_and_block(
          app->sni->conn, abt, 500, NULL);
      dbus_message_unref(abt);
      if (abt_reply) {
        dbus_message_unref(abt_reply);
      }
    }
  }
  DBusMessage *msg = dbus_message_new_method_call(
      item->service, item->menu_path,
      "com.canonical.dbusmenu", "GetLayout");
  if (!msg) {
    return 0;
  }
  int32_t parent = 0;
  int32_t depth = -1;
  DBusMessageIter iter;
  dbus_message_iter_init_append(msg, &iter);
  dbus_message_iter_append_basic(&iter, DBUS_TYPE_INT32, &parent);
  dbus_message_iter_append_basic(&iter, DBUS_TYPE_INT32, &depth);
  DBusMessageIter props;
  dbus_message_iter_open_container(&iter, DBUS_TYPE_ARRAY, "s", &props);
  const char *prop_label = "label";
  const char *prop_enabled = "enabled";
  const char *prop_type = "type";
  const char *prop_visible = "visible";
  const char *prop_toggle_type = "toggle-type";
  const char *prop_toggle_state = "toggle-state";
  const char *prop_children_display = "children-display";
  dbus_message_iter_append_basic(&props, DBUS_TYPE_STRING, &prop_label);
  dbus_message_iter_append_basic(&props, DBUS_TYPE_STRING, &prop_enabled);
  dbus_message_iter_append_basic(&props, DBUS_TYPE_STRING, &prop_type);
  dbus_message_iter_append_basic(&props, DBUS_TYPE_STRING, &prop_visible);
  dbus_message_iter_append_basic(&props, DBUS_TYPE_STRING, &prop_toggle_type);
  dbus_message_iter_append_basic(&props, DBUS_TYPE_STRING, &prop_toggle_state);
  dbus_message_iter_append_basic(&props, DBUS_TYPE_STRING, &prop_children_display);
  dbus_message_iter_close_container(&iter, &props);

  DBusError err;
  dbus_error_init(&err);
  DBusMessage *reply = dbus_connection_send_with_reply_and_block(
      app->sni->conn, msg, 500, &err);
  dbus_message_unref(msg);
  if (!reply) {
    if (nizam_dock_debug_enabled()) {
      fprintf(stderr, "nizam-dock: sni menu GetLayout failed (%s %s): %s\n",
              item->service, item->menu_path,
              err.message ? err.message : "unknown");
    }
    dbus_error_free(&err);
    return 0;
  }
  DBusMessageIter riter;
  dbus_message_iter_init(reply, &riter);
  if (dbus_message_iter_get_arg_type(&riter) != DBUS_TYPE_UINT32) {
    if (nizam_dock_debug_enabled()) {
      fprintf(stderr, "nizam-dock: sni menu layout bad type=%c\n",
              dbus_message_iter_get_arg_type(&riter));
    }
    dbus_message_unref(reply);
    return 0;
  }
  if (nizam_dock_debug_enabled()) {
    uint32_t rev = 0;
    dbus_message_iter_get_basic(&riter, &rev);
    fprintf(stderr, "nizam-dock: sni menu layout revision=%u\n", rev);
  }
  dbus_message_iter_next(&riter);
  if (dbus_message_iter_get_arg_type(&riter) != DBUS_TYPE_STRUCT) {
    if (nizam_dock_debug_enabled()) {
      fprintf(stderr, "nizam-dock: sni menu layout missing struct type=%c\n",
              dbus_message_iter_get_arg_type(&riter));
    }
    dbus_message_unref(reply);
    return 0;
  }
  DBusMessageIter layout;
  dbus_message_iter_recurse(&riter, &layout);
  dbus_message_iter_next(&layout); 
  if (dbus_message_iter_get_arg_type(&layout) != DBUS_TYPE_ARRAY) {
    if (nizam_dock_debug_enabled()) {
      fprintf(stderr, "nizam-dock: sni menu layout root props type=%c\n",
              dbus_message_iter_get_arg_type(&layout));
    }
    dbus_message_unref(reply);
    return 0;
  }
  dbus_message_iter_next(&layout); 
  if (dbus_message_iter_get_arg_type(&layout) != DBUS_TYPE_ARRAY) {
    if (nizam_dock_debug_enabled()) {
      fprintf(stderr, "nizam-dock: sni menu layout children type=%c\n",
              dbus_message_iter_get_arg_type(&layout));
    }
    dbus_message_unref(reply);
    return 0;
  }
  DBusMessageIter children;
  dbus_message_iter_recurse(&layout, &children);

  struct nizam_dock_menu_item *out = NULL;
  size_t out_count = 0;
  size_t out_cap = 0;
  while (dbus_message_iter_get_arg_type(&children) == DBUS_TYPE_STRUCT ||
         dbus_message_iter_get_arg_type(&children) == DBUS_TYPE_VARIANT) {
    DBusMessageIter child;
    if (dbus_message_iter_get_arg_type(&children) == DBUS_TYPE_VARIANT) {
      DBusMessageIter var;
      dbus_message_iter_recurse(&children, &var);
      if (dbus_message_iter_get_arg_type(&var) != DBUS_TYPE_STRUCT) {
        dbus_message_iter_next(&children);
        continue;
      }
      dbus_message_iter_recurse(&var, &child);
    } else {
      dbus_message_iter_recurse(&children, &child);
    }
    menu_parse_node(&child, 0, &out, &out_count, &out_cap);
    dbus_message_iter_next(&children);
  }
  dbus_message_unref(reply);
  if (!out || out_count == 0) {
    if (nizam_dock_debug_enabled()) {
      fprintf(stderr, "nizam-dock: sni menu layout empty\n");
    }
    free(out);
    return 0;
  }
  if (nizam_dock_debug_enabled()) {
    fprintf(stderr, "nizam-dock: sni menu items=%zu\n", out_count);
    size_t limit = out_count < 5 ? out_count : 5;
    for (size_t i = 0; i < limit; ++i) {
      fprintf(stderr, "nizam-dock: sni menu item[%zu] id=%d label=%s sep=%d enabled=%d level=%d submenu=%d\n",
              i, out[i].id, out[i].label[0] ? out[i].label : "(empty)",
              out[i].separator, out[i].enabled, out[i].level, out[i].submenu);
    }
  }
  *items = out;
  *count = out_count;
  return 1;
}

int nizam_dock_sni_menu_event(struct nizam_dock_app *app, size_t idx, int32_t item_id, uint32_t time) {
  if (!app || !app->sni || idx >= app->sni->count) {
    return 0;
  }
  struct nizam_dock_sni_item *item = &app->sni->items[idx];
  if (!item->menu_path[0]) {
    return 0;
  }
  DBusMessage *msg = dbus_message_new_method_call(
      item->service, item->menu_path,
      "com.canonical.dbusmenu", "Event");
  if (!msg) {
    return 0;
  }
  const char *event = "clicked";
  DBusMessageIter iter;
  dbus_message_iter_init_append(msg, &iter);
  dbus_message_iter_append_basic(&iter, DBUS_TYPE_INT32, &item_id);
  dbus_message_iter_append_basic(&iter, DBUS_TYPE_STRING, &event);
  DBusMessageIter var;
  dbus_message_iter_open_container(&iter, DBUS_TYPE_VARIANT, "s", &var);
  const char *empty = "";
  dbus_message_iter_append_basic(&var, DBUS_TYPE_STRING, &empty);
  dbus_message_iter_close_container(&iter, &var);
  dbus_message_iter_append_basic(&iter, DBUS_TYPE_UINT32, &time);
  DBusMessage *reply = dbus_connection_send_with_reply_and_block(
      app->sni->conn, msg, 500, NULL);
  dbus_message_unref(msg);
  if (!reply) {
    return 0;
  }
  dbus_message_unref(reply);
  dbus_connection_flush(app->sni->conn);
  return 1;
}
