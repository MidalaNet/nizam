using GLib;

namespace NizamCommon {
    public class RequirementsResult : Object {
        public bool ok { get; set; default = false; }
        public bool schema_installed { get; set; default = false; }
        public string schema_id { get; set; default = ""; }
        public string message { get; set; default = ""; }

        public string glib_version { get; set; default = ""; }
        public string gsettings_cli_version { get; set; default = ""; }
        public string dconf_cli_version { get; set; default = ""; }
        public string backend_hint { get; set; default = ""; }
    }

    public class NizamGSettings : Object {
        public const string GTK_INTERFACE_SCHEMA = "org.gnome.desktop.interface";
        public const string NIZAM_SCHEMA = "com.nizam.desktop";

        private Settings? gtk_interface = null;
        private Settings? nizam = null;

        public signal void gtk_interface_changed (string key);
        public signal void nizam_changed (string key);

        public static bool schema_exists (string schema_id) {
            var src = SettingsSchemaSource.get_default();
            if (src == null) return false;
            var schema = src.lookup(schema_id, true);
            return schema != null;
        }

        private static string read_first_line (string s) {
            if (s == null) return "";
            var t = s.strip();
            if (t.length == 0) return "";
            var idx = t.index_of_char('\n');
            if (idx < 0) return t;
            return t.substring(0, idx).strip();
        }

        private static string try_spawn_version (string cmd) {
            try {
                string? out_s = null;
                string? err_s = null;
                int status = 0;
                Process.spawn_command_line_sync(cmd, out out_s, out err_s, out status);
                if (status != 0) return "";
                return read_first_line(out_s ?? "");
            } catch (Error e) {
                return "";
            }
        }

        public static RequirementsResult check_requirements () {
            var r = new RequirementsResult();
            r.schema_id = GTK_INTERFACE_SCHEMA;

            
            r.glib_version = "%u.%u.%u".printf(GLib.Version.major, GLib.Version.minor, GLib.Version.micro);

            var env_backend = Environment.get_variable("GSETTINGS_BACKEND");
            if (env_backend != null && env_backend.strip().length > 0) {
                r.backend_hint = env_backend.strip();
            } else {
                r.backend_hint = "default";
            }

            r.schema_installed = schema_exists(GTK_INTERFACE_SCHEMA);
            if (!r.schema_installed) {
                r.ok = false;
                r.message = "Schema GSettings mancante: %s".printf(GTK_INTERFACE_SCHEMA);
            } else {
                r.ok = true;
                r.message = "GSettings schema OK";
            }

            
            r.gsettings_cli_version = try_spawn_version("gsettings --version");
            r.dconf_cli_version = try_spawn_version("dconf --version");

            return r;
        }

        public bool gtk_interface_available () {
            return gtk_interface != null;
        }

        public bool nizam_available () {
            return nizam != null;
        }

        public bool init_gtk_interface () {
            if (gtk_interface != null) return true;
            if (!schema_exists(GTK_INTERFACE_SCHEMA)) return false;
            gtk_interface = new Settings(GTK_INTERFACE_SCHEMA);
            gtk_interface.changed.connect((key) => {
                gtk_interface_changed(key);
            });
            return true;
        }

        public bool init_nizam () {
            if (nizam != null) return true;
            if (!schema_exists(NIZAM_SCHEMA)) return false;
            nizam = new Settings(NIZAM_SCHEMA);
            nizam.changed.connect((key) => {
                nizam_changed(key);
            });
            return true;
        }

        private Settings? get_gtk_interface () {
            if (gtk_interface != null) return gtk_interface;
            if (!init_gtk_interface()) return null;
            return gtk_interface;
        }

        private Settings? get_nizam () {
            if (nizam != null) return nizam;
            if (!init_nizam()) return null;
            return nizam;
        }

        
        public bool get_nizam_debug () {
            var s = get_nizam();
            if (s == null) return false;
            return s.get_boolean("debug");
        }

        public void set_nizam_debug (bool value) {
            var s = get_nizam();
            if (s == null) return;
            s.set_boolean("debug", value);
        }

        public bool get_panel_show_clock () {
            var s = get_nizam();
            if (s == null) return true;
            return s.get_boolean("panel-show-clock");
        }

        public string get_panel_clock_format () {
            var s = get_nizam();
            if (s == null) return "%H:%M";
            return s.get_string("panel-clock-format");
        }

        public string get_gtk_theme () {
            var s = get_gtk_interface();
            if (s == null) return "";
            return s.get_string("gtk-theme");
        }

        public void set_gtk_theme (string value) {
            var s = get_gtk_interface();
            if (s == null) return;
            s.set_string("gtk-theme", value);
        }

        public string get_icon_theme () {
            var s = get_gtk_interface();
            if (s == null) return "";
            return s.get_string("icon-theme");
        }

        public void set_icon_theme (string value) {
            var s = get_gtk_interface();
            if (s == null) return;
            s.set_string("icon-theme", value);
        }

        public string get_font_name () {
            var s = get_gtk_interface();
            if (s == null) return "";
            return s.get_string("font-name");
        }

        public void set_font_name (string value) {
            var s = get_gtk_interface();
            if (s == null) return;
            s.set_string("font-name", value);
        }

        public string get_cursor_theme () {
            var s = get_gtk_interface();
            if (s == null) return "";
            return s.get_string("cursor-theme");
        }

        public void set_cursor_theme (string value) {
            var s = get_gtk_interface();
            if (s == null) return;
            s.set_string("cursor-theme", value);
        }

        public int get_cursor_size () {
            var s = get_gtk_interface();
            if (s == null) return 0;
            return s.get_int("cursor-size");
        }

        public void set_cursor_size (int value) {
            var s = get_gtk_interface();
            if (s == null) return;
            s.set_int("cursor-size", value);
        }

        public bool get_enable_animations () {
            var s = get_gtk_interface();
            if (s == null) return false;
            return s.get_boolean("enable-animations");
        }

        public void set_enable_animations (bool value) {
            var s = get_gtk_interface();
            if (s == null) return;
            s.set_boolean("enable-animations", value);
        }

        
        public bool gtk_interface_has_key (string key) {
            var s = get_gtk_interface();
            if (s == null) return false;
            return s.settings_schema.has_key(key);
        }

        
        public string get_color_scheme () {
            var s = get_gtk_interface();
            if (s == null) return "";
            if (!s.settings_schema.has_key("color-scheme")) return "";
            return s.get_string("color-scheme");
        }

        public void set_color_scheme (string value) {
            var s = get_gtk_interface();
            if (s == null) return;
            if (!s.settings_schema.has_key("color-scheme")) return;
            s.set_string("color-scheme", value);
        }
    }
}
