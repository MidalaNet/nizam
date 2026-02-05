using GLib;
using Sqlite;

namespace NizamSettings {
    public class PekwmAutostartItem : Object {
        public int64 id;
        public string command;
        public bool enabled;

        public PekwmAutostartItem (int64 id, string command, bool enabled) {
            this.id = id;
            this.command = command;
            this.enabled = enabled;
        }
    }

    public class PekwmAutostartStore : Object {
        private NizamDb db;

        public PekwmAutostartStore (NizamDb db) {
            this.db = db;
        }

        public PtrArray list_items () throws Error {
            var items = new PtrArray();
            Statement stmt;
            var rc = db.handle.prepare_v2(
                "SELECT id, command, enabled FROM wm_autostart ORDER BY id",
                -1,
                out stmt
            );
            if (rc != Sqlite.OK) throw new IOError.FAILED(db.handle.errmsg());

            while ((rc = stmt.step()) == Sqlite.ROW) {
                var id = stmt.column_int64(0);
                
                var cmd = (stmt.column_text(1) ?? "").dup();
                var enabled = stmt.column_int(2) != 0;
                items.add(new PekwmAutostartItem(id, cmd, enabled));
            }
            return items;
        }

        public int64 add_item (string command, bool enabled) throws Error {
            var cmd = (command ?? "").strip();
            if (cmd.length == 0) throw new IOError.FAILED("Command cannot be empty");

            Statement stmt;
            var sql = "INSERT INTO wm_autostart(command, enabled) VALUES(?1, ?2)";
            var rc = db.handle.prepare_v2(sql, -1, out stmt);
            if (rc != Sqlite.OK) throw new IOError.FAILED(db.handle.errmsg());
            stmt.bind_text(1, cmd);
            stmt.bind_int(2, enabled ? 1 : 0);
            rc = stmt.step();
            if (rc != Sqlite.DONE) throw new IOError.FAILED(db.handle.errmsg());

            return db.handle.last_insert_rowid();
        }

        public void update_item (int64 id, string command, bool enabled) throws Error {
            var cmd = (command ?? "").strip();
            if (cmd.length == 0) throw new IOError.FAILED("Command cannot be empty");

            Statement stmt;
            var sql = "UPDATE wm_autostart SET command=?1, enabled=?2 WHERE id=?3";
            var rc = db.handle.prepare_v2(sql, -1, out stmt);
            if (rc != Sqlite.OK) throw new IOError.FAILED(db.handle.errmsg());
            stmt.bind_text(1, cmd);
            stmt.bind_int(2, enabled ? 1 : 0);
            stmt.bind_int64(3, id);
            rc = stmt.step();
            if (rc != Sqlite.DONE) throw new IOError.FAILED(db.handle.errmsg());
        }

        public void set_enabled (int64 id, bool enabled) throws Error {
            Statement stmt;
            var sql = "UPDATE wm_autostart SET enabled=?1 WHERE id=?2";
            var rc = db.handle.prepare_v2(sql, -1, out stmt);
            if (rc != Sqlite.OK) throw new IOError.FAILED(db.handle.errmsg());
            stmt.bind_int(1, enabled ? 1 : 0);
            stmt.bind_int64(2, id);
            rc = stmt.step();
            if (rc != Sqlite.DONE) throw new IOError.FAILED(db.handle.errmsg());
        }

        public void delete_item (int64 id) throws Error {
            Statement stmt;
            var sql = "DELETE FROM wm_autostart WHERE id=?1";
            var rc = db.handle.prepare_v2(sql, -1, out stmt);
            if (rc != Sqlite.OK) throw new IOError.FAILED(db.handle.errmsg());
            stmt.bind_int64(1, id);
            rc = stmt.step();
            if (rc != Sqlite.DONE) throw new IOError.FAILED(db.handle.errmsg());
        }
    }
}
