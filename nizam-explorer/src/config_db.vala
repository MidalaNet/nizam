using GLib;
using Sqlite;

public class ExplorerConfigDb : Object {
    private Sqlite.Database db;
    private bool available = false;

    public ExplorerConfigDb () {
        try_open();
    }

    private static string db_path () {
        return Path.build_filename(Environment.get_user_config_dir(), "nizam", "nizam.db");
    }

    private void ensure_parent_dir () {
        var dir = Path.build_filename(Environment.get_user_config_dir(), "nizam");
        try {
            File.new_for_path(dir).make_directory_with_parents();
        } catch (Error e) {
            
        }
    }

    private void try_open () {
        ensure_parent_dir();
        var path = db_path();
        var rc = Sqlite.Database.open(path, out db);
        if (rc != Sqlite.OK) {
            available = false;
            return;
        }
        ensure_tables();
        available = true;
    }

    private void ensure_tables () {
        if (db == null) return;
        string errmsg;
        
        db.exec("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);", null, out errmsg);
        db.exec("CREATE TABLE IF NOT EXISTS settings (scope TEXT NOT NULL, key TEXT NOT NULL, type TEXT NOT NULL, value TEXT NOT NULL, PRIMARY KEY(scope,key));", null, out errmsg);

        
        db.exec("ALTER TABLE settings ADD COLUMN type TEXT NOT NULL DEFAULT 'text';", null, out errmsg);
    }

    private bool is_available () {
        if (!available || db == null) {
            try_open();
        }
        return available;
    }

    private string? get_value (string scope, string key) {
        if (!is_available()) return null;

        Sqlite.Statement stmt;
        var rc = db.prepare_v2("SELECT value FROM settings WHERE scope=?1 AND key=?2", -1, out stmt);
        if (rc != Sqlite.OK) return null;

        string? result = null;
        try {
            stmt.bind_text(1, scope);
            stmt.bind_text(2, key);
            rc = stmt.step();
            if (rc == Sqlite.ROW) result = stmt.column_text(0);
        } finally {
            stmt = null;
        }
        return result;
    }

    private void set_value (string scope, string key, string value) {
        if (!is_available()) return;

        Sqlite.Statement stmt;
        var rc = db.prepare_v2(
            "INSERT INTO settings(scope, key, type, value) VALUES(?1, ?2, ?3, ?4) " +
            "ON CONFLICT(scope,key) DO UPDATE SET type=excluded.type, value=excluded.value",
            -1,
            out stmt
        );
        if (rc != Sqlite.OK) return;

        try {
            stmt.bind_text(1, scope);
            stmt.bind_text(2, key);
            stmt.bind_text(3, "text");
            stmt.bind_text(4, value);
            stmt.step();
        } finally {
            stmt = null;
        }
    }

    public int get_int (string scope, string key, int def) {
        var v = get_value(scope, key);
        if (v == null) return def;
        return int.parse(v);
    }

    public bool get_bool (string scope, string key, bool def) {
        var v = get_value(scope, key);
        if (v == null) return def;
        var low = v.down();
        return (v == "1" || low == "true" || low == "yes" || low == "on");
    }

    public void set_int (string scope, string key, int value) {
        set_value(scope, key, value.to_string());
    }

    public void set_bool (string scope, string key, bool value) {
        set_value(scope, key, value ? "1" : "0");
    }
}
