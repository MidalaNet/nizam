#ifndef NIZAM_DOCK_CONFIG_H
#define NIZAM_DOCK_CONFIG_H

#include <stddef.h>

struct nizam_dock_launcher {
  char *icon;
  char *cmd;
  char *category;
};

struct nizam_dock_config {
  int enabled;
  int icon_size;
  int padding;
  int spacing;
  int bottom_margin;
  int hide_delay_ms;
  int handle_px;

  double bg_dim;

  struct nizam_dock_launcher *launchers;
  size_t launcher_count;
};

void nizam_dock_config_init_defaults(struct nizam_dock_config *cfg);
void nizam_dock_config_free(struct nizam_dock_config *cfg);






int nizam_dock_config_load_launchers(struct nizam_dock_config *cfg);

#endif
