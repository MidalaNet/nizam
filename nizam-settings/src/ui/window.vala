using GLib;
using Gtk;
using Gdk;

namespace NizamSettings {
    public class MainWindow : NizamGtk3.NizamAppWindow {
        private SettingsStore store;
        private Gtk.Stack? stack = null;
        private Gtk.ListBox? sidebar_list = null;
        private bool sidebar_locked = false;
        private delegate void ToolCallback ();
        private string[] history = {};
        private int history_index = -1;
        private bool history_locked = false;

        public MainWindow (Gtk.Application app, SettingsStore store) throws Error {
            base(app, "Nizam Settings", 760, 460);
            this.store = store;

            this.icon_name = "nizam-settings";

            set_about_info(
                "Nizam Settings",
                APP_VERSION,
                "Settings UI for Nizam.",
                "nizam"
            );
            set_toolbar(build_toolbar());

            sidebar_list = build_sidebar();
            set_sidebar(sidebar_list);

            stack = new Gtk.Stack();
            stack.hexpand = true;
            
            stack.vexpand = false;
            
            
            stack.hhomogeneous = false;
            stack.vhomogeneous = false;

            
            set_content(stack, true);

            
            var home_view = build_home_view();
            stack.add_named(home_view, "home");

            var wm_page = new PekwmPage(store);
            stack.add_named(wm_page, "wm");

            var gtk_page = new GtkPage();
            stack.add_named(gtk_page, "gtk");

            var apps_page = new ApplicationsPage(store);
            stack.add_named(apps_page, "apps");

            navigate_to(stack, "home", "Home");

            set_status_left("Ready");
            set_status_right("Nizam Settings " + APP_VERSION);

            this.show_all();
        }

        private Gtk.Widget build_toolbar () {
            var toolbar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            toolbar.margin_top = 6;
            toolbar.margin_bottom = 6;
            toolbar.margin_start = 8;
            toolbar.margin_end = 8;

            toolbar.pack_start(build_tool_button("go-previous-symbolic", "Back", () => {
                if (stack != null) navigate_back(stack);
            }), false, false, 0);

            toolbar.pack_start(build_tool_button("go-next-symbolic", "Forward", () => {
                if (stack != null) navigate_forward(stack);
            }), false, false, 0);

            toolbar.pack_start(build_tool_button("go-up-symbolic", "Up", () => {
                if (stack != null) navigate_to(stack, "home", "Home");
            }), false, false, 0);

            toolbar.pack_start(build_tool_button("go-home-symbolic", "Home", () => {
                if (stack != null) navigate_to(stack, "home", "Home");
            }), false, false, 0);

            return toolbar;
        }

        private Gtk.Button build_tool_button (string icon_name, string tooltip, ToolCallback? callback) {
            var btn = new Gtk.Button();
            btn.tooltip_text = tooltip;
            var img = new Gtk.Image.from_icon_name(icon_name, Gtk.IconSize.LARGE_TOOLBAR);
            img.set_pixel_size(20);
            btn.add(img);
            if (callback != null) btn.clicked.connect(() => { callback(); });
            return btn;
        }

        private Gtk.ListBox build_sidebar () {
            var list = new Gtk.ListBox();
            list.selection_mode = Gtk.SelectionMode.SINGLE;

            list.add(build_sidebar_row("Nizam Desktop Environment", "", null, null, true));
            list.add(build_sidebar_row("Window Manager", "wm", "nizam-page-window-manager", "pekwm-logo.png"));
            list.add(build_sidebar_row("GUI Toolkit", "gtk", "nizam-page-gui-toolkit", "gtk-logo.png"));
            list.add(build_sidebar_row("Applications", "apps", "nizam-page-applications"));

            list.row_selected.connect((row) => {
                if (sidebar_locked) return;
                if (row == null || stack == null) return;
                var page = row.get_data<string>("page");
                var title = row.get_data<string>("title");
                if (page != null && page.strip().length > 0) {
                    navigate_to(stack, page, title);
                }
            });

            return list;
        }

        private Gtk.ListBoxRow build_sidebar_row (string title, string page, string? icon_name, string? asset_name = null, bool header = false) {
            var row = new Gtk.ListBoxRow();
            row.set_data("page", page);
            row.set_data("title", title);
            row.set_selectable(!header);

            var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            box.margin_top = 6;
            box.margin_bottom = 6;
            box.margin_start = 8;
            box.margin_end = 8;

            Gtk.Widget? leading = null;
            if (asset_name != null && asset_name.strip().length > 0) {
                try {
                    var path = Assets.find_ui_file(asset_name);
                    var pix = new Pixbuf.from_file_at_scale(path, 16, 16, true);
                    var img = new Gtk.Image.from_pixbuf(pix);
                    img.set_pixel_size(16);
                    leading = img;
                } catch (Error e) {
                    
                }
            }
            if (leading == null && icon_name != null && icon_name.strip().length > 0) {
                var icon = new Gtk.Image.from_icon_name(icon_name, Gtk.IconSize.MENU);
                icon.set_pixel_size(16);
                leading = icon;
            }

            if (leading != null) {
                box.pack_start(leading, false, false, 0);
            } else {
                var spacer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
                spacer.set_size_request(16, 16);
                box.pack_start(spacer, false, false, 0);
            }

            var label = new Gtk.Label(title);
            label.halign = Gtk.Align.START;
            label.hexpand = true;
            if (header) {
                label.set_markup("<b>%s</b>".printf(Markup.escape_text(title)));
            }
            box.pack_start(label, true, true, 0);
            row.add(box);
            row.show_all();
            return row;
        }

        private Gtk.Widget build_home_view () {
            var wrap = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
            wrap.margin_top = 12;
            wrap.margin_bottom = 12;
            wrap.margin_start = 12;
            wrap.margin_end = 12;

            
            var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
            header.halign = Gtk.Align.START;
            wrap.pack_start(header, false, false, 0);

            var icon = new Gtk.Image.from_icon_name("nizam", Gtk.IconSize.DIALOG);
            icon.set_pixel_size(48);
            header.pack_start(icon, false, false, 0);

            var header_text = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
            header.pack_start(header_text, true, true, 0);

            var title = new Gtk.Label("Nizam Desktop Environment");
            title.halign = Gtk.Align.START;
            title.set_xalign(0.0f);
            title.get_style_context().add_class("title-1");
            header_text.pack_start(title, false, false, 0);

            var version = new Gtk.Label("Version %s".printf(APP_VERSION));
            version.halign = Gtk.Align.START;
            version.set_xalign(0.0f);
            version.get_style_context().add_class("dim-label");
            header_text.pack_start(version, false, false, 0);

            var subtitle = new Gtk.Label("Configure Window Manager, GUI toolkit appearance, and Applications.");
            subtitle.halign = Gtk.Align.START;
            subtitle.set_xalign(0.0f);
            subtitle.wrap = true;
            subtitle.get_style_context().add_class("dim-label");
            header_text.pack_start(subtitle, false, false, 0);

            var sections_frame = new Gtk.Frame(null);
            sections_frame.set_shadow_type(Gtk.ShadowType.IN);
            wrap.pack_start(sections_frame, false, false, 0);

            var list = new Gtk.ListBox();
            list.selection_mode = Gtk.SelectionMode.SINGLE;
            list.activate_on_single_click = true;
            list.set_header_func((row, before) => {
                
                row.set_margin_top(0);
                row.set_margin_bottom(0);
            });
            sections_frame.add(list);

            list.add(build_home_row("Window Manager", "pekwm integration", "nizam-page-window-manager", "wm", "pekwm-logo.png"));
            list.add(build_home_row("GUI Toolkit", "Theme and appearance", "nizam-page-gui-toolkit", "gtk", "gtk-logo.png"));
            list.add(build_home_row("Applications", "Manage local desktop entries", "nizam-page-applications", "apps"));

            list.row_activated.connect((row) => {
                if (row == null || stack == null) return;
                var page = row.get_data<string>("page");
                var t = row.get_data<string>("title");
                if (page != null && page.strip().length > 0) {
                    navigate_to(stack, page, t);
                }
            });

            return wrap;
        }

        private Gtk.ListBoxRow build_home_row (string title, string subtitle, string icon_name, string page, string? asset_name = null) {
            var row = new Gtk.ListBoxRow();
            row.set_data("page", page);
            row.set_data("title", title);

            var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 10);
            box.margin_top = 10;
            box.margin_bottom = 10;
            box.margin_start = 10;
            box.margin_end = 10;

            Gtk.Widget? leading = null;
            if (asset_name != null && asset_name.strip().length > 0) {
                try {
                    var path = Assets.find_ui_file(asset_name);
                    var pix = new Pixbuf.from_file_at_scale(path, 20, 20, true);
                    var img = new Gtk.Image.from_pixbuf(pix);
                    img.set_pixel_size(20);
                    leading = img;
                } catch (Error e) {
                    
                }
            }
            if (leading == null) {
                var icon = new Gtk.Image.from_icon_name(pick_icon(icon_name, "application-x-executable"), Gtk.IconSize.MENU);
                icon.set_pixel_size(20);
                leading = icon;
            }
            box.pack_start(leading, false, false, 0);

            var text = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
            text.hexpand = true;
            box.pack_start(text, true, true, 0);

            var name = new Gtk.Label(title);
            name.halign = Gtk.Align.START;
            name.set_xalign(0.0f);
            name.get_style_context().add_class("nizam-app-title");
            text.pack_start(name, false, false, 0);

            var desc = new Gtk.Label(subtitle);
            desc.halign = Gtk.Align.START;
            desc.set_xalign(0.0f);
            desc.wrap = true;
            desc.get_style_context().add_class("dim-label");
            text.pack_start(desc, false, false, 0);

            var chevron = new Gtk.Image.from_icon_name(pick_icon("go-next-symbolic", "go-next"), Gtk.IconSize.MENU);
            chevron.set_pixel_size(16);
            chevron.get_style_context().add_class("dim-label");
            box.pack_end(chevron, false, false, 0);

            row.add(box);
            row.show_all();
            return row;
        }

        private string pick_icon (string primary, string fallback) {
            var theme = Gtk.IconTheme.get_default();
            if (theme != null) {
                if (theme.has_icon(primary)) return primary;
                if (theme.has_icon(fallback)) return fallback;
            }
            return fallback;
        }

        private void navigate_to (Gtk.Stack stack, string page, string? title = null) {
            push_history(page);
            stack.set_visible_child_name(page);
            
            stack.queue_resize();
            stack.queue_draw();
            sync_sidebar_selection(page);
            var label = title;
            if (label == null || label.strip().length == 0) {
                label = title_for_page(page);
            }
            if (label != null && label.strip().length > 0) {
                set_status_left("Viewing: %s".printf(label));
            }
        }

        private void navigate_back (Gtk.Stack stack) {
            if (history_index <= 0) return;
            history_index -= 1;
            var page = history[history_index];
            history_locked = true;
            stack.set_visible_child_name(page);
            stack.queue_resize();
            stack.queue_draw();
            history_locked = false;
            sync_sidebar_selection(page);
            var label = title_for_page(page);
            if (label != null && label.strip().length > 0) {
                set_status_left("Viewing: %s".printf(label));
            }
        }

        private void navigate_forward (Gtk.Stack stack) {
            if (history_index < 0 || history_index >= (int) history.length - 1) return;
            history_index += 1;
            var page = history[history_index];
            history_locked = true;
            stack.set_visible_child_name(page);
            stack.queue_resize();
            stack.queue_draw();
            history_locked = false;
            sync_sidebar_selection(page);
            var label = title_for_page(page);
            if (label != null && label.strip().length > 0) {
                set_status_left("Viewing: %s".printf(label));
            }
        }

        private void sync_sidebar_selection (string page) {
            if (sidebar_list == null) return;

            sidebar_locked = true;
            if (page == "home") {
                sidebar_list.select_row(null);
                sidebar_locked = false;
                return;
            }

            foreach (var child in sidebar_list.get_children()) {
                if (!(child is Gtk.ListBoxRow)) continue;
                var row = (Gtk.ListBoxRow) child;
                if (!row.get_selectable()) continue;
                var row_page = row.get_data<string>("page");
                if (row_page == page) {
                    sidebar_list.select_row(row);
                    sidebar_locked = false;
                    return;
                }
            }

            
            sidebar_list.select_row(null);
            sidebar_locked = false;
        }

        private void push_history (string page) {
            if (history_locked) return;
            if (history_index >= 0 && history_index < (int) history.length && history[history_index] == page) return;
            if (history_index < (int) history.length - 1) {
                string[] trimmed = {};
                for (int i = 0; i <= history_index; i++) {
                    trimmed += history[i];
                }
                history = trimmed;
            }
            history += page;
            history_index = history.length - 1;
        }

        private string? title_for_page (string page) {
            switch (page) {
            case "home":
                return "Nizam Desktop Environment";
            case "gtk":
                return "GUI Toolkit";
            case "apps":
                return "Applications";
            case "wm":
                return "Window Manager";
            default:
                return null;
            }
        }
    }

    public class Assets : Object {
        public static string find_ui_file (string name) throws Error {
            
            var env_dir = Environment.get_variable("NIZAM_SETTINGS_UI_DIR");
            if (env_dir == null || env_dir.strip().length == 0) {
                env_dir = Environment.get_variable("NIZAM_CONFIG_UI_DIR");
            }
            if (env_dir != null && env_dir.strip().length > 0) {
                var p = Path.build_filename(env_dir, name);
                if (FileUtils.test(p, FileTest.IS_REGULAR)) return p;
            }

            
            var installed = Path.build_filename(Environment.get_user_data_dir(), "nizam-settings", "ui", name);
            if (FileUtils.test(installed, FileTest.IS_REGULAR)) return installed;
            
            installed = Path.build_filename(Environment.get_user_data_dir(), "nizam-settings", "ui", "ui", name);
            if (FileUtils.test(installed, FileTest.IS_REGULAR)) return installed;

            
            var xdg_data_dirs = Environment.get_variable("XDG_DATA_DIRS");
            if (xdg_data_dirs == null || xdg_data_dirs.strip().length == 0) {
                xdg_data_dirs = "/usr/local/share:/usr/share";
            } else {
                
                if (!xdg_data_dirs.contains("/usr/local/share")) {
                    xdg_data_dirs = "/usr/local/share:" + xdg_data_dirs;
                }
                if (!xdg_data_dirs.contains("/usr/share")) {
                    xdg_data_dirs = xdg_data_dirs + ":/usr/share";
                }
            }

            foreach (var base_dir in xdg_data_dirs.split(":")) {
                if (base_dir == null || base_dir.strip().length == 0) continue;
                installed = Path.build_filename(base_dir, "nizam-settings", "ui", name);
                if (FileUtils.test(installed, FileTest.IS_REGULAR)) return installed;
                installed = Path.build_filename(base_dir, "nizam-settings", "ui", "ui", name);
                if (FileUtils.test(installed, FileTest.IS_REGULAR)) return installed;
            }

            
            try {
                var exe = FileUtils.read_link("/proc/self/exe");
                if (exe != null && exe.strip().length > 0) {
                    var exe_dir = Path.get_dirname(exe);
                    for (int up = 1; up <= 6; up++) {
                        string rel = "";
                        for (int i = 0; i < up; i++) {
                            rel = Path.build_filename(rel, "..");
                        }
                        var dev = Path.build_filename(exe_dir, rel, "nizam-settings", "data", "ui", name);
                        if (FileUtils.test(dev, FileTest.IS_REGULAR)) return dev;
                    }
                }
            } catch (Error e) {
                
            }

            
            var dev = Path.build_filename(Environment.get_current_dir(), "nizam-settings", "data", "ui", name);
            if (FileUtils.test(dev, FileTest.IS_REGULAR)) return dev;

            throw new IOError.NOT_FOUND("UI file not found: %s".printf(name));
        }
    }
}
