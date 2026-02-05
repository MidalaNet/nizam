using GLib;
using Cairo;
using Rsvg;

namespace NizamSettings {
    public class PekwmThemeBuilder : Object {
        private static int ceil_pos (double v) {
            var i = (int) v;
            if ((double) i < v) i++;
            return i > 0 ? i : 0;
        }

        private static bool render_one (string svg_path, string png_path, out string error) {
            error = "";
            try {
                var handle = new Rsvg.Handle.from_file(svg_path);
                double width_px = 0.0;
                double height_px = 0.0;

                if (!handle.get_intrinsic_size_in_pixels(out width_px, out height_px) || width_px <= 0.0 || height_px <= 0.0) {
                    bool has_width;
                    bool has_height;
                    bool has_viewbox;
                    Rsvg.Length w_len;
                    Rsvg.Length h_len;
                    Rsvg.Rectangle viewbox;

                    handle.get_intrinsic_dimensions(out has_width, out w_len, out has_height, out h_len, out has_viewbox, out viewbox);

                    if (has_width && w_len.unit == Rsvg.Unit.PX) width_px = w_len.length;
                    if (has_height && h_len.unit == Rsvg.Unit.PX) height_px = h_len.length;

                    if ((width_px <= 0.0 || height_px <= 0.0) && has_viewbox) {
                        width_px = viewbox.width;
                        height_px = viewbox.height;
                    }
                }

                if (width_px <= 0.0 || height_px <= 0.0) {
                    width_px = 16.0;
                    height_px = 16.0;
                }

                var width = ceil_pos(width_px);
                var height = ceil_pos(height_px);
                if (width <= 0 || height <= 0) {
                    width = 16;
                    height = 16;
                }

                var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, width, height);
                var cr = new Cairo.Context(surface);
                var viewport = Rsvg.Rectangle() { x = 0.0, y = 0.0, width = (double) width, height = (double) height };
                if (!handle.render_document(cr, viewport)) {
                    error = "render_document failed";
                    return false;
                }
                surface.write_to_png(png_path);
                return true;
            } catch (GLib.Error e) {
                error = e.message;
                return false;
            }
        }

        private static bool clear_png_dir (File png_dir, out string error) {
            error = "";
            try {
                if (!png_dir.query_exists()) return true;
                var enumerator = png_dir.enumerate_children("standard::name,standard::type", FileQueryInfoFlags.NONE);
                FileInfo info;
                while ((info = enumerator.next_file()) != null) {
                    if (info.get_file_type() != FileType.REGULAR) continue;
                    var name = info.get_name();
                    if (name == null || !name.has_suffix(".png")) continue;
                    png_dir.get_child(name).delete();
                }
                return true;
            } catch (GLib.Error e) {
                error = e.message;
                return false;
            }
        }

        public static bool render_svg_to_png (File theme_dir, out string error) {
            error = "";
            var src_svg = theme_dir.get_child("svg");
            if (!src_svg.query_exists()) {
                error = "missing svg directory";
                return false;
            }

            var png_dir = theme_dir.get_child("png");
            try {
                PekwmPaths.ensure_dir(png_dir);
            } catch (GLib.Error e) {
                error = e.message;
                return false;
            }
            string clear_error;
            if (!clear_png_dir(png_dir, out clear_error)) {
                error = "png cleanup failed: %s".printf(clear_error);
                return false;
            }

            var errors = new StringBuilder();
            bool ok = true;
            try {
                var enumerator = src_svg.enumerate_children("standard::name,standard::type", FileQueryInfoFlags.NONE);
                FileInfo info;
                while ((info = enumerator.next_file()) != null) {
                    if (info.get_file_type() != FileType.REGULAR) continue;
                    var name = info.get_name();
                    if (name == null || !name.has_suffix(".svg")) continue;

                    var base_name = name.substring(0, name.length - 4);
                    var svg_path = src_svg.get_child(name).get_path();
                    var png_path = png_dir.get_child(base_name + ".png").get_path();
                    if (svg_path == null || png_path == null) continue;

                    string one_error;
                    if (!render_one(svg_path, png_path, out one_error)) {
                        ok = false;
                        errors.append("render failed: %s: %s\n".printf(name, one_error));
                    }
                }
            } catch (GLib.Error e) {
                error = e.message;
                return false;
            }

            if (!ok) {
                error = errors.str.strip();
                return false;
            }
            return true;
        }

        public static bool validate_theme (File theme_dir, out string error) {
            error = "";
            var theme_file = theme_dir.get_child("theme");
            if (!theme_file.query_exists()) {
                error = "missing theme file";
                return false;
            }

            string contents;
            try {
                if (!FileUtils.get_contents(theme_file.get_path(), out contents)) {
                    error = "failed to read theme file";
                    return false;
                }
            } catch (GLib.Error e) {
                error = e.message;
                return false;
            }

            Regex re;
            try {
                re = new Regex("Image +([^\" ]+)");
            } catch (RegexError e) {
                error = e.message;
                return false;
            }

            var ref_map = new HashTable<string, string>(str_hash, str_equal);
            var errors = new StringBuilder();
            bool missing = false;

            MatchInfo match;
            if (re.match(contents, 0, out match)) {
                while (true) {
                    var path = match.fetch(1);
                    if (path != null) {
                        var hash_idx = path.index_of("#");
                        if (hash_idx >= 0) path = path.substring(0, hash_idx);
                        path = path.strip();
                        if (path.length > 0) {
                            if (path.has_prefix("png/")) {
                                ref_map.insert(path, "1");
                            }

                            var full = theme_dir.get_child(path);
                            if (!full.query_exists()) {
                                missing = true;
                                errors.append("missing: %s\n".printf(path));
                            }
                        }
                    }
                    try {
                        if (!match.next()) break;
                    } catch (GLib.RegexError e) {
                        error = e.message;
                        return false;
                    }
                }
            }

            var png_dir = theme_dir.get_child("png");
            if (png_dir.query_exists()) {
                try {
                    var enumerator = png_dir.enumerate_children("standard::name,standard::type", FileQueryInfoFlags.NONE);
                    FileInfo info;
                    while ((info = enumerator.next_file()) != null) {
                        if (info.get_file_type() != FileType.REGULAR) continue;
                        var name = info.get_name();
                        if (name == null || !name.has_suffix(".png")) continue;
                        var rel = "png/" + name;
                        if (ref_map.lookup(rel) == null) {
                            errors.append("unused png: %s\n".printf(rel));
                            missing = true;
                        }
                    }
                } catch (GLib.Error e) {
                    errors.append("png scan failed: %s\n".printf(e.message));
                    missing = true;
                }
            }

            if (missing) {
                error = errors.str.strip();
                return false;
            }
            return true;
        }
    }
}
