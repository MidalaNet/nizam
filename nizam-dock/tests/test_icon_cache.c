#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <cairo/cairo.h>
#include <glib.h>

#include "icon_policy.h"
#include "icon_surface_cache.h"

const char *nizam_dock_resolve_icon_path(const char *name, char *out, size_t out_size) {
  (void)name;
  (void)out;
  (void)out_size;
  return NULL;
}

static char *write_temp_png(void) {
  char tmpl[] = "/tmp/nizam-dock-icon-XXXXXX";
  int fd = mkstemp(tmpl);
  if (fd < 0) {
    return NULL;
  }
  close(fd);

  cairo_surface_t *surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 4, 4);
  cairo_t *cr = cairo_create(surface);
  cairo_set_source_rgba(cr, 1.0, 0.0, 0.0, 1.0);
  cairo_paint(cr);
  cairo_destroy(cr);

  if (cairo_surface_write_to_png(surface, tmpl) != CAIRO_STATUS_SUCCESS) {
    cairo_surface_destroy(surface);
    unlink(tmpl);
    return NULL;
  }
  cairo_surface_destroy(surface);
  return g_strdup(tmpl);
}

int main(void) {
  struct nizam_dock_icon_cache *cache =
      nizam_dock_icon_cache_new(2, NIZAM_DOCK_ICON_PX, NIZAM_DOCK_ICON_SCALE);
  assert(cache != NULL);

  char *p1 = write_temp_png();
  char *p2 = write_temp_png();
  char *p3 = write_temp_png();
  assert(p1 && p2 && p3);

  cairo_surface_t *s1 = nizam_dock_icon_cache_get(cache, p1);
  cairo_surface_t *s2 = nizam_dock_icon_cache_get(cache, p2);
  assert(s1 && s2);

  struct nizam_dock_icon_cache_stats stats;
  nizam_dock_icon_cache_get_stats(cache, &stats);
  assert(stats.size == 2);

  cairo_surface_t *s1b = nizam_dock_icon_cache_get(cache, p1);
  assert(s1b == s1);

  nizam_dock_icon_cache_get(cache, p3);
  nizam_dock_icon_cache_get_stats(cache, &stats);
  assert(stats.size == 2);
  assert(stats.evictions >= 1);

  nizam_dock_icon_cache_free(cache);
  unlink(p1);
  unlink(p2);
  unlink(p3);
  g_free(p1);
  g_free(p2);
  g_free(p3);
  return 0;
}
