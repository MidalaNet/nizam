using GLib;

namespace NizamSettings {
    public class DesktopEntryIO : Object {
        public static DesktopEntry? read (File file) throws Error {
            var path = file.get_path();
            if (path == null) return null;
            var kf = new KeyFile();
            kf.load_from_file(path, KeyFileFlags.NONE);

            if (!kf.has_group("Desktop Entry")) return null;
            var type = kf.get_string("Desktop Entry", "Type");
            if (type == null || type.strip() != "Application") return null;

            bool hidden = false;
            bool nodisplay = false;
            try { hidden = kf.get_boolean("Desktop Entry", "Hidden"); } catch (Error e) { }
            try { nodisplay = kf.get_boolean("Desktop Entry", "NoDisplay"); } catch (Error e) { }
            if (hidden || nodisplay) return null;

            var e = new DesktopEntry();
            e.filename = file.get_basename() ?? "";
            e.name = safe_get(kf, "Desktop Entry", "Name");
            e.exec = safe_get(kf, "Desktop Entry", "Exec");
            e.categories = safe_get(kf, "Desktop Entry", "Categories");
            e.icon = safe_get(kf, "Desktop Entry", "Icon");
            e.managed = safe_get_bool(kf, "Desktop Entry", "X-Nizam-Managed");
            e.enabled = safe_get_bool_default(kf, "Desktop Entry", "X-Nizam-Enabled", true);
            e.source = safe_get(kf, "Desktop Entry", "X-Nizam-Source");
            return e;
        }

        public static void write (File file, DesktopEntry entry, bool preserve_existing = true) throws Error {
            var path = file.get_path();
            if (path == null) throw new IOError.FAILED("Invalid desktop path");

            var kf = new KeyFile();
            if (preserve_existing && FileUtils.test(path, FileTest.IS_REGULAR)) {
                try { kf.load_from_file(path, KeyFileFlags.NONE); } catch (Error e) { }
            }

            kf.set_string("Desktop Entry", "Type", "Application");
            if (entry.name.strip().length > 0) kf.set_string("Desktop Entry", "Name", entry.name);
            if (entry.exec.strip().length > 0) kf.set_string("Desktop Entry", "Exec", entry.exec);
            if (entry.categories.strip().length > 0) {
                var cats = entry.categories.strip();
                if (!cats.has_suffix(";")) cats += ";";
                kf.set_string("Desktop Entry", "Categories", cats);
            }
            if (entry.icon.strip().length > 0) kf.set_string("Desktop Entry", "Icon", entry.icon);

            kf.set_boolean("Desktop Entry", "X-Nizam-Managed", true);
            kf.set_boolean("Desktop Entry", "X-Nizam-Enabled", entry.enabled);
            if (entry.source.strip().length > 0) kf.set_string("Desktop Entry", "X-Nizam-Source", entry.source);

            size_t len = 0;
            var data = kf.to_data(out len);
            atomic_write(path, data);
        }

        private static void atomic_write (string path, string content) throws Error {
            var tmp = path + ".tmp";
            FileUtils.set_contents(tmp, content);
            FileUtils.rename(tmp, path);
        }

        private static string safe_get (KeyFile kf, string group, string key) {
            try { return kf.get_string(group, key) ?? ""; } catch (Error e) { return ""; }
        }

        private static bool safe_get_bool (KeyFile kf, string group, string key) {
            try { return kf.get_boolean(group, key); } catch (Error e) { return false; }
        }

        private static bool safe_get_bool_default (KeyFile kf, string group, string key, bool def) {
            try { return kf.get_boolean(group, key); } catch (Error e) { return def; }
        }
    }
}
