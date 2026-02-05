using GLib;
using Sqlite;

namespace NizamSettings {
    public class NizamDb : Object {
        private Database db;

        public NizamDb (string path) throws Error {
            var rc = Database.open(path, out db);
            if (rc != Sqlite.OK) {
                throw new IOError.FAILED("Impossibile aprire DB: %s".printf(db.errmsg()));
            }

            exec("PRAGMA foreign_keys=ON;");
            exec("PRAGMA journal_mode=WAL;");
            exec("PRAGMA busy_timeout=2000;");
        }

        public void exec (string sql) throws Error {
            string? err = null;
            var rc = db.exec(sql, null, out err);
            if (rc != Sqlite.OK) {
                var msg = (err != null) ? err : db.errmsg();
                throw new IOError.FAILED("SQLite exec error: %s".printf(msg));
            }
        }

        public Database handle {
            get { return db; }
        }
    }
}
