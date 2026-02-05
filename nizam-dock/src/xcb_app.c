#define _POSIX_C_SOURCE 200809L
#include "xcb_app.h"

#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/types.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

#include <cairo/cairo.h>
#include <cairo/cairo-xcb.h>

#include <xcb/randr.h>

#include "cairo_draw.h"
#include "icon_surface_cache.h"
#include "icon_policy.h"
#include "sni.h"

#define SYSTEM_TRAY_REQUEST_DOCK 0
#define XEMBED_EMBEDDED_NOTIFY 0


#define NIZAM_DOCK_TRAY_BG_PIXEL 0x353a3du

static int64_t now_ms(void);

static int nizam_dock_debug_enabled(void) {
  const char *env = getenv("NIZAM_DOCK_DEBUG");
  return env && *env && strcmp(env, "0") != 0;
}

static int nizam_dock_debug_events_enabled(void) {
  const char *env = getenv("NIZAM_DOCK_DEBUG");
  return env && *env && strcmp(env, "0") != 0;
}

static int nizam_dock_debug_mem_enabled(void) {
  const char *env = getenv("NIZAM_DOCK_DEBUG_MEM");
  return env && *env && strcmp(env, "0") != 0;
}

static void nizam_dock_debug_log(const char *msg) {
  if (nizam_dock_debug_enabled()) {
    fprintf(stderr, "nizam-dock: %s\n", msg);
  }
}

static void handle_screen_change(struct nizam_dock_app *app, const struct nizam_dock_config *cfg);
static int show_dock(struct nizam_dock_app *app);
static int hit_test_launcher(const struct nizam_dock_app *app, int x, int y);
static int hit_test_tray(const struct nizam_dock_app *app, const struct nizam_dock_config *cfg, int x, int y);
static ssize_t xembed_find(const struct nizam_dock_app *app, xcb_window_t win);
static void xembed_add_client(struct nizam_dock_app *app, xcb_window_t win);
static void xembed_remove_client(struct nizam_dock_app *app, xcb_window_t win);
static void xembed_update_background(struct nizam_dock_app *app);
static void menu_hide(struct nizam_dock_app *app);
static void menu_draw(struct nizam_dock_app *app);
static int menu_show(struct nizam_dock_app *app, const struct nizam_dock_config *cfg,
                     size_t tray_idx, int anchor_x, int anchor_y);
static void tray_icon_root_anchor(const struct nizam_dock_app *app, int idx,
                                  int ex, int ey, int rx, int ry,
                                  int *out_x, int *out_y);
static void launch_cmd(const char *cmd);

enum redraw_reason {
  REDRAW_REASON_MOTION = 1,
  REDRAW_REASON_TIMEOUT = 2,
  REDRAW_REASON_EXPOSE = 3
};

static void schedule_redraw(struct nizam_dock_app *app, int force, enum redraw_reason reason) {
  if (!app) {
    return;
  }
  app->redraw_pending = 1;
  if (force) {
    app->redraw_force = 1;
  }
  app->redraw_total++;
  if (reason == REDRAW_REASON_MOTION) {
    app->redraw_reason_motion++;
  } else if (reason == REDRAW_REASON_TIMEOUT) {
    app->redraw_reason_timeout++;
  } else if (reason == REDRAW_REASON_EXPOSE) {
    app->redraw_reason_expose++;
  }
}

static int nizam_dock_no_autohide(void) {
  const char *env = getenv("NIZAM_DOCK_NO_AUTOHIDE");
  return env && *env && strcmp(env, "0") != 0;
}

static int query_pointer_root_xy(struct nizam_dock_app *app, int *out_x, int *out_y) {
  if (out_x) *out_x = 0;
  if (out_y) *out_y = 0;
  if (!app || !app->conn || !app->screen) {
    return 0;
  }
  xcb_query_pointer_cookie_t c = xcb_query_pointer(app->conn, app->screen->root);
  xcb_query_pointer_reply_t *r = xcb_query_pointer_reply(app->conn, c, NULL);
  if (!r) {
    return 0;
  }
  if (out_x) *out_x = r->root_x;
  if (out_y) *out_y = r->root_y;
  free(r);
  return 1;
}

static int point_in_rect(int x, int y, int rx, int ry, int rw, int rh) {
  return x >= rx && x < rx + rw && y >= ry && y < ry + rh;
}

static void dock_set_default_monitor(struct nizam_dock_app *app) {
  if (!app || !app->screen) {
    return;
  }
  app->mon_x = 0;
  app->mon_y = 0;
  app->mon_w = (int)app->screen->width_in_pixels;
  app->mon_h = (int)app->screen->height_in_pixels;
}

static void dock_pick_monitor_for_pointer(struct nizam_dock_app *app) {
  dock_set_default_monitor(app);
  if (!app || !app->conn || !app->screen) {
    return;
  }

  int px = 0;
  int py = 0;
  int have_ptr = query_pointer_root_xy(app, &px, &py);

  xcb_randr_output_t primary = XCB_NONE;
  {
    xcb_randr_get_output_primary_cookie_t pc = xcb_randr_get_output_primary(app->conn, app->screen->root);
    xcb_randr_get_output_primary_reply_t *pr = xcb_randr_get_output_primary_reply(app->conn, pc, NULL);
    if (pr) {
      primary = pr->output;
      free(pr);
    }
  }

  xcb_randr_get_screen_resources_current_cookie_t rc =
      xcb_randr_get_screen_resources_current(app->conn, app->screen->root);
  xcb_randr_get_screen_resources_current_reply_t *res =
      xcb_randr_get_screen_resources_current_reply(app->conn, rc, NULL);
  if (!res) {
    return;
  }

  int picked = 0;
  int primary_x = 0, primary_y = 0, primary_w = 0, primary_h = 0;
  int have_primary_geom = 0;

  int nout = xcb_randr_get_screen_resources_current_outputs_length(res);
  xcb_randr_output_t *outs = xcb_randr_get_screen_resources_current_outputs(res);
  for (int i = 0; i < nout; ++i) {
    xcb_randr_output_t out = outs[i];
    xcb_randr_get_output_info_cookie_t oc =
        xcb_randr_get_output_info(app->conn, out, XCB_CURRENT_TIME);
    xcb_randr_get_output_info_reply_t *oi =
        xcb_randr_get_output_info_reply(app->conn, oc, NULL);
    if (!oi) {
      continue;
    }
    if (oi->connection != XCB_RANDR_CONNECTION_CONNECTED || oi->crtc == XCB_NONE) {
      free(oi);
      continue;
    }
    xcb_randr_get_crtc_info_cookie_t cc =
        xcb_randr_get_crtc_info(app->conn, oi->crtc, XCB_CURRENT_TIME);
    xcb_randr_get_crtc_info_reply_t *ci =
        xcb_randr_get_crtc_info_reply(app->conn, cc, NULL);
    if (!ci) {
      free(oi);
      continue;
    }

    int rx = (int)ci->x;
    int ry = (int)ci->y;
    int rw = (int)ci->width;
    int rh = (int)ci->height;

    if (rw > 0 && rh > 0) {
      if (out == primary) {
        primary_x = rx;
        primary_y = ry;
        primary_w = rw;
        primary_h = rh;
        have_primary_geom = 1;
      }

      if (!picked && have_ptr && point_in_rect(px, py, rx, ry, rw, rh)) {
        app->mon_x = rx;
        app->mon_y = ry;
        app->mon_w = rw;
        app->mon_h = rh;
        picked = 1;
      }
    }

    free(ci);
    free(oi);
    if (picked) {
      break;
    }
  }

  if (!picked && have_primary_geom) {
    app->mon_x = primary_x;
    app->mon_y = primary_y;
    app->mon_w = primary_w;
    app->mon_h = primary_h;
    picked = 1;
  }

  if (nizam_dock_debug_enabled()) {
    fprintf(stderr, "nizam-dock: monitor pick ptr=%s (%d,%d) mon=%dx%d+%d+%d primary=0x%08x\n",
            have_ptr ? "yes" : "no", px, py,
            app->mon_w, app->mon_h, app->mon_x, app->mon_y,
            (unsigned)primary);
  }

  free(res);
}

static void cancel_hide_pending(struct nizam_dock_app *app) {
  if (!app) {
    return;
  }
  app->hide_pending = 0;
  app->hide_deadline_ms = 0;
}

static void schedule_hide(struct nizam_dock_app *app, const struct nizam_dock_config *cfg) {
  if (!app || !cfg) {
    return;
  }
  if (nizam_dock_no_autohide()) {
    return;
  }
  if (app->is_hidden || app->menu_visible) {
    return;
  }
  if (cfg->hide_delay_ms <= 0) {
    return;
  }
  int64_t now = now_ms();
  int64_t delay = (int64_t)cfg->hide_delay_ms;
  if (delay < 0) delay = 0;
  if (delay > 30000) delay = 30000;
  app->hide_pending = 1;
  app->hide_deadline_ms = now + delay;
}

struct nizam_dock_wm_hints {
  uint32_t flags;
  uint32_t input;
  uint32_t initial_state;
  xcb_pixmap_t icon_pixmap;
  xcb_window_t icon_window;
  int32_t icon_x;
  int32_t icon_y;
  xcb_pixmap_t icon_mask;
  xcb_window_t window_group;
};

static volatile sig_atomic_t g_reload_config = 0;

static xcb_atom_t intern_atom(xcb_connection_t *conn, const char *name) {
  xcb_intern_atom_cookie_t cookie = xcb_intern_atom(conn, 0, (uint16_t)strlen(name), name);
  xcb_intern_atom_reply_t *reply = xcb_intern_atom_reply(conn, cookie, NULL);
  if (!reply) {
    return XCB_NONE;
  }
  xcb_atom_t atom = reply->atom;
  free(reply);
  return atom;
}

static int window_has_nonzero_cardinals(xcb_connection_t *conn, xcb_window_t win,
                                        xcb_atom_t prop_atom) {
  if (!conn || win == XCB_NONE || prop_atom == XCB_NONE) {
    return 0;
  }
  xcb_get_property_cookie_t c = xcb_get_property(conn, 0, win, prop_atom,
                                                 XCB_ATOM_CARDINAL, 0, 16);
  xcb_get_property_reply_t *r = xcb_get_property_reply(conn, c, NULL);
  if (!r) {
    return 0;
  }
  int ok = 0;
  int len = xcb_get_property_value_length(r);
  if (len > 0 && (len % (int)sizeof(uint32_t)) == 0) {
    const uint32_t *vals = (const uint32_t *)xcb_get_property_value(r);
    int n = len / (int)sizeof(uint32_t);
    for (int i = 0; i < n; ++i) {
      if (vals[i] != 0) {
        ok = 1;
        break;
      }
    }
  }
  free(r);
  return ok;
}

static int window_has_type(xcb_connection_t *conn, xcb_window_t win,
                           xcb_atom_t net_wm_window_type, xcb_atom_t desired_type) {
  if (!conn || win == XCB_NONE || net_wm_window_type == XCB_NONE || desired_type == XCB_NONE) {
    return 0;
  }
  xcb_get_property_cookie_t c = xcb_get_property(conn, 0, win,
                                                 net_wm_window_type,
                                                 XCB_ATOM_ATOM, 0, 16);
  xcb_get_property_reply_t *r = xcb_get_property_reply(conn, c, NULL);
  if (!r) {
    return 0;
  }
  int ok = 0;
  int len = xcb_get_property_value_length(r);
  if (len > 0 && (len % (int)sizeof(xcb_atom_t)) == 0) {
    const xcb_atom_t *atoms = (const xcb_atom_t *)xcb_get_property_value(r);
    int n = len / (int)sizeof(xcb_atom_t);
    for (int i = 0; i < n; ++i) {
      if (atoms[i] == desired_type) {
        ok = 1;
        break;
      }
    }
  }
  free(r);
  return ok;
}

static int is_panel_candidate(struct nizam_dock_app *app,
                              xcb_window_t w,
                              xcb_atom_t net_wm_strut_partial,
                              xcb_atom_t net_wm_strut) {
  if (!app || !app->conn || !app->screen || w == XCB_NONE || w == app->window) {
    return 0;
  }

  
  int has_strut = 0;
  if (net_wm_strut_partial != XCB_NONE &&
      window_has_nonzero_cardinals(app->conn, w, net_wm_strut_partial)) {
    has_strut = 1;
  }
  if (!has_strut && net_wm_strut != XCB_NONE &&
      window_has_nonzero_cardinals(app->conn, w, net_wm_strut)) {
    has_strut = 1;
  }
  if (!has_strut) {
    return 0;
  }

  
  if (app->atoms.net_wm_window_type != XCB_NONE && app->atoms.net_wm_window_type_dock != XCB_NONE) {
    if (!window_has_type(app->conn, w, app->atoms.net_wm_window_type,
                         app->atoms.net_wm_window_type_dock)) {
      return 0;
    }
  }

  xcb_get_geometry_cookie_t gc = xcb_get_geometry(app->conn, w);
  xcb_get_geometry_reply_t *gr = xcb_get_geometry_reply(app->conn, gc, NULL);
  if (!gr) {
    return 0;
  }
  int is_panelish_height = gr->height > 0 && gr->height <= 128;
  int is_wide = gr->width >= (uint16_t)(app->screen->width_in_pixels * 3 / 4);
  free(gr);
  return is_panelish_height && is_wide;
}

static xcb_window_t find_panel_window(struct nizam_dock_app *app) {
  if (!app || !app->conn || !app->screen) {
    return XCB_NONE;
  }

  xcb_atom_t net_wm_strut_partial = intern_atom(app->conn, "_NET_WM_STRUT_PARTIAL");
  xcb_atom_t net_wm_strut = intern_atom(app->conn, "_NET_WM_STRUT");

  xcb_query_tree_cookie_t tc = xcb_query_tree(app->conn, app->screen->root);
  xcb_query_tree_reply_t *tr = xcb_query_tree_reply(app->conn, tc, NULL);
  if (!tr) {
    return XCB_NONE;
  }

  int count = xcb_query_tree_children_length(tr);
  xcb_window_t *children = xcb_query_tree_children(tr);
  xcb_window_t best = XCB_NONE;

  
  for (int i = 0; i < count; ++i) {
    if (is_panel_candidate(app, children[i], net_wm_strut_partial, net_wm_strut)) {
      best = children[i];
      break;
    }
  }

  
  if (best == XCB_NONE) {
    for (int i = 0; i < count; ++i) {
      xcb_window_t parent = children[i];
      if (parent == XCB_NONE) {
        continue;
      }
      xcb_query_tree_cookie_t tc2 = xcb_query_tree(app->conn, parent);
      xcb_query_tree_reply_t *tr2 = xcb_query_tree_reply(app->conn, tc2, NULL);
      if (!tr2) {
        continue;
      }
      int count2 = xcb_query_tree_children_length(tr2);
      xcb_window_t *children2 = xcb_query_tree_children(tr2);
      for (int j = 0; j < count2; ++j) {
        if (is_panel_candidate(app, children2[j], net_wm_strut_partial, net_wm_strut)) {
          best = children2[j];
          break;
        }
      }
      free(tr2);
      if (best != XCB_NONE) {
        break;
      }
    }
  }

  free(tr);
  return best;
}

static void notify_panel_redraw(struct nizam_dock_app *app) {
  xcb_window_t panel = find_panel_window(app);
  if (panel == XCB_NONE) {
    return;
  }
  if (nizam_dock_debug_enabled()) {
    fprintf(stderr, "nizam-dock: notify panel redraw win=0x%08x\n", (unsigned)panel);
  }

  xcb_atom_t redraw_atom = intern_atom(app->conn, "_NIZAM_PANEL_REDRAW");
  if (redraw_atom != XCB_NONE) {
    xcb_client_message_event_t msg = {0};
    msg.response_type = XCB_CLIENT_MESSAGE;
    msg.window = panel;
    msg.type = redraw_atom;
    msg.format = 32;
    msg.data.data32[0] = XCB_CURRENT_TIME;
    xcb_send_event(app->conn, 0, panel, XCB_EVENT_MASK_NO_EVENT, (char *)&msg);
    return;
  }

  
  xcb_expose_event_t ev = {0};
  ev.response_type = XCB_EXPOSE;
  ev.window = panel;
  ev.x = 0;
  ev.y = 0;
  ev.width = (uint16_t)app->screen->width_in_pixels;
  ev.height = 128;
  ev.count = 0;
  xcb_send_event(app->conn, 0, panel, XCB_EVENT_MASK_EXPOSURE, (char *)&ev);
}

static xcb_visualtype_t *find_visual_type(xcb_screen_t *screen, xcb_visualid_t visual_id) {
  xcb_depth_iterator_t depth_iter = xcb_screen_allowed_depths_iterator(screen);
  for (; depth_iter.rem; xcb_depth_next(&depth_iter)) {
    xcb_visualtype_iterator_t visual_iter = xcb_depth_visuals_iterator(depth_iter.data);
    for (; visual_iter.rem; xcb_visualtype_next(&visual_iter)) {
      if (visual_iter.data->visual_id == visual_id) {
        return visual_iter.data;
      }
    }
  }
  return NULL;
}

static void destroy_buffer(struct nizam_dock_app *app) {
  if (app->buffer) {
    xcb_free_pixmap(app->conn, app->buffer);
    app->buffer = XCB_NONE;
  }
  if (app->gc) {
    xcb_free_gc(app->conn, app->gc);
    app->gc = XCB_NONE;
  }
}

static int create_buffer(struct nizam_dock_app *app) {
  destroy_buffer(app);
  app->buffer_w = app->panel_w;
  app->buffer_h = app->panel_h;

  app->buffer = xcb_generate_id(app->conn);
  xcb_create_pixmap(app->conn, app->screen->root_depth,
                    app->buffer, app->window,
                    app->buffer_w, app->buffer_h);

  app->gc = xcb_generate_id(app->conn);
  xcb_create_gc(app->conn, app->gc, app->window, 0, NULL);

  app->backbuffer_recreates_total += 1;
  app->backbuffer_bytes = (size_t)app->buffer_w * (size_t)app->buffer_h * 4u;

  return 0;
}

void nizam_dock_request_config_reload(void) {
  g_reload_config = 1;
}

static int64_t now_ms(void) {
  struct timeval tv;
  gettimeofday(&tv, NULL);
  return (int64_t)tv.tv_sec * 1000 + (int64_t)tv.tv_usec / 1000;
}

static int read_proc_status_kb(const char *key, long *out_kb) {
  if (!key || !out_kb) {
    return 0;
  }
  *out_kb = 0;
  FILE *fp = fopen("/proc/self/status", "r");
  if (!fp) {
    return 0;
  }
  char line[256];
  size_t key_len = strlen(key);
  int found = 0;
  while (fgets(line, sizeof(line), fp)) {
    if (strncmp(line, key, key_len) == 0) {
      const char *p = line + key_len;
      while (*p == ' ' || *p == '\t' || *p == ':') {
        p++;
      }
      long val = strtol(p, NULL, 10);
      *out_kb = val;
      found = 1;
      break;
    }
  }
  fclose(fp);
  return found;
}

static void nizam_dock_log_mem_stats(struct nizam_dock_app *app) {
  if (!nizam_dock_debug_mem_enabled() || !app) {
    return;
  }
  int64_t now = now_ms();
  if (app->last_mem_log_ms && (now - app->last_mem_log_ms) < 30000) {
    return;
  }
  app->last_mem_log_ms = now;

  long rss = 0, anon = 0, file = 0, shmem = 0;
  read_proc_status_kb("VmRSS", &rss);
  read_proc_status_kb("RssAnon", &anon);
  read_proc_status_kb("RssFile", &file);
  read_proc_status_kb("RssShmem", &shmem);

  fprintf(stderr, "[dock] rss=%.1fMB anon=%.1fMB file=%.1fMB shmem=%.1fMB\n",
          rss / 1024.0, anon / 1024.0, file / 1024.0, shmem / 1024.0);

  if (app->icon_cache) {
    struct nizam_dock_icon_cache_stats stats;
    nizam_dock_icon_cache_get_stats(app->icon_cache, &stats);
    fprintf(stderr,
            "[dock] icon-cache size=%d hits=%llu misses=%llu evictions=%llu icon_px=%d scale=%d\n",
            stats.size,
            (unsigned long long)stats.hits,
            (unsigned long long)stats.misses,
            (unsigned long long)stats.evictions,
            stats.icon_px,
            stats.scale);
    fprintf(stderr,
            "[dock] surfaces_alive=%llu backbuffer=%dx%d (%.2fMB) recreates=%d\n",
            (unsigned long long)stats.alive_surfaces,
            app->buffer_w,
            app->buffer_h,
            app->backbuffer_bytes / (1024.0 * 1024.0),
            app->backbuffer_recreates_total);
  }
}

static void nizam_dock_log_event_stats(struct nizam_dock_app *app) {
  if (!nizam_dock_debug_events_enabled() || !app) {
    return;
  }
  int64_t now = now_ms();
  if (app->last_debug_log_ms && (now - app->last_debug_log_ms) < 5000) {
    return;
  }
  app->last_debug_log_ms = now;
  fprintf(stderr,
          "[dock] motion=%llu redraw=%llu hover_changes=%llu timeout_redraw=%llu expose_redraw=%llu\n",
          (unsigned long long)app->motion_events_total,
          (unsigned long long)app->redraw_total,
          (unsigned long long)app->hover_changes,
          (unsigned long long)app->redraw_reason_timeout,
          (unsigned long long)app->redraw_reason_expose);
  app->motion_events_total = 0;
  app->redraw_total = 0;
  app->hover_changes = 0;
  app->redraw_reason_motion = 0;
  app->redraw_reason_timeout = 0;
  app->redraw_reason_expose = 0;
}

static void set_dock_stack(struct nizam_dock_app *app, int above);

static void lower_dock_for_external_popup(struct nizam_dock_app *app, int64_t duration_ms) {
  if (!app || app->window == XCB_NONE || app->is_hidden) {
    return;
  }
  if (duration_ms < 0) {
    duration_ms = 0;
  }
  int64_t until = now_ms() + duration_ms;
  if (until > app->suppress_raise_until_ms) {
    app->suppress_raise_until_ms = until;
  }
  set_dock_stack(app, 0);
  xcb_flush(app->conn);
}

static void set_strip_stack(struct nizam_dock_app *app, int above) {
  if (app->strip == XCB_NONE) {
    return;
  }
  uint32_t stack_mode = above ? XCB_STACK_MODE_ABOVE : XCB_STACK_MODE_BELOW;
  xcb_configure_window(app->conn, app->strip,
                       XCB_CONFIG_WINDOW_STACK_MODE, &stack_mode);
}

static int update_hover_state(struct nizam_dock_app *app,
                              const struct nizam_dock_config *cfg,
                              int x, int y) {
  if (!app || !cfg) {
    return 0;
  }
  int new_launcher = hit_test_launcher(app, x, y);
  int new_tray = hit_test_tray(app, cfg, x, y);
  if (new_launcher == app->hovered_launcher_idx &&
      new_tray == app->hovered_tray_idx) {
    return 0;
  }
  app->hovered_launcher_idx = new_launcher;
  app->hovered_tray_idx = new_tray;
  app->hover_changes++;
  return 1;
}

static void handle_motion_event(struct nizam_dock_app *app,
                                const struct nizam_dock_config *cfg,
                                xcb_motion_notify_event_t *motion) {
  if (!app || !cfg || !motion) {
    return;
  }
  app->motion_events_total++;
  if (app->is_hidden && app->strip != XCB_NONE && motion->event == app->strip) {
    if (show_dock(app)) {
      schedule_redraw(app, 1, REDRAW_REASON_MOTION);
    }
    return;
  }
  if (motion->event == app->window) {
    if (update_hover_state(app, cfg, motion->event_x, motion->event_y)) {
      schedule_redraw(app, 0, REDRAW_REASON_MOTION);
    }
  }
}

static void process_event(struct nizam_dock_app *app,
                          const struct nizam_dock_config *cfg,
                          xcb_generic_event_t *event) {
  if (!app || !cfg || !event) {
    return;
  }
  uint8_t type = event->response_type & ~0x80;
  if (type == 0) {
    return;
  }
  switch (type) {
    case XCB_RANDR_SCREEN_CHANGE_NOTIFY:
      handle_screen_change(app, cfg);
      schedule_redraw(app, 1, REDRAW_REASON_TIMEOUT);
      break;
    case XCB_PROPERTY_NOTIFY: {
      xcb_property_notify_event_t *prop = (xcb_property_notify_event_t *)event;
      if (prop->window == app->screen->root &&
          (prop->atom == app->atoms.xrootpmap_id || prop->atom == app->atoms.xsetroot_id)) {
        if (nizam_dock_xcb_update_root_pixmap(app)) {
          schedule_redraw(app, 0, REDRAW_REASON_TIMEOUT);
        }
      }
      break;
    }
    case XCB_CLIENT_MESSAGE: {
      xcb_client_message_event_t *cm = (xcb_client_message_event_t *)event;
      if (cm->type == app->atoms.net_system_tray_opcode &&
          (cm->window == app->xembed_window || cm->window == app->window || cm->window == app->screen->root)) {
        int opcode = (int)cm->data.data32[1];
        if (opcode == SYSTEM_TRAY_REQUEST_DOCK) {
          xcb_window_t win = (xcb_window_t)cm->data.data32[2];
          if (nizam_dock_debug_enabled()) {
            fprintf(stderr, "nizam-dock: systray REQUEST_DOCK from=0x%08x icon=0x%08x\n",
                    (unsigned)cm->window, (unsigned)win);
          }
          xembed_add_client(app, win);
          handle_screen_change(app, cfg);
          schedule_redraw(app, 1, REDRAW_REASON_TIMEOUT);
        }
      }
      break;
    }
    case XCB_DESTROY_NOTIFY: {
      xcb_destroy_notify_event_t *destroy = (xcb_destroy_notify_event_t *)event;
      if (xembed_find(app, destroy->window) >= 0) {
        xembed_remove_client(app, destroy->window);
        handle_screen_change(app, cfg);
        schedule_redraw(app, 1, REDRAW_REASON_TIMEOUT);
      }
      break;
    }
    case XCB_UNMAP_NOTIFY: {
      xcb_unmap_notify_event_t *unmap = (xcb_unmap_notify_event_t *)event;
      if (xembed_find(app, unmap->window) >= 0) {
        xembed_remove_client(app, unmap->window);
        handle_screen_change(app, cfg);
        schedule_redraw(app, 1, REDRAW_REASON_TIMEOUT);
      }
      break;
    }
    case XCB_ENTER_NOTIFY: {
      xcb_enter_notify_event_t *enter = (xcb_enter_notify_event_t *)event;
      if (enter->event == app->window) {
        cancel_hide_pending(app);
      }
      if (app->is_hidden && (app->strip != XCB_NONE && enter->event == app->strip)) {
        if (show_dock(app)) {
          schedule_redraw(app, 1, REDRAW_REASON_MOTION);
        }
      }
      break;
    }
    case XCB_MOTION_NOTIFY: {
      xcb_motion_notify_event_t *motion = (xcb_motion_notify_event_t *)event;
      handle_motion_event(app, cfg, motion);
      break;
    }
    case XCB_LEAVE_NOTIFY: {
      xcb_leave_notify_event_t *leave = (xcb_leave_notify_event_t *)event;
      if (leave->event == app->window) {
        if (leave->detail != XCB_NOTIFY_DETAIL_INFERIOR) {
          schedule_hide(app, cfg);
        }
      }
      break;
    }
    case XCB_FOCUS_OUT: {
      xcb_focus_out_event_t *focus = (xcb_focus_out_event_t *)event;
      if (focus->event == app->window) {
        schedule_hide(app, cfg);
      }
      break;
    }
    case XCB_BUTTON_PRESS: {
      xcb_button_press_event_t *press = (xcb_button_press_event_t *)event;
      if (app->menu_visible && press->event == app->menu_window) {
        int idx = press->event_y / app->menu_item_h;
        if (idx >= 0 && (size_t)idx < app->menu_count) {
          struct nizam_dock_menu_item *item = &app->menu_items[idx];
          if (!item->separator && item->enabled) {
            if (nizam_dock_debug_enabled()) {
              fprintf(stderr, "nizam-dock: menu click id=%d\n", item->id);
            }
            nizam_dock_sni_menu_event(app, app->menu_owner_idx, item->id, press->time);
          }
        }
        menu_hide(app);
        xembed_update_background(app);
        break;
      } else if (app->menu_visible && press->event != app->menu_window) {
        menu_hide(app);
        xembed_update_background(app);
      }
      if (press->detail == 3 && app->menu_visible) {
        menu_hide(app);
        xembed_update_background(app);
      }
      if (press->event == app->window) {
        app->suppress_hide_until_ms = now_ms() + 250;
        cancel_hide_pending(app);
      }
      if (nizam_dock_debug_enabled()) {
        fprintf(stderr, "nizam-dock: button press detail=%u event=0x%08x x=%d y=%d root=%d,%d\n",
                press->detail, press->event, press->event_x, press->event_y,
                press->root_x, press->root_y);
      }
      if (press->detail == 3) {
        int tray_idx = hit_test_tray(app, cfg, press->event_x, press->event_y);
        if (tray_idx >= 0) {
          int anchor_x = press->root_x;
          int anchor_y = press->root_y;
          tray_icon_root_anchor(app, tray_idx,
                                press->event_x, press->event_y,
                                press->root_x, press->root_y,
                                &anchor_x, &anchor_y);
          if (nizam_dock_debug_enabled()) {
            fprintf(stderr, "nizam-dock: tray hit (right) idx=%d\n", tray_idx);
          }
          if (!menu_show(app, cfg, (size_t)tray_idx, anchor_x, anchor_y)) {
            if (nizam_dock_sni_item_has_context(app, (size_t)tray_idx)) {
              lower_dock_for_external_popup(app, 8000);
              nizam_dock_sni_context_menu(app, (size_t)tray_idx, anchor_x, anchor_y);
            }
          }
          break;
        }
      }
      {
        int idx = hit_test_launcher(app, press->event_x, press->event_y);
        if (idx >= 0 && (size_t)idx < cfg->launcher_count) {
          launch_cmd(cfg->launchers[idx].cmd);
        }
      }
      break;
    }
    case XCB_BUTTON_RELEASE: {
      xcb_button_release_event_t *release = (xcb_button_release_event_t *)event;
      if (app->menu_visible && release->detail != 3 &&
          release->event != app->menu_window) {
        menu_hide(app);
        xembed_update_background(app);
      }
      if (release->event == app->window) {
        app->suppress_hide_until_ms = now_ms() + 250;
      }
      if (nizam_dock_debug_enabled()) {
        fprintf(stderr, "nizam-dock: button release detail=%u event=0x%08x x=%d y=%d root=%d,%d\n",
                release->detail, release->event, release->event_x, release->event_y,
                release->root_x, release->root_y);
      }
      if (release->detail == 1) {
        int tray_idx = hit_test_tray(app, cfg, release->event_x, release->event_y);
        if (tray_idx >= 0) {
          int anchor_x = release->root_x;
          int anchor_y = release->root_y;
          tray_icon_root_anchor(app, tray_idx,
                                release->event_x, release->event_y,
                                release->root_x, release->root_y,
                                &anchor_x, &anchor_y);
          if (nizam_dock_debug_enabled()) {
            fprintf(stderr, "nizam-dock: tray hit (left) idx=%d\n", tray_idx);
          }

          if (nizam_dock_sni_item_has_menu(app, (size_t)tray_idx)) {
            if (menu_show(app, cfg, (size_t)tray_idx, anchor_x, anchor_y)) {
              break;
            }
          }

          int acted = 0;
          if (nizam_dock_sni_item_has_xayatana_secondary(app, (size_t)tray_idx)) {
            lower_dock_for_external_popup(app, 3000);
            acted |= nizam_dock_sni_xayatana_secondary(app, (size_t)tray_idx, release->time);
          }
          if (nizam_dock_sni_item_has_secondary(app, (size_t)tray_idx)) {
            lower_dock_for_external_popup(app, 8000);
            acted |= nizam_dock_sni_secondary_activate(app, (size_t)tray_idx,
                                                  anchor_x, anchor_y);
          }
          if (!acted && nizam_dock_sni_item_has_activate(app, (size_t)tray_idx)) {
            lower_dock_for_external_popup(app, 8000);
            acted = nizam_dock_sni_activate(app, (size_t)tray_idx,
                                       anchor_x, anchor_y);
          }
          if (!acted && nizam_dock_sni_item_is_menu(app, (size_t)tray_idx)) {
            acted = menu_show(app, cfg, (size_t)tray_idx,
                              anchor_x, anchor_y);
            if (!acted) {
              lower_dock_for_external_popup(app, 8000);
              acted = nizam_dock_sni_context_menu(app, (size_t)tray_idx,
                                                  anchor_x, anchor_y);
            }
          }
          if (!acted && nizam_dock_debug_enabled()) {
            fprintf(stderr, "nizam-dock: tray left no action available\n");
          }
          break;
        }
      }
      break;
    }
    case XCB_EXPOSE: {
      xcb_expose_event_t *expose = (xcb_expose_event_t *)event;
      if (app->menu_visible && expose->window == app->menu_window) {
        menu_draw(app);
      } else if (expose->window == app->xembed_window) {
        xembed_update_background(app);
      } else if (expose->window == app->window) {
        schedule_redraw(app, 1, REDRAW_REASON_EXPOSE);
      }
      break;
    }
    case XCB_VISIBILITY_NOTIFY: {
      xcb_visibility_notify_event_t *vis = (xcb_visibility_notify_event_t *)event;
      if (vis->window == app->window) {
        if (!app->menu_visible && !app->is_hidden &&
            vis->state == XCB_VISIBILITY_FULLY_OBSCURED &&
            (!app->suppress_raise_until_ms || now_ms() >= app->suppress_raise_until_ms)) {
          set_dock_stack(app, 1);
        }
        schedule_redraw(app, 1, REDRAW_REASON_EXPOSE);
      } else if (vis->window == app->xembed_window) {
        xembed_update_background(app);
      }
      break;
    }
    default:
      break;
  }
}

static void set_dock_stack(struct nizam_dock_app *app, int above) {
  if (!app || app->window == XCB_NONE) {
    return;
  }
  uint32_t stack_mode = above ? XCB_STACK_MODE_ABOVE : XCB_STACK_MODE_BELOW;
  xcb_configure_window(app->conn, app->window,
                       XCB_CONFIG_WINDOW_STACK_MODE, &stack_mode);
}

static void move_window_x(struct nizam_dock_app *app, int x) {
  uint32_t values[1] = {(uint32_t)x};
  xcb_configure_window(app->conn, app->window, XCB_CONFIG_WINDOW_X, values);
  app->panel_x = x;
}

static void slide_window_x(struct nizam_dock_app *app, int from_x, int to_x) {
  int steps = 10;
  int delay_ms = 16;
  for (int i = 1; i <= steps; ++i) {
    int x = from_x + ((to_x - from_x) * i) / steps;
    move_window_x(app, x);
    xcb_flush(app->conn);
    struct timespec ts = {0};
    ts.tv_nsec = delay_ms * 1000000L;
    nanosleep(&ts, NULL);
  }
}

static int show_dock(struct nizam_dock_app *app) {
  if (!app->is_hidden) {
    return 0;
  }
  int64_t now = now_ms();
  if (app->last_toggle_ms && now - app->last_toggle_ms < 200) {
    return 0;
  }
  
  set_dock_stack(app, 1);

  
  
  move_window_x(app, app->x_hidden);
  xcb_map_window(app->conn, app->window);
  if (app->xembed_window != XCB_NONE) {
    xcb_map_window(app->conn, app->xembed_window);
  }
  xcb_flush(app->conn);

  slide_window_x(app, app->x_hidden, app->x_visible);
  set_strip_stack(app, 0);
  app->is_hidden = 0;
  app->hide_pending = 0;
  app->last_toggle_ms = now;
  xcb_flush(app->conn);
  return 1;
}

static int pointer_inside_window(struct nizam_dock_app *app) {
  if (!app || app->window == XCB_NONE) {
    return 0;
  }
  xcb_query_pointer_cookie_t cookie = xcb_query_pointer(app->conn, app->window);
  xcb_query_pointer_reply_t *reply = xcb_query_pointer_reply(app->conn, cookie, NULL);
  if (!reply) {
    return 0;
  }
  int inside = reply->same_screen &&
               reply->win_x >= 0 && reply->win_y >= 0 &&
               reply->win_x < app->panel_w &&
               reply->win_y < app->panel_h;
  free(reply);
  return inside;
}

static void xembed_update_background(struct nizam_dock_app *app);
static void xembed_remove_client(struct nizam_dock_app *app, xcb_window_t win);

static void debug_print_window_props(struct nizam_dock_app *app, xcb_window_t win) {
  if (!nizam_dock_debug_enabled() || !app || win == XCB_NONE) {
    return;
  }

  xcb_atom_t wm_class = intern_atom(app->conn, "WM_CLASS");
  if (wm_class != XCB_NONE) {
    xcb_get_property_cookie_t c = xcb_get_property(app->conn, 0, win, wm_class,
                                                   XCB_GET_PROPERTY_TYPE_ANY, 0, 128);
    xcb_get_property_reply_t *r = xcb_get_property_reply(app->conn, c, NULL);
    if (r) {
      int len = xcb_get_property_value_length(r);
      if (len > 0) {
        const char *v = (const char *)xcb_get_property_value(r);
        const char *clazz = memchr(v, '\0', (size_t)len);
        if (clazz && (clazz + 1) < (v + len)) {
            fprintf(stderr, "nizam-dock: xembed win=0x%08x WM_CLASS=%s/%s\n",
                  (unsigned)win, v, clazz + 1);
        } else {
            fprintf(stderr, "nizam-dock: xembed win=0x%08x WM_CLASS=%.*s\n",
                  (unsigned)win, len, v);
        }
      }
      free(r);
    }
  }
}

static void debug_print_geometry(struct nizam_dock_app *app, xcb_window_t win, const char *tag) {
  if (!nizam_dock_debug_enabled() || !app || win == XCB_NONE) {
    return;
  }
  xcb_get_geometry_cookie_t gc = xcb_get_geometry(app->conn, win);
  xcb_get_geometry_reply_t *gr = xcb_get_geometry_reply(app->conn, gc, NULL);
  if (gr) {
    fprintf(stderr,
          "nizam-dock: xembed %s win=0x%08x depth=%u geom=%dx%d+%d+%d\n",
            tag ? tag : "geom", (unsigned)win, (unsigned)gr->depth,
            (int)gr->width, (int)gr->height, (int)gr->x, (int)gr->y);
    free(gr);
  }
}

static void menu_free(struct nizam_dock_app *app) {
  if (!app) {
    return;
  }
  free(app->menu_items);
  app->menu_items = NULL;
  app->menu_count = 0;
  app->menu_owner_idx = 0;
}

static void menu_hide(struct nizam_dock_app *app) {
  if (!app || !app->menu_visible) {
    return;
  }
  if (app->menu_window != XCB_NONE) {
    xcb_destroy_window(app->conn, app->menu_window);
    app->menu_window = XCB_NONE;
  }
  app->menu_visible = 0;
  app->suppress_raise_until_ms = 0;
  
  
  app->suppress_hide_until_ms = now_ms() + 250;
  app->menu_dirty = 1;
  menu_free(app);
  
  if (!app->is_hidden) {
    set_dock_stack(app, 1);
  }
  xembed_update_background(app);
  xcb_flush(app->conn);
}

static void menu_draw(struct nizam_dock_app *app) {
  if (!app || app->menu_window == XCB_NONE) {
    return;
  }
  cairo_surface_t *surface = cairo_xcb_surface_create(app->conn, app->menu_window,
                                                      app->visual_type,
                                                      app->menu_w, app->menu_h);
  if (cairo_surface_status(surface) != CAIRO_STATUS_SUCCESS) {
    cairo_surface_destroy(surface);
    return;
  }
  cairo_t *cr = cairo_create(surface);
  cairo_set_source_rgba(cr, 0.08, 0.08, 0.08, 0.96);
  cairo_paint(cr);
  cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.15);
  cairo_rectangle(cr, 0.5, 0.5, app->menu_w - 1.0, app->menu_h - 1.0);
  cairo_set_line_width(cr, 1.0);
  cairo_stroke(cr);

  cairo_select_font_face(cr, "Sans", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL);
  cairo_set_font_size(cr, 12.0);
  int y = 0;
  for (size_t i = 0; i < app->menu_count; ++i) {
    struct nizam_dock_menu_item *item = &app->menu_items[i];
    if (item->separator) {
      cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.15);
      cairo_move_to(cr, 8.0, y + app->menu_item_h / 2.0);
      cairo_line_to(cr, app->menu_w - 8.0, y + app->menu_item_h / 2.0);
      cairo_set_line_width(cr, 1.0);
      cairo_stroke(cr);
    } else {
      double alpha = item->enabled ? 0.90 : 0.40;
      cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, alpha);
      double indent = 12.0 + item->level * 12.0;
      cairo_move_to(cr, indent, y + app->menu_item_h - 6);
      cairo_show_text(cr, item->label[0] ? item->label : "(untitled)");
      if (item->submenu) {
        cairo_move_to(cr, app->menu_w - 14.0, y + app->menu_item_h - 6);
        cairo_show_text(cr, ">");
      }
    }
    y += app->menu_item_h;
  }
  cairo_destroy(cr);
  cairo_surface_flush(surface);
  cairo_surface_destroy(surface);
  xcb_flush(app->conn);
}

static int menu_show(struct nizam_dock_app *app, const struct nizam_dock_config *cfg,
                     size_t owner_idx, int x, int y) {
  if (!app || !cfg) {
    return 0;
  }
  menu_free(app);
  struct nizam_dock_menu_item *items = NULL;
  size_t count = 0;
  if (!nizam_dock_sni_menu_fetch(app, owner_idx, &items, &count)) {
    if (nizam_dock_debug_enabled()) {
      fprintf(stderr, "nizam-dock: menu fetch failed for idx=%zu\n", owner_idx);
    }
    return 0;
  }
  if (nizam_dock_debug_enabled()) {
    fprintf(stderr, "nizam-dock: menu show count=%zu at %d,%d\n", count, x, y);
  }
  
  
  app->menu_visible = 1;
  app->menu_items = items;
  app->menu_count = count;
  app->menu_owner_idx = owner_idx;
  app->menu_item_h = 22;
  app->menu_w = 220;
  app->menu_h = (int)count * app->menu_item_h;
  
  
  app->menu_x = x - app->menu_w / 2;
  
  app->menu_y = y - app->menu_h - 8;
  if (app->menu_x < 2) {
    app->menu_x = 2;
  }
  if (app->menu_x + app->menu_w > app->screen->width_in_pixels) {
    app->menu_x = app->screen->width_in_pixels - app->menu_w - 2;
  }
  if (app->menu_y + app->menu_h > app->screen->height_in_pixels) {
    app->menu_y = app->screen->height_in_pixels - app->menu_h - 2;
  }
  if (app->menu_y < 2) {
    app->menu_y = 2;
  }
  if (nizam_dock_debug_enabled()) {
    fprintf(stderr, "nizam-dock: menu geom %d,%d %dx%d\n",
            app->menu_x, app->menu_y, app->menu_w, app->menu_h);
  }
  if (app->menu_window == XCB_NONE) {
    app->menu_window = xcb_generate_id(app->conn);
    
    
    uint32_t mask = XCB_CW_BACK_PIXEL | XCB_CW_OVERRIDE_REDIRECT | XCB_CW_EVENT_MASK;
    uint32_t values[] = {
      app->screen->black_pixel,
      1,
      XCB_EVENT_MASK_EXPOSURE | XCB_EVENT_MASK_BUTTON_PRESS | XCB_EVENT_MASK_BUTTON_RELEASE
    };
    xcb_create_window(app->conn,
                      XCB_COPY_FROM_PARENT,
                      app->menu_window,
                      app->screen->root,
                      app->menu_x,
                      app->menu_y,
                      app->menu_w,
                      app->menu_h,
                      0,
                      XCB_WINDOW_CLASS_INPUT_OUTPUT,
                      app->visual,
                      mask,
                      values);
    xcb_atom_t menu_state_values[] = {
      app->atoms.net_wm_state_above,
      app->atoms.net_wm_state_skip_taskbar,
      app->atoms.net_wm_state_skip_pager
    };
    xcb_change_property(app->conn, XCB_PROP_MODE_REPLACE,
                        app->menu_window, app->atoms.net_wm_window_type,
                        XCB_ATOM_ATOM, 32, 1, &app->atoms.net_wm_window_type_popup_menu);
    xcb_change_property(app->conn, XCB_PROP_MODE_REPLACE,
                        app->menu_window, app->atoms.net_wm_state,
                        XCB_ATOM_ATOM, 32, 3, menu_state_values);
    xcb_change_property(app->conn, XCB_PROP_MODE_REPLACE,
                        app->menu_window, app->atoms.wm_transient_for,
                        XCB_ATOM_WINDOW, 32, 1, &app->window);
    if (app->atoms.motif_wm_hints != XCB_NONE) {
      struct {
        uint32_t flags;
        uint32_t functions;
        uint32_t decorations;
        int32_t input_mode;
        uint32_t status;
      } hints = {0};
      hints.flags = 1u << 1; 
      hints.decorations = 0;
      xcb_change_property(app->conn, XCB_PROP_MODE_REPLACE,
                          app->menu_window, app->atoms.motif_wm_hints,
                          app->atoms.motif_wm_hints, 32,
                          sizeof(hints) / sizeof(uint32_t), &hints);
    }
  } else {
    uint32_t values[4] = {
      (uint32_t)app->menu_x,
      (uint32_t)app->menu_y,
      (uint32_t)app->menu_w,
      (uint32_t)app->menu_h
    };
    xcb_configure_window(app->conn, app->menu_window,
                         XCB_CONFIG_WINDOW_X | XCB_CONFIG_WINDOW_Y |
                           XCB_CONFIG_WINDOW_WIDTH | XCB_CONFIG_WINDOW_HEIGHT,
                         values);
  }

  xcb_map_window(app->conn, app->menu_window);

  if (nizam_dock_debug_enabled()) {
    xcb_flush(app->conn);
    xcb_get_geometry_cookie_t gc = xcb_get_geometry(app->conn, app->menu_window);
    xcb_get_geometry_reply_t *gr = xcb_get_geometry_reply(app->conn, gc, NULL);
    if (gr) {
      fprintf(stderr, "nizam-dock: menu mapped geom=%dx%d+%d+%d\n",
              (int)gr->width, (int)gr->height, (int)gr->x, (int)gr->y);
      free(gr);
    }
  }

  
  
  
  app->suppress_hide_until_ms = now_ms() + 60000;

  
  {
    uint32_t stack_mode = XCB_STACK_MODE_ABOVE;
    xcb_configure_window(app->conn, app->menu_window,
                         XCB_CONFIG_WINDOW_STACK_MODE,
                         &stack_mode);
  }
  menu_draw(app);
  return 1;
}

static int hide_dock(struct nizam_dock_app *app) {
  if (app->is_hidden) {
    return 0;
  }
  if (nizam_dock_no_autohide()) {
    return 0;
  }
  if (app->menu_visible) {
    return 0;
  }
  int64_t now = now_ms();
  if (app->suppress_hide_until_ms && now < app->suppress_hide_until_ms) {
    return 0;
  }
  if (pointer_inside_window(app)) {
    return 0;
  }
  if (app->last_toggle_ms && now - app->last_toggle_ms < 200) {
    return 0;
  }
  
  
  set_dock_stack(app, 0);
  slide_window_x(app, app->x_visible, app->x_hidden);

  
  
  xcb_unmap_window(app->conn, app->window);

  set_strip_stack(app, 1);
  app->is_hidden = 1;
  app->hide_pending = 0;
  app->last_toggle_ms = now;

  
  notify_panel_redraw(app);
  xcb_flush(app->conn);
  return 1;
}

static int hit_test_launcher(const struct nizam_dock_app *app, int x, int y) {
  if (!app || !app->launcher_rects || app->launcher_rect_count == 0) {
    return -1;
  }
  for (size_t i = 0; i < app->launcher_rect_count; ++i) {
    const struct nizam_dock_launcher_rect *rect = &app->launcher_rects[i];
    if (x >= rect->x && x < rect->x + rect->w &&
        y >= rect->y && y < rect->y + rect->h) {
      return (int)i;
    }
  }
  return -1;
}

static int hit_test_tray(const struct nizam_dock_app *app, const struct nizam_dock_config *cfg,
                         int x, int y) {
  (void)cfg;
  if (!app || app->tray_count == 0 || app->tray_size <= 0) {
    return -1;
  }
  int tray_spacing = app->tray_gap > 0 ? app->tray_gap : 3;
  int top = app->tray_y;
  int bottom = top + app->tray_size;
  int left = app->tray_x;
  int right = left + (int)app->tray_count * app->tray_size +
              (int)(app->tray_count - 1) * tray_spacing;
  if (x < left || x > right || y < top || y > bottom) {
    return -1;
  }
  int rel_x = x - left;
  int stride = app->tray_size + tray_spacing;
  int idx = rel_x / stride;
  int inside = rel_x % stride;
  if (idx < 0 || (size_t)idx >= app->tray_count || inside >= app->tray_size) {
    return -1;
  }
  return idx;
}

static void tray_icon_root_anchor(const struct nizam_dock_app *app,
                                  int tray_idx,
                                  int event_x,
                                  int event_y,
                                  int root_x,
                                  int root_y,
                                  int *out_root_x,
                                  int *out_root_y) {
  if (!app || tray_idx < 0 || app->tray_size <= 0) {
    if (out_root_x) {
      *out_root_x = root_x;
    }
    if (out_root_y) {
      *out_root_y = root_y;
    }
    return;
  }

  int tray_spacing = app->tray_gap > 0 ? app->tray_gap : 3;
  int icon_x = app->tray_x + tray_idx * (app->tray_size + tray_spacing);
  int icon_y = app->tray_y;
  int center_x = icon_x + app->tray_size / 2;
  int center_y = icon_y + app->tray_size / 2;

  
  
  
  int ok = 0;
  int dock_root_x = 0;
  int dock_root_y = 0;
  if (app->conn && app->screen && app->window != XCB_NONE) {
    xcb_translate_coordinates_cookie_t tc =
      xcb_translate_coordinates(app->conn, app->window, app->screen->root, 0, 0);
    xcb_translate_coordinates_reply_t *tr =
      xcb_translate_coordinates_reply(app->conn, tc, NULL);
    if (tr) {
      dock_root_x = tr->dst_x;
      dock_root_y = tr->dst_y;
      ok = 1;
      free(tr);
    }
  }

  if (!ok) {
    
    dock_root_x = root_x - event_x;
    dock_root_y = root_y - event_y;
  }

  if (out_root_x) {
    *out_root_x = dock_root_x + center_x;
  }
  if (out_root_y) {
    *out_root_y = dock_root_y + center_y;
  }
}

static void launch_cmd(const char *cmd) {
  if (!cmd || !*cmd) {
    return;
  }
  pid_t pid = fork();
  if (pid == 0) {
    execl("/bin/sh", "sh", "-c", cmd, (char *)NULL);
    _exit(127);
  }
}

static int xembed_ensure_capacity(struct nizam_dock_app *app) {
  if (app->xembed_count < app->xembed_cap) {
    return 1;
  }
  size_t next = app->xembed_cap == 0 ? 8 : app->xembed_cap * 2;
  struct nizam_dock_xembed_icon *icons = realloc(app->xembed_icons, next * sizeof(*icons));
  if (!icons) {
    return 0;
  }
  app->xembed_icons = icons;
  app->xembed_cap = next;
  return 1;
}

static ssize_t xembed_find(const struct nizam_dock_app *app, xcb_window_t win) {
  if (!app) {
    return -1;
  }
  for (size_t i = 0; i < app->xembed_count; ++i) {
    if (app->xembed_icons[i].win == win) {
      return (ssize_t)i;
    }
  }
  return -1;
}

static void xembed_send_embedded_notify(struct nizam_dock_app *app, xcb_window_t win) {
  xcb_client_message_event_t msg = {0};
  msg.response_type = XCB_CLIENT_MESSAGE;
  msg.window = win;
  msg.type = app->atoms.xembed;
  msg.format = 32;
  msg.data.data32[0] = XCB_CURRENT_TIME;
  msg.data.data32[1] = XEMBED_EMBEDDED_NOTIFY;
  msg.data.data32[2] = 0;
  msg.data.data32[3] = app->xembed_window;
  msg.data.data32[4] = 0;
  xcb_send_event(app->conn, 0, win, XCB_EVENT_MASK_NO_EVENT, (char *)&msg);
}

static void xembed_update_background(struct nizam_dock_app *app) {
  if (!app || app->xembed_window == XCB_NONE) {
    return;
  }
  uint32_t bg = NIZAM_DOCK_TRAY_BG_PIXEL;
  xcb_change_window_attributes(app->conn, app->xembed_window,
                               XCB_CW_BACK_PIXEL, &bg);
  xcb_clear_area(app->conn, 0, app->xembed_window, 0, 0, 0, 0);
}

static void xembed_add_client(struct nizam_dock_app *app, xcb_window_t win) {
  if (!app || win == XCB_NONE || app->xembed_window == XCB_NONE) {
    return;
  }
  if (xembed_find(app, win) >= 0) {
    return;
  }
  if (!xembed_ensure_capacity(app)) {
    return;
  }

  debug_print_window_props(app, win);
  debug_print_geometry(app, win, "before");

  app->xembed_icons[app->xembed_count].win = win;
  app->xembed_count += 1;

  xcb_void_cookie_t rep = xcb_reparent_window_checked(app->conn, win, app->xembed_window, 0, 0);
  xcb_generic_error_t *rep_err = xcb_request_check(app->conn, rep);
  if (rep_err) {
    if (nizam_dock_debug_enabled()) {
      fprintf(stderr, "nizam-dock: xembed reparent failed win=0x%08x err=%u\n",
              (unsigned)win, (unsigned)rep_err->error_code);
    }
    free(rep_err);
    xembed_remove_client(app, win);
    return;
  }

  uint32_t values[] = {
    (uint32_t)(app->xembed_size > 0 ? app->xembed_size : 16),
    (uint32_t)(app->xembed_size > 0 ? app->xembed_size : 16)
  };

  xcb_void_cookie_t cfg = xcb_configure_window_checked(app->conn, win,
                                                       XCB_CONFIG_WINDOW_WIDTH | XCB_CONFIG_WINDOW_HEIGHT,
                                                       values);
  xcb_generic_error_t *cfg_err = xcb_request_check(app->conn, cfg);
  if (cfg_err) {
    if (nizam_dock_debug_enabled()) {
      fprintf(stderr, "nizam-dock: xembed configure failed win=0x%08x err=%u\n",
              (unsigned)win, (unsigned)cfg_err->error_code);
    }
    free(cfg_err);
  }

  xembed_send_embedded_notify(app, win);

  xcb_void_cookie_t mapc = xcb_map_window_checked(app->conn, win);
  xcb_generic_error_t *map_err = xcb_request_check(app->conn, mapc);
  if (map_err) {
    if (nizam_dock_debug_enabled()) {
      fprintf(stderr, "nizam-dock: xembed map failed win=0x%08x err=%u\n",
              (unsigned)win, (unsigned)map_err->error_code);
    }
    free(map_err);
  }

  xcb_flush(app->conn);

  debug_print_geometry(app, win, "after");
}

static void xembed_remove_client(struct nizam_dock_app *app, xcb_window_t win) {
  ssize_t idx = xembed_find(app, win);
  if (idx < 0) {
    return;
  }
  size_t i = (size_t)idx;
  if (i + 1 < app->xembed_count) {
    memmove(&app->xembed_icons[i], &app->xembed_icons[i + 1],
            (app->xembed_count - i - 1) * sizeof(*app->xembed_icons));
  }
  app->xembed_count -= 1;
}

void nizam_dock_xembed_layout(struct nizam_dock_app *app, const struct nizam_dock_config *cfg) {
  (void)cfg;
  if (!app || app->xembed_window == XCB_NONE) {
    return;
  }
  if (app->xembed_count == 0) {
    xcb_unmap_window(app->conn, app->xembed_window);
    return;
  }
  int size = 24;
  app->xembed_size = size;
  int gap = app->xembed_gap > 0 ? app->xembed_gap : 3;
  int width = (int)app->xembed_count * size +
              (int)(app->xembed_count - 1) * gap;
  {
    uint32_t values[4] = {
      (uint32_t)app->xembed_x,
      (uint32_t)app->xembed_y,
      (uint32_t)width,
      (uint32_t)size
    };
    xcb_configure_window(app->conn, app->xembed_window,
                         XCB_CONFIG_WINDOW_X | XCB_CONFIG_WINDOW_Y |
                           XCB_CONFIG_WINDOW_WIDTH | XCB_CONFIG_WINDOW_HEIGHT,
                         values);
    xembed_update_background(app);
    xcb_map_window(app->conn, app->xembed_window);
  }
  int x = 0;
  int y = 0;
  for (size_t i = 0; i < app->xembed_count; ++i) {
    xcb_window_t win = app->xembed_icons[i].win;
    uint32_t values[4] = {
      (uint32_t)x,
      (uint32_t)y,
      (uint32_t)size,
      (uint32_t)size
    };
    xcb_configure_window(app->conn, win,
                         XCB_CONFIG_WINDOW_X | XCB_CONFIG_WINDOW_Y |
                           XCB_CONFIG_WINDOW_WIDTH | XCB_CONFIG_WINDOW_HEIGHT,
                         values);
    x += size + gap;
  }
  xcb_flush(app->conn);
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

static int max_launchers_per_category(const struct nizam_dock_config *cfg) {
  if (!cfg || cfg->launcher_count == 0) {
    return 1;
  }
  int max_count = 1;
  int current = 0;
  const char *current_cat = NULL;
  for (size_t i = 0; i < cfg->launcher_count; ++i) {
    const char *cat = launcher_category_key(&cfg->launchers[i]);
    if (!current_cat || strcasecmp(cat, current_cat) != 0) {
      if (current > max_count) {
        max_count = current;
      }
      current_cat = cat;
      current = 1;
    } else {
      current += 1;
    }
  }
  if (current > max_count) {
    max_count = current;
  }
  return max_count;
}

static size_t max_category_label_len(const struct nizam_dock_config *cfg) {
  if (!cfg || cfg->launcher_count == 0) {
    return strlen("Other");
  }
  size_t max_len = 0;
  size_t i = 0;
  while (i < cfg->launcher_count) {
    const char *cat = launcher_category_key(&cfg->launchers[i]);
    const char *label = (cat && *cat) ? category_display_name(cat) : "Other";
    size_t len = strlen(label);
    if (len > max_len) {
      max_len = len;
    }
    while (i < cfg->launcher_count &&
           strcasecmp(launcher_category_key(&cfg->launchers[i]), cat) == 0) {
      i += 1;
    }
  }
  return max_len;
}

static size_t max_sysinfo_len(const struct nizam_dock_app *app) {
  size_t max_len = 0;
  if (!app) {
    return 0;
  }
  for (int i = 0; i < NIZAM_DOCK_INFO_LINES; ++i) {
    size_t len = strlen(app->sysinfo_lines[i]);
    if (len > max_len) {
      max_len = len;
    }
  }
  return max_len;
}

static int compute_content_width(const struct nizam_dock_app *app, const struct nizam_dock_config *cfg) {
  int max_row = max_launchers_per_category(cfg);
  if (max_row < 1) {
    max_row = 1;
  }
  int row_w = max_row * cfg->icon_size + (max_row - 1) * cfg->spacing;

  size_t label_len = max_category_label_len(cfg);
  int label_w = (int)(label_len * 9) + 8;

  size_t info_len = max_sysinfo_len(app);
  int info_w = (int)(info_len * 7) + 8;

  size_t tray_count = nizam_dock_sni_count(app) + app->xembed_count;
  int tray_size = 24;
  int tray_spacing = 3;
  int tray_w = 0;
  if (tray_count > 0) {
    tray_w = (int)tray_count * tray_size +
             (int)(tray_count - 1) * tray_spacing;
  }

  int content_w = row_w;
  if (label_w > content_w) {
    content_w = label_w;
  }
  if (info_w > content_w) {
    content_w = info_w;
  }
  if (tray_w > content_w) {
    content_w = tray_w;
  }
  return content_w;
}

void nizam_dock_xcb_recalc_geometry(struct nizam_dock_app *app, const struct nizam_dock_config *cfg) {
  int content_w = compute_content_width(app, cfg);
  if (NIZAM_DOCK_INFO_MAX_WIDTH > content_w) {
    content_w = NIZAM_DOCK_INFO_MAX_WIDTH;
  }
  app->panel_w = cfg->padding * 2 + content_w;
  if (app->mon_w <= 0 || app->mon_h <= 0) {
    dock_set_default_monitor(app);
  }
  app->panel_h = app->mon_h;

  int mon_x = app->mon_x;
  int mon_y = app->mon_y;
  int mon_w = app->mon_w;

  app->panel_y = mon_y;
  
  app->x_visible = mon_x + mon_w - app->panel_w;
  
  
  app->x_hidden = mon_x + mon_w;
  app->panel_x = app->is_hidden ? app->x_hidden : app->x_visible;
}

static void set_window_hints(struct nizam_dock_app *app) {
  xcb_atom_t state_values[] = {
    app->atoms.net_wm_state_sticky,
    app->atoms.net_wm_state_above,
    app->atoms.net_wm_state_skip_taskbar,
    app->atoms.net_wm_state_skip_pager
  };
  uint32_t desktop_all = 0xFFFFFFFFu;

  xcb_change_property(app->conn, XCB_PROP_MODE_REPLACE,
                      app->window, app->atoms.net_wm_window_type,
                      XCB_ATOM_ATOM, 32, 1, &app->atoms.net_wm_window_type_dock);

  xcb_change_property(app->conn, XCB_PROP_MODE_REPLACE,
                      app->window, app->atoms.net_wm_state,
                      XCB_ATOM_ATOM, 32, 4, state_values);

  if (app->atoms.net_wm_desktop != XCB_NONE) {
    xcb_change_property(app->conn, XCB_PROP_MODE_REPLACE,
                        app->window, app->atoms.net_wm_desktop,
                        XCB_ATOM_CARDINAL, 32, 1, &desktop_all);
  }

  struct nizam_dock_wm_hints hints = {0};
  hints.flags = 1; 
  hints.input = 0;
  xcb_change_property(app->conn, XCB_PROP_MODE_REPLACE,
                      app->window, app->atoms.wm_hints,
                      app->atoms.wm_hints, 32,
                      sizeof(hints) / sizeof(uint32_t), &hints);
}

int nizam_dock_xcb_init(struct nizam_dock_app *app, const struct nizam_dock_config *cfg) {
  memset(app, 0, sizeof(*app));
  nizam_dock_debug_log("xcb init start");

  
  
  app->suppress_hide_until_ms = now_ms() + 8000;

  int screen_nbr = 0;
  app->conn = xcb_connect(NULL, &screen_nbr);
  if (xcb_connection_has_error(app->conn)) {
    return -1;
  }
  app->screen_nbr = screen_nbr;

  const xcb_setup_t *setup = xcb_get_setup(app->conn);
  xcb_screen_iterator_t iter = xcb_setup_roots_iterator(setup);
  for (int i = 0; i < screen_nbr; ++i) {
    xcb_screen_next(&iter);
  }
  app->screen = iter.data;
  app->visual = app->screen->root_visual;
  app->visual_type = find_visual_type(app->screen, app->visual);
  if (!app->visual_type) {
    xcb_disconnect(app->conn);
    app->conn = NULL;
    return -1;
  }
  nizam_dock_debug_log("xcb visual ok");

  dock_pick_monitor_for_pointer(app);

  nizam_dock_xcb_recalc_geometry(app, cfg);
  app->root_pixmap = XCB_NONE;
  app->have_root_pixmap = 0;

  uint32_t value_mask = XCB_CW_BACK_PIXEL | XCB_CW_OVERRIDE_REDIRECT | XCB_CW_EVENT_MASK;
  uint32_t value_list[] = {
    app->screen->black_pixel,
    1,
    XCB_EVENT_MASK_ENTER_WINDOW |
      XCB_EVENT_MASK_LEAVE_WINDOW |
      XCB_EVENT_MASK_EXPOSURE |
      XCB_EVENT_MASK_FOCUS_CHANGE |
      XCB_EVENT_MASK_BUTTON_PRESS |
      XCB_EVENT_MASK_BUTTON_RELEASE |
      XCB_EVENT_MASK_VISIBILITY_CHANGE
  };

  app->window = xcb_generate_id(app->conn);
  xcb_create_window(app->conn,
                    XCB_COPY_FROM_PARENT,
                    app->window,
                    app->screen->root,
                    app->panel_x,
                    app->panel_y,
                    app->panel_w,
                    app->panel_h,
                    0,
                    XCB_WINDOW_CLASS_INPUT_OUTPUT,
                    app->visual,
                    value_mask,
                    value_list);

  app->xembed_window = xcb_generate_id(app->conn);
  {
    uint32_t tray_mask = XCB_CW_BACK_PIXEL | XCB_CW_EVENT_MASK;
    uint32_t tray_values[] = {
      NIZAM_DOCK_TRAY_BG_PIXEL,
      XCB_EVENT_MASK_STRUCTURE_NOTIFY |
        XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY |
        XCB_EVENT_MASK_PROPERTY_CHANGE |
        XCB_EVENT_MASK_EXPOSURE |
        XCB_EVENT_MASK_VISIBILITY_CHANGE
    };
    xcb_create_window(app->conn,
                      XCB_COPY_FROM_PARENT,
                      app->xembed_window,
                      app->window,
                      0,
                      0,
                      1,
                      1,
                      0,
                      XCB_WINDOW_CLASS_INPUT_OUTPUT,
                      app->visual,
                      tray_mask,
                      tray_values);
  }

  int handle_px = 1;
  if (cfg && cfg->handle_px > 0) {
    handle_px = cfg->handle_px;
    if (handle_px < 1) handle_px = 1;
    if (handle_px > 64) handle_px = 64;
  }
  app->handle_px = handle_px;

  app->strip = xcb_generate_id(app->conn);
  uint32_t strip_mask = XCB_CW_OVERRIDE_REDIRECT | XCB_CW_EVENT_MASK;
  uint32_t strip_values[] = {
    1,
    XCB_EVENT_MASK_ENTER_WINDOW | XCB_EVENT_MASK_LEAVE_WINDOW | XCB_EVENT_MASK_POINTER_MOTION
  };
  xcb_void_cookie_t strip_cookie = xcb_create_window_checked(app->conn,
                                                             0,
                                                             app->strip,
                                                             app->screen->root,
                                                             (int16_t)(app->mon_x + app->mon_w - handle_px),
                                                             (int16_t)app->mon_y,
                                                             (uint16_t)handle_px,
                                                             (uint16_t)app->mon_h,
                                                             0,
                                                             XCB_WINDOW_CLASS_INPUT_ONLY,
                                                             XCB_COPY_FROM_PARENT,
                                                             strip_mask,
                                                             strip_values);
  xcb_generic_error_t *strip_err = xcb_request_check(app->conn, strip_cookie);
  if (strip_err) {
    if (nizam_dock_debug_enabled()) {
      fprintf(stderr, "nizam-dock: strip error code=%u\n", strip_err->error_code);
    }
    free(strip_err);
    app->strip = XCB_NONE;
    nizam_dock_debug_log("strip create failed");
  } else {
    nizam_dock_debug_log("strip create ok");
  }

  create_buffer(app);

  app->atoms.net_wm_window_type = intern_atom(app->conn, "_NET_WM_WINDOW_TYPE");
  app->atoms.net_wm_window_type_dock = intern_atom(app->conn, "_NET_WM_WINDOW_TYPE_DOCK");
  app->atoms.net_wm_window_type_popup_menu = intern_atom(app->conn, "_NET_WM_WINDOW_TYPE_POPUP_MENU");
  {
    char tray_name[64];
    snprintf(tray_name, sizeof(tray_name), "_NET_SYSTEM_TRAY_S%d", app->screen_nbr);
    app->atoms.net_system_tray = intern_atom(app->conn, tray_name);
  }
  app->atoms.net_system_tray_opcode = intern_atom(app->conn, "_NET_SYSTEM_TRAY_OPCODE");
  app->atoms.net_system_tray_orientation = intern_atom(app->conn, "_NET_SYSTEM_TRAY_ORIENTATION");
  app->atoms.net_system_tray_visual = intern_atom(app->conn, "_NET_SYSTEM_TRAY_VISUAL");
  app->atoms.manager = intern_atom(app->conn, "MANAGER");
  app->atoms.xembed = intern_atom(app->conn, "_XEMBED");
  app->atoms.xembed_info = intern_atom(app->conn, "_XEMBED_INFO");
  app->atoms.net_wm_state = intern_atom(app->conn, "_NET_WM_STATE");
  app->atoms.net_wm_state_sticky = intern_atom(app->conn, "_NET_WM_STATE_STICKY");
  app->atoms.net_wm_state_above = intern_atom(app->conn, "_NET_WM_STATE_ABOVE");
  app->atoms.net_wm_state_skip_taskbar = intern_atom(app->conn, "_NET_WM_STATE_SKIP_TASKBAR");
  app->atoms.net_wm_state_skip_pager = intern_atom(app->conn, "_NET_WM_STATE_SKIP_PAGER");
  app->atoms.wm_hints = intern_atom(app->conn, "WM_HINTS");
  app->atoms.motif_wm_hints = intern_atom(app->conn, "_MOTIF_WM_HINTS");
  app->atoms.wm_transient_for = intern_atom(app->conn, "WM_TRANSIENT_FOR");
  app->atoms.net_wm_desktop = intern_atom(app->conn, "_NET_WM_DESKTOP");
  app->atoms.xrootpmap_id = intern_atom(app->conn, "_XROOTPMAP_ID");
  app->atoms.xsetroot_id = intern_atom(app->conn, "_XSETROOT_ID");

  if (app->atoms.net_system_tray != XCB_NONE) {
    xcb_set_selection_owner(app->conn, app->window,
                            app->atoms.net_system_tray, XCB_CURRENT_TIME);

    xcb_get_selection_owner_cookie_t owner_cookie = xcb_get_selection_owner(app->conn, app->atoms.net_system_tray);
    xcb_get_selection_owner_reply_t *owner_reply = xcb_get_selection_owner_reply(app->conn, owner_cookie, NULL);
    if (owner_reply) {
      if (owner_reply->owner != app->window && nizam_dock_debug_enabled()) {
        fprintf(stderr, "nizam-dock: systray owner mismatch (owner=0x%08x expected=0x%08x)\n",
                (unsigned)owner_reply->owner, (unsigned)app->window);
      }
      free(owner_reply);
    }

    if (app->atoms.net_system_tray_orientation != XCB_NONE) {
      uint32_t orient = 0; 
      xcb_change_property(app->conn, XCB_PROP_MODE_REPLACE,
                          app->window, app->atoms.net_system_tray_orientation,
                          XCB_ATOM_CARDINAL, 32, 1, &orient);
    }
    if (app->atoms.net_system_tray_visual != XCB_NONE) {
      uint32_t visual = (uint32_t)app->visual;
      xcb_change_property(app->conn, XCB_PROP_MODE_REPLACE,
                          app->window, app->atoms.net_system_tray_visual,
                          XCB_ATOM_VISUALID, 32, 1, &visual);
    }

    xcb_client_message_event_t ev = {0};
    ev.response_type = XCB_CLIENT_MESSAGE;
    ev.window = app->screen->root;
    ev.type = app->atoms.manager;
    ev.format = 32;
    ev.data.data32[0] = XCB_CURRENT_TIME;
    ev.data.data32[1] = app->atoms.net_system_tray;
    ev.data.data32[2] = app->xembed_window;
    ev.data.data32[3] = 0;
    ev.data.data32[4] = 0;
    xcb_send_event(app->conn, 0, app->screen->root,
                   XCB_EVENT_MASK_STRUCTURE_NOTIFY, (char *)&ev);
  }

  set_window_hints(app);
  nizam_dock_xcb_update_root_pixmap(app);
  xembed_update_background(app);

  xcb_randr_select_input(app->conn, app->screen->root,
                         XCB_RANDR_NOTIFY_MASK_SCREEN_CHANGE);

  if (app->strip != XCB_NONE) {
    xcb_map_window(app->conn, app->strip);
  }
  xcb_map_window(app->conn, app->window);
  if (app->xembed_window != XCB_NONE) {
    xcb_map_window(app->conn, app->xembed_window);
  }
  set_strip_stack(app, app->is_hidden);
  {
    uint32_t stack_mode = XCB_STACK_MODE_ABOVE;
    xcb_configure_window(app->conn, app->window,
                         XCB_CONFIG_WINDOW_STACK_MODE, &stack_mode);
  }
  {
    uint32_t values[2] = {(uint32_t)app->panel_x, (uint32_t)app->panel_y};
    xcb_configure_window(app->conn, app->window,
                         XCB_CONFIG_WINDOW_X | XCB_CONFIG_WINDOW_Y, values);
  }
  {
    uint32_t root_mask = XCB_EVENT_MASK_PROPERTY_CHANGE;
    xcb_change_window_attributes(app->conn, app->screen->root,
                                 XCB_CW_EVENT_MASK, &root_mask);
  }
  xcb_flush(app->conn);

  nizam_dock_debug_log("xcb init done");
  return 0;
}

void nizam_dock_xcb_cleanup(struct nizam_dock_app *app) {
  if (!app || !app->conn) {
    return;
  }
  destroy_buffer(app);
  if (app->menu_window != XCB_NONE) {
    xcb_destroy_window(app->conn, app->menu_window);
    app->menu_window = XCB_NONE;
  }
  menu_free(app);
  if (app->xembed_window != XCB_NONE) {
    xcb_destroy_window(app->conn, app->xembed_window);
    app->xembed_window = XCB_NONE;
  }
  free(app->xembed_icons);
  app->xembed_icons = NULL;
  app->xembed_count = 0;
  app->xembed_cap = 0;
  if (app->strip != XCB_NONE) {
    xcb_destroy_window(app->conn, app->strip);
  }
  free(app->launcher_rects);
  app->launcher_rects = NULL;
  app->launcher_rect_count = 0;
  xcb_destroy_window(app->conn, app->window);
  xcb_disconnect(app->conn);
  app->conn = NULL;
}

static xcb_pixmap_t get_root_pixmap_atom(struct nizam_dock_app *app, xcb_atom_t atom) {
  if (atom == XCB_NONE) {
    return XCB_NONE;
  }
  xcb_get_property_cookie_t cookie = xcb_get_property(app->conn, 0,
                                                      app->screen->root,
                                                      atom,
                                                      XCB_ATOM_PIXMAP,
                                                      0, 1);
  xcb_get_property_reply_t *reply = xcb_get_property_reply(app->conn, cookie, NULL);
  if (!reply) {
    return XCB_NONE;
  }
  xcb_pixmap_t pixmap = XCB_NONE;
  if (xcb_get_property_value_length(reply) == sizeof(xcb_pixmap_t)) {
    pixmap = *(xcb_pixmap_t *)xcb_get_property_value(reply);
  }
  free(reply);
  return pixmap;
}

int nizam_dock_xcb_update_root_pixmap(struct nizam_dock_app *app) {
  xcb_pixmap_t pixmap = get_root_pixmap_atom(app, app->atoms.xrootpmap_id);
  if (pixmap == XCB_NONE) {
    pixmap = get_root_pixmap_atom(app, app->atoms.xsetroot_id);
  }
  int had = app->have_root_pixmap;
  xcb_pixmap_t prev = app->root_pixmap;
  if (pixmap != XCB_NONE) {
    app->root_pixmap = pixmap;
    app->have_root_pixmap = 1;
  } else {
    app->root_pixmap = XCB_NONE;
    app->have_root_pixmap = 0;
  }
  if (had != app->have_root_pixmap || prev != app->root_pixmap) {
    xembed_update_background(app);
    return 1;
  }
  return 0;
}

static void handle_screen_change(struct nizam_dock_app *app, const struct nizam_dock_config *cfg) {
  int old_w = app->panel_w;
  int old_h = app->panel_h;
  dock_pick_monitor_for_pointer(app);
  nizam_dock_xcb_recalc_geometry(app, cfg);
  uint32_t values[4] = {
    (uint32_t)app->panel_x,
    (uint32_t)app->panel_y,
    (uint32_t)app->panel_w,
    (uint32_t)app->panel_h
  };
  xcb_configure_window(app->conn, app->window,
                       XCB_CONFIG_WINDOW_X |
                         XCB_CONFIG_WINDOW_Y |
                         XCB_CONFIG_WINDOW_WIDTH |
                         XCB_CONFIG_WINDOW_HEIGHT,
                       values);
  if (app->strip != XCB_NONE) {
    int handle_px = 1;
    if (app->handle_px > 0) {
      handle_px = app->handle_px;
      if (handle_px < 1) handle_px = 1;
      if (handle_px > 64) handle_px = 64;
    }
    uint32_t strip_values[4] = {
      (uint32_t)(app->mon_x + app->mon_w - handle_px),
      (uint32_t)app->mon_y,
      (uint32_t)handle_px,
      (uint32_t)app->mon_h
    };
    xcb_configure_window(app->conn, app->strip,
                         XCB_CONFIG_WINDOW_X |
                           XCB_CONFIG_WINDOW_Y |
                           XCB_CONFIG_WINDOW_WIDTH |
                           XCB_CONFIG_WINDOW_HEIGHT,
                         strip_values);
    set_strip_stack(app, app->is_hidden);
  }
  if (app->panel_w != old_w || app->panel_h != old_h) {
    create_buffer(app);
  }
}

void nizam_dock_xcb_apply_geometry(struct nizam_dock_app *app, const struct nizam_dock_config *cfg) {
  if (!app || !cfg) {
    return;
  }
  handle_screen_change(app, cfg);
}

static void maybe_draw(struct nizam_dock_app *app, const struct nizam_dock_config *cfg, int force) {
  int64_t now = now_ms();
  if (!force) {
    if (app->last_draw_ms != 0 && now - app->last_draw_ms < 50) {
      return;
    }
  }
  nizam_dock_draw(app, cfg);
  app->last_draw_ms = now;
}

int nizam_dock_xcb_event_loop(struct nizam_dock_app *app, struct nizam_dock_config *cfg) {
  int running = 1;
  app->last_draw_ms = 0;
  app->redraw_pending = 0;
  app->redraw_force = 0;
  app->hovered_launcher_idx = -1;
  app->hovered_tray_idx = -1;
  int xcb_fd = xcb_get_file_descriptor(app->conn);
  maybe_draw(app, cfg, 1);
  while (running) {
    nizam_dock_log_mem_stats(app);
    nizam_dock_log_event_stats(app);
    if (g_reload_config) {
      g_reload_config = 0;
      nizam_dock_config_free(cfg);
      nizam_dock_config_init_defaults(cfg);

      (void)nizam_dock_config_load_launchers(cfg);

      if (!cfg->enabled) {
        if (nizam_dock_debug_enabled()) {
          fprintf(stderr, "nizam-dock: disabled via config (reload), exiting\n");
        }
        running = 0;
        break;
      }
      nizam_dock_icons_free(app);
      nizam_dock_icons_init(app, cfg);
      handle_screen_change(app, cfg);
      schedule_redraw(app, 1, REDRAW_REASON_TIMEOUT);
    }

    int sni_fd = nizam_dock_sni_get_fd(app);
    int sni_enabled = app->sni != NULL;
    int sni_pollable = sni_fd >= 0;
    int sni_index = -1;
    struct pollfd fds[2];
    int nfds = 0;
    fds[nfds].fd = xcb_fd;
    fds[nfds].events = POLLIN;
    fds[nfds].revents = 0;
    nfds++;
    if (sni_pollable) {
      sni_index = nfds;
      fds[nfds].fd = sni_fd;
      fds[nfds].events = POLLIN;
      fds[nfds].revents = 0;
      nfds++;
    }

    int64_t now = now_ms();
    if (app->suppress_raise_until_ms && now >= app->suppress_raise_until_ms) {
      app->suppress_raise_until_ms = 0;
      if (!app->is_hidden && !app->menu_visible) {
        set_dock_stack(app, 1);
        schedule_redraw(app, 1, REDRAW_REASON_TIMEOUT);
      }
    }

    int timeout = app->redraw_pending ? 0 : -1;
    if (!sni_pollable && sni_enabled && timeout < 0) {
      timeout = 1000;
    }

    
    if (app->hide_pending && app->hide_deadline_ms > 0) {
      int64_t now2 = now_ms();
      int64_t ms_left = app->hide_deadline_ms - now2;
      if (ms_left < 0) ms_left = 0;
      if (ms_left > INT32_MAX) ms_left = INT32_MAX;
      if (timeout < 0 || ms_left < timeout) {
        timeout = (int)ms_left;
      }
    }

    if (app->suppress_raise_until_ms && now < app->suppress_raise_until_ms) {
      int64_t ms_left = app->suppress_raise_until_ms - now;
      if (ms_left < 0) {
        ms_left = 0;
      }
      if (ms_left > INT32_MAX) {
        ms_left = INT32_MAX;
      }
      if (timeout < 0 || ms_left < timeout) {
        timeout = (int)ms_left;
      }
    }
    int pr = poll(fds, nfds, timeout);
    if (pr < 0) {
      if (errno == EINTR) {
        continue;
      }
      break;
    }
    if (sni_pollable && sni_index >= 0 && (fds[sni_index].revents & POLLIN)) {
      if (nizam_dock_sni_process(app)) {
        handle_screen_change(app, cfg);
        schedule_redraw(app, 1, REDRAW_REASON_TIMEOUT);
      }
    }
    if (!sni_pollable && sni_enabled) {
      if (nizam_dock_sni_process(app)) {
        handle_screen_change(app, cfg);
        schedule_redraw(app, 1, REDRAW_REASON_TIMEOUT);
      }
    }

    xcb_generic_event_t *event = NULL;
    while ((event = xcb_poll_for_event(app->conn)) != NULL) {
      uint8_t type = event->response_type & ~0x80;
      if (type == XCB_MOTION_NOTIFY) {
        xcb_generic_event_t *last = event;
        xcb_generic_event_t *next = NULL;
        while ((next = xcb_poll_for_queued_event(app->conn)) != NULL) {
          uint8_t ntype = next->response_type & ~0x80;
          if (ntype == XCB_MOTION_NOTIFY) {
            free(last);
            last = next;
            continue;
          }
          process_event(app, cfg, next);
          free(next);
        }
        process_event(app, cfg, last);
        free(last);
        continue;
      }
      process_event(app, cfg, event);
      free(event);
    }

    
    {
      int64_t nowh = now_ms();
      if (!app->is_hidden && !app->menu_visible &&
          (!app->suppress_hide_until_ms || nowh >= app->suppress_hide_until_ms)) {
        if (pointer_inside_window(app)) {
          cancel_hide_pending(app);
        } else if (!app->hide_pending) {
          schedule_hide(app, cfg);
        }
      }

      if (app->hide_pending && app->hide_deadline_ms > 0 && nowh >= app->hide_deadline_ms) {
        app->hide_pending = 0;
        app->hide_deadline_ms = 0;
        if (hide_dock(app)) {
          schedule_redraw(app, 1, REDRAW_REASON_TIMEOUT);
        }
      }
    }
    if (app->menu_dirty) {
      app->menu_dirty = 0;
      schedule_redraw(app, 1, REDRAW_REASON_TIMEOUT);
    }
    if (app->redraw_pending) {
      maybe_draw(app, cfg, app->redraw_force);
      app->redraw_pending = 0;
      app->redraw_force = 0;
    }

  }
  return 0;
}
