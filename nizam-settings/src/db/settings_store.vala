using GLib;
using Sqlite;

namespace NizamSettings {
    public class SettingsStore : Object {
        private NizamDb ndb;
        private uint pekwm_apply_id = 0;
        private uint apps_notify_id = 0;

        public SettingsStore (NizamDb ndb) {
            this.ndb = ndb;
        }

        public NizamDb get_db () {
            return ndb;
        }

        

        
        public void queue_applications_changed_notify () {
            if (apps_notify_id != 0) return;
            apps_notify_id = Timeout.add(150, () => {
                apps_notify_id = 0;
                notify_applications_changed_now();
                return false;
            });
        }

        private static string build_dock_socket_path () {
            var runtime = Environment.get_variable("XDG_RUNTIME_DIR");
            if (runtime != null && runtime.strip().length > 0) {
                return Path.build_filename(runtime, "nizam-dock.sock");
            }
            var user = Environment.get_variable("USER");
            if (user == null || user.strip().length == 0) user = "user";
            return "/tmp/nizam-dock-%s.sock".printf(user);
        }

        private static void try_reload_dock () {
            
            
            try {
                var path = build_dock_socket_path();
                var addr = new GLib.UnixSocketAddress(path);
                var client = new GLib.SocketClient();
                var conn = client.connect(addr);
                if (conn != null) {
                    var os = conn.get_output_stream();
                    
                    os.write("reload\n".data);
                    os.flush();
                    conn.close();
                }
            } catch (Error _e) {
                
            }
        }

        private void notify_applications_changed_now () {
            
            
            try_reload_dock();
        }

        private string? get_raw (string scope, string key) throws Error {
            Statement stmt;
            var sql = "SELECT value FROM settings WHERE scope=?1 AND key=?2";
            var rc = ndb.handle.prepare_v2(sql, -1, out stmt);
            if (rc != Sqlite.OK) throw new IOError.FAILED(ndb.handle.errmsg());

            string? result = null;
            stmt.bind_text(1, scope);
            stmt.bind_text(2, key);
            rc = stmt.step();
            if (rc == Sqlite.ROW) result = stmt.column_text(0);
            stmt = null;
            return result;
        }

        private void set_raw (string scope, string key, string type, string value) throws Error {
            Statement stmt;
            var sql = "INSERT INTO settings(scope,key,type,value) VALUES(?1,?2,?3,?4) " +
                      "ON CONFLICT(scope,key) DO UPDATE SET type=excluded.type, value=excluded.value";
            var rc = ndb.handle.prepare_v2(sql, -1, out stmt);
            if (rc != Sqlite.OK) throw new IOError.FAILED(ndb.handle.errmsg());

            stmt.bind_text(1, scope);
            stmt.bind_text(2, key);
            stmt.bind_text(3, type);
            stmt.bind_text(4, value);

            rc = stmt.step();
            if (rc != Sqlite.DONE) {
                stmt = null;
                throw new IOError.FAILED(ndb.handle.errmsg());
            }
            stmt = null;

            touch_updated_at();
            if (scope.has_prefix("wm") || scope.has_prefix("pekwm")) {
                queue_pekwm_apply();
            }
        }

        private void queue_pekwm_apply () {
            if (pekwm_apply_id != 0) return;
            pekwm_apply_id = Timeout.add(300, () => {
                pekwm_apply_id = 0;
                apply_pekwm_now();
                return false;
            });
        }

        public void apply_pekwm_now () {
            string msg;
            var status = PekwmBackend.apply_from_common(out msg, ndb);
            if (status == PekwmApplyStatus.OK) {
                message("pekwm: %s", msg);
            } else {
                warning("pekwm: apply failed: %s", msg);
            }
        }

        private void touch_updated_at () throws Error {
            Statement stmt;
            var sql = "INSERT INTO meta(key,value) VALUES('updated_at',?1) " +
                      "ON CONFLICT(key) DO UPDATE SET value=excluded.value";
            var rc = ndb.handle.prepare_v2(sql, -1, out stmt);
            if (rc != Sqlite.OK) throw new IOError.FAILED(ndb.handle.errmsg());

            var now = (int64) (new DateTime.now_utc()).to_unix();
            stmt.bind_text(1, now.to_string());
            rc = stmt.step();
            if (rc != Sqlite.DONE) {
                stmt = null;
                throw new IOError.FAILED(ndb.handle.errmsg());
            }
            stmt = null;
        }

        private string? get_wm_raw (string key) throws Error {
            Statement stmt;
            var sql = "SELECT value FROM wm_settings WHERE key=?1";
            var rc = ndb.handle.prepare_v2(sql, -1, out stmt);
            if (rc != Sqlite.OK) throw new IOError.FAILED(ndb.handle.errmsg());
            string? result = null;
            stmt.bind_text(1, key);
            rc = stmt.step();
            if (rc == Sqlite.ROW) result = stmt.column_text(0);
            stmt = null;
            return result;
        }

        private void set_wm_raw (string key, string value) throws Error {
            Statement stmt;
            var sql = "INSERT INTO wm_settings(key,value) VALUES(?1,?2) " +
                      "ON CONFLICT(key) DO UPDATE SET value=excluded.value";
            var rc = ndb.handle.prepare_v2(sql, -1, out stmt);
            if (rc != Sqlite.OK) throw new IOError.FAILED(ndb.handle.errmsg());
            stmt.bind_text(1, key);
            stmt.bind_text(2, value);
            rc = stmt.step();
            if (rc != Sqlite.DONE) {
                stmt = null;
                throw new IOError.FAILED(ndb.handle.errmsg());
            }
            stmt = null;
        }

        public bool get_bool (string scope, string key, bool def=false) throws Error {
            var v = get_raw(scope, key);
            if (v == null) return def;
            var low = v.down();
            return (v == "1" || low == "true" || low == "yes" || low == "on");
        }

        public int get_int (string scope, string key, int def=0) throws Error {
            var v = get_raw(scope, key);
            if (v == null) return def;
            return int.parse(v);
        }

        public double get_double (string scope, string key, double def=0.0) throws Error {
            var v = get_raw(scope, key);
            if (v == null) return def;
            return double.parse(v);
        }

        public string get_text (string scope, string key, string def="") throws Error {
            var v = get_raw(scope, key);
            return v ?? def;
        }

        public string get_wm_text (string key, string def="") throws Error {
            var v = get_wm_raw(key);
            return v ?? def;
        }

        public int get_wm_int (string key, int def=0) throws Error {
            var v = get_wm_raw(key);
            if (v == null) return def;
            return int.parse(v);
        }

        public void set_bool (string scope, string key, bool value) throws Error {
            set_raw(scope, key, "bool", value ? "1" : "0");
        }

        public void set_int (string scope, string key, int value) throws Error {
            set_raw(scope, key, "int", value.to_string());
        }

        public void set_double (string scope, string key, double value) throws Error {
            
            set_raw(scope, key, "real", "%.2f".printf(value));
        }

        public void set_text (string scope, string key, string value) throws Error {
            set_raw(scope, key, "text", value);
        }

        public void set_wm_text (string key, string value) throws Error {
            set_wm_raw(key, value);
            queue_pekwm_apply();
        }

        public void set_wm_int (string key, int value) throws Error {
            set_wm_raw(key, value.to_string());
            queue_pekwm_apply();
        }
    }
}
