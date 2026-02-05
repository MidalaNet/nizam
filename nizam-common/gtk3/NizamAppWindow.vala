using GLib;
using Gtk;
using Gdk;

#if HAVE_GFM_DOCS
using WebKit;
#endif


[CCode (cname = "gtk_menu_item_set_submenu")]
private extern static void gtk_menu_item_set_submenu_widget (Gtk.MenuItem item, Gtk.Widget submenu);


[CCode (cname = "gtk_dialog_get_content_area")]
private extern static unowned Gtk.Widget nizam_gtk_dialog_get_content_area_widget (Gtk.Dialog dlg);

#if HAVE_GFM_DOCS

[CCode (cname = "cmark_gfm_core_extensions_ensure_registered")]
private extern static void cmark_gfm_core_extensions_ensure_registered();

[CCode (cname = "cmark_parser_new")]
private extern static void* cmark_parser_new(int options);

[CCode (cname = "cmark_parser_free")]
private extern static void cmark_parser_free(void* parser);

[CCode (cname = "cmark_find_syntax_extension")]
private extern static void* cmark_find_syntax_extension(string name);

[CCode (cname = "cmark_parser_attach_syntax_extension")]
private extern static int cmark_parser_attach_syntax_extension(void* parser, void* extension);

[CCode (cname = "cmark_parser_feed")]
private extern static void cmark_parser_feed(void* parser, string buffer, size_t len);

[CCode (cname = "cmark_parser_finish")]
private extern static void* cmark_parser_finish(void* parser);

[CCode (cname = "cmark_node_free")]
private extern static void cmark_node_free(void* node);

[CCode (cname = "cmark_parser_get_syntax_extensions")]
private extern static void* cmark_parser_get_syntax_extensions(void* parser);

[CCode (cname = "cmark_render_html", free_function = "free")]
private extern static string cmark_render_html(void* root, int options, void* extensions);


private const int CMARK_OPT_DEFAULT = 0;
private const int CMARK_OPT_FOOTNOTES = 1 << 13;
private const int CMARK_OPT_TABLE_PREFER_STYLE_ATTRIBUTES = 1 << 15;

private const int CMARK_OPT_GITHUB_PRE_LANG = 1 << 11;
private const int CMARK_OPT_STRIKETHROUGH_DOUBLE_TILDE = 1 << 14;

#endif

namespace NizamGtk3 {
    public class NizamAppWindow : Gtk.ApplicationWindow {
        private static bool css_loaded = false;

        private Gtk.Box root_vbox;
        private Gtk.MenuBar shell_menubar;
        private Gtk.AccelGroup shell_accel_group;
        private Gtk.MenuItem? window_toggle_max_item = null;
        private Gtk.Box toolbar_wrapper;
        private Gtk.Widget? toolbar_widget;

        private Gtk.Dialog? doc_dialog = null;

        private Gtk.Paned paned;
        private Gtk.ScrolledWindow sidebar_scroller;
        private Gtk.Box sidebar_pad;
        private Gtk.ScrolledWindow content_scroller;
        private Gtk.Box content_pad;

        private Gtk.Box status_wrapper;
        private Gtk.Box status_box;
        private Gtk.Label status_left;
        private Gtk.Label status_right;

        private string about_program_name;
        private string about_version;
        private string about_comments;
        private string about_logo_icon_name;
        private string? about_website;

        public NizamAppWindow (Gtk.Application app, string title,
                              int default_width = 800, int default_height = 500) {
            Object(application: app, title: title,
                   default_width: default_width, default_height: default_height);

            ensure_css_loaded();

            root_vbox = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            root_vbox.hexpand = true;
            root_vbox.vexpand = true;
            root_vbox.get_style_context().add_class("nizam-root");
            add(root_vbox);

            
            shell_accel_group = new Gtk.AccelGroup();
            add_accel_group(shell_accel_group);

            
            about_program_name = title;
            about_version = "";
            about_comments = "";
            about_logo_icon_name = "nizam";
            about_website = null;

            shell_menubar = build_shell_menubar();
            install_shell_menubar(shell_menubar);

            
            toolbar_wrapper = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            toolbar_wrapper.hexpand = true;
            toolbar_wrapper.halign = Gtk.Align.FILL;
            toolbar_wrapper.get_style_context().add_class("nizam-toolbar");
            root_vbox.pack_start(toolbar_wrapper, false, false, 0);

            
            var default_toolbar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            set_toolbar(default_toolbar);

            
            paned = new Gtk.Paned(Gtk.Orientation.HORIZONTAL);
            paned.hexpand = true;
            paned.vexpand = true;
            paned.get_style_context().add_class("nizam-paned");

            sidebar_scroller = new Gtk.ScrolledWindow(null, null);
            sidebar_scroller.set_shadow_type(Gtk.ShadowType.NONE);
            sidebar_scroller.hscrollbar_policy = Gtk.PolicyType.NEVER;
            sidebar_scroller.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
            sidebar_scroller.hexpand = false;
            sidebar_scroller.vexpand = true;

            sidebar_pad = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            sidebar_pad.hexpand = false;
            sidebar_pad.vexpand = true;
            sidebar_pad.get_style_context().add_class("nizam-sidebar");
            sidebar_scroller.add(sidebar_pad);

            content_scroller = new Gtk.ScrolledWindow(null, null);
            content_scroller.set_shadow_type(Gtk.ShadowType.NONE);
            content_scroller.hscrollbar_policy = Gtk.PolicyType.NEVER;
            content_scroller.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
            content_scroller.hexpand = true;
            content_scroller.vexpand = true;

            content_pad = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            content_pad.hexpand = true;
            content_pad.vexpand = true;
            content_pad.get_style_context().add_class("nizam-main");
            content_pad.get_style_context().add_class("nizam-content");
            content_scroller.add(content_pad);

            paned.pack1(sidebar_scroller, false, false);
            paned.pack2(content_scroller, true, false);
            paned.position = 240;

            root_vbox.pack_start(paned, true, true, 0);

            
            status_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            status_box.hexpand = true;
            status_box.halign = Gtk.Align.FILL;

            status_left = new Gtk.Label("Ready");
            status_left.halign = Gtk.Align.START;
            status_left.hexpand = true;
            status_left.ellipsize = Pango.EllipsizeMode.END;
            status_left.get_style_context().add_class("nizam-status-text");

            status_right = new Gtk.Label("");
            status_right.halign = Gtk.Align.END;
            status_right.ellipsize = Pango.EllipsizeMode.END;
            status_right.get_style_context().add_class("nizam-status-text");

            status_box.pack_start(status_left, true, true, 0);
            status_box.pack_end(status_right, false, false, 0);

            
            status_wrapper = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            status_wrapper.hexpand = true;
            status_wrapper.halign = Gtk.Align.FILL;
            status_wrapper.get_style_context().add_class("nizam-statusbar");
            status_wrapper.pack_start(status_box, false, false, 0);
            root_vbox.pack_end(status_wrapper, false, false, 0);
        }

        public void set_about_info (
            string program_name,
            string version,
            string comments,
            string logo_icon_name,
            string? website = null
        ) {
            about_program_name = program_name;
            about_version = version;
            about_comments = comments;
            about_logo_icon_name = logo_icon_name;
            about_website = website;
        }

        public void set_status_left (string text) {
            status_left.set_text(text);
        }

        public void set_status_right (string text) {
            status_right.set_text(text);
        }

        public Gtk.Label get_status_left_label () {
            return status_left;
        }

        public Gtk.Label get_status_right_label () {
            return status_right;
        }

        
        
        public void set_menubar (Gtk.Widget w) {
            
        }

        private Gtk.Window? get_target_window () {
            var a = this.get_application();
            if (a != null) {
                var aw = a.get_active_window();
                if (aw != null) return aw;
            }
            return this;
        }

        private bool target_is_maximized () {
            var win = get_target_window();
            if (win == null) return false;
            var gdk_win = win.get_window();
            if (gdk_win == null) return false;
            return (gdk_win.get_state() & Gdk.WindowState.MAXIMIZED) != 0;
        }

        private void update_window_menu_labels () {
            if (window_toggle_max_item == null) return;
            window_toggle_max_item.set_label(target_is_maximized() ? "Restore" : "Maximize");
        }

        private string? find_gtk_logo_path () {
            
            string p;
            p = Path.build_filename(Environment.get_current_dir(), "nizam-settings", "data", "ui", "gtk-logo.png");
            if (FileUtils.test(p, FileTest.EXISTS)) return p;
            p = Path.build_filename(Environment.get_current_dir(), "data", "ui", "gtk-logo.png");
            if (FileUtils.test(p, FileTest.EXISTS)) return p;

            
            var user_data = Environment.get_user_data_dir();
            if (user_data != null && user_data.length > 0) {
                p = Path.build_filename(user_data, "nizam-settings", "ui", "gtk-logo.png");
                if (FileUtils.test(p, FileTest.EXISTS)) return p;
                p = Path.build_filename(user_data, "nizam-settings", "ui", "ui", "gtk-logo.png");
                if (FileUtils.test(p, FileTest.EXISTS)) return p;
            }

            
            p = Path.build_filename("/usr/local/share", "nizam-settings", "ui", "gtk-logo.png");
            if (FileUtils.test(p, FileTest.EXISTS)) return p;
            p = Path.build_filename("/usr/local/share", "nizam-settings", "ui", "ui", "gtk-logo.png");
            if (FileUtils.test(p, FileTest.EXISTS)) return p;
            p = Path.build_filename("/usr/share", "nizam-settings", "ui", "gtk-logo.png");
            if (FileUtils.test(p, FileTest.EXISTS)) return p;
            p = Path.build_filename("/usr/share", "nizam-settings", "ui", "ui", "gtk-logo.png");
            if (FileUtils.test(p, FileTest.EXISTS)) return p;

            var xdg_data_dirs = Environment.get_variable("XDG_DATA_DIRS");
            if (xdg_data_dirs == null || xdg_data_dirs.strip().length == 0) {
                
                xdg_data_dirs = "/usr/local/share:/usr/share";
            }
            foreach (var base_dir in xdg_data_dirs.split(":")) {
                if (base_dir == null || base_dir.length == 0) continue;
                p = Path.build_filename(base_dir, "nizam-settings", "ui", "gtk-logo.png");
                if (FileUtils.test(p, FileTest.EXISTS)) return p;
                p = Path.build_filename(base_dir, "nizam-settings", "ui", "ui", "gtk-logo.png");
                if (FileUtils.test(p, FileTest.EXISTS)) return p;
            }

            return null;
        }

        private void show_about_gtk () {
            string version = "%u.%u.%u".printf(Gtk.get_major_version(), Gtk.get_minor_version(), Gtk.get_micro_version());

            var dlg = new Gtk.AboutDialog();
            dlg.set_transient_for(this);
            dlg.set_modal(true);
            dlg.program_name = "GTK";
            dlg.version = version;
            dlg.comments = "GIMP Toolkit";
            dlg.website = "https://www.gtk.org";
            dlg.website_label = "gtk.org";

            
            var logo_path = find_gtk_logo_path();
            if (logo_path != null) {
                try {
                    var pix = new Gdk.Pixbuf.from_file_at_scale(logo_path, 96, 96, true);
                    dlg.logo = pix;
                    dlg.set_icon(pix);
                } catch (Error e) {
                    
                }
            }
            dlg.run();
            dlg.destroy();
        }

        private void install_shell_menubar (Gtk.MenuBar menubar) {
            menubar.get_style_context().add_class("nizam-menubar");
            menubar.hexpand = true;
            menubar.halign = Gtk.Align.FILL;
            root_vbox.pack_start(menubar, false, false, 0);
            root_vbox.reorder_child(menubar, 0);
        }

        private Gtk.MenuBar build_shell_menubar () {
            var menubar = new Gtk.MenuBar();

            
            var window_item = new Gtk.MenuItem.with_label("Window");
            var window_menu = new Gtk.Menu();
            window_menu.get_style_context().add_class("nizam-menu");
            gtk_menu_item_set_submenu_widget(window_item, (Gtk.Widget) window_menu);

            var minimize_item = make_menu_item("Minimize", "window-minimize-symbolic");
            minimize_item.activate.connect(on_window_minimize);
            window_menu.add(minimize_item);

            window_toggle_max_item = make_menu_item("Maximize", "window-maximize-symbolic");
            window_toggle_max_item.activate.connect(on_window_toggle_maximize);
            window_menu.add(window_toggle_max_item);

            window_menu.add(new Gtk.SeparatorMenuItem());

            var close_item = make_menu_item("Close", "window-close-symbolic");
            close_item.activate.connect(on_window_close);
            close_item.add_accelerator(
                "activate",
                shell_accel_group,
                (uint) Gdk.Key.w,
                Gdk.ModifierType.CONTROL_MASK,
                Gtk.AccelFlags.VISIBLE
            );
            window_menu.add(close_item);

            var quit_item = make_menu_item("Quit", "application-exit-symbolic");
            quit_item.activate.connect(on_window_quit);
            quit_item.add_accelerator(
                "activate",
                shell_accel_group,
                (uint) Gdk.Key.q,
                Gdk.ModifierType.CONTROL_MASK,
                Gtk.AccelFlags.VISIBLE
            );
            window_menu.add(new Gtk.SeparatorMenuItem());
            window_menu.add(quit_item);

            menubar.add(window_item);

            
            var tools_item = new Gtk.MenuItem.with_label("Tools");
            var tools_menu = new Gtk.Menu();
            tools_menu.get_style_context().add_class("nizam-menu");
            gtk_menu_item_set_submenu_widget(tools_item, (Gtk.Widget) tools_menu);

            var tools_terminal = make_menu_item("Terminal", "utilities-terminal-symbolic");
            tools_terminal.activate.connect(on_tools_terminal);
            tools_menu.add(tools_terminal);

            var tools_explorer = make_menu_item("Explorer", "system-file-manager-symbolic");
            tools_explorer.activate.connect(on_tools_explorer);
            tools_menu.add(tools_explorer);

            var tools_text = make_menu_item("Text", "accessories-text-editor-symbolic");
            tools_text.activate.connect(on_tools_text);
            tools_menu.add(tools_text);

            var tools_settings = make_menu_item("Settings", "preferences-system-symbolic");
            tools_settings.activate.connect(on_tools_settings);
            tools_menu.add(tools_settings);

            menubar.add(tools_item);

            
            var help_item = new Gtk.MenuItem.with_label("Help");
            var help_menu = new Gtk.Menu();
            help_menu.get_style_context().add_class("nizam-menu");
            gtk_menu_item_set_submenu_widget(help_item, (Gtk.Widget) help_menu);

            var intro_item = make_menu_item("Introduction", "help-contents-symbolic");
            intro_item.activate.connect(() => { show_markdown_doc("Introduction", "README.md"); });
            help_menu.add(intro_item);

            var install_item = make_menu_item("Installation", "help-contents-symbolic");
            install_item.activate.connect(() => { show_markdown_doc("Installation", "INSTALL.md"); });
            help_menu.add(install_item);

            var usage_item = make_menu_item("Usage", "help-contents-symbolic");
            usage_item.activate.connect(() => { show_markdown_doc("Usage", "USAGE.md"); });
            help_menu.add(usage_item);

            var contrib_item = make_menu_item("Contributing", "help-contents-symbolic");
            contrib_item.activate.connect(() => { show_markdown_doc("Contributing", "CONTRIBUTING.md"); });
            help_menu.add(contrib_item);

            var authors_item = make_menu_item("Authors", "help-contents-symbolic");
            authors_item.activate.connect(() => { show_markdown_doc("Authors", "AUTHORS.md"); });
            help_menu.add(authors_item);

            var license_item = make_menu_item("License", "help-contents-symbolic");
            license_item.activate.connect(() => { show_markdown_doc("License", "LICENSE.md"); });
            help_menu.add(license_item);

            help_menu.add(new Gtk.SeparatorMenuItem());

            var about_item = make_menu_item("About", "help-about-symbolic");
            about_item.activate.connect(on_help_about);
            about_item.add_accelerator(
                "activate",
                shell_accel_group,
                (uint) Gdk.Key.F1,
                0,
                Gtk.AccelFlags.VISIBLE
            );
            help_menu.add(about_item);

            var about_gtk_item = make_menu_item("About GTK", "help-about-symbolic");
            about_gtk_item.activate.connect(on_help_about_gtk);
            help_menu.add(about_gtk_item);
            menubar.add(help_item);

            
            this.window_state_event.connect((_ev) => {
                update_window_menu_labels();
                return false;
            });
            this.map_event.connect((_ev) => {
                update_window_menu_labels();
                return false;
            });
            Idle.add(() => {
                update_window_menu_labels();
                return false;
            });

            menubar.show_all();
            return menubar;
        }

        private void show_markdown_doc (string title, string filename) {
            string? path = find_doc_path(filename);
            string text;
            if (path != null) {
                try {
                    FileUtils.get_contents(path, out text);
                } catch (Error e) {
                    text = "# Error\n\nFailed to read `" + filename + "`.";
                    path = null;
                }
            } else {
                text = "# Not found\n\nCould not find `" + filename + "` on this system.";
            }
            show_markdown_dialog(title, text, path);
        }

        private string? find_doc_path (string filename) {
            
            var dir = Environment.get_current_dir();
            if (dir != null && dir.strip() != "") {
                for (int i = 0; i < 8; i++) {
                    var cand = Path.build_filename(dir, filename);
                    if (FileUtils.test(cand, FileTest.IS_REGULAR)) return cand;
                    dir = Path.get_dirname(dir);
                }
            }

            
            string[] prefixes = { "/usr/local/share", "/usr/share" };
            foreach (var p in prefixes) {
                var cand = Path.build_filename(p, "doc", "nizam", filename);
                if (FileUtils.test(cand, FileTest.IS_REGULAR)) return cand;
            }

            
            var xdg_data_dirs = Environment.get_variable("XDG_DATA_DIRS");
            if (xdg_data_dirs == null || xdg_data_dirs.strip().length == 0) {
                xdg_data_dirs = "/usr/local/share:/usr/share";
            }
            foreach (var base_dir in xdg_data_dirs.split(":")) {
                if (base_dir == null || base_dir.strip().length == 0) continue;
                var cand = Path.build_filename(base_dir, "doc", "nizam", filename);
                if (FileUtils.test(cand, FileTest.IS_REGULAR)) return cand;
            }

            return null;
        }

        private void show_markdown_dialog (string title, string markdown, string? source_path) {
#if HAVE_GFM_DOCS
            show_markdown_dialog_webview(title, markdown, source_path);
#else
            
            if (doc_dialog != null) {
                doc_dialog.destroy();
                doc_dialog = null;
            }

            var dlg = new Gtk.Dialog();
            dlg.set_transient_for(this);
            dlg.set_modal(true);
            dlg.set_title(title);
            dlg.set_default_size(760, 560);
            dlg.add_button("Close", Gtk.ResponseType.CLOSE);
            dlg.set_default_response(Gtk.ResponseType.CLOSE);

            Gtk.Widget content_area_widget = nizam_gtk_dialog_get_content_area_widget(dlg);
            content_area_widget.margin_top = 12;
            content_area_widget.margin_bottom = 12;
            content_area_widget.margin_start = 12;
            content_area_widget.margin_end = 12;
            var content_area = (Gtk.Box) content_area_widget;
            content_area.spacing = 8;

            if (source_path != null) {
                var path_label = new Gtk.Label(source_path);
                path_label.halign = Gtk.Align.START;
                path_label.xalign = 0.0f;
                path_label.ellipsize = Pango.EllipsizeMode.MIDDLE;
                path_label.get_style_context().add_class("dim-label");
                content_area.pack_start(path_label, false, false, 0);
            }

            var scroller = new Gtk.ScrolledWindow(null, null);
            scroller.set_shadow_type(Gtk.ShadowType.IN);
            scroller.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroller.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC; 
            scroller.hexpand = true;
            scroller.vexpand = true;

            var view = new Gtk.TextView();
            view.editable = false;
            view.cursor_visible = false;
            view.wrap_mode = Gtk.WrapMode.WORD_CHAR;
            view.left_margin = 12;
            view.right_margin = 12;
            view.top_margin = 12;
            view.bottom_margin = 12;

            var buffer = view.get_buffer();
            render_markdown_into_buffer(buffer, markdown);

            scroller.add(view);
            content_area.pack_start(scroller, true, true, 0);

            doc_dialog = dlg;

            dlg.show_all();
            dlg.run();
            dlg.destroy();
            if (doc_dialog == dlg) doc_dialog = null;
#endif
        }

#if HAVE_GFM_DOCS
        private static string html_escape (string s) {
            return Markup.escape_text(s);
        }

        private static string build_doc_html (string title, string body_html) {
            
            var css = "body{font-family:sans-serif;margin:18px;line-height:1.45;}"
                      + "h1,h2,h3,h4{margin:1.0em 0 0.4em 0;}"
                      + "pre,code{font-family:monospace;}"
                      + "pre{padding:12px;border:1px solid #ccc;border-radius:6px;overflow:auto;}"
                      + "code{background:rgba(127,127,127,0.12);padding:0 0.25em;border-radius:4px;}"
                      + "pre code{background:transparent;padding:0;}"
                      + "hr{border:0;border-top:1px solid #ccc;margin:1.2em 0;}"
                      + "img{max-width:100%;height:auto;}"
                      + "table{border-collapse:collapse;}"
                      + "th,td{border:1px solid #ccc;padding:6px 8px;}"
                      + "blockquote{border-left:4px solid #ccc;margin:0.8em 0;padding:0.2em 0.8em;color:#444;}"
                      + "a{color:#1a5fb4;text-decoration:underline;}";

            return "<!doctype html><html><head><meta charset=\"utf-8\">"
                   + "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
                   + "<title>" + html_escape(title) + "</title>"
                   + "<style>" + css + "</style></head><body>"
                   + body_html
                   + "</body></html>";
        }

        private static string markdown_to_html_gfm (string markdown) {
            
            cmark_gfm_core_extensions_ensure_registered();

            int options = CMARK_OPT_DEFAULT
                          | CMARK_OPT_FOOTNOTES
                          | CMARK_OPT_TABLE_PREFER_STYLE_ATTRIBUTES
                          | CMARK_OPT_GITHUB_PRE_LANG
                          | CMARK_OPT_STRIKETHROUGH_DOUBLE_TILDE;

            var parser = cmark_parser_new(options);
            if (parser == null) {
                return "<pre>" + html_escape(markdown) + "</pre>";
            }

            
            string[] ext_names = {
                "table",
                "strikethrough",
                "tasklist",
                "autolink",
                "tagfilter"
            };
            foreach (var name in ext_names) {
                var ext = cmark_find_syntax_extension(name);
                if (ext != null) {
                    cmark_parser_attach_syntax_extension(parser, ext);
                }
            }

            cmark_parser_feed(parser, markdown, (size_t) markdown.length);
            var root = cmark_parser_finish(parser);
            var exts = cmark_parser_get_syntax_extensions(parser);

            string html = "";
            if (root != null) {
                html = cmark_render_html(root, options, exts);
                cmark_node_free(root);
            } else {
                html = "<pre>" + html_escape(markdown) + "</pre>";
            }

            cmark_parser_free(parser);
            return html;
        }

        private void load_markdown_uri_into_webview (Gtk.Dialog dlg, WebKit.WebView web, string uri) {
            
            if (!uri.has_prefix("file://")) {
                web.load_uri(uri);
                return;
            }

            try {
                var f = File.new_for_uri(uri);
                var path = f.get_path();
                if (path == null) return;

                string md;
                FileUtils.get_contents(path, out md);

                string body_html = markdown_to_html_gfm(md);
                string doc_name = Path.get_basename(path);
                dlg.set_title(doc_name);
                string full_html = build_doc_html(doc_name, body_html);

                string? base_uri = null;
                var parent = f.get_parent();
                if (parent != null) {
                    base_uri = parent.get_uri() + "/";
                }
                if (base_uri == null) {
                    base_uri = "file:///usr/share/doc/nizam/";
                }

                web.load_html(full_html, base_uri);
            } catch (Error e) {
                
            }
        }

        private void show_markdown_dialog_webview (string title, string markdown, string? source_path) {
            if (doc_dialog != null) {
                doc_dialog.destroy();
                doc_dialog = null;
            }

            var dlg = new Gtk.Dialog();
            dlg.set_transient_for(this);
            dlg.set_modal(true);
            dlg.set_title(title);
            dlg.set_default_size(860, 640);
            dlg.add_button("Close", Gtk.ResponseType.CLOSE);
            dlg.set_default_response(Gtk.ResponseType.CLOSE);

            Gtk.Widget content_area_widget = nizam_gtk_dialog_get_content_area_widget(dlg);
            content_area_widget.margin_top = 16;
            content_area_widget.margin_bottom = 16;
            content_area_widget.margin_start = 14;
            content_area_widget.margin_end = 14;
            var content_area = (Gtk.Box) content_area_widget;
            content_area.spacing = 10;

            
            var frame = new Gtk.Frame(null);
            frame.shadow_type = Gtk.ShadowType.IN;
            frame.hexpand = true;
            frame.vexpand = true;

            var web = new WebKit.WebView();
            web.hexpand = true;
            web.vexpand = true;

            
            web.context_menu.connect((_menu, _event, _hit) => {
                return true; 
            });

            string? pending_fragment = null;

            
            web.decide_policy.connect((decision, type) => {
                
                var nav = decision as WebKit.NavigationPolicyDecision;
                bool is_user = false;
                string? uri = null;
                if (nav != null) {
                    var action = nav.get_navigation_action();
                    is_user = action.is_user_gesture();
                    uri = action.get_request().get_uri();
                }

                if (!is_user || uri == null) {
                    return false;
                }

                
                if (uri.has_prefix("http://") || uri.has_prefix("https://") || uri.has_prefix("mailto:")) {
                    decision.ignore();
                    try {
                        Gtk.show_uri_on_window(this, uri, Gdk.CURRENT_TIME);
                    } catch (Error e) {
                    }
                    return true;
                }

                
                string uri_base = uri;
                string? frag = null;
                int hash = uri.index_of("#");
                if (hash >= 0) {
                    uri_base = uri.substring(0, hash);
                    frag = uri.substring(hash + 1);
                }
                string uri_base_down = uri_base.down();
                if (uri_base_down.has_suffix(".md") || uri_base_down.has_suffix(".markdown")) {
                    decision.ignore();
                    pending_fragment = frag;
                    load_markdown_uri_into_webview(dlg, web, uri_base);
                    return true;
                }

                
                decision.ignore();
                return true;
            });

            
            web.load_changed.connect((ev) => {
                if (ev == WebKit.LoadEvent.FINISHED && pending_fragment != null && pending_fragment.strip().length > 0) {
                    string frag = pending_fragment;
                    pending_fragment = null;
                    
                    string escaped = frag.replace("\\", "\\\\").replace("'", "\\'");
                    string js = "location.hash = '#" + escaped + "'";
                    web.evaluate_javascript.begin(js, -1, null, null, null);
                }
            });

            string body_html = markdown_to_html_gfm(markdown);
            string full_html = build_doc_html(title, body_html);

            string? base_uri = null;
            if (source_path != null) {
                var f = File.new_for_path(source_path);
                var parent = f.get_parent();
                if (parent != null) {
                    base_uri = parent.get_uri() + "/";
                }
            }
            if (base_uri == null) {
                base_uri = "file:///usr/share/doc/nizam/";
            }

            web.load_html(full_html, base_uri);
            frame.add(web);
            content_area.pack_start(frame, true, true, 0);

            doc_dialog = dlg;
            dlg.show_all();
            dlg.run();
            dlg.destroy();
            if (doc_dialog == dlg) doc_dialog = null;
        }
#endif

#if !HAVE_GFM_DOCS
        private void render_markdown_into_buffer (Gtk.TextBuffer buffer, string markdown) {
            var table = buffer.get_tag_table();

            var tag_h1 = new Gtk.TextTag(null);
            tag_h1.weight = Pango.Weight.BOLD;
            tag_h1.scale = 1.40;
            tag_h1.pixels_above_lines = 10;
            tag_h1.pixels_below_lines = 6;
            table.add(tag_h1);

            var tag_h2 = new Gtk.TextTag(null);
            tag_h2.weight = Pango.Weight.BOLD;
            tag_h2.scale = 1.22;
            tag_h2.pixels_above_lines = 10;
            tag_h2.pixels_below_lines = 4;
            table.add(tag_h2);

            var tag_h3 = new Gtk.TextTag(null);
            tag_h3.weight = Pango.Weight.BOLD;
            tag_h3.scale = 1.10;
            tag_h3.pixels_above_lines = 8;
            tag_h3.pixels_below_lines = 3;
            table.add(tag_h3);

            var tag_para = new Gtk.TextTag(null);
            tag_para.pixels_below_lines = 6;
            table.add(tag_para);

            var tag_bold = new Gtk.TextTag(null);
            tag_bold.weight = Pango.Weight.BOLD;
            table.add(tag_bold);

            var tag_italic = new Gtk.TextTag(null);
            tag_italic.style = Pango.Style.ITALIC;
            table.add(tag_italic);

            var tag_code_inline = new Gtk.TextTag(null);
            tag_code_inline.family = "monospace";
            table.add(tag_code_inline);

            var tag_code_block = new Gtk.TextTag(null);
            tag_code_block.family = "monospace";
            tag_code_block.left_margin = 12;
            tag_code_block.pixels_above_lines = 4;
            tag_code_block.pixels_below_lines = 4;
            table.add(tag_code_block);

            var tag_list = new Gtk.TextTag(null);
            tag_list.left_margin = 18;
            tag_list.pixels_below_lines = 2;
            table.add(tag_list);

            var tag_link = new Gtk.TextTag(null);
            tag_link.underline = Pango.Underline.SINGLE;
            table.add(tag_link);

            Gtk.TextIter iter;
            buffer.get_end_iter(out iter);

            bool in_code = false;
            foreach (var raw_line in markdown.split("\n")) {
                var line = raw_line;

                if (line.strip().has_prefix("```")) {
                    in_code = !in_code;
                    continue;
                }

                if (in_code) {
                    buffer.insert_with_tags(ref iter, line + "\n", -1, tag_code_block);
                    continue;
                }

                if (line.has_prefix("# ")) {
                    buffer.insert_with_tags(ref iter, line.substring(2).strip() + "\n", -1, tag_h1);
                    continue;
                }
                if (line.has_prefix("## ")) {
                    buffer.insert_with_tags(ref iter, line.substring(3).strip() + "\n", -1, tag_h2);
                    continue;
                }
                if (line.has_prefix("### ")) {
                    buffer.insert_with_tags(ref iter, line.substring(4).strip() + "\n", -1, tag_h3);
                    continue;
                }

                var trimmed = line.strip();
                if (trimmed.has_prefix("- ") || trimmed.has_prefix("* ")) {
                    buffer.insert_with_tags(ref iter, "• ", -1, tag_list);
                    insert_markdown_inline(buffer, ref iter, trimmed.substring(2), tag_bold, tag_italic, tag_code_inline, tag_link);
                    buffer.insert(ref iter, "\n", -1);
                    continue;
                }

                
                int dot = trimmed.index_of(". ");
                if (dot > 0) {
                    bool all_digits = true;
                    for (int i = 0; i < dot; i++) {
                        if (!trimmed.get_char(i).isdigit()) { all_digits = false; break; }
                    }
                    if (all_digits) {
                        buffer.insert_with_tags(ref iter, trimmed.substring(0, dot + 2), -1, tag_list);
                        insert_markdown_inline(buffer, ref iter, trimmed.substring(dot + 2), tag_bold, tag_italic, tag_code_inline, tag_link);
                        buffer.insert(ref iter, "\n", -1);
                        continue;
                    }
                }

                if (trimmed.length == 0) {
                    buffer.insert(ref iter, "\n", -1);
                    continue;
                }

                insert_markdown_inline(buffer, ref iter, line, tag_bold, tag_italic, tag_code_inline, tag_link);
                buffer.insert_with_tags(ref iter, "\n", -1, tag_para);
            }
        }

        private void insert_markdown_inline (
            Gtk.TextBuffer buffer,
            ref Gtk.TextIter iter,
            string text,
            Gtk.TextTag tag_bold,
            Gtk.TextTag tag_italic,
            Gtk.TextTag tag_code,
            Gtk.TextTag tag_link
        ) {
            int i = 0;
            while (i < text.length) {
                if (text.index_of("`", i) == i) {
                    int j = text.index_of("`", i + 1);
                    if (j > i + 1) {
                        buffer.insert_with_tags(ref iter, text.substring(i + 1, j - (i + 1)), -1, tag_code);
                        i = j + 1;
                        continue;
                    }
                }

                if (text.index_of("**", i) == i) {
                    int j = text.index_of("**", i + 2);
                    if (j > i + 2) {
                        buffer.insert_with_tags(ref iter, text.substring(i + 2, j - (i + 2)), -1, tag_bold);
                        i = j + 2;
                        continue;
                    }
                }

                if (text.index_of("*", i) == i) {
                    int j = text.index_of("*", i + 1);
                    if (j > i + 1) {
                        buffer.insert_with_tags(ref iter, text.substring(i + 1, j - (i + 1)), -1, tag_italic);
                        i = j + 1;
                        continue;
                    }
                }

                if (text.index_of("[", i) == i) {
                    int close_bracket = text.index_of("](", i + 1);
                    if (close_bracket > i + 1) {
                        int close_paren = text.index_of(")", close_bracket + 2);
                        if (close_paren > close_bracket + 2) {
                            var label = text.substring(i + 1, close_bracket - (i + 1));
                            var url = text.substring(close_bracket + 2, close_paren - (close_bracket + 2));
                            buffer.insert_with_tags(ref iter, label, -1, tag_link);
                            if (url.strip().length > 0) {
                                buffer.insert(ref iter, " (" + url + ")", -1);
                            }
                            i = close_paren + 1;
                            continue;
                        }
                    }
                }

                buffer.insert(ref iter, text.substring(i, 1), -1);
                i += 1;
            }
        }
#endif

        private Gtk.MenuItem make_menu_item (string label, string? icon_name) {
            var item = new Gtk.MenuItem();
            item.get_style_context().add_class("nizam-menuitem");
            var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            box.margin_top = 2;
            box.margin_bottom = 2;
            
            box.margin_start = 0;
            box.margin_end = 6;

            if (icon_name != null && icon_name.strip().length > 0) {
                var img = new Gtk.Image.from_icon_name(icon_name, Gtk.IconSize.MENU);
                box.pack_start(img, false, false, 0);
            }

            var lbl = new Gtk.Label(label);
            lbl.xalign = 0.0f;
            lbl.hexpand = true;
            box.pack_start(lbl, true, true, 0);
            item.add(box);
            return item;
        }

        private void spawn_tool (string cmd) {
            try {
                Process.spawn_command_line_async(cmd);
            } catch (Error e) {
                
            }
        }

        private void on_window_minimize () {
            var win = get_target_window();
            if (win != null) win.iconify();
        }

        private void on_window_toggle_maximize () {
            var win = get_target_window();
            if (win == null) return;
            if (target_is_maximized()) {
                win.unmaximize();
            } else {
                win.maximize();
            }
            update_window_menu_labels();
        }

        private void on_window_close () {
            var win = get_target_window();
            if (win != null) win.close();
        }

        private void on_window_quit () {
            var a = this.get_application();
            if (a != null) {
                a.quit();
            } else {
                this.close();
            }
        }

        private void on_tools_terminal () {
            spawn_tool("nizam-terminal");
        }

        private void on_tools_explorer () {
            spawn_tool("nizam-explorer");
        }

        private void on_tools_text () {
            spawn_tool("nizam-text");
        }

        private void on_tools_settings () {
            spawn_tool("nizam-settings");
        }

        private void on_help_about () {
            NizamGtk3.NizamAbout.show(
                this,
                about_program_name,
                about_version,
                about_comments,
                about_logo_icon_name,
                about_website
            );
        }

        private void on_help_about_gtk () {
            show_about_gtk();
        }

        public void set_toolbar (Gtk.Widget w) {
            if (toolbar_widget != null) {
                toolbar_wrapper.remove(toolbar_widget);
            }
            toolbar_widget = w;
            toolbar_widget.hexpand = true;
            toolbar_widget.halign = Gtk.Align.FILL;
            toolbar_wrapper.pack_start(toolbar_widget, false, false, 0);
        }

        public void set_sidebar (Gtk.Widget? w) {
            foreach (var child in sidebar_pad.get_children()) {
                sidebar_pad.remove(child);
            }
            if (w != null) {
                sidebar_pad.pack_start(w, true, true, 0);
                sidebar_scroller.show();
                paned.set_position(240);
            } else {
                sidebar_scroller.hide();
            }
        }

        public void set_content (Gtk.Widget w, bool scrollable = true) {
            foreach (var child in content_pad.get_children()) {
                content_pad.remove(child);
            }

            
            
            if (scrollable) {
                content_scroller.hscrollbar_policy = Gtk.PolicyType.NEVER;
                content_scroller.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
            } else {
                content_scroller.hscrollbar_policy = Gtk.PolicyType.NEVER;
                content_scroller.vscrollbar_policy = Gtk.PolicyType.NEVER;
            }

            content_pad.pack_start(w, true, true, 0);
            content_scroller.show();
        }

        private static string? find_css_path () {
            var env = Environment.get_variable("NIZAM_GTK3_CSS");
            if (env != null && env.strip() != "" && FileUtils.test(env, FileTest.IS_REGULAR)) {
                return env;
            }

            
            try {
                var exe = FileUtils.read_link("/proc/self/exe");
                var dir = Path.get_dirname(exe);
                for (int i = 0; i < 6; i++) {
                    var cand = Path.build_filename(dir, "nizam-common", "gtk3", "nizam-gtk3.css");
                    if (FileUtils.test(cand, FileTest.IS_REGULAR)) return cand;
                    dir = Path.get_dirname(dir);
                }
            } catch (Error e) {
                
            }

            
            var user_data = Environment.get_user_data_dir();
            if (user_data != null && user_data.strip() != "") {
                var cand = Path.build_filename(user_data, "nizam-common", "gtk3", "nizam-gtk3.css");
                if (FileUtils.test(cand, FileTest.IS_REGULAR)) return cand;
            }

            
            
            var xdg_data_dirs = Environment.get_variable("XDG_DATA_DIRS");
            string[] sys_dirs;
            if (xdg_data_dirs != null && xdg_data_dirs.strip() != "") {
                sys_dirs = xdg_data_dirs.split(":");
            } else {
                sys_dirs = { "/usr/local/share", "/usr/share" };
            }

            foreach (var sys_data in sys_dirs) {
                if (sys_data == null || sys_data.strip() == "") continue;
                var cand = Path.build_filename(sys_data, "nizam-common", "gtk3", "nizam-gtk3.css");
                if (FileUtils.test(cand, FileTest.IS_REGULAR)) return cand;
            }

            return null;
        }

        public static void ensure_css_loaded () {
            if (css_loaded) return;
            css_loaded = true;

            var path = find_css_path();
            if (path == null) return;

            try {
                var provider = new Gtk.CssProvider();
                provider.load_from_path(path);
                var screen = Gdk.Screen.get_default();
                if (screen != null) {
                    Gtk.StyleContext.add_provider_for_screen(screen, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
                }
            } catch (Error e) {
                
            }
        }
    }
}
