using GLib;
using Sqlite;

namespace NizamSettings {
    public class Migrations : Object {
        private const int LATEST_SCHEMA = 19;

        
        private static void maybe_remove_legacy_autostart_seed (NizamDb ndb) {
            try {
                
                Statement st;
                var rc = ndb.handle.prepare_v2("SELECT value FROM meta WHERE key='wm_autostart_seed_removed'", -1, out st);
                if (rc == Sqlite.OK) {
                    rc = st.step();
                    if (rc == Sqlite.ROW) {
                        return;
                    }
                }

                
                int total = 0;
                {
                    Statement s;
                    rc = ndb.handle.prepare_v2("SELECT count(*) FROM wm_autostart", -1, out s);
                    if (rc != Sqlite.OK) return;
                    rc = s.step();
                    if (rc == Sqlite.ROW) total = s.column_int(0);
                }
                if (total != 4) return;

                int seeded = 0;
                {
                    Statement s;
                    rc = ndb.handle.prepare_v2(
                        "SELECT count(*) FROM wm_autostart WHERE command IN (" +
                        "'volumeicon','volumeicon &'," +
                        "'nm-applet','nm-applet &'," +
                        "'xpad','xpad &'," +
                        "'dropbox start'" +
                        ")",
                        -1,
                        out s
                    );
                    if (rc != Sqlite.OK) return;
                    rc = s.step();
                    if (rc == Sqlite.ROW) seeded = s.column_int(0);
                }
                if (seeded != 4) return;

                
                ndb.exec("DELETE FROM wm_autostart;");
                try { ndb.exec("DELETE FROM wm_settings WHERE key='pekwm.start.autostart.block';"); } catch (Error e) { }
                ndb.exec("INSERT OR IGNORE INTO meta(key,value) VALUES('wm_autostart_seed_removed','1');");
            } catch (Error e) {
                
            }
        }

        private static bool table_has_column (NizamDb ndb, string table, string column) {
            Statement stmt;
            var rc = ndb.handle.prepare_v2("PRAGMA table_info(%s)".printf(table), -1, out stmt);
            if (rc != Sqlite.OK) return false;

            while ((rc = stmt.step()) == Sqlite.ROW) {
                var name = stmt.column_text(1);
                if (name != null && name == column) return true;
            }
            return false;
        }

        private static string select_text_expr (NizamDb ndb, string table, string column, string fallback_literal) {
            return table_has_column(ndb, table, column)
                ? "coalesce(%s,%s)".printf(column, fallback_literal)
                : fallback_literal;
        }

        private static string select_int_expr (NizamDb ndb, string table, string column, int fallback) {
            return table_has_column(ndb, table, column)
                ? "coalesce(%s,%d)".printf(column, fallback)
                : "%d".printf(fallback);
        }

        public static void ensure_schema (NizamDb ndb) throws Error {
            
            ndb.exec(@"
                CREATE TABLE IF NOT EXISTS meta (
                  key   TEXT PRIMARY KEY,
                  value TEXT NOT NULL
                );
            ");

            int current = get_schema_version(ndb);
            if (current < 0) current = 0;

            
            
            
            
            
            if (current == LATEST_SCHEMA) {
                
                
                try { ndb.exec("DROP INDEX IF EXISTS idx_wm_menu_items_menu_sort;"); } catch (Error e) { }
                try { ndb.exec("DROP TABLE IF EXISTS wm_menu_items;"); } catch (Error e) { }
                try { ndb.exec("DELETE FROM wm_settings WHERE key='pekwm.menu.block';"); } catch (Error e) { }

                
                maybe_remove_legacy_autostart_seed(ndb);
                return;
            }

            
            
            if (current == 17) {
                create_schema_v19(ndb);
                set_schema_version(ndb, LATEST_SCHEMA);
                return;
            }

            if (current != 0) {
                throw new IOError.FAILED(
                    ("Unsupported nizam.db schema_version=%d (only v%d is supported). " +
                     "Delete $XDG_CONFIG_HOME/nizam/nizam.db to reinitialize.")
                    .printf(current, LATEST_SCHEMA)
                );
            }

            create_schema_v19(ndb);
            set_schema_version(ndb, LATEST_SCHEMA);
        }

        private static int get_schema_version (NizamDb ndb) throws Error {
            Statement stmt;
            var rc = ndb.handle.prepare_v2("SELECT value FROM meta WHERE key='schema_version'", -1, out stmt);
            if (rc != Sqlite.OK) throw new IOError.FAILED(ndb.handle.errmsg());

            rc = stmt.step();
            if (rc == Sqlite.ROW) {
                var v = stmt.column_text(0);
                if (v == null) return 0;
                return int.parse(v);
            }
            return 0;
        }

        private static void set_schema_version (NizamDb ndb, int ver) throws Error {
            Statement stmt;
            var sql = "INSERT INTO meta(key,value) VALUES('schema_version',?1) " +
                      "ON CONFLICT(key) DO UPDATE SET value=excluded.value";
            var rc = ndb.handle.prepare_v2(sql, -1, out stmt);
            if (rc != Sqlite.OK) throw new IOError.FAILED(ndb.handle.errmsg());
            stmt.bind_text(1, ver.to_string());
            rc = stmt.step();
            if (rc != Sqlite.DONE) throw new IOError.FAILED(ndb.handle.errmsg());
        }

        private static void create_schema_v19 (NizamDb ndb) throws Error {
            
            ndb.exec(@"
                CREATE TABLE IF NOT EXISTS settings (
                  scope TEXT NOT NULL,
                  key   TEXT NOT NULL,
                  type  TEXT NOT NULL,
                  value TEXT NOT NULL,
                  PRIMARY KEY (scope, key)
                );

                CREATE TABLE IF NOT EXISTS wm_settings (
                  key   TEXT PRIMARY KEY,
                  value TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS wm_keys (
                  id      INTEGER PRIMARY KEY,
                  accel   TEXT NOT NULL,
                  action  TEXT NOT NULL,
                  enabled INTEGER NOT NULL DEFAULT 1
                );

                CREATE TABLE IF NOT EXISTS wm_autostart (
                  id      INTEGER PRIMARY KEY,
                  command TEXT NOT NULL,
                  enabled INTEGER NOT NULL DEFAULT 1
                );
            ");

            
            try { ndb.exec("ALTER TABLE settings ADD COLUMN type TEXT NOT NULL DEFAULT 'text';"); } catch (Error e) { }

            ndb.exec("INSERT OR IGNORE INTO meta(key,value) VALUES('updated_at','0');");

            
            
            
            try { ndb.exec("DELETE FROM settings WHERE scope='dock' OR scope LIKE 'panel%';"); } catch (Error e) { }

            
            ndb.exec(@"
                INSERT OR IGNORE INTO wm_settings(key,value) VALUES
                ('pekwm.theme','$$_PEKWM_THEME_PATH/default'),
                ('pekwm.workspaces.count','4'),
                ('pekwm.focus.mode','click'),
                ('pekwm.border.width','2'),
                ('pekwm.title.height','22'),
                ('pekwm.start.block',''),

                ('pekwm.start.wallpaper.mode','--bg-scale'),
                ('pekwm.start.wallpaper.path',''),
                ('pekwm.start.feh.version','');

                INSERT OR IGNORE INTO wm_keys(accel,action,enabled) VALUES
                ('Mod4-Return','Exec x-terminal-emulator',1),
                ('Mod4-d','Exec nizam-launcher --show',1),
                ('Mod4-Left','GotoWorkspace Left',1),
                ('Mod4-Right','GotoWorkspace Right',1),
                ('Mod4-q','Close',1);

                -- Autostart is managed by the UI (wm_autostart). Keep it empty by default.
            ");

            ensure_desktop_entries_v19(ndb);
            ensure_indexes_v19(ndb);
            try { ndb.exec("PRAGMA optimize;"); } catch (Error e) { }
        }

        private static void ensure_indexes_v19 (NizamDb ndb) {
            
            try { ndb.exec("CREATE INDEX IF NOT EXISTS idx_wm_autostart_enabled ON wm_autostart(enabled, id);"); } catch (Error e) { }
            try { ndb.exec("CREATE INDEX IF NOT EXISTS idx_desktop_entries_menu ON desktop_entries(category, lower(coalesce(user_name, name))) WHERE enabled = 1 AND deleted = 0;"); } catch (Error e) { }
            try { ndb.exec("CREATE INDEX IF NOT EXISTS idx_desktop_entries_dock ON desktop_entries(category, lower(coalesce(user_name, name))) WHERE enabled = 1 AND deleted = 0 AND add_to_dock = 1;"); } catch (Error e) { }
            try { ndb.exec("CREATE INDEX IF NOT EXISTS idx_desktop_entries_settings_list ON desktop_entries(lower(coalesce(user_name, name)), enabled, filename) WHERE deleted = 0;"); } catch (Error e) { }
        }

        private static void ensure_desktop_entries_v19 (NizamDb ndb) throws Error {
            
            ndb.exec(@"
                CREATE TABLE IF NOT EXISTS desktop_entries (
                  filename    TEXT PRIMARY KEY,
                  name        TEXT NOT NULL,
                  exec        TEXT NOT NULL,
                  categories  TEXT NOT NULL DEFAULT '',
                  icon        TEXT NOT NULL DEFAULT '',
                  managed     INTEGER NOT NULL DEFAULT 0,
                  enabled     INTEGER NOT NULL DEFAULT 1,
                  add_to_dock INTEGER NOT NULL DEFAULT 0,
                  updated_at  INTEGER NOT NULL DEFAULT 0,
                  category    TEXT NOT NULL DEFAULT 'System',
                  source      TEXT NOT NULL DEFAULT '',
                  user_name   TEXT,
                  user_exec   TEXT,
                  user_categories TEXT,
                  deleted     INTEGER NOT NULL DEFAULT 0
                );
            ");

            
            bool looks_v19 = table_has_column(ndb, "desktop_entries", "category") &&
                             table_has_column(ndb, "desktop_entries", "source") &&
                             table_has_column(ndb, "desktop_entries", "user_categories") &&
                             table_has_column(ndb, "desktop_entries", "deleted");
            if (!looks_v19) {
                
                var has_filename = table_has_column(ndb, "desktop_entries", "filename");
                var has_name = table_has_column(ndb, "desktop_entries", "name");
                var has_exec = table_has_column(ndb, "desktop_entries", "exec");
                if (!has_filename || !has_name || !has_exec) {
                    
                    return;
                }

                ndb.exec("BEGIN IMMEDIATE;");
                try {
                    ndb.exec(@"
                        CREATE TABLE IF NOT EXISTS desktop_entries_new (
                          filename    TEXT PRIMARY KEY,
                          name        TEXT NOT NULL,
                          exec        TEXT NOT NULL,
                          categories  TEXT NOT NULL DEFAULT '',
                          icon        TEXT NOT NULL DEFAULT '',
                          managed     INTEGER NOT NULL DEFAULT 0,
                          enabled     INTEGER NOT NULL DEFAULT 1,
                          add_to_dock INTEGER NOT NULL DEFAULT 0,
                          updated_at  INTEGER NOT NULL DEFAULT 0,
                          category    TEXT NOT NULL DEFAULT 'System',
                          source      TEXT NOT NULL DEFAULT '',
                          user_name   TEXT,
                          user_exec   TEXT,
                          user_categories TEXT,
                          deleted     INTEGER NOT NULL DEFAULT 0
                        );
                    ");

                    var insert_sql = "INSERT INTO desktop_entries_new(" +
                                     "filename,name,exec,categories,icon,managed,enabled,add_to_dock,updated_at,category,source,user_name,user_exec,user_categories,deleted" +
                                     ") SELECT " +
                                     "filename, " +
                                     select_text_expr(ndb, "desktop_entries", "name", "''") + ", " +
                                     select_text_expr(ndb, "desktop_entries", "exec", "''") + ", " +
                                     select_text_expr(ndb, "desktop_entries", "categories", "''") + ", " +
                                     select_text_expr(ndb, "desktop_entries", "icon", "''") + ", " +
                                     select_int_expr(ndb, "desktop_entries", "managed", 0) + ", " +
                                     select_int_expr(ndb, "desktop_entries", "enabled", 1) + ", " +
                                     select_int_expr(ndb, "desktop_entries", "add_to_dock", 0) + ", " +
                                     select_int_expr(ndb, "desktop_entries", "updated_at", 0) + ", " +
                                     select_text_expr(ndb, "desktop_entries", "category", "'System'") + ", " +
                                     select_text_expr(ndb, "desktop_entries", "source", "''") + ", " +
                                     (table_has_column(ndb, "desktop_entries", "user_name") ? "user_name" : "NULL") + ", " +
                                     (table_has_column(ndb, "desktop_entries", "user_exec") ? "user_exec" : "NULL") + ", " +
                                     (table_has_column(ndb, "desktop_entries", "user_categories") ? "user_categories" : "NULL") + ", " +
                                     select_int_expr(ndb, "desktop_entries", "deleted", 0) +
                                     " FROM desktop_entries";

                    ndb.exec(insert_sql);
                    ndb.exec("DROP TABLE desktop_entries;");
                    ndb.exec("ALTER TABLE desktop_entries_new RENAME TO desktop_entries;");
                    ndb.exec("COMMIT;");
                } catch (Error e) {
                    try { ndb.exec("ROLLBACK;"); } catch (Error ee) { }
                    throw e;
                }
            }

            
            var now = (int64) (new DateTime.now_utc()).to_unix();
            var cutoff = now - (int64) (30 * 24 * 60 * 60);
            try {
                ndb.exec("BEGIN IMMEDIATE;");
                ndb.exec("DELETE FROM desktop_entries WHERE coalesce(deleted,0)=1 AND updated_at > 0 AND updated_at < " + cutoff.to_string() + ";");
                ndb.exec("COMMIT;");
            } catch (Error e) {
                try { ndb.exec("ROLLBACK;"); } catch (Error ee) { }
            }

            
            try { ndb.exec("ANALYZE;"); } catch (Error e) { }
            try { ndb.exec("VACUUM;"); } catch (Error e) { }
        }
    }
}
