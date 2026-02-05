#ifndef NIZAM_DOCK_XCB_APP_H
#define NIZAM_DOCK_XCB_APP_H

#include <stdint.h>
#include <xcb/xcb.h>

#include "config.h"

struct nizam_dock_sni;
struct nizam_dock_icon_cache;

#define NIZAM_DOCK_INFO_LINES 3
#define NIZAM_DOCK_INFO_LINE_HEIGHT 14
#define NIZAM_DOCK_INFO_LINE_GAP 4
#define NIZAM_DOCK_INFO_TOP_GAP 10
#define NIZAM_DOCK_INFO_MAX_WIDTH 220
#define NIZAM_DOCK_INFO_LINE_MAX 128

struct nizam_dock_atoms {
  xcb_atom_t net_wm_window_type;
  xcb_atom_t net_wm_window_type_dock;
  xcb_atom_t net_wm_window_type_popup_menu;
  xcb_atom_t net_system_tray;
  xcb_atom_t net_system_tray_opcode;
  xcb_atom_t net_system_tray_orientation;
  xcb_atom_t net_system_tray_visual;
  xcb_atom_t manager;
  xcb_atom_t xembed;
  xcb_atom_t xembed_info;
  xcb_atom_t net_wm_state;
  xcb_atom_t net_wm_state_sticky;
  xcb_atom_t net_wm_state_above;
  xcb_atom_t net_wm_state_skip_taskbar;
  xcb_atom_t net_wm_state_skip_pager;
  xcb_atom_t wm_hints;
  xcb_atom_t motif_wm_hints;
  xcb_atom_t wm_transient_for;
  xcb_atom_t net_wm_desktop;
  xcb_atom_t xrootpmap_id;
  xcb_atom_t xsetroot_id;
};

typedef struct _cairo_surface cairo_surface_t;

struct nizam_dock_menu_item {
  int32_t id;
  char label[128];
  int enabled;
  int separator;
  int level;
  int submenu;
};

struct nizam_dock_launcher_rect {
  int x;
  int y;
  int w;
  int h;
};

struct nizam_dock_xembed_icon {
  xcb_window_t win;
};

struct nizam_dock_app {
  xcb_connection_t *conn;
  xcb_screen_t *screen;
  xcb_window_t window;
  xcb_window_t strip;
  xcb_window_t xembed_window;
  struct nizam_dock_sni *sni;
  xcb_window_t menu_window;
  xcb_pixmap_t buffer;
  xcb_gcontext_t gc;
  xcb_visualid_t visual;
  xcb_visualtype_t *visual_type;
  int screen_nbr;
  xcb_pixmap_t root_pixmap;
  int have_root_pixmap;

  struct nizam_dock_icon_cache *icon_cache;

  int panel_x;
  int panel_y;
  int panel_w;
  int panel_h;
  int mon_x;
  int mon_y;
  int mon_w;
  int mon_h;
  int handle_px;
  int buffer_w;
  int buffer_h;
  int backbuffer_recreates_total;
  size_t backbuffer_bytes;
  int64_t last_mem_log_ms;
  int redraw_pending;
  int redraw_force;
  uint64_t redraw_total;
  uint64_t redraw_reason_motion;
  uint64_t redraw_reason_timeout;
  uint64_t redraw_reason_expose;
  uint64_t motion_events_total;
  uint64_t hover_changes;
  int hovered_launcher_idx;
  int hovered_tray_idx;
  int64_t last_debug_log_ms;
  int y_visible;
  int x_visible;
  int x_hidden;
  int is_hidden;
  int hide_pending;
  int64_t hide_deadline_ms;
  int64_t last_draw_ms;
  int64_t last_toggle_ms;
  int64_t suppress_hide_until_ms;
  int64_t suppress_raise_until_ms;
  int tray_y;
  int tray_size;
  size_t tray_count;
  int tray_x;
  int tray_gap;
  int xembed_x;
  int xembed_y;
  int xembed_size;
  int xembed_gap;
  struct nizam_dock_xembed_icon *xembed_icons;
  size_t xembed_count;
  size_t xembed_cap;
  struct nizam_dock_launcher_rect *launcher_rects;
  size_t launcher_rect_count;
  int menu_x;
  int menu_y;
  int menu_w;
  int menu_h;
  int menu_item_h;
  size_t menu_count;
  size_t menu_owner_idx;
  int menu_visible;
  int menu_dirty;
  struct nizam_dock_menu_item *menu_items;
  char sysinfo_lines[NIZAM_DOCK_INFO_LINES][NIZAM_DOCK_INFO_LINE_MAX];

  struct nizam_dock_atoms atoms;
};

int nizam_dock_xcb_init(struct nizam_dock_app *app, const struct nizam_dock_config *cfg);
void nizam_dock_xcb_cleanup(struct nizam_dock_app *app);
int nizam_dock_xcb_event_loop(struct nizam_dock_app *app, struct nizam_dock_config *cfg);
void nizam_dock_xcb_recalc_geometry(struct nizam_dock_app *app, const struct nizam_dock_config *cfg);
void nizam_dock_xcb_apply_geometry(struct nizam_dock_app *app, const struct nizam_dock_config *cfg);
int nizam_dock_xcb_update_root_pixmap(struct nizam_dock_app *app);
void nizam_dock_xembed_layout(struct nizam_dock_app *app, const struct nizam_dock_config *cfg);
void nizam_dock_request_config_reload(void);

#endif
