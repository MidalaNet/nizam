#ifndef NIZAM_DOCK_SNI_H
#define NIZAM_DOCK_SNI_H

#include <stddef.h>
#include <stdint.h>

struct nizam_dock_app;
struct nizam_dock_menu_item;
typedef struct _cairo_surface cairo_surface_t;

int nizam_dock_sni_init(struct nizam_dock_app *app);
void nizam_dock_sni_cleanup(struct nizam_dock_app *app);
int nizam_dock_sni_get_fd(const struct nizam_dock_app *app);
int nizam_dock_sni_process(struct nizam_dock_app *app);
size_t nizam_dock_sni_count(const struct nizam_dock_app *app);
cairo_surface_t *nizam_dock_sni_icon(const struct nizam_dock_app *app, size_t idx);
const char *nizam_dock_resolve_icon_path(const char *name, char *out, size_t out_size);
cairo_surface_t *nizam_dock_load_icon_surface(const char *path);
int nizam_dock_sni_activate(struct nizam_dock_app *app, size_t idx, int x, int y);
int nizam_dock_sni_secondary_activate(struct nizam_dock_app *app, size_t idx, int x, int y);
int nizam_dock_sni_xayatana_secondary(struct nizam_dock_app *app, size_t idx, uint32_t time);
int nizam_dock_sni_context_menu(struct nizam_dock_app *app, size_t idx, int x, int y);
int nizam_dock_sni_item_has_activate(const struct nizam_dock_app *app, size_t idx);
int nizam_dock_sni_item_has_secondary(const struct nizam_dock_app *app, size_t idx);
int nizam_dock_sni_item_has_context(const struct nizam_dock_app *app, size_t idx);
int nizam_dock_sni_item_has_xayatana_secondary(const struct nizam_dock_app *app, size_t idx);
int nizam_dock_sni_item_is_menu(const struct nizam_dock_app *app, size_t idx);
int nizam_dock_sni_item_has_menu(const struct nizam_dock_app *app, size_t idx);
int nizam_dock_sni_menu_fetch(struct nizam_dock_app *app, size_t idx,
                            struct nizam_dock_menu_item **items, size_t *count);
int nizam_dock_sni_menu_event(struct nizam_dock_app *app, size_t idx, int32_t item_id, uint32_t time);

#endif
