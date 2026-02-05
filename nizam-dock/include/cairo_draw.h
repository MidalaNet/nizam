#ifndef NIZAM_DOCK_CAIRO_DRAW_H
#define NIZAM_DOCK_CAIRO_DRAW_H

#include "config.h"
#include "xcb_app.h"

int nizam_dock_icons_init(struct nizam_dock_app *app, const struct nizam_dock_config *cfg);
void nizam_dock_icons_free(struct nizam_dock_app *app);
int nizam_dock_sysinfo_init(struct nizam_dock_app *app);
int nizam_dock_draw(struct nizam_dock_app *app, const struct nizam_dock_config *cfg);

#endif
