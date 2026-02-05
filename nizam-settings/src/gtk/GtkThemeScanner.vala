using GLib;
using Gtk;

namespace NizamSettings {
    public class GtkThemeScanner : Object {
        private static string[] add_unique (HashTable<string, bool> seen, string[] list, string name) {
            if (name.strip().length == 0) return list;
            if (seen.contains(name)) return list;
            seen.insert(name, true);
            var out = new string[list.length + 1];
            for (int i = 0; i < list.length; i++) out[i] = list[i];
            out[list.length] = name;
            return out;
        }

        private static string[] sort_strings (string[] input) {
            for (int i = 0; i < input.length; i++) {
                for (int j = i + 1; j < input.length; j++) {
                    if (strcmp(input[i], input[j]) > 0) {
                        var tmp = input[i];
                        input[i] = input[j];
                        input[j] = tmp;
                    }
                }
            }
            return input;
        }

        public static string[] list_gtk_themes () {
            string[] themes = {};
            var seen = new HashTable<string, bool>(str_hash, str_equal);

            string home = Environment.get_home_dir();
            string[] roots = {
                Path.build_filename(home, ".themes"),
                Path.build_filename(home, ".local", "share", "themes"),
                "/usr/share/themes",
                "/usr/local/share/themes"
            };

            string[] gtk_dirs = { "gtk-4.0", "gtk-3.0" };
            foreach (var root in roots) {
                if (!FileUtils.test(root, FileTest.IS_DIR)) continue;
                try {
                    var d = Dir.open(root, 0);
                    while (true) {
                        var name = d.read_name();
                        if (name == null) break;
                        if (name == "." || name == "..") continue;
                        bool found = false;
                        foreach (var gtk_dir in gtk_dirs) {
                            var theme_dir = Path.build_filename(root, name, gtk_dir);
                            if (!FileUtils.test(theme_dir, FileTest.IS_DIR)) continue;
                            var css = Path.build_filename(theme_dir, "gtk.css");
                            var gresource = Path.build_filename(theme_dir, "gtk.gresource");
                            var gresource_xml = Path.build_filename(theme_dir, "gtk.gresource.xml");
                            if (!FileUtils.test(css, FileTest.IS_REGULAR) &&
                                !FileUtils.test(gresource, FileTest.IS_REGULAR) &&
                                !FileUtils.test(gresource_xml, FileTest.IS_REGULAR)) {
                                bool has_css = false;
                                try {
                                    var td = Dir.open(theme_dir, 0);
                                    while (true) {
                                        var fname = td.read_name();
                                        if (fname == null) break;
                                        if (fname.has_suffix(".css")) {
                                            has_css = true;
                                            break;
                                        }
                                    }
                                } catch (Error e) {
                                    
                                }
                                if (!has_css) continue;
                            }
                            found = true;
                            break;
                        }
                        if (!found) continue;
                        themes = add_unique(seen, themes, name);
                    }
                } catch (Error e) {
                    
                }
            }

            
            var settings = Gtk.Settings.get_default();
            if (settings != null) {
                var current = settings.gtk_theme_name;
                if (current != null) themes = add_unique(seen, themes, current);
            }

            return sort_strings(themes);
        }

        public static string[] list_icon_themes () {
            string[] themes = {};
            var seen = new HashTable<string, bool>(str_hash, str_equal);

            string home = Environment.get_home_dir();
            string[] roots = {
                Path.build_filename(home, ".icons"),
                Path.build_filename(home, ".local", "share", "icons"),
                "/usr/share/icons",
                "/usr/local/share/icons"
            };

            foreach (var root in roots) {
                if (!FileUtils.test(root, FileTest.IS_DIR)) continue;
                try {
                    var d = Dir.open(root, 0);
                    while (true) {
                        var name = d.read_name();
                        if (name == null) break;
                        if (name == "." || name == "..") continue;
                        var index_theme = Path.build_filename(root, name, "index.theme");
                        if (!FileUtils.test(index_theme, FileTest.IS_REGULAR) &&
                            !FileUtils.test(index_theme, FileTest.IS_SYMLINK)) {
                            continue;
                        }
                        themes = add_unique(seen, themes, name);
                    }
                } catch (Error e) {
                    
                }
            }

            
            var settings = Gtk.Settings.get_default();
            if (settings != null) {
                var current = settings.gtk_icon_theme_name;
                if (current != null) themes = add_unique(seen, themes, current);
            }

            return sort_strings(themes);
        }

        public static string[] list_cursor_themes () {
            string[] themes = {};
            var seen = new HashTable<string, bool>(str_hash, str_equal);

            string home = Environment.get_home_dir();
            string[] roots = {
                Path.build_filename(home, ".icons"),
                Path.build_filename(home, ".local", "share", "icons"),
                "/usr/share/icons",
                "/usr/local/share/icons"
            };

            foreach (var root in roots) {
                if (!FileUtils.test(root, FileTest.IS_DIR)) continue;
                try {
                    var d = Dir.open(root, 0);
                    while (true) {
                        var name = d.read_name();
                        if (name == null) break;
                        if (name == "." || name == "..") continue;
                        var cursor_dir = Path.build_filename(root, name, "cursors");
                        if (!FileUtils.test(cursor_dir, FileTest.IS_DIR) &&
                            !FileUtils.test(cursor_dir, FileTest.IS_SYMLINK)) {
                            continue;
                        }
                        themes = add_unique(seen, themes, name);
                    }
                } catch (Error e) {
                    
                }
            }

            return sort_strings(themes);
        }
    }
}
