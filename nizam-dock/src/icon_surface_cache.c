#include "icon_surface_cache.h"

#include <cairo/cairo.h>
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <glib.h>
#include <stdlib.h>
#include <string.h>

#include "icon_policy.h"
#include "sni.h"

struct icon_key {
  char *name;
  int size_px;
  int scale;
};

struct icon_entry {
  struct icon_key *key;
  cairo_surface_t *surface;
  struct icon_entry *prev;
  struct icon_entry *next;
};

struct nizam_dock_icon_cache {
  GHashTable *map;
  struct icon_entry *head;
  struct icon_entry *tail;
  int size;
  int capacity;
  int icon_px;
  int scale;
  uint64_t hits;
  uint64_t misses;
  uint64_t evictions;
  uint64_t alive_surfaces;
};

static guint icon_key_hash(gconstpointer data) {
  const struct icon_key *k = data;
  guint h = g_str_hash(k->name);
  h ^= (guint)(k->size_px * 1315423911u);
  h ^= (guint)(k->scale * 2654435761u);
  return h;
}

static gboolean icon_key_equal(gconstpointer a, gconstpointer b) {
  const struct icon_key *ka = a;
  const struct icon_key *kb = b;
  if (ka->size_px != kb->size_px || ka->scale != kb->scale) {
    return FALSE;
  }
  return strcmp(ka->name, kb->name) == 0;
}

static void icon_key_free(struct icon_key *key) {
  if (!key) {
    return;
  }
  free(key->name);
  free(key);
}

static void icon_entry_unlink(struct nizam_dock_icon_cache *cache, struct icon_entry *entry) {
  if (!cache || !entry) {
    return;
  }
  if (entry->prev) {
    entry->prev->next = entry->next;
  } else {
    cache->head = entry->next;
  }
  if (entry->next) {
    entry->next->prev = entry->prev;
  } else {
    cache->tail = entry->prev;
  }
  entry->prev = NULL;
  entry->next = NULL;
}

static void icon_entry_link_head(struct nizam_dock_icon_cache *cache, struct icon_entry *entry) {
  if (!cache || !entry) {
    return;
  }
  entry->prev = NULL;
  entry->next = cache->head;
  if (cache->head) {
    cache->head->prev = entry;
  } else {
    cache->tail = entry;
  }
  cache->head = entry;
}

static void icon_entry_touch(struct nizam_dock_icon_cache *cache, struct icon_entry *entry) {
  if (!cache || !entry || cache->head == entry) {
    return;
  }
  icon_entry_unlink(cache, entry);
  icon_entry_link_head(cache, entry);
}

static void icon_entry_destroy(struct nizam_dock_icon_cache *cache, struct icon_entry *entry) {
  if (!entry) {
    return;
  }
  if (entry->surface) {
    cairo_surface_destroy(entry->surface);
    if (cache) {
      cache->alive_surfaces--;
    }
  }
  icon_key_free(entry->key);
  free(entry);
}

static cairo_surface_t *surface_from_pixbuf(GdkPixbuf *pixbuf) {
  if (!pixbuf) {
    return NULL;
  }
  int w = gdk_pixbuf_get_width(pixbuf);
  int h = gdk_pixbuf_get_height(pixbuf);
  int stride_src = gdk_pixbuf_get_rowstride(pixbuf);
  int channels = gdk_pixbuf_get_n_channels(pixbuf);
  int has_alpha = gdk_pixbuf_get_has_alpha(pixbuf);
  const guchar *src = gdk_pixbuf_get_pixels(pixbuf);
  int stride_dst = cairo_format_stride_for_width(CAIRO_FORMAT_ARGB32, w);
  unsigned char *dst = calloc(1, (size_t)stride_dst * (size_t)h);
  if (!dst) {
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

  cairo_surface_t *surface = cairo_image_surface_create_for_data(
      dst, CAIRO_FORMAT_ARGB32, w, h, stride_dst);
  if (cairo_surface_status(surface) != CAIRO_STATUS_SUCCESS) {
    cairo_surface_destroy(surface);
    free(dst);
    return NULL;
  }
  cairo_surface_mark_dirty(surface);
  static cairo_user_data_key_t data_key;
  cairo_surface_set_user_data(surface, &data_key, dst, free);
  return surface;
}

static cairo_surface_t *load_icon_surface_fixed(const char *icon_name_or_path,
                                                int icon_px,
                                                int scale) {
  if (!icon_name_or_path || !*icon_name_or_path) {
    return NULL;
  }

  const char *use_path = icon_name_or_path;
  char resolved[512];
  if (!strchr(icon_name_or_path, '/')) {
    const char *found = nizam_dock_resolve_icon_path(icon_name_or_path, resolved, sizeof(resolved));
    if (found) {
      use_path = found;
    }
  }

  int target = icon_px * scale;
  if (target < 1) {
    target = icon_px;
  }

  GError *gerr = NULL;
  GdkPixbuf *pixbuf = gdk_pixbuf_new_from_file_at_scale(use_path, target, target, TRUE, &gerr);
  if (!pixbuf) {
    if (gerr) {
      g_error_free(gerr);
    }
    return NULL;
  }

  cairo_surface_t *surface = surface_from_pixbuf(pixbuf);
  g_object_unref(pixbuf);
  return surface;
}

struct nizam_dock_icon_cache *nizam_dock_icon_cache_new(int capacity, int icon_px, int scale) {
  struct nizam_dock_icon_cache *cache = calloc(1, sizeof(*cache));
  if (!cache) {
    return NULL;
  }
  cache->capacity = capacity;
  cache->icon_px = icon_px;
  cache->scale = scale;
  cache->map = g_hash_table_new(icon_key_hash, icon_key_equal);
  return cache;
}

void nizam_dock_icon_cache_clear(struct nizam_dock_icon_cache *cache) {
  if (!cache) {
    return;
  }
  struct icon_entry *entry = cache->head;
  while (entry) {
    struct icon_entry *next = entry->next;
    icon_entry_destroy(cache, entry);
    entry = next;
  }
  cache->head = NULL;
  cache->tail = NULL;
  cache->size = 0;
  g_hash_table_remove_all(cache->map);
}

void nizam_dock_icon_cache_free(struct nizam_dock_icon_cache *cache) {
  if (!cache) {
    return;
  }
  nizam_dock_icon_cache_clear(cache);
  g_hash_table_destroy(cache->map);
  free(cache);
}

cairo_surface_t *nizam_dock_icon_cache_get(struct nizam_dock_icon_cache *cache,
                                           const char *icon_name_or_path) {
  if (!cache || !icon_name_or_path || !*icon_name_or_path) {
    return NULL;
  }

  char norm[256];
  nizam_dock_icon_normalize(icon_name_or_path, norm, sizeof(norm));
  if (!norm[0]) {
    return NULL;
  }

  struct icon_key lookup_key = {
    .name = norm,
    .size_px = cache->icon_px,
    .scale = cache->scale
  };

  struct icon_entry *entry = g_hash_table_lookup(cache->map, &lookup_key);
  if (entry) {
    cache->hits++;
    icon_entry_touch(cache, entry);
    return entry->surface;
  }
  cache->misses++;

  cairo_surface_t *surface = load_icon_surface_fixed(icon_name_or_path,
                                                     cache->icon_px,
                                                     cache->scale);
  if (!surface) {
    return NULL;
  }

  if (cache->size >= cache->capacity && cache->tail) {
    struct icon_entry *victim = cache->tail;
    icon_entry_unlink(cache, victim);
    g_hash_table_remove(cache->map, victim->key);
    cache->evictions++;
    cache->size--;
    icon_entry_destroy(cache, victim);
  }

  struct icon_key *key = calloc(1, sizeof(*key));
  if (!key) {
    cairo_surface_destroy(surface);
    return NULL;
  }
  key->name = strdup(norm);
  key->size_px = cache->icon_px;
  key->scale = cache->scale;

  entry = calloc(1, sizeof(*entry));
  if (!entry) {
    icon_key_free(key);
    cairo_surface_destroy(surface);
    return NULL;
  }
  entry->key = key;
  entry->surface = surface;
  cache->alive_surfaces++;

  icon_entry_link_head(cache, entry);
  g_hash_table_insert(cache->map, entry->key, entry);
  cache->size++;

  return entry->surface;
}

void nizam_dock_icon_cache_get_stats(const struct nizam_dock_icon_cache *cache,
                                     struct nizam_dock_icon_cache_stats *out) {
  if (!cache || !out) {
    return;
  }
  out->hits = cache->hits;
  out->misses = cache->misses;
  out->evictions = cache->evictions;
  out->alive_surfaces = cache->alive_surfaces;
  out->size = cache->size;
  out->capacity = cache->capacity;
  out->icon_px = cache->icon_px;
  out->scale = cache->scale;
}
