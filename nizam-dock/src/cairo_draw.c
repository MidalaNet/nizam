#include "cairo_draw.h"

#include <cairo/cairo.h>
#include <cairo/cairo-xcb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/utsname.h>
#include <unistd.h>

#include "icon_policy.h"
#include "icon_surface_cache.h"
#include "sni.h"

#define NIZAM_DOCK_CATEGORY_LABEL_HEIGHT 24
#define NIZAM_DOCK_CATEGORY_LABEL_GAP 14
#define NIZAM_DOCK_CATEGORY_ROW_GAP 10
#define NIZAM_DOCK_INFO_TRAY_GAP 14
#define NIZAM_DOCK_TRAY_SPACING 3
#define NIZAM_DOCK_TRAY_PAD 10
#define NIZAM_DOCK_TRAY_RADIUS 8.0


#define NIZAM_COLOR_BG_PRIMARY   0x2e3436u
#define NIZAM_COLOR_BG_SECONDARY 0x353a3du
#define NIZAM_COLOR_BG_BORDER    0x1c1f21u
#define NIZAM_COLOR_FG_PRIMARY   0xeeeeecu
#define NIZAM_COLOR_FG_SECONDARY 0xc0c5c9u
#define NIZAM_COLOR_FG_DISABLED  0x888a85u

static void set_source_hex(cairo_t *cr, uint32_t rgb, double a) {
  double r = ((rgb >> 16) & 0xff) / 255.0;
  double g = ((rgb >> 8) & 0xff) / 255.0;
  double b = (rgb & 0xff) / 255.0;
  cairo_set_source_rgba(cr, r, g, b, a);
}

static const char *launcher_category_key(const struct nizam_dock_launcher *launcher) {
  if (launcher && launcher->category && *launcher->category) {
    return launcher->category;
  }
  return "";
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

static const char *launcher_category_label(const struct nizam_dock_launcher *launcher) {
  if (launcher && launcher->category && *launcher->category) {
    return category_display_name(launcher->category);
  }
  return "Other";
}

static void draw_placeholder(cairo_t *cr, int x, int y, int size) {
  cairo_rectangle(cr, x, y, size, size);
  set_source_hex(cr, NIZAM_COLOR_FG_DISABLED, 0.10);
  cairo_fill_preserve(cr);
  set_source_hex(cr, NIZAM_COLOR_FG_DISABLED, 0.35);
  cairo_set_line_width(cr, 1.0);
  cairo_stroke(cr);
}

static void rounded_rect(cairo_t *cr, double x, double y, double w, double h, double r) {
  double x2 = x + w;
  double y2 = y + h;
  cairo_new_sub_path(cr);
  cairo_arc(cr, x2 - r, y + r, r, -1.5708, 0.0);
  cairo_arc(cr, x2 - r, y2 - r, r, 0.0, 1.5708);
  cairo_arc(cr, x + r, y2 - r, r, 1.5708, 3.1416);
  cairo_arc(cr, x + r, y + r, r, 3.1416, 4.7124);
  cairo_close_path(cr);
}

static void read_kernel(char *out, size_t out_size) {
  struct utsname uts;
  if (uname(&uts) == 0) {
    snprintf(out, out_size, "Linux %.72s", uts.release);
  } else {
    snprintf(out, out_size, "Linux unknown");
  }
}

static void read_cpu(char *out, size_t out_size) {
  FILE *fp = fopen("/proc/cpuinfo", "r");
  if (!fp) {
    snprintf(out, out_size, "unknown");
    return;
  }
  char line[256];
  while (fgets(line, sizeof(line), fp)) {
    if (strncmp(line, "model name", 10) == 0) {
      char *colon = strchr(line, ':');
      if (colon) {
        char *val = colon + 1;
        while (*val == ' ' || *val == '\t') {
          ++val;
        }
        size_t len = strcspn(val, "\n");
        if (len >= out_size) {
          len = out_size - 1;
        }
        memcpy(out, val, len);
        out[len] = '\0';
        fclose(fp);
        return;
      }
    }
  }
  fclose(fp);
  snprintf(out, out_size, "unknown");
}

static void read_xversion(char *out, size_t out_size, const struct nizam_dock_app *app) {
  const xcb_setup_t *setup = xcb_get_setup(app->conn);
  if (setup) {
    snprintf(out, out_size, "%.*s r%u",
             (int)setup->vendor_len, xcb_setup_vendor(setup), setup->release_number);
  } else {
    snprintf(out, out_size, "unknown");
  }
}

static void draw_icon(cairo_t *cr, cairo_surface_t *icon, int x, int y, int size) {
  if (!icon || cairo_surface_status(icon) != CAIRO_STATUS_SUCCESS) {
    draw_placeholder(cr, x, y, size);
    return;
  }

  int iw = cairo_image_surface_get_width(icon);
  int ih = cairo_image_surface_get_height(icon);
  if (iw <= 0 || ih <= 0) {
    draw_placeholder(cr, x, y, size);
    return;
  }

  double scale = (double)size / (double)(iw > ih ? iw : ih);
  double dw = iw * scale;
  double dh = ih * scale;

  cairo_save(cr);
  cairo_translate(cr, x + (size - dw) / 2.0, y + (size - dh) / 2.0);
  cairo_scale(cr, scale, scale);
  cairo_set_source_surface(cr, icon, 0, 0);
  cairo_paint(cr);
  cairo_restore(cr);
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

int nizam_dock_icons_init(struct nizam_dock_app *app, const struct nizam_dock_config *cfg) {
  if (!app || !cfg) {
    return -1;
  }
  nizam_dock_debug_log("icons init start");
  if (!app->icon_cache) {
    app->icon_cache = nizam_dock_icon_cache_new(NIZAM_DOCK_ICON_CACHE_CAP,
                                                NIZAM_DOCK_ICON_PX,
                                                NIZAM_DOCK_ICON_SCALE);
  } else {
    nizam_dock_icon_cache_clear(app->icon_cache);
  }
  nizam_dock_debug_log("icons init done");
  return 0;
}

void nizam_dock_icons_free(struct nizam_dock_app *app) {
  if (!app || !app->icon_cache) {
    return;
  }
  nizam_dock_icon_cache_free(app->icon_cache);
  app->icon_cache = NULL;
}

int nizam_dock_sysinfo_init(struct nizam_dock_app *app) {
  if (!app) {
    return -1;
  }
  read_kernel(app->sysinfo_lines[0], sizeof(app->sysinfo_lines[0]));
  read_xversion(app->sysinfo_lines[1], sizeof(app->sysinfo_lines[1]), app);
  read_cpu(app->sysinfo_lines[2], sizeof(app->sysinfo_lines[2]));
  return 0;
}

int nizam_dock_draw(struct nizam_dock_app *app, const struct nizam_dock_config *cfg) {
  nizam_dock_debug_log("draw start");
  if (app->have_root_pixmap) {
    int src_x = app->x_visible;
    if (src_x < 0) {
      src_x = 0;
    }
    if (src_x + app->panel_w > app->screen->width_in_pixels) {
      src_x = app->screen->width_in_pixels - app->panel_w;
      if (src_x < 0) {
        src_x = 0;
      }
    }
    xcb_copy_area(app->conn, app->root_pixmap, app->buffer, app->gc,
                  src_x, app->panel_y, 0, 0, app->panel_w, app->panel_h);
  }

  cairo_surface_t *surface = cairo_xcb_surface_create(app->conn, app->buffer,
                                                      app->visual_type,
                                                      app->panel_w, app->panel_h);
  if (cairo_surface_status(surface) != CAIRO_STATUS_SUCCESS) {
    nizam_dock_debug_log("draw surface create failed");
    cairo_surface_destroy(surface);
    return -1;
  }

  cairo_t *cr = cairo_create(surface);
  if (app->have_root_pixmap) {
    
    
    double a = cfg ? cfg->bg_dim : 0.80;
    if (a < 0.0) a = 0.0;
    if (a > 1.0) a = 1.0;
    set_source_hex(cr, NIZAM_COLOR_BG_PRIMARY, a);
  } else {
    
    set_source_hex(cr, NIZAM_COLOR_BG_PRIMARY, 1.0);
  }
  cairo_paint(cr);

  rounded_rect(cr, 0.5, 0.5, app->panel_w - 1.0, app->panel_h - 1.0, 6.0);
  set_source_hex(cr, NIZAM_COLOR_BG_BORDER, 1.0);
  cairo_set_line_width(cr, 1.0);
  cairo_stroke(cr);

  size_t count = cfg->launcher_count;
  if (app->launcher_rect_count != count) {
    free(app->launcher_rects);
    app->launcher_rects = NULL;
    app->launcher_rect_count = 0;
    if (count > 0) {
      app->launcher_rects = calloc(count, sizeof(*app->launcher_rects));
      if (app->launcher_rects) {
        app->launcher_rect_count = count;
      }
    }
  }

  int x = cfg->padding;
  int y = cfg->padding;
  int info_y = y;
  cairo_select_font_face(cr, "Sans", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL);
  cairo_set_font_size(cr, 12.0);
  set_source_hex(cr, NIZAM_COLOR_FG_SECONDARY, 1.0);
  for (int i = 0; i < NIZAM_DOCK_INFO_LINES; ++i) {
    cairo_move_to(cr, x, info_y + NIZAM_DOCK_INFO_LINE_HEIGHT);
    cairo_show_text(cr, app->sysinfo_lines[i]);
    info_y += NIZAM_DOCK_INFO_LINE_HEIGHT + NIZAM_DOCK_INFO_LINE_GAP;
  }
  y = info_y + NIZAM_DOCK_INFO_TOP_GAP;

  if (count > 0) {
    cairo_select_font_face(cr, "Sans", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD);
    cairo_set_font_size(cr, 12.0);
    size_t i = 0;
    while (i < count) {
      const char *cat_key = launcher_category_key(&cfg->launchers[i]);
      const char *cat_label = launcher_category_label(&cfg->launchers[i]);
      size_t group_start = i;
      while (i < count &&
             strcasecmp(launcher_category_key(&cfg->launchers[i]), cat_key) == 0) {
        i += 1;
      }
      size_t group_count = i - group_start;

      set_source_hex(cr, NIZAM_COLOR_FG_PRIMARY, 1.0);
      cairo_set_font_size(cr, 17.0);
      cairo_move_to(cr, x, y + NIZAM_DOCK_CATEGORY_LABEL_HEIGHT);
      cairo_show_text(cr, cat_label);
      y += NIZAM_DOCK_CATEGORY_LABEL_HEIGHT + NIZAM_DOCK_CATEGORY_LABEL_GAP;

      int row_x = x;
      for (size_t j = 0; j < group_count; ++j) {
        size_t idx = group_start + j;
        cairo_surface_t *icon = NULL;
        if (app->icon_cache && idx < cfg->launcher_count) {
          const char *name = cfg->launchers[idx].icon;
          if (name && *name) {
            icon = nizam_dock_icon_cache_get(app->icon_cache, name);
          }
        }
        draw_icon(cr, icon, row_x, y, NIZAM_DOCK_ICON_PX);
        if (idx < app->launcher_rect_count) {
          app->launcher_rects[idx].x = row_x;
          app->launcher_rects[idx].y = y;
          app->launcher_rects[idx].w = NIZAM_DOCK_ICON_PX;
          app->launcher_rects[idx].h = NIZAM_DOCK_ICON_PX;
        }
        row_x += NIZAM_DOCK_ICON_PX + cfg->spacing;
      }
      y += NIZAM_DOCK_ICON_PX + cfg->spacing + NIZAM_DOCK_CATEGORY_ROW_GAP;
    }
  }

  size_t sni_count = nizam_dock_sni_count(app);
  size_t xembed_count = app->xembed_count;
  size_t tray_count = sni_count + xembed_count;
  int tray_size = 0;
  int tray_y = 0;

  if (tray_count > 0) {
    const int bottom_gap = (cfg->padding > 2) ? cfg->padding : 2;
    tray_size = 24;
    int tray_total_w = (int)tray_count * tray_size;
    if (tray_count > 1) {
      tray_total_w += (int)(tray_count - 1) * NIZAM_DOCK_TRAY_SPACING;
    }
    if (tray_total_w > 0) {
      int cart_w = tray_total_w + NIZAM_DOCK_TRAY_PAD * 2;
      int cart_h = tray_size + NIZAM_DOCK_TRAY_PAD * 2;
      int cart_x = app->panel_w - cfg->padding - cart_w;
      int cart_y = app->panel_h - bottom_gap - cart_h;
      if (cart_x < 0) {
        cart_x = 0;
      }
      if (cart_y < 0) {
        cart_y = 0;
      }
      if (cart_x + cart_w > app->panel_w) {
        cart_w = app->panel_w - cart_x;
      }
      if (cart_y + cart_h > app->panel_h) {
        cart_h = app->panel_h - cart_y;
      }

      tray_y = cart_y + NIZAM_DOCK_TRAY_PAD;
      if (tray_y < 0) {
        tray_y = 0;
      }
      if (tray_y + tray_size > app->panel_h) {
        tray_y = app->panel_h - tray_size;
        if (tray_y < 0) {
          tray_y = 0;
        }
      }

      app->tray_count = sni_count;
      app->tray_size = tray_size;
      app->xembed_size = tray_size;
      app->tray_y = tray_y;
      app->xembed_y = tray_y;

      cairo_save(cr);
      rounded_rect(cr, cart_x + 0.5, cart_y + 0.5,
                   cart_w - 1.0, cart_h - 1.0, NIZAM_DOCK_TRAY_RADIUS);
      
      set_source_hex(cr, NIZAM_COLOR_BG_SECONDARY, 1.0);
      cairo_fill_preserve(cr);
      set_source_hex(cr, NIZAM_COLOR_BG_BORDER, 1.0);
      cairo_set_line_width(cr, 1.0);
      cairo_stroke(cr);
      cairo_restore(cr);
      int total_icons = (int)tray_count;
      int gap = NIZAM_DOCK_TRAY_SPACING;
      app->tray_gap = gap;
      app->xembed_gap = gap;
      int content_w = total_icons * tray_size + (total_icons - 1) * gap;
      int start_x = cart_x + (cart_w - content_w) / 2;
      if (start_x < 0) {
        start_x = 0;
      }
      if (start_x + content_w > app->panel_w) {
        start_x = app->panel_w - content_w;
        if (start_x < 0) {
          start_x = 0;
        }
      }
      int xembed_w = 0;
      if (xembed_count > 0) {
        xembed_w = (int)xembed_count * tray_size +
                   (int)(xembed_count - 1) * gap;
      }
      app->xembed_x = start_x;
      app->tray_x = start_x + xembed_w;
      if (xembed_count > 0 && sni_count > 0) {
        app->tray_x += gap;
      }
      int tx = app->tray_x;
      for (size_t i = 0; i < sni_count; ++i) {
        draw_icon(cr, nizam_dock_sni_icon(app, i), tx, tray_y, tray_size);
        tx += tray_size + gap;
      }
      nizam_dock_xembed_layout(app, cfg);
      goto tray_done;
    }
  } else {
    app->tray_count = 0;
    app->tray_size = 0;
    app->tray_x = 0;
    app->tray_y = 0;
    app->tray_gap = 0;
    app->xembed_x = 0;
    app->xembed_y = 0;
    app->xembed_size = 0;
    app->xembed_gap = 0;
  }

tray_done:

  cairo_destroy(cr);
  cairo_surface_flush(surface);
  cairo_surface_destroy(surface);
  xcb_copy_area(app->conn, app->buffer, app->window, app->gc,
                0, 0, 0, 0, app->panel_w, app->panel_h);
  xcb_flush(app->conn);

  nizam_dock_debug_log("draw done");
  return 0;
}
