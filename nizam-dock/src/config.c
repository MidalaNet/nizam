#include "config.h"

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include <sqlite3.h>

#include "icon_policy.h"

static int nizam_dock_debug_enabled(void) {
  const char *env = getenv("NIZAM_DOCK_DEBUG");
  return env && *env && strcmp(env, "0") != 0;
}

static char *nizam_dock_strdup(const char *s) {
  size_t len = strlen(s);
  char *out = malloc(len + 1);
  if (!out) {
    return NULL;
  }
  memcpy(out, s, len + 1);
  return out;
}

static int nizam_dock_build_path(char **out, const char *a, const char *b, const char *c) {
  if (!out) {
    return -1;
  }
  *out = NULL;
  size_t la = a ? strlen(a) : 0;
  size_t lb = b ? strlen(b) : 0;
  size_t lc = c ? strlen(c) : 0;
  size_t total = la + lb + lc + 1;
  char *buf = malloc(total);
  if (!buf) {
    return -1;
  }
  buf[0] = '\0';
  if (a) {
    strcat(buf, a);
  }
  if (b) {
    strcat(buf, b);
  }
  if (c) {
    strcat(buf, c);
  }
  *out = buf;
  return 0;
}

static int parse_bool(const char *s, int def) {
  if (!s) {
    return def;
  }
  while (*s == ' ' || *s == '\t' || *s == '\n' || *s == '\r') {
    ++s;
  }
  if (*s == '\0') {
    return def;
  }
  if (strcmp(s, "1") == 0) return 1;
  if (strcmp(s, "0") == 0) return 0;
  if (strcasecmp(s, "true") == 0) return 1;
  if (strcasecmp(s, "false") == 0) return 0;
  if (strcasecmp(s, "yes") == 0) return 1;
  if (strcasecmp(s, "no") == 0) return 0;
  if (strcasecmp(s, "on") == 0) return 1;
  if (strcasecmp(s, "off") == 0) return 0;
  return def;
}

static int sqlite_column_exists(sqlite3 *db, const char *table, const char *column) {
  if (!db || !table || !*table || !column || !*column) {
    return 0;
  }
  sqlite3_stmt *stmt = NULL;
  char sql[256];
  snprintf(sql, sizeof(sql), "PRAGMA table_info(%s)", table);
  if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK || !stmt) {
    return 0;
  }

  int found = 0;
  while (sqlite3_step(stmt) == SQLITE_ROW) {
    const unsigned char *name = sqlite3_column_text(stmt, 1);
    if (name && strcmp((const char *)name, column) == 0) {
      found = 1;
      break;
    }
  }
  sqlite3_finalize(stmt);
  return found;
}

static void str_trim(char *s) {
  if (!s) {
    return;
  }
  size_t n = strlen(s);
  while (n > 0 && (s[n - 1] == '\n' || s[n - 1] == '\r' || s[n - 1] == ' ' || s[n - 1] == '\t')) {
    s[n - 1] = '\0';
    n--;
  }
  size_t i = 0;
  while (s[i] == ' ' || s[i] == '\t') {
    i++;
  }
  if (i > 0) {
    memmove(s, s + i, strlen(s + i) + 1);
  }
}

static void sanitize_exec(const char *in, char *out, size_t out_len) {
  
  if (!out || out_len == 0) {
    return;
  }
  out[0] = '\0';
  if (!in) {
    return;
  }
  size_t j = 0;
  for (size_t i = 0; in[i] != '\0' && j + 1 < out_len; i++) {
    if (in[i] == '%') {
      if (in[i + 1] != '\0') {
        i++; 
      }
      continue;
    }
    out[j++] = in[i];
  }
  out[j] = '\0';
  str_trim(out);
}

static const char *map_category_token(const char *tok) {
  if (!tok || tok[0] == '\0') {
    return NULL;
  }

  
  if (!strcasecmp(tok, "Development") || !strcasecmp(tok, "IDE") || !strcasecmp(tok, "Programming") ||
      !strcasecmp(tok, "Debugger") || !strcasecmp(tok, "Profiling") || !strcasecmp(tok, "RevisionControl") ||
      !strcasecmp(tok, "Translation")) {
    return "Development";
  }

  
  if (!strcasecmp(tok, "Game") || !strcasecmp(tok, "Games")) {
    return "Games";
  }

  
  if (!strcasecmp(tok, "Graphics") || !strcasecmp(tok, "2DGraphics") || !strcasecmp(tok, "3DGraphics") ||
      !strcasecmp(tok, "Photography") || !strcasecmp(tok, "RasterGraphics") || !strcasecmp(tok, "VectorGraphics")) {
    return "Graphics";
  }

  
  if (!strcasecmp(tok, "AudioVideo") || !strcasecmp(tok, "Audio") || !strcasecmp(tok, "Video") ||
      !strcasecmp(tok, "Player") || !strcasecmp(tok, "Recorder") || !strcasecmp(tok, "Music") ||
      !strcasecmp(tok, "TV")) {
    return "Multimedia";
  }

  
  if (!strcasecmp(tok, "Education") || !strcasecmp(tok, "Science") || !strcasecmp(tok, "Math") ||
      !strcasecmp(tok, "Astronomy") || !strcasecmp(tok, "Biology") || !strcasecmp(tok, "Chemistry") ||
      !strcasecmp(tok, "Physics") || !strcasecmp(tok, "Geography") || !strcasecmp(tok, "History") ||
      !strcasecmp(tok, "Office") || !strcasecmp(tok, "WordProcessor") || !strcasecmp(tok, "Spreadsheet") ||
      !strcasecmp(tok, "Presentation")) {
    return "Office";
  }

  
  if (!strcasecmp(tok, "Utility") || !strcasecmp(tok, "Utilities") || !strcasecmp(tok, "Accessories")) {
    return "Utilities";
  }

  
  if (!strcasecmp(tok, "System") || !strcasecmp(tok, "Settings") || !strcasecmp(tok, "Preferences") ||
      !strcasecmp(tok, "Monitor") || !strcasecmp(tok, "Security") || !strcasecmp(tok, "PackageManager")) {
    return "System";
  }

  
  if (!strcasecmp(tok, "Network") || !strcasecmp(tok, "WebBrowser") || !strcasecmp(tok, "Email") ||
      !strcasecmp(tok, "Chat") || !strcasecmp(tok, "IRCClient") || !strcasecmp(tok, "FileTransfer") ||
      !strcasecmp(tok, "P2P") || !strcasecmp(tok, "InstantMessaging") || !strcasecmp(tok, "RemoteAccess")) {
    return "Network";
  }

  return NULL;
}

static void pick_category_mapped(char *out, size_t out_len, const char *cats) {
  if (!out || out_len == 0) {
    return;
  }
  out[0] = '\0';

  if (!cats || cats[0] == '\0') {
    strncpy(out, "System", out_len - 1);
    return;
  }

  
  const char *p = cats;
  while (*p) {
    while (*p == ' ' || *p == '\t' || *p == ';') {
      p++;
    }
    if (!*p) {
      break;
    }

    const char *start = p;
    while (*p && *p != ';') {
      p++;
    }
    const char *end = p;
    while (end > start && (end[-1] == ' ' || end[-1] == '\t')) {
      end--;
    }
    size_t n = (size_t)(end - start);
    if (n > 0) {
      char token[64];
      if (n >= sizeof(token)) {
        n = sizeof(token) - 1;
      }
      memcpy(token, start, n);
      token[n] = '\0';
      const char *mapped = map_category_token(token);
      if (mapped) {
        strncpy(out, mapped, out_len - 1);
        return;
      }
    }
    if (*p == ';') {
      p++;
    }
  }

  strncpy(out, "System", out_len - 1);
}

static int is_allowed_category_bucket(const char *cat) {
  if (!cat || cat[0] == '\0') {
    return 0;
  }
  if (!strcasecmp(cat, "Development")) return 1;
  if (!strcasecmp(cat, "Games")) return 1;
  if (!strcasecmp(cat, "Graphics")) return 1;
  if (!strcasecmp(cat, "Multimedia")) return 1;
  if (!strcasecmp(cat, "Office")) return 1;
  if (!strcasecmp(cat, "System")) return 1;
  if (!strcasecmp(cat, "Network")) return 1;
  if (!strcasecmp(cat, "Utilities")) return 1;
  return 0;
}

static char *nizam_db_path(void) {
  const char *env = getenv("NIZAM_DB");
  if (env && *env) {
    return nizam_dock_strdup(env);
  }
  const char *xdg = getenv("XDG_CONFIG_HOME");
  const char *home = getenv("HOME");
  char *p = NULL;
  if (xdg && *xdg) {
    if (nizam_dock_build_path(&p, xdg, "/nizam/nizam.db", NULL) != 0) {
      return NULL;
    }
    return p;
  }
  if (!home || !*home) {
    return NULL;
  }
  if (nizam_dock_build_path(&p, home, "/.config/nizam/nizam.db", NULL) != 0) {
    return NULL;
  }
  return p;
}

void nizam_dock_config_init_defaults(struct nizam_dock_config *cfg) {
  cfg->enabled = 1;
  cfg->icon_size = NIZAM_DOCK_ICON_PX;
  cfg->padding = 8;
  cfg->spacing = 10;
  cfg->bottom_margin = 12;
  cfg->hide_delay_ms = 800;
  cfg->handle_px = 16;
  
  cfg->bg_dim = 0.80;
  cfg->launchers = NULL;
  cfg->launcher_count = 0;
}

void nizam_dock_config_free(struct nizam_dock_config *cfg) {
  if (!cfg) {
    return;
  }
  for (size_t i = 0; i < cfg->launcher_count; ++i) {
    free(cfg->launchers[i].icon);
    free(cfg->launchers[i].cmd);
    free(cfg->launchers[i].category);
  }
  free(cfg->launchers);
  cfg->launchers = NULL;
  cfg->launcher_count = 0;
}

static char *trim_left(char *s) {
  while (*s && isspace((unsigned char)*s)) {
    ++s;
  }
  return s;
}

static void trim_right(char *s) {
  size_t len = strlen(s);
  while (len > 0 && isspace((unsigned char)s[len - 1])) {
    s[len - 1] = '\0';
    --len;
  }
}

static char *strip_quotes(char *s) {
  size_t len = strlen(s);
  if (len >= 2 && ((s[0] == '"' && s[len - 1] == '"') || (s[0] == '\'' && s[len - 1] == '\''))) {
    s[len - 1] = '\0';
    return s + 1;
  }
  return s;
}

static void config_add_launcher(struct nizam_dock_config *cfg) {
  struct nizam_dock_launcher *new_arr = realloc(cfg->launchers, sizeof(*cfg->launchers) * (cfg->launcher_count + 1));
  if (!new_arr) {
    return;
  }
  cfg->launchers = new_arr;
  cfg->launchers[cfg->launcher_count].icon = NULL;
  cfg->launchers[cfg->launcher_count].cmd = NULL;
  cfg->launchers[cfg->launcher_count].category = NULL;
  cfg->launcher_count += 1;
}

static void config_clear_launchers(struct nizam_dock_config *cfg) {
  if (!cfg) {
    return;
  }
  for (size_t i = 0; i < cfg->launcher_count; ++i) {
    free(cfg->launchers[i].icon);
    free(cfg->launchers[i].cmd);
    free(cfg->launchers[i].category);
  }
  free(cfg->launchers);
  cfg->launchers = NULL;
  cfg->launcher_count = 0;
}

static char *get_xdg_data_home(void) {
  const char *xdg = getenv("XDG_DATA_HOME");
  if (xdg && *xdg) {
    return nizam_dock_strdup(xdg);
  }
  const char *home = getenv("HOME");
  if (!home || !*home) {
    return NULL;
  }
  size_t len = strlen(home) + strlen("/.local/share") + 1;
  char *out = malloc(len);
  if (!out) {
    return NULL;
  }
  snprintf(out, len, "%s/.local/share", home);
  return out;
}

static char *build_local_applications_dir(void) {
  char *base = get_xdg_data_home();
  if (!base) {
    return NULL;
  }
  size_t len = strlen(base) + strlen("/applications") + 1;
  char *out = malloc(len);
  if (!out) {
    free(base);
    return NULL;
  }
  snprintf(out, len, "%s/applications", base);
  free(base);
  return out;
}

static int key_to_bool(const char *value) {
  return parse_bool(value, 0);
}

static void load_launchers_from_desktop(struct nizam_dock_config *cfg) {
  char *dir_path = build_local_applications_dir();
  if (!dir_path) {
    return;
  }

  DIR *dir = opendir(dir_path);
  if (!dir) {
    free(dir_path);
    return;
  }

  struct dirent *ent;
  while ((ent = readdir(dir)) != NULL) {
    const char *name = ent->d_name;
    size_t name_len = strlen(name);
    if (name_len < 9 || strcmp(name + name_len - 8, ".desktop") != 0) {
      continue;
    }

    size_t path_len = strlen(dir_path) + 1 + strlen(name) + 1;
    char *path = malloc(path_len);
    if (!path) {
      continue;
    }
    snprintf(path, path_len, "%s/%s", dir_path, name);

    FILE *fp = fopen(path, "r");
    if (!fp) {
      free(path);
      continue;
    }

    int in_entry = 0;
    int managed = 0;
    int enabled = 0;
    int hidden = 0;
    int nodisplay = 0;
    char *exec = NULL;
    char *icon = NULL;
    char *cats = NULL;

    char line[1024];
    while (fgets(line, sizeof(line), fp)) {
      char *cursor = trim_left(line);
      if (*cursor == '\0' || *cursor == '\n' || *cursor == '#' || *cursor == ';') {
        continue;
      }
      if (*cursor == '[') {
        in_entry = (strncmp(cursor, "[Desktop Entry]", 15) == 0);
        continue;
      }
      if (!in_entry) {
        continue;
      }

      char *eq = strchr(cursor, '=');
      if (!eq) {
        continue;
      }
      *eq = '\0';
      char *key = trim_left(cursor);
      trim_right(key);
      char *value = trim_left(eq + 1);
      trim_right(value);
      value = strip_quotes(value);

      if (strcmp(key, "Type") == 0) {
        if (strcasecmp(value, "Application") != 0) {
          in_entry = 0;
        }
      } else if (strcmp(key, "Hidden") == 0) {
        hidden = key_to_bool(value);
      } else if (strcmp(key, "NoDisplay") == 0) {
        nodisplay = key_to_bool(value);
      } else if (strcmp(key, "Exec") == 0) {
        free(exec);
        exec = nizam_dock_strdup(value);
      } else if (strcmp(key, "Icon") == 0) {
        free(icon);
        icon = nizam_dock_strdup(value);
      } else if (strcmp(key, "Categories") == 0) {
        free(cats);
        cats = nizam_dock_strdup(value);
      } else if (strcmp(key, "X-Nizam-Managed") == 0) {
        managed = key_to_bool(value);
      } else if (strcmp(key, "X-Nizam-Enabled") == 0) {
        enabled = key_to_bool(value);
      }
    }
    fclose(fp);
    free(path);

    if (hidden || nodisplay || !managed || !enabled || !exec || !*exec) {
      free(exec);
      free(icon);
      free(cats);
      continue;
    }

    char exec_clean[1024];
    sanitize_exec(exec, exec_clean, sizeof(exec_clean));
    if (!exec_clean[0]) {
      free(exec);
      free(icon);
      free(cats);
      continue;
    }

    char cat_buf[64];
    pick_category_mapped(cat_buf, sizeof(cat_buf), cats ? cats : "");

    config_add_launcher(cfg);
    struct nizam_dock_launcher *launcher = &cfg->launchers[cfg->launcher_count - 1];
    launcher->cmd = nizam_dock_strdup(exec_clean);
    if (icon && *icon) {
      launcher->icon = nizam_dock_strdup(icon);
    } else {
      launcher->icon = nizam_dock_strdup("nizam-app-generic");
    }
    if (cat_buf[0]) {
      launcher->category = nizam_dock_strdup(cat_buf);
    }

    free(exec);
    free(icon);
    free(cats);
  }

  closedir(dir);
  free(dir_path);
}

static void load_launchers_from_nizam_db_where(sqlite3 *db,
                                               struct nizam_dock_config *cfg,
                                               const char *where_tail,
                                               int has_user_name,
                                               int has_user_exec,
                                               int has_user_categories,
                                               int has_deleted) {
  if (!db || !cfg) {
    return;
  }

  const char *base_sql = NULL;
  if (has_user_name || has_user_exec || has_user_categories) {
    base_sql =
        "SELECT "
        "coalesce(user_exec, exec) as exec, "
        "icon, category, "
        "coalesce(user_categories, categories) as categories "
        "FROM desktop_entries "
        "WHERE enabled=1";
  } else {
    base_sql =
        "SELECT exec, icon, category, categories "
        "FROM desktop_entries "
        "WHERE enabled=1";
  }

  char sql_buf[768];
  snprintf(sql_buf, sizeof(sql_buf), "%s", base_sql);
  if (where_tail && *where_tail) {
    strncat(sql_buf, " AND ", sizeof(sql_buf) - strlen(sql_buf) - 1);
    strncat(sql_buf, where_tail, sizeof(sql_buf) - strlen(sql_buf) - 1);
  }
  if (has_deleted) {
    strncat(sql_buf, " AND coalesce(deleted,0)=0", sizeof(sql_buf) - strlen(sql_buf) - 1);
  }

  
  if (has_user_name) {
    strncat(sql_buf, " ORDER BY category, lower(coalesce(user_name, name))", sizeof(sql_buf) - strlen(sql_buf) - 1);
  } else {
    strncat(sql_buf, " ORDER BY category, lower(name)", sizeof(sql_buf) - strlen(sql_buf) - 1);
  }

  sqlite3_stmt *st = NULL;
  if (sqlite3_prepare_v2(db, sql_buf, -1, &st, NULL) != SQLITE_OK || !st) {
    return;
  }

  while (sqlite3_step(st) == SQLITE_ROW) {
    const char *exec = (const char *)sqlite3_column_text(st, 0);
    const char *icon = (const char *)sqlite3_column_text(st, 1);
    const char *cat = (const char *)sqlite3_column_text(st, 2);
    const char *cats = (const char *)sqlite3_column_text(st, 3);

    if (!exec || !*exec) {
      continue;
    }

    char exec_clean[1024];
    sanitize_exec(exec, exec_clean, sizeof(exec_clean));
    if (!exec_clean[0]) {
      continue;
    }

    char cat_buf[64];
    if (cat && *cat && is_allowed_category_bucket(cat)) {
      snprintf(cat_buf, sizeof(cat_buf), "%s", cat);
    } else {
      pick_category_mapped(cat_buf, sizeof(cat_buf), cats ? cats : "");
    }

    config_add_launcher(cfg);
    struct nizam_dock_launcher *launcher = &cfg->launchers[cfg->launcher_count - 1];
    launcher->cmd = nizam_dock_strdup(exec_clean);
    if (icon && *icon) {
      launcher->icon = nizam_dock_strdup(icon);
    } else {
      launcher->icon = nizam_dock_strdup("nizam-app-generic");
    }
    if (cat_buf[0]) {
      launcher->category = nizam_dock_strdup(cat_buf);
    }
  }

  sqlite3_finalize(st);
}

static void load_launchers_from_nizam_db(struct nizam_dock_config *cfg) {
  if (!cfg) {
    return;
  }

  char *path = nizam_db_path();
  if (!path) {
    return;
  }

  
  if (access(path, R_OK) != 0) {
    if (nizam_dock_debug_enabled()) {
      fprintf(stderr, "nizam-dock: launchers DB not readable: %s\n", path);
    }
    free(path);
    return;
  }

  sqlite3 *db = NULL;
  
  int rc_open = sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, NULL);
  if (rc_open != SQLITE_OK || !db) {
    if (db) sqlite3_close(db);
    db = NULL;
    
    rc_open = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, NULL);
    if (rc_open != SQLITE_OK || !db) {
      free(path);
      if (db) sqlite3_close(db);
      return;
    }
  }
  free(path);

  sqlite3_busy_timeout(db, 2000);
  (void)sqlite3_exec(db, "PRAGMA query_only=ON;", NULL, NULL, NULL);

  int has_add_to_dock = sqlite_column_exists(db, "desktop_entries", "add_to_dock");
  int has_deleted = sqlite_column_exists(db, "desktop_entries", "deleted");
  int has_user_name = sqlite_column_exists(db, "desktop_entries", "user_name");
  int has_user_exec = sqlite_column_exists(db, "desktop_entries", "user_exec");
  int has_user_categories = sqlite_column_exists(db, "desktop_entries", "user_categories");

  if (has_add_to_dock) {
    load_launchers_from_nizam_db_where(db, cfg, "add_to_dock=1", has_user_name, has_user_exec, has_user_categories, has_deleted);
  }

  sqlite3_close(db);
}

static void set_int_field(int *field, const char *value) {
  char *end = NULL;
  errno = 0;
  long parsed = strtol(value, &end, 10);
  if (errno == 0 && end != value) {
    *field = (int)parsed;
  }
}

static void set_double_field(double *field, const char *value) {
  char *end = NULL;
  errno = 0;
  double parsed = strtod(value, &end);
  if (errno == 0 && end != value) {
    if (parsed < 0.0) {
      parsed = 0.0;
    } else if (parsed > 1.0) {
      parsed = 1.0;
    }
    *field = parsed;
  }
}

static const char *launcher_category(const struct nizam_dock_launcher *launcher) {
  if (launcher && launcher->category && *launcher->category) {
    return launcher->category;
  }
  return "";
}

static const char *launcher_sort_key(const struct nizam_dock_launcher *launcher) {
  if (launcher && launcher->cmd && *launcher->cmd) {
    return launcher->cmd;
  }
  if (launcher && launcher->icon && *launcher->icon) {
    return launcher->icon;
  }
  return "";
}

static int compare_launchers(const void *a, const void *b) {
  const struct nizam_dock_launcher *left = a;
  const struct nizam_dock_launcher *right = b;
  int cmp = strcasecmp(launcher_category(left), launcher_category(right));
  if (cmp != 0) {
    return cmp;
  }
  cmp = strcasecmp(launcher_sort_key(left), launcher_sort_key(right));
  if (cmp != 0) {
    return cmp;
  }
  return strcasecmp(left->icon ? left->icon : "", right->icon ? right->icon : "");
}

int nizam_dock_config_load(struct nizam_dock_config *cfg, const char *path) {
  FILE *fp = fopen(path, "r");
  if (!fp) {
    return -1;
  }

  char line[512];
  while (fgets(line, sizeof(line), fp)) {
    char *cursor = trim_left(line);
    if (*cursor == '\0' || *cursor == '\n' || *cursor == '#' || *cursor == ';') {
      continue;
    }

    char *eq = strchr(cursor, '=');
    if (!eq) {
      continue;
    }
    *eq = '\0';
    char *key = trim_left(cursor);
    trim_right(key);

    char *value = trim_left(eq + 1);
    trim_right(value);
    value = strip_quotes(value);

    if (strcmp(key, "enabled") == 0) {
      cfg->enabled = parse_bool(value, cfg->enabled);
    } else if (strcmp(key, "padding") == 0) {
      set_int_field(&cfg->padding, value);
    } else if (strcmp(key, "spacing") == 0) {
      set_int_field(&cfg->spacing, value);
    } else if (strcmp(key, "bottom_margin") == 0) {
      set_int_field(&cfg->bottom_margin, value);
    } else if (strcmp(key, "hide_delay_ms") == 0) {
      set_int_field(&cfg->hide_delay_ms, value);
    } else if (strcmp(key, "handle_px") == 0) {
      set_int_field(&cfg->handle_px, value);
    } else if (strcmp(key, "bg_dim") == 0) {
      set_double_field(&cfg->bg_dim, value);
    }
  }

  fclose(fp);
  cfg->icon_size = NIZAM_DOCK_ICON_PX;
  return 0;
}

int nizam_dock_config_load_launchers(struct nizam_dock_config *cfg) {
  if (!cfg) {
    return -1;
  }

  config_clear_launchers(cfg);
  load_launchers_from_nizam_db(cfg);
  if (cfg->launcher_count == 0) {
    if (nizam_dock_debug_enabled()) {
      fprintf(stderr, "nizam-dock: no launcher(s) from nizam.db, falling back to local .desktop scan\n");
    }
    load_launchers_from_desktop(cfg);
  } else if (nizam_dock_debug_enabled()) {
    fprintf(stderr, "nizam-dock: loaded %zu launcher(s) from nizam.db\n", cfg->launcher_count);
  }
  if (cfg->launcher_count > 1) {
    qsort(cfg->launchers, cfg->launcher_count, sizeof(*cfg->launchers), compare_launchers);
  }
  return 0;
}
