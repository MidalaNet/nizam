using GLib;
using Gtk;
using Gdk;


[CCode (cname = "gtk_info_bar_get_content_area")]
private extern static unowned Gtk.Widget gtk_info_bar_get_content_area_widget (Gtk.InfoBar bar);

namespace NizamSettings {
    public class GtkPage : Gtk.Box {
        private Gtk.InfoBar? infobar = null;
        private Gtk.Label status;
        private Gtk.Label tech_info;

        private Gtk.Widget? prefs_area = null;
        private Gtk.Switch sw_dark;
        private Gtk.Button? apply_btn = null;

        private const string THEME_LIGHT = "Adwaita";
        private const string THEME_DARK = "Adwaita-dark";
        private const string ICON_THEME = "Adwaita";
        private const string CURSOR_THEME_PREFERRED = "Adwaita";
        private const string FONT_NAME = "Sans 10";

        private NizamCommon.NizamGSettings gs;
        private bool ui_lock = false;
        private bool enforce_lock = false;

        public GtkPage () {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 12);
            gs = new NizamCommon.NizamGSettings();

            var content = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
            content.margin_top = 12;
            content.margin_bottom = 12;
            content.margin_start = 12;
            content.margin_end = 12;
            content.set_hexpand(true);
            content.set_vexpand(false);
            
            this.pack_start(content, false, false, 0);

            infobar = build_infobar();
            content.pack_start(infobar, false, false, 0);

            
            var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
            header.halign = Gtk.Align.START;
            header.valign = Gtk.Align.START;
            content.pack_start(header, false, false, 0);

            var logo = build_logo_image();
            header.pack_start(logo, false, false, 0);

            var header_text = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
            header_text.hexpand = true;
            header.pack_start(header_text, true, true, 0);

            var title = new Gtk.Label("GUI Toolkit");
            title.halign = Gtk.Align.START;
            title.set_xalign(0.0f);
            title.get_style_context().add_class("title-1");
            header_text.pack_start(title, false, false, 0);

            var subtitle = new Gtk.Label("GTK3 appearance is configured through GSettings (org.gnome.desktop.interface).\nNizam can enforce Adwaita defaults; the only preference here is Dark mode. Click Apply to write settings.");
            subtitle.halign = Gtk.Align.START;
            subtitle.set_xalign(0.0f);
            subtitle.wrap = true;
            subtitle.get_style_context().add_class("dim-label");
            header_text.pack_start(subtitle, false, false, 0);

            
            var about_frame = new Gtk.Frame("About");
            var about_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
            about_box.margin_top = 10;
            about_box.margin_bottom = 10;
            about_box.margin_start = 10;
            about_box.margin_end = 10;

            var about_1 = new Gtk.Label(
                "Nizam uses the standard GNOME stack (<b>GTK3</b> + <b>GLib</b> + <b>GIO</b>) to keep the UI consistent and predictable.\n" +
                "This page changes global GTK settings through <b>GSettings</b> only."
            );
            about_1.halign = Gtk.Align.START;
            about_1.set_xalign(0.0f);
            about_1.wrap = true;
            about_1.use_markup = true;
            about_box.pack_start(about_1, false, false, 0);

            var about_2 = new Gtk.Label(
                "If GSettings is not available at runtime (missing schema/backend), settings are not applied."
            );
            about_2.halign = Gtk.Align.START;
            about_2.set_xalign(0.0f);
            about_2.wrap = true;
            about_2.use_markup = true;
            about_box.pack_start(about_2, false, false, 0);

            about_frame.add(about_box);
            content.pack_start(about_frame, false, false, 0);

            
            var tech_frame = new Gtk.Frame("Technical");
            var tech_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
            tech_box.margin_top = 10;
            tech_box.margin_bottom = 10;
            tech_box.margin_start = 10;
            tech_box.margin_end = 10;

            tech_info = new Gtk.Label("");
            tech_info.halign = Gtk.Align.START;
            tech_info.set_xalign(0.0f);
            tech_info.wrap = true;
            tech_info.get_style_context().add_class("nizam-status-text");
            tech_box.pack_start(tech_info, false, false, 0);

            tech_frame.add(tech_box);
            content.pack_start(tech_frame, false, false, 0);

            
            var settings_frame = new Gtk.Frame("Preferences");
            var settings_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 10);
            settings_box.margin_top = 10;
            settings_box.margin_bottom = 10;
            settings_box.margin_start = 10;
            settings_box.margin_end = 10;

            var grid = new Gtk.Grid();
            grid.row_spacing = 10;
            grid.column_spacing = 12;

            sw_dark = new Gtk.Switch();
            add_switch_row(grid, 0, "Dark", sw_dark);

            settings_box.pack_start(grid, false, false, 0);
            settings_frame.add(settings_box);
            content.pack_start(settings_frame, false, false, 0);
            prefs_area = settings_frame;

            
            status = new Gtk.Label("");
            status.halign = Gtk.Align.START;
            status.set_xalign(0.0f);
            status.wrap = true;
            status.get_style_context().add_class("nizam-status-text");
            content.pack_start(status, false, false, 0);

            var action_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            action_row.halign = Gtk.Align.END;

            apply_btn = new Gtk.Button.with_label("Apply");
            apply_btn.always_show_image = true;
            apply_btn.image = new Gtk.Image.from_icon_name(pick_apply_icon_name(), Gtk.IconSize.BUTTON);
            apply_btn.get_style_context().add_class("suggested-action");
            apply_btn.clicked.connect(() => { apply_gsettings(); });
            action_row.pack_end(apply_btn, false, false, 0);
            content.pack_start(action_row, false, false, 0);

            connect_live_updates();
            refresh_all();
        }

        private Gtk.InfoBar build_infobar () {
            var bar = new Gtk.InfoBar();
            bar.set_no_show_all(true);
            bar.show_close_button = true;
            bar.response.connect((resp) => {
                bar.hide();
            });

            var label = new Gtk.Label("");
            label.halign = Gtk.Align.START;
            label.set_xalign(0.0f);
            label.wrap = true;
            label.use_markup = true;
            Gtk.Widget area_widget = gtk_info_bar_get_content_area_widget(bar);
            ((Gtk.Container) area_widget).add(label);
            label.show();

            bar.set_data("label", label);
            return bar;
        }

        private void infobar_show_error (string message) {
            if (infobar == null) return;
            var label = (Gtk.Label) infobar.get_data<Gtk.Label>("label");
            infobar.set_message_type(Gtk.MessageType.ERROR);
            label.set_markup(message);
            infobar.show_all();
        }

        private void infobar_hide () {
            if (infobar == null) return;
            infobar.hide();
        }

        private static void add_switch_row (Gtk.Grid grid, int row, string label, Gtk.Switch sw) {
            var l = new Gtk.Label(label);
            l.halign = Gtk.Align.START;
            grid.attach(l, 0, row, 1, 1);

            sw.set_hexpand(false);
            sw.halign = Gtk.Align.START;
            sw.valign = Gtk.Align.CENTER;
            var wrap = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            wrap.pack_start(sw, false, false, 0);
            grid.attach(wrap, 1, row, 1, 1);
        }

        private static bool looks_dark_theme (string theme) {
            var t = theme.strip().down();
            return t.contains("dark");
        }

        private bool read_dark_from_gsettings () {
            if (!gs.init_gtk_interface()) return false;

            if (gs.gtk_interface_has_key("color-scheme")) {
                var cs = gs.get_color_scheme().strip();
                if (cs == "prefer-dark") return true;
                if (cs == "prefer-light") return false;
                
            }
            return looks_dark_theme(gs.get_gtk_theme());
        }

        private static bool cursor_theme_installed (string name) {
            var home = Environment.get_home_dir();
            string[] bases = {
                Path.build_filename(home, ".icons"),
                Path.build_filename(home, ".local", "share", "icons"),
                "/usr/local/share/icons",
                "/usr/share/icons"
            };

            foreach (var base_dir in bases) {
                var cursors_dir = Path.build_filename(base_dir, name, "cursors");
                if (FileUtils.test(cursors_dir, FileTest.IS_DIR)) return true;
            }
            return false;
        }

        private void apply_hardcoded_defaults (bool dark) {
            if (enforce_lock) return;
            var req = NizamCommon.NizamGSettings.check_requirements();
            if (!req.schema_installed || !gs.init_gtk_interface()) return;

            enforce_lock = true;
            gs.set_icon_theme(ICON_THEME);

            var cursor_theme = CURSOR_THEME_PREFERRED;
            if (!cursor_theme_installed(cursor_theme) && cursor_theme_installed("Adwaita")) {
                cursor_theme = "Adwaita";
            }
            gs.set_cursor_theme(cursor_theme);

            gs.set_font_name(FONT_NAME);
            gs.set_gtk_theme(dark ? THEME_DARK : THEME_LIGHT);

            
            if (gs.gtk_interface_has_key("color-scheme")) {
                gs.set_color_scheme(dark ? "prefer-dark" : "prefer-light");
            }

            enforce_lock = false;
        }

        private void apply_gsettings () {
            var req = NizamCommon.NizamGSettings.check_requirements();
            if (!req.schema_installed || !gs.init_gtk_interface()) {
                infobar_show_error(
                    "<b>Cannot apply settings</b>: missing schema %s\n".printf(Markup.escape_text(req.schema_id)) +
                    "Install: <tt>gsettings-desktop-schemas</tt> <tt>dconf-gsettings-backend</tt> <tt>dconf-service</tt>"
                );
                status.set_text("Not applied");
                return;
            }

            apply_hardcoded_defaults(sw_dark.active);
            sync_process_appearance_from_gsettings();
            refresh_all();
            status.set_text("Applied via GSettings");
        }

        private void sync_process_appearance_from_gsettings () {
            if (!gs.init_gtk_interface()) return;
            var settings = Gtk.Settings.get_default();
            if (settings == null) return;

            var theme = gs.get_gtk_theme();
            var icons = gs.get_icon_theme();
            var cursor = gs.get_cursor_theme();
            var font = gs.get_font_name();
            var dark = read_dark_from_gsettings();

            
            
            if (theme.strip().length > 0) settings.set_property("gtk-theme-name", theme);
            if (icons.strip().length > 0) settings.set_property("gtk-icon-theme-name", icons);
            if (cursor.strip().length > 0) settings.set_property("gtk-cursor-theme-name", cursor);
            if (font.strip().length > 0) settings.set_property("gtk-font-name", font);
            settings.set_property("gtk-application-prefer-dark-theme", dark);

            var cs = gs.get_cursor_size();
            if (cs > 0) settings.set_property("gtk-cursor-theme-size", cs);

            var icon_theme = Gtk.IconTheme.get_default();
            if (icon_theme != null) icon_theme.rescan_if_needed();
        }

        private static string pick_apply_icon_name () {
            var theme = Gtk.IconTheme.get_default();
            if (theme != null && theme.has_icon("object-select-symbolic")) return "object-select-symbolic";
            if (theme != null && theme.has_icon("gtk-apply")) return "gtk-apply";
            return "document-save-symbolic";
        }

        private void refresh_all () {
            var req = NizamCommon.NizamGSettings.check_requirements();
            refresh_technical_info(req);

            bool ok = req.schema_installed;
            if (!ok) {
                infobar_show_error(
                    "<b>Schema GSettings mancante:</b> %s\n".printf(Markup.escape_text(req.schema_id)) +
                    "Installa i pacchetti runtime: <tt>gsettings-desktop-schemas</tt> <tt>dconf-gsettings-backend</tt> <tt>dconf-service</tt>"
                );
            } else {
                infobar_hide();
            }

            if (prefs_area != null) prefs_area.set_sensitive(ok);
            if (apply_btn != null) apply_btn.set_sensitive(ok);
            if (!ok) {
                status.set_text("GTK settings are unavailable (GSettings schema missing). ");
                return;
            }

            if (!ok || !gs.init_gtk_interface()) {
                status.set_text("GTK settings are unavailable (GSettings schema missing).");
                return;
            }

            ui_lock = true;
            sw_dark.active = read_dark_from_gsettings();
            ui_lock = false;

            status.set_text("Ready");
        }

        private void refresh_technical_info (NizamCommon.RequirementsResult req) {
            var gtk_v = "%u.%u.%u".printf(Gtk.get_major_version(), Gtk.get_minor_version(), Gtk.get_micro_version());
            var lines = new StringBuilder();
            lines.append("GLib: %s\n".printf(req.glib_version));
            lines.append("GTK: %s\n".printf(gtk_v));
            lines.append("GSettings schema (%s): %s\n".printf(req.schema_id, req.schema_installed ? "OK" : "MISSING"));
            lines.append("Backend: %s\n".printf(req.backend_hint));

            if (req.gsettings_cli_version.strip().length > 0) {
                lines.append("gsettings: %s\n".printf(req.gsettings_cli_version));
            }
            if (req.dconf_cli_version.strip().length > 0) {
                lines.append("dconf: %s\n".printf(req.dconf_cli_version));
            }

            tech_info.set_text(lines.str.strip());
        }

        private void connect_live_updates () {
            gs.gtk_interface_changed.connect((key) => {
                if (ui_lock) return;

                
                if (enforce_lock) return;
                if (key == "gtk-theme" || key == "color-scheme") {
                    ui_lock = true;
                    sw_dark.active = read_dark_from_gsettings();
                    ui_lock = false;
                    return;
                }
            });
        }

        private Gtk.Image build_logo_image () {
            try {
                var path = Assets.find_ui_file("gtk-logo.png");
                var pix = new Pixbuf.from_file_at_scale(path, 64, 64, true);
                return new Gtk.Image.from_pixbuf(pix);
            } catch (Error e) {
                var img = new Gtk.Image.from_icon_name("preferences-desktop-theme", Gtk.IconSize.DIALOG);
                img.set_pixel_size(64);
                return img;
            }
        }
    }
}
