using GLib;

namespace NizamSettings {
    public class DesktopEntryScanner : Object {
        private const string SYSTEM_APPS_DIR = "/usr/share/applications";

        public static string get_local_apps_dir () {
            return Path.build_filename(Environment.get_user_data_dir(), "applications");
        }

        public List<DesktopEntry> scan_system_apps () throws Error {
            var list = new List<DesktopEntry>();
            if (!FileUtils.test(SYSTEM_APPS_DIR, FileTest.IS_DIR)) return list;

            var dir = Dir.open(SYSTEM_APPS_DIR, 0);
            while (true) {
                var name = dir.read_name();
                if (name == null) break;
                if (!name.has_suffix(".desktop")) continue;

                var path = Path.build_filename(SYSTEM_APPS_DIR, name);
                var file = File.new_for_path(path);
                var entry = DesktopEntryIO.read(file);
                if (entry == null) continue;

                if (entry.name.strip().length == 0 || entry.exec.strip().length == 0) continue;

                entry.source = path;
                entry.exec = DesktopEntryUtils.sanitize_exec(entry.exec);
                entry.category = DesktopEntryUtils.pick_category_mapped(entry.categories);
                list.append(entry);
            }
            return list;
        }

        public List<DesktopEntry> scan_local_managed () throws Error {
            var list = new List<DesktopEntry>();
            var dir_path = get_local_apps_dir();
            if (!FileUtils.test(dir_path, FileTest.IS_DIR)) return list;

            var dir = Dir.open(dir_path, 0);
            while (true) {
                var name = dir.read_name();
                if (name == null) break;
                if (!name.has_suffix(".desktop")) continue;
                var file = File.new_for_path(Path.build_filename(dir_path, name));
                var entry = DesktopEntryIO.read(file);
                if (entry == null) continue;
                if (!entry.managed) continue;
                list.append(entry);
            }
            return list;
        }
    }
}
