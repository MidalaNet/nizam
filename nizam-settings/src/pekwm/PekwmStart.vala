using GLib;
using Sqlite;
using Gdk;
using Cairo;

namespace NizamSettings {
    public class PekwmStartConfig : Object {
        public string wallpaper_mode = "--bg-scale";
        public string wallpaper_path = "";
        public string feh_version = "";
    }

    public class PekwmStartStore : Object {
        private NizamDb db;

        public PekwmStartStore (NizamDb db) {
            this.db = db;
        }

        private string get_wm_setting (string key, string def = "") throws GLib.Error {
            Statement stmt;
            var rc = db.handle.prepare_v2("SELECT value FROM wm_settings WHERE key=?1", -1, out stmt);
            if (rc != Sqlite.OK) throw new IOError.FAILED(db.handle.errmsg());
            stmt.bind_text(1, key);
            rc = stmt.step();
            if (rc == Sqlite.ROW) {
                return stmt.column_text(0) ?? def;
            }
            return def;
        }

        private void set_wm_setting (string key, string value) throws GLib.Error {
            Statement stmt;
            var sql = "INSERT INTO wm_settings(key,value) VALUES(?1,?2) " +
                      "ON CONFLICT(key) DO UPDATE SET value=excluded.value";
            var rc = db.handle.prepare_v2(sql, -1, out stmt);
            if (rc != Sqlite.OK) throw new IOError.FAILED(db.handle.errmsg());
            stmt.bind_text(1, key);
            stmt.bind_text(2, value);
            rc = stmt.step();
            if (rc != Sqlite.DONE) throw new IOError.FAILED(db.handle.errmsg());
        }

        public PekwmStartConfig load () throws GLib.Error {
            var cfg = new PekwmStartConfig();

            var w_mode = get_wm_setting("pekwm.start.wallpaper.mode", cfg.wallpaper_mode);
            var w_path = get_wm_setting("pekwm.start.wallpaper.path", cfg.wallpaper_path);
            var fv = get_wm_setting("pekwm.start.feh.version", cfg.feh_version);

            cfg.wallpaper_mode = w_mode;
            cfg.wallpaper_path = w_path;
            cfg.feh_version = fv;
            return cfg;
        }

        public void save (PekwmStartConfig cfg) throws GLib.Error {
            set_wm_setting("pekwm.start.wallpaper.mode", cfg.wallpaper_mode);
            set_wm_setting("pekwm.start.wallpaper.path", cfg.wallpaper_path);
            if (cfg.feh_version != null) {
                set_wm_setting("pekwm.start.feh.version", cfg.feh_version);
            }
        }

        public static string detect_feh_version () {
            string? out_text = null;
            string? err_text = null;
            int status = 0;
            try {
                Process.spawn_sync(null, new string[] { "feh", "--version" }, null, SpawnFlags.SEARCH_PATH, null, out out_text, out err_text, out status);
                if (status == 0) {
                    var s = (out_text ?? "").strip();
                    if (s.length > 0) return s.split("\n")[0].strip();
                }
            } catch (GLib.Error e) {
                
            }

            var in_path = Environment.find_program_in_path("feh");
            if (in_path == null || in_path.strip().length == 0) return "not installed";
            return "installed (version unknown)";
        }
    }

    public class PekwmStartBuilder : Object {
        private const string FALLBACK_WALLPAPER_VERSION = "2";

        private static string normalize_feh_mode (string mode) {
            var m = (mode ?? "").strip();
            if (m.length == 0) return "--bg-scale";

            
            switch (m) {
            case "--bg-scale":
            case "--bg-fill":
            case "--bg-center":
            case "--bg-max":
                return m;
            default:
                return "--bg-scale";
            }
        }

        private static string get_fallback_wallpaper_path () {
            return GLib.Path.build_filename(Environment.get_user_config_dir(), "nizam", "wallpaper-fallback.png");
        }

        private static string get_fallback_wallpaper_version_path () {
            return GLib.Path.build_filename(Environment.get_user_config_dir(), "nizam", "wallpaper-fallback.version");
        }

        private static string read_text_file (string path) {
            try {
                string contents;
                if (FileUtils.get_contents(path, out contents)) {
                    return (contents ?? "").strip();
                }
            } catch (GLib.Error e) {
                
            }
            return "";
        }

        private static string? locate_fallback_wallpaper_svg_path () {
            
            var p1 = GLib.Path.build_filename(NizamSettings.PKGDATADIR, "nizam-settings", "desktop", "default.svg");
            if (FileUtils.test(p1, FileTest.EXISTS)) return p1;

            
            try {
                var exe = FileUtils.read_link("/proc/self/exe");
                var dir = GLib.Path.get_dirname(exe);
                for (int i = 0; i < 7; i++) {
                    var cand = GLib.Path.build_filename(dir, "nizam-settings", "data", "desktop", "default.svg");
                    if (FileUtils.test(cand, FileTest.EXISTS)) return cand;
                    dir = GLib.Path.get_dirname(dir);
                }
            } catch (GLib.Error e) {
                
            }

            return null;
        }

        private static string fallback_wallpaper_tag (string svg_path) {
            
            try {
                var f = File.new_for_path(svg_path);
                var info = f.query_info("time::modified,standard::size", FileQueryInfoFlags.NONE);
                var m = info.get_attribute_uint64("time::modified");
                var s = info.get_size();
                return "defaultsvg:%s:%s".printf(m.to_string(), s.to_string());
            } catch (GLib.Error e) {
                return "defaultsvg";
            }
        }

        private static bool is_valid_wallpaper_file (string path) {
            var p = (path ?? "").strip();
            if (p.length == 0) return false;

            try {
                var f = File.new_for_path(p);
                var info = f.query_info("standard::type,standard::size", FileQueryInfoFlags.NONE);
                var t = info.get_file_type();
                if (t != FileType.REGULAR && t != FileType.SYMBOLIC_LINK) return false;
                if (info.get_size() <= 0) return false;
                return true;
            } catch (GLib.Error e) {
                return false;
            }
        }

        public static void regenerate_fallback_wallpaper () {
            
            ensure_fallback_wallpaper(true);
        }

        private static string ensure_fallback_wallpaper (bool force = false) {
            var out_path = get_fallback_wallpaper_path();
            var ver_path = get_fallback_wallpaper_version_path();

            var svg_path = locate_fallback_wallpaper_svg_path();
            var expected_tag = (svg_path != null) ? fallback_wallpaper_tag(svg_path) : "plain";
            var expected_version = "%s:%s".printf(FALLBACK_WALLPAPER_VERSION, expected_tag);

            if (!force && is_valid_wallpaper_file(out_path)) {
                var have_version = read_text_file(ver_path);
                if (have_version == expected_version) {
                    return out_path;
                }
            }

            var dir = GLib.Path.get_dirname(out_path);
            DirUtils.create_with_parents(dir, 0755);

            
            const int width = 1920;
            const int height = 1080;

            var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, width, height);
            var cr = new Cairo.Context(surface);

            bool rendered = false;
            if (svg_path != null) {
                try {
                    var handle = new Rsvg.Handle.from_file(svg_path);
                    var viewport = Rsvg.Rectangle() { x = 0, y = 0, width = width, height = height };
                    handle.render_document(cr, viewport);
                    rendered = true;
                } catch (GLib.Error e) {
                    
                    try {
                        var pix = new Pixbuf.from_file_at_scale(svg_path, width, height, true);
                        Gdk.cairo_set_source_pixbuf(cr, pix, 0, 0);
                        cr.paint();
                        rendered = true;
                    } catch (GLib.Error e2) {
                        rendered = false;
                    }
                }
            }

            if (!rendered) {
                
                cr.set_source_rgb(0x2e / 255.0, 0x34 / 255.0, 0x36 / 255.0);
                cr.paint();
            }

            surface.write_to_png(out_path);

            try {
                FileUtils.set_contents(ver_path, expected_version + "\n");
            } catch (GLib.Error e) {
                
            }

            if (is_valid_wallpaper_file(out_path)) return out_path;

            
            return "";
        }

        private static string dq_escape (string s) {
            
            return s.replace("\\", "\\\\")
                    .replace("\"", "\\\"")
                    .replace("$", "\\$")
                    .replace("`", "\\`");
        }

        private static string format_feh_version_comment (string raw) {
            var s = (raw ?? "").strip();
            if (s.length == 0) return "";
            if (s.has_prefix("feh version ")) return s;
            
            if (s.has_prefix("feh ")) {
                var v = s.substring(4).strip();
                if (v.length > 0) return "feh version %s".printf(v);
            }
            return s;
        }

        private static string normalize_autostart_command (string cmd) {
            var s = (cmd ?? "").strip();
            
            if (s.has_suffix("&")) {
                s = s.substring(0, s.length - 1).strip();
            }
            return s;
        }

        private static void append_autostart_items (StringBuilder sb, PtrArray items) {
            int last_enabled_index = -1;
            for (uint i = 0; i < items.length; i++) {
                var item = (PekwmAutostartItem) items.get(i);
                if (!item.enabled) continue;
                var cmd = normalize_autostart_command(item.command ?? "");
                if (cmd.length == 0) continue;
                last_enabled_index = (int) i;
            }

            if (last_enabled_index < 0) {
                sb.append("# (none)\n");
                return;
            }

            for (uint i = 0; i < items.length; i++) {
                var item = (PekwmAutostartItem) items.get(i);
                if (!item.enabled) continue;
                var cmd = normalize_autostart_command(item.command ?? "");
                if (cmd.length == 0) continue;

                if ((int) i != last_enabled_index) {
                    sb.append(cmd);
                    sb.append(" &\n");
                } else {
                    sb.append(cmd);
                    sb.append("\n");
                }
            }
        }

        public static string build (PekwmStartConfig cfg, PtrArray? autostart_items = null) {
            var sb = new StringBuilder();
            sb.append("#!/bin/sh\n");
            sb.append("# PekWM start file\n");
            sb.append("# Generated by Nizam - DO NOT EDIT\n\n");

            sb.append("# Wallpaper\n");

            
            var feh_comment = format_feh_version_comment(cfg.feh_version ?? "");
            if (feh_comment.length > 0) {
                sb.append("# feh: %s\n".printf(feh_comment));
            }

            
            var feh_bin = Environment.find_program_in_path("feh");
            if (feh_bin == null || feh_bin.strip().length == 0) {
                sb.append("# feh not installed; wallpaper not applied\n\n");
            } else {
                var mode = normalize_feh_mode(cfg.wallpaper_mode);
                var chosen = (cfg.wallpaper_path ?? "").strip();
                string wp = "";

                if (chosen.length > 0 && is_valid_wallpaper_file(chosen)) {
                    wp = chosen;
                } else {
                    
                    wp = ensure_fallback_wallpaper(false);
                }

                if (wp.length > 0) {
                    sb.append("feh %s \"%s\" &\n\n".printf(mode, dq_escape(wp)));
                } else {
                    sb.append("# Wallpaper: none\n\n");
                }
            }

            sb.append("# Always start\n");
            sb.append("nizam-panel &\n");
            sb.append("nizam-dock &\n");

            sb.append("# Autostart\n");
            sb.append("# See nizam-settings / Window Manager\n");
            if (autostart_items != null) append_autostart_items(sb, autostart_items);
            else sb.append("# (none)\n");

            return sb.str;
        }

        public static string build_from_db (NizamDb db) throws GLib.Error {
            var store = new PekwmStartStore(db);
            var cfg = store.load();
            cfg.feh_version = PekwmStartStore.detect_feh_version();
            
            store.save(cfg);

            var auto_store = new PekwmAutostartStore(db);
            var items = auto_store.list_items();
            return build(cfg, items);
        }
    }
}
