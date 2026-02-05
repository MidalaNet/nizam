using GLib;
using Gtk;

namespace NizamSettings {
    private static string? detect_nizam_common_icons_dir () {
        
        var common_dir = GLib.Environment.get_variable ("NIZAM_COMMON_DIR");
        if (common_dir != null && common_dir != "") {
            var icons_dir = GLib.Path.build_filename (common_dir, "icons");
            if (GLib.FileUtils.test (icons_dir, GLib.FileTest.IS_DIR)) {
                return icons_dir;
            }
        }

        
        try {
            var exe = GLib.FileUtils.read_link ("/proc/self/exe");
            var dir = GLib.Path.get_dirname (exe);
            dir = GLib.Path.get_dirname (dir);
            dir = GLib.Path.get_dirname (dir);
            dir = GLib.Path.get_dirname (dir);
            var icons_dir = GLib.Path.build_filename (dir, "nizam-common", "icons");
            if (GLib.FileUtils.test (icons_dir, GLib.FileTest.IS_DIR)) {
                return icons_dir;
            }
        } catch (Error e) {
            
        }

        
        var cwd = GLib.Environment.get_current_dir ();
        var cwd_icons_dir = GLib.Path.build_filename (cwd, "nizam-common", "icons");
        if (GLib.FileUtils.test (cwd_icons_dir, GLib.FileTest.IS_DIR)) {
            return cwd_icons_dir;
        }

        return null;
    }

    private static string ensure_user_db_path () throws Error {
        var cfg = Path.build_filename(Environment.get_user_config_dir(), "nizam");
        DirUtils.create_with_parents(cfg, 0755);
        return Path.build_filename(cfg, "nizam.db");
    }

    private static int run_migrations_cli () {
        try {
            var db_path = ensure_user_db_path();
            var ndb = new NizamDb(db_path);
            Migrations.ensure_schema(ndb);
            stdout.printf("nizam-settings: migrations OK (%s)\n", db_path);
            return 0;
        } catch (Error e) {
            stderr.printf("nizam-settings: migrations FAILED: %s\n", e.message);
            return 1;
        }
    }

    private static int run_apply_pekwm_cli () {
        try {
            var db_path = ensure_user_db_path();
            var ndb = new NizamDb(db_path);
            Migrations.ensure_schema(ndb);

            string message;
            var status = PekwmBackend.apply_from_db(ndb, out message);
            if (status == PekwmApplyStatus.FAILED) {
                stderr.printf("nizam-settings: apply-pekwm FAILED: %s\n", message);
                return 1;
            }

            stdout.printf("nizam-settings: apply-pekwm OK: %s\n", message);
            return 0;
        } catch (Error e) {
            stderr.printf("nizam-settings: apply-pekwm FAILED: %s\n", e.message);
            return 1;
        }
    }

    public class App : Gtk.Application {
        public App () {
            Object(application_id: "org.nizam.Settings", flags: ApplicationFlags.DEFAULT_FLAGS);
        }

        protected override void startup () {
            base.startup ();

            
            var icons_dir = detect_nizam_common_icons_dir ();
            if (icons_dir != null) {
                Gtk.IconTheme.get_default ().append_search_path (icons_dir);
            }
        }

        protected override void activate () {
            try {
                
                Gtk.Window.set_default_icon_name("nizam");

                var db_path = ensure_user_db_path();
                var ndb = new NizamDb(db_path);
                Migrations.ensure_schema(ndb);
                var store = new SettingsStore(ndb);

                var win = new MainWindow(this, store);
                win.present();
            } catch (Error e) {
                stderr.printf("nizam-settings: %s\n", e.message);
            }
        }
    }
}



int main (string[] args) {
    foreach (var a in args) {
        if (a == "--migrate" || a == "--migrate-db") {
            return NizamSettings.run_migrations_cli();
        }
        if (a == "--apply-pekwm") {
            return NizamSettings.run_apply_pekwm_cli();
        }
    }
    return new NizamSettings.App().run(args);
}
