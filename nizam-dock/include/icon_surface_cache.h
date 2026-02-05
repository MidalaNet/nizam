#ifndef NIZAM_DOCK_ICON_SURFACE_CACHE_H
#define NIZAM_DOCK_ICON_SURFACE_CACHE_H

#include <stdint.h>

typedef struct _cairo_surface cairo_surface_t;
struct nizam_dock_icon_cache;

struct nizam_dock_icon_cache_stats {
  uint64_t hits;
  uint64_t misses;
  uint64_t evictions;
  uint64_t alive_surfaces;
  int size;
  int capacity;
  int icon_px;
  int scale;
};

struct nizam_dock_icon_cache *nizam_dock_icon_cache_new(int capacity, int icon_px, int scale);
void nizam_dock_icon_cache_free(struct nizam_dock_icon_cache *cache);
void nizam_dock_icon_cache_clear(struct nizam_dock_icon_cache *cache);
cairo_surface_t *nizam_dock_icon_cache_get(struct nizam_dock_icon_cache *cache,
                                           const char *icon_name_or_path);
void nizam_dock_icon_cache_get_stats(const struct nizam_dock_icon_cache *cache,
                                     struct nizam_dock_icon_cache_stats *out);

#endif
