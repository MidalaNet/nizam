using GLib;

namespace NizamSettings {
    public class PekwmPaths : Object {
        
        public static File get_pekwm_bootstrap_dir () {
            var home = Environment.get_home_dir();
            return File.new_for_path(Path.build_filename(home, ".pekwm"));
        }

        public static File get_pekwm_bootstrap_file (string name) {
            return get_pekwm_bootstrap_dir().get_child(name);
        }

        
        public static File get_nizam_pekwm_dir () {
            var cfg = Environment.get_user_config_dir();
            return File.new_for_path(Path.build_filename(cfg, "nizam", "pekwm"));
        }

        public static File get_nizam_pekwm_file (string name) {
            return get_nizam_pekwm_dir().get_child(name);
        }

        public static void ensure_dir (File dir) throws Error {
            try {
                dir.make_directory_with_parents();
            } catch (IOError.EXISTS e) {
                
            }
        }

        public static void atomic_write (File target, string content) throws Error {
            var path = target.get_path();
            if (path == null || path.strip().length == 0) {
                throw new IOError.FAILED("Invalid target path");
            }
            var tmp_path = path + ".tmp";
            FileUtils.set_contents(tmp_path, content);
            FileUtils.chmod(tmp_path, 0644);
            if (FileUtils.test(path, FileTest.EXISTS)) {
                FileUtils.remove(path);
            }
            FileUtils.rename(tmp_path, path);
        }

        public static File? find_theme_source_dir () {
            var env_dir = Environment.get_variable("NIZAM_PEKWM_THEME_DIR");
            if (env_dir != null && env_dir.strip().length > 0 && FileUtils.test(env_dir, FileTest.IS_DIR)) {
                return File.new_for_path(env_dir);
            }

            
            
            var candidates = new string[] {
                
                Path.build_filename(Environment.get_user_data_dir(), "nizam-settings", "ui", "pekwm", "theme"),
                Path.build_filename(Environment.get_user_data_dir(), "nizam-settings", "ui", "ui", "pekwm", "theme"),
                Path.build_filename(Environment.get_user_data_dir(), "nizam-settings", "ui", "ui", "pekwm", "pekwm", "theme"),

                
                Path.build_filename(NizamSettings.PKGDATADIR, "nizam-settings", "ui", "pekwm", "theme"),
                Path.build_filename(NizamSettings.PKGDATADIR, "nizam-settings", "ui", "ui", "pekwm", "theme"),
                Path.build_filename(NizamSettings.PKGDATADIR, "nizam-settings", "ui", "ui", "pekwm", "pekwm", "theme"),

                
                Path.build_filename("/usr/share", "nizam-settings", "ui", "pekwm", "theme"),
                Path.build_filename("/usr/share", "nizam-settings", "ui", "ui", "pekwm", "theme"),
                Path.build_filename("/usr/share", "nizam-settings", "ui", "ui", "pekwm", "pekwm", "theme"),
                Path.build_filename("/usr/local/share", "nizam-settings", "ui", "pekwm", "theme"),
                Path.build_filename("/usr/local/share", "nizam-settings", "ui", "ui", "pekwm", "theme"),
                Path.build_filename("/usr/local/share", "nizam-settings", "ui", "ui", "pekwm", "pekwm", "theme"),
            };

            foreach (var c in candidates) {
                if (FileUtils.test(c, FileTest.IS_DIR)) return File.new_for_path(c);
            }

            try {
                var exe = FileUtils.read_link("/proc/self/exe");
                if (exe != null && exe.strip().length > 0) {
                    var exe_dir = Path.get_dirname(exe);
                    
                    
                    
                    for (int up = 0; up <= 8; up++) {
                        string rel = ".";
                        for (int i = 0; i < up; i++) rel = Path.build_filename(rel, "..");

                        var dev1 = Path.build_filename(exe_dir, rel, "data", "ui", "pekwm", "theme");
                        if (FileUtils.test(dev1, FileTest.IS_DIR)) return File.new_for_path(dev1);

                        var dev2 = Path.build_filename(exe_dir, rel, "nizam-settings", "data", "ui", "pekwm", "theme");
                        if (FileUtils.test(dev2, FileTest.IS_DIR)) return File.new_for_path(dev2);
                    }
                }
            } catch (Error e) {
                
            }

            var cwd = Environment.get_current_dir();
            var dev_cwd = Path.build_filename(cwd, "nizam-settings", "data", "ui", "pekwm", "theme");
            if (FileUtils.test(dev_cwd, FileTest.IS_DIR)) return File.new_for_path(dev_cwd);

            return null;
        }

    }
}
