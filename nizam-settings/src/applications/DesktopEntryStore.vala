using GLib;
using Sqlite;

namespace NizamSettings {
    public class DesktopEntryStore : Object {
        private NizamDb ndb;

        public DesktopEntryStore (NizamDb ndb) {
            this.ndb = ndb;
        }

        public void sync_entries (List<DesktopEntry> entries) throws Error {
            Statement stmt;
            var sql = "INSERT INTO desktop_entries(filename,name,exec,categories,icon,managed,enabled,updated_at) " +
                      "VALUES(?1,?2,?3,?4,?5,?6,?7,?8) " +
                      "ON CONFLICT(filename) DO UPDATE SET " +
                      "name=excluded.name, exec=excluded.exec, categories=excluded.categories, icon=excluded.icon, " +
                      "managed=excluded.managed, enabled=excluded.enabled, updated_at=excluded.updated_at";
            var rc = ndb.handle.prepare_v2(sql, -1, out stmt);
            if (rc != Sqlite.OK) throw new IOError.FAILED(ndb.handle.errmsg());

            int64 ts = (new DateTime.now_utc()).to_unix();
            for (unowned List<DesktopEntry> it = entries; it != null; it = it.next) {
                var e = it.data;
                stmt.reset();
                stmt.clear_bindings();
                stmt.bind_text(1, e.filename);
                stmt.bind_text(2, e.name);
                stmt.bind_text(3, e.exec);
                stmt.bind_text(4, e.categories);
                stmt.bind_text(5, e.icon);
                stmt.bind_int(6, e.managed ? 1 : 0);
                stmt.bind_int(7, e.enabled ? 1 : 0);
                stmt.bind_int64(8, ts);
                rc = stmt.step();
                if (rc != Sqlite.DONE) throw new IOError.FAILED(ndb.handle.errmsg());
            }
        }

        public void sync_system_entries (List<DesktopEntry> entries) throws Error {
            
            
            
            
            
            Statement stmt;
            var sql =
                "INSERT INTO desktop_entries(" +
                "filename,name,exec,categories,icon,category,source,managed,enabled,add_to_dock,updated_at" +
                ",deleted" +
                ") VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12) " +
                "ON CONFLICT(filename) DO UPDATE SET " +
                "name=excluded.name, exec=excluded.exec, categories=excluded.categories, icon=excluded.icon, " +
                "category=excluded.category, source=excluded.source, updated_at=excluded.updated_at, " +
                "deleted=0, " +
                
                "enabled=CASE WHEN coalesce(desktop_entries.deleted,0)=1 THEN 1 ELSE desktop_entries.enabled END, " +
                "add_to_dock=CASE WHEN coalesce(desktop_entries.deleted,0)=1 THEN 0 ELSE desktop_entries.add_to_dock END " +
                "WHERE " +
                "(coalesce(desktop_entries.deleted,0) = 1) OR (" +
                "coalesce(desktop_entries.name,'') <> coalesce(excluded.name,'') OR " +
                "coalesce(desktop_entries.exec,'') <> coalesce(excluded.exec,'') OR " +
                "coalesce(desktop_entries.categories,'') <> coalesce(excluded.categories,'') OR " +
                "coalesce(desktop_entries.icon,'') <> coalesce(excluded.icon,'') OR " +
                "coalesce(desktop_entries.category,'') <> coalesce(excluded.category,'') OR " +
                "coalesce(desktop_entries.source,'') <> coalesce(excluded.source,'')" +
                ")";

            var rc = ndb.handle.prepare_v2(sql, -1, out stmt);
            if (rc != Sqlite.OK) throw new IOError.FAILED(ndb.handle.errmsg());

            int64 ts = (new DateTime.now_utc()).to_unix();
            for (unowned List<DesktopEntry> it = entries; it != null; it = it.next) {
                var e = it.data;
                stmt.reset();
                stmt.clear_bindings();
                stmt.bind_text(1, e.filename);
                stmt.bind_text(2, e.name);
                stmt.bind_text(3, e.exec);
                stmt.bind_text(4, e.categories);
                stmt.bind_text(5, e.icon);
                stmt.bind_text(6, e.category);
                stmt.bind_text(7, e.source);
                stmt.bind_int(8, 0);            
                stmt.bind_int(9, 1);            
                stmt.bind_int(10, 0);           
                stmt.bind_int64(11, ts);
                stmt.bind_int(12, 0);           

                rc = stmt.step();
                if (rc != Sqlite.DONE) throw new IOError.FAILED(ndb.handle.errmsg());
            }
        }

        public List<DesktopEntry> load_entries () throws Error {
            var list = new List<DesktopEntry>();
            Statement stmt;
            var rc = ndb.handle.prepare_v2(
                "SELECT " +
                "filename, " +
                "name, exec, " +
                "categories, " +
                "coalesce(user_name,''), coalesce(user_exec,''), coalesce(user_categories,''), " +
                "coalesce(user_name,name), coalesce(user_exec,exec), coalesce(user_categories,categories), " +
                "icon, managed, enabled, add_to_dock, category, source " +
                "FROM desktop_entries " +
                "WHERE deleted = 0 " +
                "ORDER BY lower(coalesce(user_name,name)), enabled DESC, filename", -1, out stmt);
            if (rc != Sqlite.OK) throw new IOError.FAILED(ndb.handle.errmsg());
            while ((rc = stmt.step()) == Sqlite.ROW) {
                var e = new DesktopEntry();
                e.filename = stmt.column_text(0) ?? "";
                e.system_name = stmt.column_text(1) ?? "";
                e.system_exec = stmt.column_text(2) ?? "";
                e.system_categories = stmt.column_text(3) ?? "";
                e.user_name = stmt.column_text(4) ?? "";
                e.user_exec = stmt.column_text(5) ?? "";
                e.user_categories = stmt.column_text(6) ?? "";
                e.name = stmt.column_text(7) ?? e.system_name;
                e.exec = stmt.column_text(8) ?? e.system_exec;
                e.categories = stmt.column_text(9) ?? e.system_categories;
                e.icon = stmt.column_text(10) ?? "";
                e.managed = (stmt.column_int(11) == 1);
                e.enabled = (stmt.column_int(12) == 1);
                e.add_to_dock = (stmt.column_int(13) == 1);
                e.category = stmt.column_text(14) ?? "System";
                e.source = stmt.column_text(15) ?? "";
                e.has_overrides = (e.user_name.strip().length > 0) ||
                                  (e.user_exec.strip().length > 0) ||
                                  (e.user_categories.strip().length > 0);
                list.append(e);
            }
            return list;
        }

        public void delete_entry (string filename) throws Error {
            Statement stmt;
            var sql = "UPDATE desktop_entries SET deleted=1, enabled=0, add_to_dock=0, user_name=NULL, user_exec=NULL, user_categories=NULL, updated_at=?2 WHERE filename=?1";
            var rc = ndb.handle.prepare_v2(sql, -1, out stmt);
            if (rc != Sqlite.OK) throw new IOError.FAILED(ndb.handle.errmsg());

            int64 ts = (new DateTime.now_utc()).to_unix();
            stmt.bind_text(1, filename);
            stmt.bind_int64(2, ts);
            rc = stmt.step();
            if (rc != Sqlite.DONE) throw new IOError.FAILED(ndb.handle.errmsg());
        }

        public void set_user_flags (string filename, bool enabled, bool add_to_dock) throws Error {
            Statement stmt;
            var sql = "UPDATE desktop_entries SET enabled=?2, add_to_dock=?3 WHERE filename=?1";
            var rc = ndb.handle.prepare_v2(sql, -1, out stmt);
            if (rc != Sqlite.OK) throw new IOError.FAILED(ndb.handle.errmsg());
            stmt.bind_text(1, filename);
            stmt.bind_int(2, enabled ? 1 : 0);
            stmt.bind_int(3, add_to_dock ? 1 : 0);
            rc = stmt.step();
            if (rc != Sqlite.DONE) throw new IOError.FAILED(ndb.handle.errmsg());
        }

        public void set_user_prefs (string filename, bool enabled, bool add_to_dock, string? user_name, string? user_exec, string? user_categories) throws Error {
            
            string system_categories = "";
            {
                Statement read_stmt;
                var rc0 = ndb.handle.prepare_v2("SELECT categories FROM desktop_entries WHERE filename=?1", -1, out read_stmt);
                if (rc0 != Sqlite.OK) throw new IOError.FAILED(ndb.handle.errmsg());
                read_stmt.bind_text(1, filename);
                if (read_stmt.step() == Sqlite.ROW) {
                    system_categories = read_stmt.column_text(0) ?? "";
                }
            }

            var effective_categories = (user_categories != null && user_categories.strip().length > 0)
                ? user_categories
                : system_categories;
            var mapped_category = DesktopEntryUtils.pick_category_mapped(effective_categories);

            Statement stmt;
            var sql = "UPDATE desktop_entries SET enabled=?2, add_to_dock=?3, user_name=?4, user_exec=?5, user_categories=?6, category=?7, updated_at=?8 WHERE filename=?1";
            var rc = ndb.handle.prepare_v2(sql, -1, out stmt);
            if (rc != Sqlite.OK) throw new IOError.FAILED(ndb.handle.errmsg());

            int64 ts = (new DateTime.now_utc()).to_unix();
            stmt.bind_text(1, filename);
            stmt.bind_int(2, enabled ? 1 : 0);
            stmt.bind_int(3, add_to_dock ? 1 : 0);
            if (user_name == null || user_name.strip().length == 0) stmt.bind_null(4);
            else stmt.bind_text(4, user_name);
            if (user_exec == null || user_exec.strip().length == 0) stmt.bind_null(5);
            else stmt.bind_text(5, user_exec);

            if (user_categories == null || user_categories.strip().length == 0) stmt.bind_null(6);
            else stmt.bind_text(6, user_categories);

            stmt.bind_text(7, mapped_category);
            stmt.bind_int64(8, ts);

            rc = stmt.step();
            if (rc != Sqlite.DONE) throw new IOError.FAILED(ndb.handle.errmsg());
        }
    }
}
