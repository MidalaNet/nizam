using Gtk;
using GLib;
using Gdk;
using Posix;


[CCode (cname = "gtk_menu_shell_append")]
private extern static void gtk_menu_shell_append_widget (Gtk.MenuShell shell, Gtk.Widget child);
[CCode (cname = "gtk_application_set_accels_for_action")]
private extern static void gtk_application_set_accels_for_action_const (
    Gtk.Application app,
    string detailed_action_name,
    [CCode (array_length = false, array_null_terminated = true, type = "const gchar * const*")] string[] accels
);
[CCode (cname = "gtk_widget_get_parent")]
private extern static unowned Gtk.Widget? gtk_widget_get_parent_widget (Gtk.Widget widget);
[CCode (cname = "gtk_container_add")]
private extern static void gtk_container_add_widget (Gtk.Container container, Gtk.Widget child);
[CCode (cname = "gtk_dialog_get_content_area")]
private extern static unowned Gtk.Widget gtk_dialog_get_content_area_widget (Gtk.Dialog dialog);
[CCode (cname = "nizam_g_subprocess_newv")]
private extern static Subprocess? nizam_g_subprocess_newv (
    [CCode (array_length = false, array_null_terminated = true)] string[] argv,
    SubprocessFlags flags,
    out Error? error
);




public class ExplorerWindow : NizamGtk3.NizamAppWindow {
    private const int TREE_COL_NAME = 0;
    private const int TREE_COL_FILE = 1;
    private const int TREE_COL_ICON = 2;
    private const int TREE_COL_PLACEHOLDER = 3;
    private const int TREE_COL_LOADED = 4;
    private const int TREE_COL_SECTION = 5;

    private const int ICON_COL_DISPLAY = 0;
    private const int ICON_COL_NAME = 1;
    private const int ICON_COL_FILE = 2;
    private const int ICON_COL_ICON = 3;
    private const int ICON_COL_IS_DIR = 4;
    private const int ICON_COL_SIZE = 5;

    private ExplorerModel model;
    private ExplorerHistory history;
    private Cancellable? list_cancellable;
    private uint load_token = 0;

    private Gtk.Entry path_entry;
    private Gtk.Button back_btn;
    private Gtk.Button forward_btn;
    private Gtk.Button up_btn;
    private Gtk.Button home_btn;
    private Gtk.Button reload_btn;

    private Gtk.Button new_file_btn;
    private Gtk.Button new_folder_btn;
    private Gtk.ToggleButton hidden_btn;
    private bool updating_hidden_toggle = false;
    private Gtk.Button prefs_btn;

    private GLib.SimpleAction act_open;
    private GLib.SimpleAction act_delete;
    private GLib.SimpleAction act_reload;
    private GLib.SimpleAction act_select_all;
    private GLib.SimpleAction act_focus_path;
    private GLib.SimpleAction act_toggle_hidden;
    private GLib.SimpleAction act_new_file;
    private GLib.SimpleAction act_new_folder;
    private GLib.SimpleAction act_preferences;
    private GLib.SimpleAction act_back;
    private GLib.SimpleAction act_forward;
    private GLib.SimpleAction act_home;
    private GLib.SimpleAction act_up;
    private GLib.SimpleAction act_bookmark_add;
    private GLib.SimpleAction act_bookmark_remove;
    private Gtk.ToggleButton? bookmark_btn;
    private bool updating_bookmark_toggle = false;
    private ExplorerConfigDb config_db;

    private Gtk.TreeStore tree_store;
    private Gtk.ListStore icon_store;
    private Gtk.IconView icon_view;
    private Gtk.CellRendererPixbuf icon_pix_renderer;
    private Gtk.CellRendererText icon_text_renderer;

    private int icon_view_last_alloc_width = -1;
    private uint icon_view_relayout_source_id = 0;
    private bool force_icon_view_recreate_next_populate = false;
    private uint icon_view_recreate_source_id = 0;

    private Gtk.Label? status_left_label;
    private Gtk.Label? status_right_label;

    private File? current_dir;
    private bool show_hidden = false;

    private bool drag_preserve_selection = false;
    private bool restoring_selection = false;
    private string[] drag_uris = {};
    private HashTable<string, bool> drag_uri_set = new HashTable<string, bool>(str_hash, str_equal);

    private int icon_size = 64;
    private HashTable<string, Gdk.Pixbuf> icon_cache = new HashTable<string, Gdk.Pixbuf>(str_hash, str_equal);
    private List<string> icon_cache_lru = new List<string>();
    private int icon_cache_count = 0;
    private const int ICON_CACHE_LIMIT = 256;

    public ExplorerWindow (Gtk.Application app) {
        base(app, "Nizam Explorer", 980, 640);

        set_about_info(
            "Nizam Explorer",
            APP_VERSION,
            "Minimal file manager for Nizam.",
            "nizam"
        );

        model = new ExplorerModel();
        history = new ExplorerHistory();
        config_db = new ExplorerConfigDb();
        load_preferences();

        status_left_label = get_status_left_label();
        status_right_label = get_status_right_label();
        set_status_left("Ready");
        set_status_right("Nizam Explorer " + APP_VERSION);
        set_toolbar(build_toolbar());

        set_sidebar(build_tree_view());
        icon_view = build_icon_view();
        set_content(icon_view, true);
        apply_icon_view_layout();
        apply_icon_size();

        setup_actions_and_accels();

        init_tree_roots();
        navigate_home();
        show_all();
        GLib.Idle.add(() => {
            if (icon_view != null) icon_view.grab_focus();
            return false;
        });
    }

    private Gtk.Widget build_toolbar () {
        var toolbar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
        toolbar.margin_start = 8;
        toolbar.margin_end = 8;
        toolbar.margin_top = 6;
        toolbar.margin_bottom = 6;

        back_btn = make_toolbar_button("go-previous-symbolic", "Back (Alt+Left)");
        back_btn.clicked.connect(on_back_clicked);

        forward_btn = make_toolbar_button("go-next-symbolic", "Forward (Alt+Right)");
        forward_btn.clicked.connect(on_forward_clicked);

        up_btn = make_toolbar_button("go-up-symbolic", "Up (Alt+Up)");
        up_btn.clicked.connect(navigate_up);

        home_btn = make_toolbar_button("go-home-symbolic", "Home (Alt+Home)");
        home_btn.clicked.connect(navigate_home);

        reload_btn = make_toolbar_button("view-refresh-symbolic", "Reload (F5 / Ctrl+R)");
        reload_btn.clicked.connect(on_reload_clicked);

        new_file_btn = make_toolbar_button("document-new-symbolic", "New File...");
        new_file_btn.clicked.connect(() => { create_new_file(); });

        new_folder_btn = make_toolbar_button("folder-new-symbolic", "New Folder...");
        new_folder_btn.clicked.connect(() => { create_new_folder(); });

        hidden_btn = new Gtk.ToggleButton();
        hidden_btn.can_focus = false;
        hidden_btn.relief = Gtk.ReliefStyle.NONE;
        var hidden_img = new Gtk.Image.from_icon_name("view-reveal-symbolic", Gtk.IconSize.LARGE_TOOLBAR);
        if (hidden_img.get_storage_type() == Gtk.ImageType.EMPTY) {
            hidden_img.set_from_icon_name("folder-visiting-symbolic", Gtk.IconSize.LARGE_TOOLBAR);
        }
        hidden_img.set_pixel_size(20);
        hidden_btn.set_image(hidden_img);
        hidden_btn.always_show_image = true;
        hidden_btn.tooltip_text = "Show hidden files (Ctrl+H)";
        hidden_btn.active = show_hidden;
        hidden_btn.toggled.connect(() => {
            if (updating_hidden_toggle) return;
            show_hidden = hidden_btn.active;
            save_preferences();
            force_icon_view_recreate_next_populate = true;
            on_reload_clicked();
        });

        toolbar.pack_start(back_btn, false, false, 0);
        toolbar.pack_start(forward_btn, false, false, 0);
        toolbar.pack_start(up_btn, false, false, 0);

        var sep = new Gtk.Separator(Gtk.Orientation.VERTICAL);
        sep.get_style_context().add_class("nizam-sep");
        toolbar.pack_start(sep, false, false, 6);

        toolbar.pack_start(home_btn, false, false, 0);
        toolbar.pack_start(reload_btn, false, false, 0);

        var sep2 = new Gtk.Separator(Gtk.Orientation.VERTICAL);
        sep2.get_style_context().add_class("nizam-sep");
        toolbar.pack_start(sep2, false, false, 6);

        toolbar.pack_start(new_file_btn, false, false, 0);
        toolbar.pack_start(new_folder_btn, false, false, 0);
        toolbar.pack_start(hidden_btn, false, false, 0);

        path_entry = new Gtk.Entry();
        path_entry.hexpand = true;
        path_entry.activate.connect(() => { finish_edit_path(); });
        path_entry.key_press_event.connect((event) => {
            if (event.keyval == Gdk.Key.Escape) {
                cancel_edit_path();
                return true;
            }
            return false;
        });

        var path_wrap = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        path_wrap.hexpand = true;
        path_wrap.pack_start(path_entry, true, true, 0);
        toolbar.pack_start(path_wrap, true, true, 12);

        prefs_btn = make_toolbar_button("preferences-system-symbolic", "Preferences...");
        prefs_btn.clicked.connect(() => { show_preferences_dialog(); });
        toolbar.pack_end(prefs_btn, false, false, 0);

        bookmark_btn = new Gtk.ToggleButton();
        bookmark_btn.can_focus = false;
        bookmark_btn.relief = Gtk.ReliefStyle.NONE;
        var bookmark_img = new Gtk.Image.from_icon_name("starred-symbolic", Gtk.IconSize.LARGE_TOOLBAR);
        if (bookmark_img.get_storage_type() == Gtk.ImageType.EMPTY) {
            bookmark_img.set_from_icon_name("emblem-favorite-symbolic", Gtk.IconSize.LARGE_TOOLBAR);
        }
        bookmark_img.set_pixel_size(20);
        bookmark_btn.set_image(bookmark_img);
        bookmark_btn.always_show_image = true;
        bookmark_btn.toggled.connect(() => {
            if (updating_bookmark_toggle) return;
            toggle_current_bookmark();
        });
        toolbar.pack_end(bookmark_btn, false, false, 0);

        update_nav_buttons();
        return toolbar;
    }

    private void setup_actions_and_accels () {
        act_open = new GLib.SimpleAction("open", null);
        act_open.activate.connect(() => { open_selected(); });
        add_action(act_open);

        act_delete = new GLib.SimpleAction("delete", null);
        act_delete.activate.connect(() => { delete_selected(); });
        add_action(act_delete);

        act_reload = new GLib.SimpleAction("reload", null);
        act_reload.activate.connect(() => { on_reload_clicked(); });
        add_action(act_reload);

        act_select_all = new GLib.SimpleAction("select-all", null);
        act_select_all.activate.connect(() => {
            if (icon_view != null) icon_view.select_all();
        });
        add_action(act_select_all);

        act_focus_path = new GLib.SimpleAction("focus-path", null);
        act_focus_path.activate.connect(() => {
            if (path_entry != null) {
                path_entry.grab_focus();
                path_entry.select_region(0, -1);
            }
        });
        add_action(act_focus_path);

        act_toggle_hidden = new GLib.SimpleAction("toggle-hidden", null);
        act_toggle_hidden.activate.connect(() => {
            show_hidden = !show_hidden;
            save_preferences();
            if (hidden_btn != null) {
                updating_hidden_toggle = true;
                hidden_btn.active = show_hidden;
                updating_hidden_toggle = false;
            }
            on_reload_clicked();
        });
        add_action(act_toggle_hidden);

        act_new_file = new GLib.SimpleAction("new-file", null);
        act_new_file.activate.connect(() => { create_new_file(); });
        add_action(act_new_file);

        act_new_folder = new GLib.SimpleAction("new-folder", null);
        act_new_folder.activate.connect(() => { create_new_folder(); });
        add_action(act_new_folder);

        act_preferences = new GLib.SimpleAction("preferences", null);
        act_preferences.activate.connect(() => { show_preferences_dialog(); });
        add_action(act_preferences);

        act_back = new GLib.SimpleAction("back", null);
        act_back.activate.connect(() => { on_back_clicked(); });
        add_action(act_back);

        act_forward = new GLib.SimpleAction("forward", null);
        act_forward.activate.connect(() => { on_forward_clicked(); });
        add_action(act_forward);

        act_home = new GLib.SimpleAction("home", null);
        act_home.activate.connect(() => { navigate_home(); });
        add_action(act_home);

        act_up = new GLib.SimpleAction("up", null);
        act_up.activate.connect(() => { navigate_up(); });
        add_action(act_up);

        act_bookmark_add = new GLib.SimpleAction("bookmark-add", null);
        act_bookmark_add.activate.connect(() => { add_current_bookmark(); });
        add_action(act_bookmark_add);

        act_bookmark_remove = new GLib.SimpleAction("bookmark-remove", null);
        act_bookmark_remove.activate.connect(() => { remove_current_bookmark(); });
        add_action(act_bookmark_remove);

        var ga = this.get_application() as Gtk.Application;
        if (ga != null) {
            gtk_application_set_accels_for_action_const(ga, "win.open", {"<Primary>o"});
            gtk_application_set_accels_for_action_const(ga, "win.delete", {"Delete"});
            gtk_application_set_accels_for_action_const(ga, "win.reload", {"F5", "<Primary>r"});
            gtk_application_set_accels_for_action_const(ga, "win.select-all", {"<Primary>a"});
            gtk_application_set_accels_for_action_const(ga, "win.focus-path", {"<Primary>l"});
            gtk_application_set_accels_for_action_const(ga, "win.toggle-hidden", {"<Primary>h"});
            gtk_application_set_accels_for_action_const(ga, "win.bookmark-add", {"<Primary>d"});
            gtk_application_set_accels_for_action_const(ga, "win.bookmark-remove", {"<Primary><Shift>d"});
            gtk_application_set_accels_for_action_const(ga, "win.back", {"<Alt>Left"});
            gtk_application_set_accels_for_action_const(ga, "win.forward", {"<Alt>Right"});
            gtk_application_set_accels_for_action_const(ga, "win.home", {"<Alt>Home"});
            gtk_application_set_accels_for_action_const(ga, "win.up", {"<Alt>Up"});
        }

        update_menu_actions();
        update_nav_buttons();
        update_bookmark_button();
    }

    private Gtk.Button make_toolbar_button (string icon_name, string tooltip) {
        var btn = new Gtk.Button();
        btn.relief = Gtk.ReliefStyle.NONE;
        btn.tooltip_text = tooltip;
        var img = new Gtk.Image.from_icon_name(icon_name, Gtk.IconSize.LARGE_TOOLBAR);
        img.set_pixel_size(20);
        btn.add(img);
        return btn;
    }

    private Gtk.TreeView build_tree_view () {
        tree_store = new Gtk.TreeStore(6, typeof(string), typeof(File), typeof(Icon), typeof(bool), typeof(bool), typeof(bool));
        var tree_view = new Gtk.TreeView.with_model(tree_store);
        tree_view.headers_visible = false;
        tree_view.enable_tree_lines = false;
        tree_view.set_property("level-indentation", 12);

        var col = new Gtk.TreeViewColumn();
        var pix = new Gtk.CellRendererPixbuf();
        var text = new Gtk.CellRendererText();
        pix.set_property("ypad", 3);
        pix.set_property("xpad", 6);
        text.set_property("ypad", 4);
        text.set_property("xpad", 2);
        col.set_spacing(6);
        col.pack_start(pix, false);
        col.add_attribute(pix, "gicon", TREE_COL_ICON);
        col.pack_start(text, true);
        col.set_cell_data_func(text, (layout, cell, model, iter) => {
            bool section = false;
            string? name = null;
            model.get(iter, TREE_COL_SECTION, out section, TREE_COL_NAME, out name);
            var renderer = cell as Gtk.CellRendererText;
            if (renderer != null) {
                if (section) {
                    renderer.markup = "<small><b>" + GLib.Markup.escape_text(name ?? "") + "</b></small>";
                } else {
                    renderer.markup = GLib.Markup.escape_text(name ?? "");
                }
                renderer.sensitive = !section;
                renderer.set_property("ypad", section ? 6 : 2);
                renderer.set_property("xpad", section ? 2 : 0);
            }
            pix.visible = !section;
        });
        tree_view.append_column(col);

        tree_view.row_expanded.connect((iter, path) => {
            load_tree_children_async.begin(path);
        });

        tree_view.row_activated.connect((path, column) => {
            Gtk.TreeIter iter;
            if (tree_store.get_iter(out iter, path)) {
                File? dir;
                bool section = false;
                tree_store.get(iter, TREE_COL_FILE, out dir, TREE_COL_SECTION, out section);
                if (section) return;
                if (dir != null) {
                    navigate_to(dir, true);
                }
            }
        });

        tree_view.get_selection().changed.connect(() => {
            Gtk.TreeIter iter;
            Gtk.TreeModel m;
            if (tree_view.get_selection().get_selected(out m, out iter)) {
                File? dir;
                bool section = false;
                tree_store.get(iter, TREE_COL_FILE, out dir, TREE_COL_SECTION, out section);
                if (section) {
                    tree_view.get_selection().unselect_all();
                    return;
                }
                if (dir != null) {
                    navigate_to(dir, true);
                }
            }
        });

        Gtk.TargetEntry[] targets = {
            { "text/uri-list", 0, 0 }
        };
        tree_view.enable_model_drag_dest(targets, Gdk.DragAction.MOVE | Gdk.DragAction.COPY);
        tree_view.drag_data_received.connect((context, x, y, selection, info, time) => {
            var ok = handle_tree_drag_drop(tree_view, x, y, selection);
            Gtk.drag_finish(context, ok, ok, time);
        });

        return tree_view;
    }

    private Gtk.IconView build_icon_view () {
        icon_store = new Gtk.ListStore(6, typeof(string), typeof(string), typeof(File), typeof(Gdk.Pixbuf), typeof(bool), typeof(uint64));
        return build_icon_view_for_store(icon_store);
    }

    private Gtk.IconView build_icon_view_for_store (Gtk.ListStore store) {
        var view = new Gtk.IconView.with_model(store);
        view.item_orientation = Gtk.Orientation.VERTICAL;
        
        view.item_width = 0;
        view.margin = 0;
        view.spacing = 12;
        view.column_spacing = 16;
        view.row_spacing = 18;
        view.hexpand = true;
        view.vexpand = true;
        view.add_events(Gdk.EventMask.BUTTON_PRESS_MASK);
        view.set_selection_mode(Gtk.SelectionMode.MULTIPLE);
        view.has_tooltip = true;
        view.query_tooltip.connect((x, y, keyboard_mode, tooltip) => {
            var path = view.get_path_at_pos(x, y);
            if (path == null) return false;
            Gtk.TreeIter iter;
            if (store.get_iter(out iter, path)) {
                File? file;
                string? name = null;
                store.get(iter, ICON_COL_FILE, out file, ICON_COL_NAME, out name);
                if (file != null) {
                    var full = file.get_path() ?? file.get_uri();
                    var display_name = name ?? file.get_basename() ?? full;
                    tooltip.set_text("%s\n%s".printf(display_name, full));
                    return true;
                }
            }
            return false;
        });

        icon_pix_renderer = new Gtk.CellRendererPixbuf();
        icon_text_renderer = new Gtk.CellRendererText();
        icon_text_renderer.xalign = 0.5f;
        icon_text_renderer.yalign = 0.0f;
        icon_text_renderer.single_paragraph_mode = false;
        icon_text_renderer.wrap_mode = Pango.WrapMode.WORD_CHAR;
        icon_text_renderer.wrap_width = 96 - 8;
        icon_text_renderer.ellipsize = Pango.EllipsizeMode.NONE;
        icon_text_renderer.ellipsize_set = true;
        icon_text_renderer.size_points = 9.0;

        view.clear();
        view.pack_start(icon_pix_renderer, false);
        view.add_attribute(icon_pix_renderer, "pixbuf", ICON_COL_ICON);
        view.pack_start(icon_text_renderer, true);
        view.add_attribute(icon_text_renderer, "text", ICON_COL_DISPLAY);

        view.item_activated.connect((path) => {
            Gtk.TreeIter iter;
            if (store.get_iter(out iter, path)) {
                bool is_dir = false;
                File? file;
                store.get(iter, ICON_COL_IS_DIR, out is_dir, ICON_COL_FILE, out file);
                if (file == null) return;
                if (is_dir) {
                    navigate_to(file, true);
                } else {
                    open_file(file);
                }
            }
        });

        view.selection_changed.connect(() => {
            if (drag_preserve_selection && drag_uris.length > 0 && !restoring_selection) {
                restore_drag_selection();
                return;
            }
            update_statusbar();
            update_menu_actions();
        });

        Gtk.TargetEntry[] targets = {
            { "text/uri-list", 0, 0 }
        };
        view.enable_model_drag_source(Gdk.ModifierType.BUTTON1_MASK, targets, Gdk.DragAction.COPY | Gdk.DragAction.MOVE);
        view.enable_model_drag_dest(targets, Gdk.DragAction.MOVE | Gdk.DragAction.COPY);
        view.drag_begin.connect((context) => {
            cache_drag_selection();
            drag_preserve_selection = true;
        });
        view.drag_end.connect((context) => {
            drag_uris = {};
            drag_uri_set.remove_all();
            drag_preserve_selection = false;
        });
        view.drag_data_get.connect((context, selection, info, time) => {
            var uris = drag_uris.length > 0 ? drag_uris : get_selected_uris();
            if (uris.length > 0) {
                selection.set_uris(uris);
            }
        });
        view.drag_data_received.connect((context, x, y, selection, info, time) => {
            var ok = handle_drag_drop(view, x, y, selection);
            Gtk.drag_finish(context, ok, ok, time);
        });

        view.button_press_event.connect((event) => {
            if (event.button == 1 && event.type == Gdk.EventType.BUTTON_PRESS) {
                var path = view.get_path_at_pos((int) event.x, (int) event.y);
                if (path != null && view.path_is_selected(path)) {
                    cache_drag_selection();
                    drag_preserve_selection = true;
                } else {
                    drag_preserve_selection = false;
                }
            }
            if (event.button == 3) {
                var path = view.get_path_at_pos((int) event.x, (int) event.y);
                if (path != null) {
                    if (!view.path_is_selected(path)) {
                        view.unselect_all();
                        view.select_path(path);
                    }
                    show_context_menu(event);
                    return true;
                }
            }
            return false;
        });

        
        view.size_allocate.connect(on_icon_view_size_allocate);
        return view;
    }

    private void apply_icon_view_layout () {
        if (icon_view == null) return;
        
        
        icon_view.item_width = 0;
        icon_view.set_columns(1);
        icon_view.margin = 0;
        icon_view.spacing = 12;
        icon_view.column_spacing = 12;
        icon_view.row_spacing = 20;
        icon_text_renderer.single_paragraph_mode = false;
        apply_icon_size();
    }

    private void schedule_icon_view_recreate () {
        if (icon_view_recreate_source_id != 0) return;
        icon_view_recreate_source_id = GLib.Idle.add(() => {
            icon_view_recreate_source_id = 0;
            recreate_icon_view_widget();
            return false;
        });
    }

    private void recreate_icon_view_widget () {
        if (icon_store == null) return;

        if (icon_view_relayout_source_id != 0) {
            Source.remove(icon_view_relayout_source_id);
            icon_view_relayout_source_id = 0;
        }

        var new_view = build_icon_view_for_store(icon_store);
        set_content(new_view, true);
        icon_view = new_view;
        icon_view_last_alloc_width = -1;

        apply_icon_view_layout();
        apply_icon_size();
        icon_view.show_all();
        icon_view.queue_resize();
        icon_view.queue_draw();
    }

    private void cache_drag_selection () {
        drag_uris = get_selected_uris();
        drag_uri_set.remove_all();
        foreach (var uri in drag_uris) {
            drag_uri_set.insert(uri, true);
        }
    }

    private void restore_drag_selection () {
        restoring_selection = true;
        icon_view.unselect_all();
        Gtk.TreeIter iter;
        if (icon_store.get_iter_first(out iter)) {
            do {
                File? file;
                icon_store.get(iter, ICON_COL_FILE, out file);
                if (file != null) {
                    var uri = file.get_uri();
                    if (drag_uri_set.contains(uri)) {
                        var path = icon_store.get_path(iter);
                        if (path != null) {
                            icon_view.select_path(path);
                        }
                    }
                }
            } while (icon_store.iter_next(ref iter));
        }
        restoring_selection = false;
        update_statusbar();
        update_menu_actions();
    }

    private void add_tree_header (string title) {
        Gtk.TreeIter iter;
        tree_store.append(out iter, null);
        tree_store.set(iter,
            TREE_COL_NAME, title,
            TREE_COL_FILE, (File?) null,
            TREE_COL_ICON, (Icon?) null,
            TREE_COL_PLACEHOLDER, false,
            TREE_COL_LOADED, true,
            TREE_COL_SECTION, true
        );
    }

    private void add_tree_root (string title, File dir, Icon icon) {
        Gtk.TreeIter iter;
        tree_store.append(out iter, null);
        tree_store.set(iter,
            TREE_COL_NAME, title,
            TREE_COL_FILE, dir,
            TREE_COL_ICON, icon,
            TREE_COL_PLACEHOLDER, false,
            TREE_COL_LOADED, false,
            TREE_COL_SECTION, false
        );
        add_placeholder_child(iter);
    }

    private void add_placeholder_child (Gtk.TreeIter parent) {
        Gtk.TreeIter child;
        tree_store.append(out child, parent);
        tree_store.set(child,
            TREE_COL_NAME, "",
            TREE_COL_FILE, (File?) null,
            TREE_COL_ICON, (Icon?) null,
            TREE_COL_PLACEHOLDER, true,
            TREE_COL_LOADED, true,
            TREE_COL_SECTION, false
        );
    }

    private async void load_tree_children_async (Gtk.TreePath path) {
        Gtk.TreeIter parent;
        if (!tree_store.get_iter(out parent, path)) return;

        File? dir;
        bool loaded = false;
        bool section = false;
        tree_store.get(parent, TREE_COL_FILE, out dir, TREE_COL_LOADED, out loaded, TREE_COL_SECTION, out section);
        if (dir == null || section || loaded) return;

        
        Gtk.TreeIter child;
        while (tree_store.iter_children(out child, parent)) {
            tree_store.remove(ref child);
        }

        try {
            var enumerator = yield dir.enumerate_children_async(
                "standard::name,standard::type,standard::icon",
                FileQueryInfoFlags.NONE,
                Priority.DEFAULT,
                null
            );

            while (true) {
                var infos = yield enumerator.next_files_async(64, Priority.DEFAULT, null);
                if (infos == null || infos.length() == 0) break;
                foreach (var info in infos) {
                    if (info.get_file_type() != FileType.DIRECTORY) continue;
                    var name = info.get_name();
                    if (name == null || name.length == 0) continue;
                    var child_file = dir.get_child(name);
                    Gtk.TreeIter it;
                    tree_store.append(out it, parent);
                    tree_store.set(it,
                        TREE_COL_NAME, name,
                        TREE_COL_FILE, child_file,
                        TREE_COL_ICON, info.get_icon() ?? new ThemedIcon("folder-symbolic"),
                        TREE_COL_PLACEHOLDER, false,
                        TREE_COL_LOADED, false,
                        TREE_COL_SECTION, false
                    );
                    add_placeholder_child(it);
                }
            }
        } catch (Error e) {
            
        }

        tree_store.set(parent, TREE_COL_LOADED, true);
    }

    private void init_tree_roots () {
        tree_store.clear();

        add_tree_header("PLACES");
        var home = File.new_for_path(Environment.get_home_dir());
        add_tree_root("Home", home, new ThemedIcon("user-home-symbolic"));
        var root = File.new_for_path("/");
        add_tree_root("/", root, new ThemedIcon("drive-harddisk-symbolic"));
        var trash_path = Path.build_filename(Environment.get_user_data_dir(), "Trash", "files");
        var trash = File.new_for_path(trash_path);
        add_tree_root("Trash", trash, new ThemedIcon("user-trash-symbolic"));

        bool has_bookmarks = add_bookmarks_root();
        if (has_bookmarks) {
            add_tree_header("BOOKMARKS");
            add_bookmarks_items();
        }
    }

    private void write_gtk_bookmarks (BookmarkItem[] items) {
        var path = Path.build_filename(Environment.get_user_config_dir(), "gtk-3.0", "bookmarks");
        var dir = Path.get_dirname(path);
        try {
            File.new_for_path(dir).make_directory_with_parents();
        } catch (Error e) {
            
        }

        var out_text = new StringBuilder();
        foreach (var b in items) {
            if (b.uri == null || !b.uri.has_prefix("file://")) continue;
            out_text.append(b.uri);
            var n = b.name;
            if (n != null) {
                n = n.replace("\n", " ").strip();
            }
            if (n != null && n.length > 0) {
                out_text.append(" ");
                out_text.append(n);
            }
            out_text.append("\n");
        }

        try {
            FileUtils.set_contents(path, out_text.str);
        } catch (Error e) {
            
        }
    }

    private bool add_bookmarks_root () {
        var bookmarks = read_gtk_bookmarks();
        return bookmarks.length > 0;
    }

    private void add_bookmarks_items () {
        var bookmarks = read_gtk_bookmarks();
        foreach (var b in bookmarks) {
            Gtk.TreeIter child;
            tree_store.append(out child, null);
            tree_store.set(child,
                TREE_COL_NAME, b.name,
                TREE_COL_FILE, b.file,
                TREE_COL_ICON, b.icon ?? new ThemedIcon("folder-symbolic"),
                TREE_COL_PLACEHOLDER, false,
                TREE_COL_LOADED, b.is_dir ? false : true,
                TREE_COL_SECTION, false
            );
            if (b.is_dir) add_placeholder_child(child);
        }
    }

    private BookmarkItem[] read_gtk_bookmarks () {
        BookmarkItem[] items = {};
        var path = Path.build_filename(Environment.get_user_config_dir(), "gtk-3.0", "bookmarks");
        string contents;
        try {
            FileUtils.get_contents(path, out contents);
        } catch (Error e) {
            return items;
        }

        foreach (var line in contents.split("\n")) {
            var trimmed = line.strip();
            if (trimmed.length == 0) continue;
            if (!trimmed.has_prefix("file://")) continue;

            string uri = trimmed;
            string? name = null;
            var space = trimmed.index_of_char(' ');
            if (space > 0) {
                uri = trimmed.substring(0, space);
                name = trimmed.substring(space + 1).strip();
            }

            if (name == null || name.length == 0) {
                name = Uri.unescape_string(uri.substring("file://".length));
                if (name != null) {
                    var base_name = Path.get_basename(name);
                    if (base_name != null && base_name.length > 0) name = base_name;
                }
            }

            var file = File.new_for_uri(uri);
            bool is_dir = false;
            Icon? icon = null;
            try {
                var info = file.query_info("standard::type,standard::icon", FileQueryInfoFlags.NONE, null);
                is_dir = info.get_file_type() == FileType.DIRECTORY;
                icon = info.get_icon();
            } catch (Error e) {
                
            }

            items += BookmarkItem(file, name ?? (file.get_basename() ?? uri), is_dir, icon, uri);
        }

        return items;
    }

    private void on_back_clicked () {
        var prev = history.pop_back();
        if (prev == null) return;
        if (current_dir != null) history.push_forward(current_dir);
        navigate_to(prev, false);
    }

    private void on_forward_clicked () {
        var next = history.pop_forward();
        if (next == null) return;
        if (current_dir != null) history.push_back(current_dir);
        navigate_to(next, false);
    }

    private void on_reload_clicked () {
        if (current_dir == null) return;
        force_icon_view_recreate_next_populate = true;
        init_tree_roots();
        navigate_to(current_dir, false);
    }

    private void reload_current_dir_only () {
        if (current_dir == null) return;
        load_directory_async.begin(current_dir, false);
    }

    private void navigate_home () {
        var home = File.new_for_path(Environment.get_home_dir());
        navigate_to(home, true);
    }

    private void navigate_to (File dir, bool push_history) {
        load_directory_async.begin(dir, push_history);
    }

    private async void load_directory_async (File dir, bool push_history) {
        var token = ++load_token;

        if (list_cancellable != null) {
            list_cancellable.cancel();
        }
        list_cancellable = new Cancellable();
        var local_cancellable = list_cancellable;

        set_busy(true);
        set_actions_enabled(false);
        set_status("Loading...");

        FileItem[] items;
        try {
            items = yield model.list_children_async(dir, false, show_hidden, local_cancellable);
        } catch (Error e) {
            if (local_cancellable != null && local_cancellable.is_cancelled()) {
                set_busy(false);
                return;
            }
            if (token != load_token) {
                set_busy(false);
                return;
            }
            var path_text = dir.get_path() ?? dir.get_uri();
            show_error("Unable to open folder", "%s\n%s".printf(path_text, e.message));
            show_status_error("Error: %s".printf(e.message));
            set_busy(false);
            set_actions_enabled(true);
            update_statusbar();
            return;
        }

        if (local_cancellable != null && local_cancellable.is_cancelled()) {
            set_busy(false);
            return;
        }
        if (token != load_token) {
            set_busy(false);
            return;
        }

        set_busy(false);
        set_actions_enabled(true);
        if (push_history && current_dir != null && !dir.equal(current_dir)) {
            history.push_back(current_dir);
            history.clear_forward();
        }

        current_dir = dir;
        update_path_entry();
        populate_icon_view(items);
        update_statusbar();
        update_nav_buttons();
        update_menu_actions();
    }

    private void set_actions_enabled (bool enabled) {
        if (back_btn != null) back_btn.sensitive = enabled && history.can_back();
        if (forward_btn != null) forward_btn.sensitive = enabled && history.can_forward();
        if (home_btn != null) home_btn.sensitive = enabled;
        if (up_btn != null) up_btn.sensitive = enabled && (current_dir != null && current_dir.get_parent() != null);
        if (reload_btn != null) reload_btn.sensitive = enabled;
        update_menu_actions();
    }

    private void show_status_error (string text) {
        set_status(text);
        Timeout.add(4000, () => {
            update_statusbar();
            return false;
        });
    }

    private void populate_icon_view (FileItem[] items) {
        icon_store.clear();
        foreach (var item in items) {
            Gtk.TreeIter iter;
            icon_store.append(out iter);
            var pixbuf = load_icon_pixbuf(item.icon, item.is_dir);
            icon_store.set(iter,
                ICON_COL_DISPLAY, item.name,
                ICON_COL_NAME, item.name,
                ICON_COL_FILE, item.file,
                ICON_COL_ICON, pixbuf,
                ICON_COL_IS_DIR, item.is_dir,
                ICON_COL_SIZE, item.size
            );
        }

        if (force_icon_view_recreate_next_populate) {
            force_icon_view_recreate_next_populate = false;
            schedule_icon_view_recreate();
            return;
        }

        if (icon_view != null) {
            apply_icon_size();
            icon_view.queue_resize();
            icon_view.queue_draw();
        }
    }

    private void open_file (File file) {
        try {
            AppInfo.launch_default_for_uri(file.get_uri(), null);
        } catch (Error e) {
            show_error("Unable to open file", e.message);
        }
    }

    private Gdk.Pixbuf? load_icon_pixbuf (Icon? icon, bool is_dir) {
        if (icon == null) return null;
        var theme = Gtk.IconTheme.get_default();
        if (theme == null) return null;
        var key = "%s:%d:%d".printf(icon.to_string(), icon_size, is_dir ? 1 : 0);
        var cached = icon_cache.lookup(key);
        if (cached != null) {
            icon_cache_lru.remove(key);
            icon_cache_lru.append(key);
            return cached;
        }
        try {
            var flags = (Gtk.IconLookupFlags) 0;
            var info = theme.lookup_by_gicon(icon, icon_size, flags);
            if (info != null) {
                var pix = info.load_icon();
                if (pix == null) return null;
                if (icon_cache_count >= ICON_CACHE_LIMIT) {
                    unowned List<string>? node = icon_cache_lru.first();
                    if (node != null) {
                        var oldest = node.data;
                        icon_cache_lru.delete_link(node);
                        icon_cache.remove(oldest);
                        icon_cache_count--;
                    }
                }
                icon_cache.insert(key, pix);
                icon_cache_lru.append(key);
                icon_cache_count++;
                int w = pix.get_width();
                int h = pix.get_height();
                if (w <= 0 || h <= 0) return pix;
                
                double scale = (double) icon_size / (double) (w > h ? w : h);
                if (scale == 1.0) return pix;
                int nw = (int) (w * scale + 0.5);
                int nh = (int) (h * scale + 0.5);
                if (nw < 1) nw = 1;
                if (nh < 1) nh = 1;
                return pix.scale_simple(nw, nh, Gdk.InterpType.BILINEAR);
            }
        } catch (Error e) {
            
        }
        return null;
    }

    private void load_preferences () {
        icon_size = config_db.get_int("explorer", "icon_size", 48);
        show_hidden = config_db.get_bool("explorer", "show_hidden", false);
    }

    private void apply_icon_size () {
        if (icon_view == null || icon_pix_renderer == null || icon_text_renderer == null) return;
        int width = icon_size + 80;
        if (width < 96) width = 96;

        
        
        int viewport_w = get_icon_view_viewport_width();
        if (viewport_w > 0) {
            int max_w = viewport_w - 24;
            if (max_w < 96) max_w = 96;
            if (width > max_w) width = max_w;
        }

        
        icon_text_renderer.wrap_width = width - 8;

        
        var cur_w = icon_view.get_item_width();
        if (cur_w == width) {
            icon_view.set_item_width(width + 1);
        }
        icon_view.set_item_width(width);

        
        
        if (viewport_w > 0) {
            int col_spacing = icon_view.get_column_spacing();
            if (col_spacing < 0) col_spacing = 0;
            int denom = width + col_spacing;
            int columns = denom > 0 ? (viewport_w + col_spacing) / denom : 1;
            if (columns < 1) columns = 1;
            icon_view.set_columns(columns);
        } else {
            icon_view.set_columns(1);
        }

        icon_view.queue_resize();
        icon_view.queue_draw();

        
        Gtk.Widget? parent = gtk_widget_get_parent_widget(icon_view);
        if (parent != null) parent.queue_resize();
    }

    private int get_icon_view_viewport_width () {
        if (icon_view == null) return -1;
        Gtk.Widget? w = gtk_widget_get_parent_widget(icon_view);
        while (w != null) {
            if (w is Gtk.Viewport) return w.get_allocated_width();
            w = gtk_widget_get_parent_widget(w);
        }
        return icon_view.get_allocated_width();
    }

    private void on_icon_view_size_allocate (Gtk.Allocation allocation) {
        if (icon_view == null) return;
        int w = get_icon_view_viewport_width();
        if (w <= 0) w = allocation.width;
        if (w <= 0) return;
        if (w == icon_view_last_alloc_width) return;
        icon_view_last_alloc_width = w;

        
        if (icon_view_relayout_source_id != 0) {
            Source.remove(icon_view_relayout_source_id);
            icon_view_relayout_source_id = 0;
        }
        icon_view_relayout_source_id = Timeout.add(60, () => {
            icon_view_relayout_source_id = 0;
            int total_items = 0;
            if (icon_store != null) {
                total_items = icon_store.iter_n_children(null);
            }

            
            
            
            if (total_items >= 400) {
                schedule_icon_view_recreate();
            } else {
                apply_icon_size();
            }
            return false;
        });
    }

    private void save_preferences () {
        config_db.set_int("explorer", "icon_size", icon_size);
        config_db.set_bool("explorer", "show_hidden", show_hidden);
    }

    private void show_preferences_dialog () {
        var dialog = new Gtk.Dialog.with_buttons(
            "Preferences",
            this,
            Gtk.DialogFlags.MODAL,
            "_Cancel", Gtk.ResponseType.CANCEL,
            "_OK", Gtk.ResponseType.OK
        );
        dialog.set_default_response(Gtk.ResponseType.OK);

        var grid = new Gtk.Grid();
        grid.margin = 12;
        grid.row_spacing = 8;
        grid.column_spacing = 12;
        gtk_container_add_widget((Gtk.Container) gtk_dialog_get_content_area_widget(dialog), grid);

        var icon_label = new Gtk.Label("File icon size");
        icon_label.halign = Gtk.Align.START;
        var icon_adjust = new Gtk.Adjustment(icon_size, 16, 256, 4, 8, 0);
        var icon_spin = new Gtk.SpinButton(icon_adjust, 1, 0);
        icon_spin.numeric = true;
        icon_spin.hexpand = false;

        var hidden_check = new Gtk.CheckButton.with_label("Show hidden files");
        hidden_check.active = show_hidden;

        grid.attach(icon_label, 0, 0, 1, 1);
        grid.attach(icon_spin, 1, 0, 1, 1);
        grid.attach(hidden_check, 0, 1, 2, 1);

        dialog.show_all();
        var response = dialog.run();
        if (response == Gtk.ResponseType.OK) {
            icon_size = (int) icon_spin.get_value();
            show_hidden = hidden_check.active;
            save_preferences();
            force_icon_view_recreate_next_populate = true;
            if (hidden_btn != null) {
                updating_hidden_toggle = true;
                hidden_btn.active = show_hidden;
                updating_hidden_toggle = false;
            }
            apply_icon_size();
            on_reload_clicked();
        }
        dialog.destroy();
    }

    private void open_with_file (File file) {
        string? content_type = null;
        try {
            var info = file.query_info("standard::content-type", FileQueryInfoFlags.NONE, null);
            content_type = info.get_content_type();
        } catch (Error e) {
            content_type = null;
        }

        Gtk.AppChooserDialog dialog;
        if (content_type != null && content_type.length > 0) {
            dialog = new Gtk.AppChooserDialog.for_content_type(this, Gtk.DialogFlags.MODAL, content_type);
        } else {
            dialog = new Gtk.AppChooserDialog(this, Gtk.DialogFlags.MODAL, file);
        }
        dialog.set_heading("Open With");

        var response = dialog.run();
        if (response == Gtk.ResponseType.OK) {
            var app = dialog.get_app_info();
            if (app != null) {
                try {
                    var uris = new GLib.List<string>();
                    uris.append(file.get_uri());
                    app.launch_uris(uris, null);
                } catch (Error e) {
                    show_error("Unable to open file", e.message);
                }
            }
        }
        dialog.destroy();
    }

    private void open_selected () {
        File? file;
        bool is_dir;
        string? name;
        if (!get_selected_item(out file, out is_dir, out name)) return;
        if (file == null) return;
        if (is_dir) {
            navigate_to(file, true);
        } else {
            open_file(file);
        }
    }

    private void open_with_selected () {
        File? file;
        bool is_dir;
        string? name;
        if (!get_selected_item(out file, out is_dir, out name)) return;
        if (file == null) return;
        if (is_dir) {
            navigate_to(file, true);
            return;
        }
        open_with_file(file);
    }

    private void delete_selected () {
        var selection = get_selected_items();
        if (selection.length == 0) return;

        string title;
        string body;
        if (selection.length == 1) {
            title = "Move to trash?";
            body = "Move \"%s\" to the trash?".printf(selection[0].name);
        } else {
            title = "Move to trash?";
            body = "Move %d items to the trash?".printf(selection.length);
        }

        if (!confirm_action(title, body)) return;

        foreach (var item in selection) {
            if (!trash_or_delete(item.file, item.name)) {
                return;
            }
        }

        set_status("Moved to trash: %d item(s)".printf(selection.length));
        on_reload_clicked();
    }

    private void update_path_entry () {
        if (current_dir == null) return;
        var path = current_dir.get_path();
        if (path == null) path = current_dir.get_uri();
        path_entry.text = path;
        update_bookmark_button();
        path_entry.tooltip_text = path;
    }

    private void finish_edit_path () {
        var text = path_entry.text.strip();
        if (text.length == 0) {
            cancel_edit_path();
            return;
        }
        var dir = File.new_for_path(text);
        navigate_to(dir, true);
    }

    private void cancel_edit_path () {
        update_path_entry();
    }

    private void update_nav_buttons () {
        bool can_back = history.can_back();
        bool can_forward = history.can_forward();
        bool can_up = (current_dir != null && current_dir.get_parent() != null);

        if (back_btn != null) back_btn.sensitive = can_back;
        if (forward_btn != null) forward_btn.sensitive = can_forward;
        if (up_btn != null) up_btn.sensitive = can_up;

        if (act_back != null) act_back.set_enabled(can_back);
        if (act_forward != null) act_forward.set_enabled(can_forward);
        if (act_up != null) act_up.set_enabled(can_up);
    }

    private void update_statusbar () {
        if (current_dir == null) return;

        int total_items = icon_store.iter_n_children(null);
        int selected_items = 0;
        int selected_files = 0;
        int selected_dirs = 0;
        uint64 selected_size = 0;

        var selected = icon_view.get_selected_items();
        for (unowned GLib.List<Gtk.TreePath>? l = selected; l != null; l = l.next) {
            var path = (Gtk.TreePath) l.data;
            Gtk.TreeIter iter;
            if (icon_store.get_iter(out iter, path)) {
                bool is_dir = false;
                uint64 size = 0;
                icon_store.get(iter, ICON_COL_IS_DIR, out is_dir, ICON_COL_SIZE, out size);
                selected_items++;
                if (is_dir) {
                    selected_dirs++;
                } else {
                    selected_files++;
                    selected_size += size;
                }
            }
        }
        
        selected = null;

        string msg;
        if (selected_items > 0) {
            var size_text = selected_files > 0 ? format_size(selected_size) : "—";
            msg = "Items: %d | Selected: %d (Files: %d, Folders: %d, Size: %s)"
                .printf(total_items, selected_items, selected_files, selected_dirs, size_text);
        } else {
            msg = "Items: %d | Selected: 0".printf(total_items);
        }
        set_status(msg);
    }

    private void set_busy (bool busy) {
        var window = get_window();
        if (window == null) return;
        if (busy) {
            var display = Gdk.Display.get_default();
            if (display != null) {
                window.set_cursor(new Gdk.Cursor.for_display(display, Gdk.CursorType.WATCH));
            }
        } else {
            window.set_cursor(null);
        }
    }

    private string format_size (uint64 bytes) {
        double size = (double) bytes;
        string[] units = {"B", "KB", "MB", "GB", "TB"};
        int unit = 0;
        while (size >= 1024.0 && unit < units.length - 1) {
            size /= 1024.0;
            unit++;
        }
        if (unit == 0) return "%d %s".printf((int) size, units[unit]);
        return "%.1f %s".printf(size, units[unit]);
    }

    private void set_status (string text) {
        if (status_left_label != null) {
            status_left_label.label = text;
        }
    }

    private void update_menu_actions () {
        if (icon_view == null) {
            if (act_open != null) act_open.set_enabled(false);
            if (act_delete != null) act_delete.set_enabled(false);
            return;
        }

        var files = get_selected_files();
        bool has_selection = files.length > 0;
        if (act_open != null) act_open.set_enabled(has_selection);
        if (act_delete != null) act_delete.set_enabled(has_selection);
    }


    private bool get_selected_item (out File? file, out bool is_dir, out string? name) {
        file = null;
        is_dir = false;
        name = null;
        var selected = icon_view.get_selected_items();
        if (selected == null) return false;
        var path = (Gtk.TreePath) selected.data;
        Gtk.TreeIter iter;
        if (!icon_store.get_iter(out iter, path)) return false;
        icon_store.get(iter, ICON_COL_FILE, out file, ICON_COL_IS_DIR, out is_dir, ICON_COL_NAME, out name);
        selected = null;
        return file != null;
    }

    private SelectionItem[] get_selected_items () {
        SelectionItem[] items = {};
        var selected = icon_view.get_selected_items();
        for (unowned GLib.List<Gtk.TreePath>? l = selected; l != null; l = l.next) {
            var path = (Gtk.TreePath) l.data;
            Gtk.TreeIter iter;
            if (icon_store.get_iter(out iter, path)) {
                File? file;
                bool is_dir = false;
                string? name;
                icon_store.get(iter, ICON_COL_FILE, out file, ICON_COL_IS_DIR, out is_dir, ICON_COL_NAME, out name);
                if (file != null) {
                    items += SelectionItem(file, name ?? "", is_dir);
                }
            }
        }
        selected = null;
        return items;
    }

    private string[] get_selected_uris () {
        string[] uris = {};
        var selected = icon_view.get_selected_items();
        for (unowned GLib.List<Gtk.TreePath>? l = selected; l != null; l = l.next) {
            var path = (Gtk.TreePath) l.data;
            Gtk.TreeIter iter;
            if (icon_store.get_iter(out iter, path)) {
                File? file;
                icon_store.get(iter, ICON_COL_FILE, out file);
                if (file != null) {
                    uris += file.get_uri();
                }
            }
        }
        selected = null;
        return uris;
    }

    private bool trash_or_delete (File file, string name) {
        try {
            file.trash(null);
            return true;
        } catch (Error e) {
            if (!confirm_action("Trash not available", "Trash failed for \"%s\". Delete permanently?".printf(name))) {
                return false;
            }
            try {
                file.delete(null);
                set_status("Deleted: %s".printf(name));
                return true;
            } catch (Error delete_error) {
                show_error("Unable to delete", delete_error.message);
                return false;
            }
        }
    }

    private File[] get_selected_files () {
        File[] files = {};
        var selected = icon_view.get_selected_items();
        for (unowned GLib.List<Gtk.TreePath>? l = selected; l != null; l = l.next) {
            var path = (Gtk.TreePath) l.data;
            Gtk.TreeIter iter;
            if (icon_store.get_iter(out iter, path)) {
                File? file;
                icon_store.get(iter, ICON_COL_FILE, out file);
                if (file != null) files += file;
            }
        }
        selected = null;
        return files;
    }

    private bool can_encrypt_selection (File[] files) {
        if (files.length == 0) return false;
        foreach (var f in files) {
            var path = f.get_path();
            if (path != null && path.has_suffix(".enc")) return false;
        }
        return true;
    }

    private bool can_decrypt_selection (File[] files) {
        if (files.length == 0) return false;
        foreach (var f in files) {
            var path = f.get_path();
            if (path == null || !path.has_suffix(".enc")) return false;
        }
        return true;
    }

    private bool can_decompress_selection (File[] files) {
        if (files.length == 0) return false;
        foreach (var f in files) {
            var path = f.get_path();
            if (path == null) return false;
            if (!(path.has_suffix(".gz") || path.has_suffix(".tar.gz"))) return false;
        }
        return true;
    }

    private bool can_compress_selection (File[] files) {
        if (files.length == 0) return false;
        foreach (var f in files) {
            var path = f.get_path();
            if (path == null) continue;
            if (path.has_suffix(".gz") || path.has_suffix(".tar.gz")) return false;
        }
        return true;
    }

    private string? prompt_password (string title, bool confirm) {
        var dialog = new Gtk.Dialog.with_buttons(
            title,
            this,
            Gtk.DialogFlags.MODAL,
            "_Cancel", Gtk.ResponseType.CANCEL,
            "_OK", Gtk.ResponseType.OK
        );
        dialog.set_default_response(Gtk.ResponseType.OK);

        var grid = new Gtk.Grid();
        grid.margin = 12;
        grid.row_spacing = 8;
        grid.column_spacing = 12;
        gtk_container_add_widget((Gtk.Container) gtk_dialog_get_content_area_widget(dialog), grid);

        var label = new Gtk.Label("Password");
        label.halign = Gtk.Align.START;
        var entry = new Gtk.Entry();
        entry.visibility = false;
        entry.invisible_char = '•';
        entry.hexpand = true;

        grid.attach(label, 0, 0, 1, 1);
        grid.attach(entry, 1, 0, 1, 1);

        Gtk.Entry? confirm_entry = null;
        if (confirm) {
            var confirm_label = new Gtk.Label("Confirm");
            confirm_label.halign = Gtk.Align.START;
            confirm_entry = new Gtk.Entry();
            confirm_entry.visibility = false;
            confirm_entry.invisible_char = '•';
            confirm_entry.hexpand = true;
            grid.attach(confirm_label, 0, 1, 1, 1);
            grid.attach(confirm_entry, 1, 1, 1, 1);
        }

        dialog.show_all();
        while (true) {
            var response = dialog.run();
            if (response != Gtk.ResponseType.OK) {
                dialog.destroy();
                return null;
            }
            var pwd = entry.text;
            if (pwd.length == 0) {
                show_error("Password required", "Please enter a password.");
                continue;
            }
            if (confirm && confirm_entry != null) {
                if (pwd != confirm_entry.text) {
                    show_error("Password mismatch", "Passwords do not match.");
                    continue;
                }
            }
            dialog.destroy();
            return pwd;
        }
    }

    private string? prompt_output_name (string title, string default_name) {
        var dialog = new Gtk.Dialog.with_buttons(
            title,
            this,
            Gtk.DialogFlags.MODAL,
            "_Cancel", Gtk.ResponseType.CANCEL,
            "_OK", Gtk.ResponseType.OK
        );
        dialog.set_default_response(Gtk.ResponseType.OK);

        var grid = new Gtk.Grid();
        grid.margin = 12;
        grid.row_spacing = 8;
        grid.column_spacing = 12;
        gtk_container_add_widget((Gtk.Container) gtk_dialog_get_content_area_widget(dialog), grid);

        var label = new Gtk.Label("Output name");
        label.halign = Gtk.Align.START;
        var entry = new Gtk.Entry();
        entry.text = default_name;
        entry.hexpand = true;

        grid.attach(label, 0, 0, 1, 1);
        grid.attach(entry, 1, 0, 1, 1);

        dialog.show_all();
        var response = dialog.run();
        if (response != Gtk.ResponseType.OK) {
            dialog.destroy();
            return null;
        }
        var name = entry.text.strip();
        dialog.destroy();
        if (name.length == 0) return null;
        return name;
    }

    private string? prompt_name (string title, string label_text, string default_name = "") {
        var dialog = new Gtk.Dialog.with_buttons(
            title,
            this,
            Gtk.DialogFlags.MODAL,
            "_Cancel", Gtk.ResponseType.CANCEL,
            "_OK", Gtk.ResponseType.OK
        );
        dialog.set_default_response(Gtk.ResponseType.OK);

        var grid = new Gtk.Grid();
        grid.margin = 12;
        grid.row_spacing = 8;
        grid.column_spacing = 12;
        gtk_container_add_widget((Gtk.Container) gtk_dialog_get_content_area_widget(dialog), grid);

        var label = new Gtk.Label(label_text);
        label.halign = Gtk.Align.START;
        var entry = new Gtk.Entry();
        entry.text = default_name;
        entry.hexpand = true;

        grid.attach(label, 0, 0, 1, 1);
        grid.attach(entry, 1, 0, 1, 1);

        dialog.show_all();
        var response = dialog.run();
        if (response != Gtk.ResponseType.OK) {
            dialog.destroy();
            return null;
        }
        var name = entry.text.strip();
        dialog.destroy();
        if (name.length == 0) return null;
        return name;
    }

    private bool run_subprocess (string[] argv, string? stdin_text, out string stderr_text) {
        stderr_text = "";
        try {
            var flags = SubprocessFlags.STDERR_PIPE | SubprocessFlags.STDIN_PIPE;
            Error? err = null;
            var proc = nizam_g_subprocess_newv(argv, flags, out err);
            if (err != null) throw err;
            if (proc == null) throw new IOError.FAILED("Failed to launch process");
            string? out_text = null;
            string? err_text = null;
            proc.communicate_utf8(stdin_text, null, out out_text, out err_text);
            stderr_text = err_text ?? "";
            return proc.get_exit_status() == 0;
        } catch (Error e) {
            stderr_text = e.message;
            return false;
        }
    }

    private bool run_subprocess_capture_bytes (string[] argv, out Bytes? stdout_bytes, out string stderr_text) {
        stdout_bytes = null;
        stderr_text = "";
        try {
            Error? err = null;
            var proc = nizam_g_subprocess_newv(argv, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE, out err);
            if (err != null) throw err;
            if (proc == null) throw new IOError.FAILED("Failed to launch process");
            Bytes? out_bytes = null;
            Bytes? err_bytes = null;
            proc.communicate(null, null, out out_bytes, out err_bytes);
            stdout_bytes = out_bytes;
            if (err_bytes != null) {
                stderr_text = (string) err_bytes.get_data();
            }
            return proc.get_exit_status() == 0;
        } catch (Error e) {
            stderr_text = e.message;
            return false;
        }
    }

    private bool write_bytes_to_file (string path, Bytes data) {
        try {
            var file = File.new_for_path(path);
            var os = file.replace(null, false, FileCreateFlags.NONE, null);
            var buffer = data.get_data();
            os.write_all(buffer, null);
            os.close(null);
            return true;
        } catch (Error e) {
            show_error("Write failed", e.message);
            return false;
        }
    }

    private string? ensure_local_path (File file) {
        var path = file.get_path();
        if (path == null) {
            show_error("Unsupported location", "Only local files are supported.");
            return null;
        }
        return path;
    }

    private void compress_selected () {
        var files = get_selected_files();
        if (files.length == 0) return;

        if (files.length == 1) {
            var items = get_selected_items();
            if (items.length == 1 && items[0].is_dir) {
                var src = ensure_local_path(items[0].file);
                if (src == null) return;
                var base_dir = Path.get_dirname(src);
                var base_name = Path.get_basename(src);
                if (base_name == null || base_name.length == 0) return;
                var out_path = src + ".tar.gz";
                string err;
                if (!run_subprocess({ "tar", "-czf", out_path, "-C", base_dir, base_name }, null, out err)) {
                    show_error("Compress failed", err);
                    return;
                }
                set_status("Compressed: %s".printf(Path.get_basename(out_path)));
                on_reload_clicked();
                return;
            }

            var src = ensure_local_path(files[0]);
            if (src == null) return;
            var out_path = src + ".gz";
            string err;
            Bytes? out_bytes;
            if (!run_subprocess_capture_bytes({ "gzip", "-c", src }, out out_bytes, out err) || out_bytes == null) {
                show_error("Compress failed", err);
                return;
            }
            if (write_bytes_to_file(out_path, out_bytes)) {
                set_status("Compressed: %s".printf(Path.get_basename(out_path)));
                on_reload_clicked();
            }
            return;
        }

        var default_name = "archive.tar.gz";
        var name = prompt_output_name("Compress", default_name);
        if (name == null) return;
        var base_dir = current_dir != null ? current_dir.get_path() : Environment.get_home_dir();
        var out_path = Path.build_filename(base_dir, name);

        string[] argv = { "tar", "-czf", out_path, "-C", base_dir };
        foreach (var f in files) {
            var p = ensure_local_path(f);
            if (p == null) return;
            var parent = f.get_parent();
            if (parent == null || parent.get_path() != base_dir) {
                show_error("Compress failed", "All selected files must be in the current folder.");
                return;
            }
            var base_name = Path.get_basename(p);
            if (base_name == null || base_name.length == 0) continue;
            argv += base_name;
        }
        string err;
        if (!run_subprocess(argv, null, out err)) {
            show_error("Compress failed", err);
            return;
        }
        set_status("Compressed: %s".printf(Path.get_basename(out_path)));
        on_reload_clicked();
    }

    private void decompress_selected () {
        var files = get_selected_files();
        if (files.length == 0) return;
        foreach (var f in files) {
            var src = ensure_local_path(f);
            if (src == null) continue;
            string err;
            if (src.has_suffix(".tar.gz")) {
                var dest_dir = Path.get_dirname(src);
                if (!run_subprocess({ "tar", "-xzf", src, "-C", dest_dir }, null, out err)) {
                    show_error("Decompress failed", err);
                    continue;
                }
                set_status("Decompressed: %s".printf(Path.get_basename(src)));
                continue;
            }
            if (!src.has_suffix(".gz")) {
                show_error("Decompress failed", "Not a .gz file: %s".printf(Path.get_basename(src)));
                continue;
            }
            var out_path = src.substring(0, src.length - 3);
            Bytes? out_bytes;
            if (!run_subprocess_capture_bytes({ "gunzip", "-c", src }, out out_bytes, out err) || out_bytes == null) {
                show_error("Decompress failed", err);
                continue;
            }
            if (write_bytes_to_file(out_path, out_bytes)) {
                set_status("Decompressed: %s".printf(Path.get_basename(out_path)));
            }
        }
        on_reload_clicked();
    }

    private void encrypt_selected () {
        var files = get_selected_files();
        if (files.length == 0) return;

        var password = prompt_password("Encrypt", true);
        if (password == null) return;

        if (files.length == 1) {
            var items = get_selected_items();
            if (items.length != 1) return;
            var src = ensure_local_path(items[0].file);
            if (src == null) return;
            string err;
            if (items[0].is_dir) {
                var base_dir = Path.get_dirname(src);
                var base_name = Path.get_basename(src);
                if (base_name == null || base_name.length == 0) return;
                var out_path = src + ".tar.gz.enc";

                string tmp_path;
                int fd;
                try {
                    fd = FileUtils.open_tmp("nizam-explorer-XXXXXX.tar.gz", out tmp_path);
                    Posix.close(fd);
                } catch (Error e) {
                    show_error("Encrypt failed", e.message);
                    return;
                }

                if (!run_subprocess({ "tar", "-czf", tmp_path, "-C", base_dir, base_name }, null, out err)) {
                    show_error("Encrypt failed", err);
                    FileUtils.remove(tmp_path);
                    return;
                }

                if (!run_subprocess({
                    "openssl", "enc", "-aes-256-cbc", "-salt", "-pbkdf2", "-iter", "100000",
                    "-in", tmp_path, "-out", out_path, "-pass", "stdin"
                }, password + "\n", out err)) {
                    show_error("Encrypt failed", err);
                    FileUtils.remove(tmp_path);
                    return;
                }
                FileUtils.remove(tmp_path);
                set_status("Encrypted: %s".printf(Path.get_basename(out_path)));
                on_reload_clicked();
                return;
            }

            var out_path = src + ".enc";
            if (!run_subprocess({
                "openssl", "enc", "-aes-256-cbc", "-salt", "-pbkdf2", "-iter", "100000",
                "-in", src, "-out", out_path, "-pass", "stdin"
            }, password + "\n", out err)) {
                show_error("Encrypt failed", err);
                return;
            }
            set_status("Encrypted: %s".printf(Path.get_basename(out_path)));
            on_reload_clicked();
            return;
        }

        var base_dir = current_dir != null ? current_dir.get_path() : Environment.get_home_dir();
        var out_name = prompt_output_name("Encrypt", "archive.tar.gz.enc");
        if (out_name == null) return;
        var out_path = Path.build_filename(base_dir, out_name);

        string tmp_path;
        int fd;
        try {
            fd = FileUtils.open_tmp("nizam-explorer-XXXXXX.tar.gz", out tmp_path);
            Posix.close(fd);
        } catch (Error e) {
            show_error("Encrypt failed", e.message);
            return;
        }

        string[] tar_argv = { "tar", "-czf", tmp_path };
        foreach (var f in files) {
            var p = ensure_local_path(f);
            if (p == null) return;
            tar_argv += p;
        }
        string err;
        if (!run_subprocess(tar_argv, null, out err)) {
            show_error("Encrypt failed", err);
            FileUtils.remove(tmp_path);
            return;
        }

        if (!run_subprocess({
            "openssl", "enc", "-aes-256-cbc", "-salt", "-pbkdf2", "-iter", "100000",
            "-in", tmp_path, "-out", out_path, "-pass", "stdin"
        }, password + "\n", out err)) {
            show_error("Encrypt failed", err);
            FileUtils.remove(tmp_path);
            return;
        }
        FileUtils.remove(tmp_path);
        set_status("Encrypted: %s".printf(Path.get_basename(out_path)));
        on_reload_clicked();
    }

    private void decrypt_selected () {
        var files = get_selected_files();
        if (files.length == 0) return;

        var password = prompt_password("Decrypt", false);
        if (password == null) return;

        foreach (var f in files) {
            var src = ensure_local_path(f);
            if (src == null) continue;
            if (!src.has_suffix(".enc")) {
                show_error("Decrypt failed", "Not a .enc file: %s".printf(Path.get_basename(src)));
                continue;
            }
            var out_path = src.substring(0, src.length - 4);
            string err;
            if (!run_subprocess({
                "openssl", "enc", "-d", "-aes-256-cbc", "-salt", "-pbkdf2", "-iter", "100000",
                "-in", src, "-out", out_path, "-pass", "stdin"
            }, password + "\n", out err)) {
                show_error("Decrypt failed", err);
                continue;
            }
            set_status("Decrypted: %s".printf(Path.get_basename(out_path)));
        }
        on_reload_clicked();
    }

    private void create_new_file () {
        if (current_dir == null) return;
        var name = prompt_name("New File", "File name");
        if (name == null) return;
        if (name.contains("/") || name.contains("\\")) {
            show_error("Invalid name", "Name must not contain path separators.");
            return;
        }
        var file = current_dir.get_child(name);
        if (file.query_exists(null)) {
            show_error("File exists", "A file or folder with this name already exists.");
            return;
        }
        try {
            var os = file.create(FileCreateFlags.NONE, null);
            os.close(null);
            set_status("Created: %s".printf(name));
            on_reload_clicked();
        } catch (Error e) {
            show_error("Create failed", e.message);
        }
    }

    private void create_new_folder () {
        if (current_dir == null) return;
        var name = prompt_name("New Folder", "Folder name");
        if (name == null) return;
        if (name.contains("/") || name.contains("\\")) {
            show_error("Invalid name", "Name must not contain path separators.");
            return;
        }
        var dir = current_dir.get_child(name);
        if (dir.query_exists(null)) {
            show_error("Folder exists", "A file or folder with this name already exists.");
            return;
        }
        try {
            dir.make_directory(null);
            set_status("Created: %s".printf(name));
            on_reload_clicked();
        } catch (Error e) {
            show_error("Create failed", e.message);
        }
    }

    private bool confirm_action (string title, string message) {
        var dialog = new Gtk.MessageDialog(this, Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION, Gtk.ButtonsType.OK_CANCEL, "%s", title);
        dialog.format_secondary_text(message);
        var response = dialog.run();
        dialog.destroy();
        return response == Gtk.ResponseType.OK;
    }

    private void navigate_up () {
        if (current_dir == null) return;
        var parent = current_dir.get_parent();
        if (parent != null) {
            navigate_to(parent, true);
        }
    }

    private void show_context_menu (Gdk.EventButton event) {
        var menu = new Gtk.Menu();

        var open_item = new Gtk.MenuItem.with_label("Open");
        open_item.activate.connect(() => { open_selected(); });
        gtk_menu_shell_append_widget(menu, open_item);

        var open_with_item = new Gtk.MenuItem.with_label("Open With...");
        open_with_item.activate.connect(() => { open_with_selected(); });
        gtk_menu_shell_append_widget(menu, open_with_item);

        var delete_item = new Gtk.MenuItem.with_label("Delete");
        delete_item.activate.connect(() => { delete_selected(); });
        gtk_menu_shell_append_widget(menu, delete_item);

        var files = get_selected_files();
        if (files.length > 0) {
            var shred_item = new Gtk.MenuItem.with_label("Shred");
            shred_item.activate.connect(() => { shred_selected(); });
            gtk_menu_shell_append_widget(menu, shred_item);

            if (files.length == 1) {
                var rename_item = new Gtk.MenuItem.with_label("Rename");
                rename_item.activate.connect(() => { rename_selected(); });
                gtk_menu_shell_append_widget(menu, rename_item);
            }
            if (can_encrypt_selection(files)) {
                var encrypt_item = new Gtk.MenuItem.with_label("Encrypt...");
                encrypt_item.activate.connect(() => { encrypt_selected(); });
                gtk_menu_shell_append_widget(menu, encrypt_item);
            }

            if (can_decrypt_selection(files)) {
                var decrypt_item = new Gtk.MenuItem.with_label("Decrypt...");
                decrypt_item.activate.connect(() => { decrypt_selected(); });
                gtk_menu_shell_append_widget(menu, decrypt_item);
            }

            if (can_compress_selection(files)) {
                var compress_item = new Gtk.MenuItem.with_label("Compress...");
                compress_item.activate.connect(() => { compress_selected(); });
                gtk_menu_shell_append_widget(menu, compress_item);
            }

            if (can_decompress_selection(files)) {
                var decompress_item = new Gtk.MenuItem.with_label("Decompress...");
                decompress_item.activate.connect(() => { decompress_selected(); });
                gtk_menu_shell_append_widget(menu, decompress_item);
            }
        }

        menu.show_all();
        menu.popup_at_pointer(event);
    }

    private void rename_selected () {
        var files = get_selected_files();
        if (files.length != 1) return;
        var file = files[0];
        if (file == null) return;
        var old_name = file.get_basename() ?? "";

        var dialog = new Gtk.Dialog.with_buttons(
            "Rename",
            this,
            Gtk.DialogFlags.MODAL,
            "_Cancel", Gtk.ResponseType.CANCEL,
            "_Rename", Gtk.ResponseType.OK
        );
        dialog.set_default_response(Gtk.ResponseType.OK);

        var entry = new Gtk.Entry();
        entry.text = old_name;
        entry.select_region(0, -1);
        var content = (Gtk.Box) gtk_dialog_get_content_area_widget(dialog);
        content.margin = 12;
        content.add(entry);
        dialog.show_all();

        if (dialog.run() == Gtk.ResponseType.OK) {
            var new_name = entry.text.strip();
            if (new_name.length > 0 && new_name != old_name) {
                try {
                    var parent = file.get_parent();
                    if (parent != null) {
                        var dest = parent.get_child(new_name);
                        file.move(dest, FileCopyFlags.NONE, null, null);
                        reload_current_dir_only();
                    }
                } catch (Error e) {
                    show_error("Unable to rename", e.message);
                }
            }
        }
        dialog.destroy();
    }

    private void shred_selected () {
        var selection = get_selected_items();
        if (selection.length == 0) return;

        string title;
        string body;
        if (selection.length == 1) {
            title = "Permanently delete?";
            body = "Permanently delete \"%s\"? This cannot be undone.".printf(selection[0].name);
        } else {
            title = "Permanently delete?";
            body = "Permanently delete %d items? This cannot be undone.".printf(selection.length);
        }

        if (!confirm_action(title, body)) return;

        foreach (var item in selection) {
            if (!shred_file(item.file)) {
                show_error("Unable to shred", item.name);
            } else {
                set_status("Deleted: %s".printf(item.name));
            }
        }
        on_reload_clicked();
    }

    private bool shred_file (File file) {
        try {
            var info = file.query_info("standard::type,standard::size", FileQueryInfoFlags.NONE, null);
            if (info.get_file_type() == FileType.DIRECTORY) {
                return shred_directory(file);
            }
            int64 size = info.get_size();
            if (size > 0) {
                var io = file.replace(null, false, FileCreateFlags.NONE, null);
                var out = new DataOutputStream(io);
                uint8[] buf = new uint8[64 * 1024];
                int64 remaining = size;
                while (remaining > 0) {
                    int chunk = (int) ((remaining < buf.length) ? remaining : buf.length);
                    var slice = buf[0:chunk];
                    out.write(slice, null);
                    remaining -= chunk;
                }
                out.flush();
                io.close(null);
            }
            file.delete(null);
            return true;
        } catch (Error e) {
            return false;
        }
    }

    private bool shred_directory (File dir) {
        try {
            var enumerator = dir.enumerate_children("standard::name,standard::type", FileQueryInfoFlags.NONE, null);
            FileInfo info;
            while ((info = enumerator.next_file(null)) != null) {
                var child = dir.get_child(info.get_name());
                if (info.get_file_type() == FileType.DIRECTORY) {
                    if (!shred_directory(child)) return false;
                } else {
                    if (!shred_file(child)) return false;
                }
            }
            enumerator.close(null);
            dir.delete(null);
            return true;
        } catch (Error e) {
            return false;
        }
    }

    private bool handle_drag_drop (Gtk.IconView view, int x, int y, Gtk.SelectionData selection) {
        if (current_dir == null) return false;
        var uris = extract_uris(selection);
        if (uris.length == 0) return false;

        File dest_dir = current_dir;
        var path = view.get_path_at_pos(x, y);
        if (path != null) {
            Gtk.TreeIter iter;
            if (icon_store.get_iter(out iter, path)) {
                bool is_dir = false;
                File? file;
                icon_store.get(iter, ICON_COL_IS_DIR, out is_dir, ICON_COL_FILE, out file);
                if (is_dir && file != null) {
                    dest_dir = file;
                }
            }
        }

        bool had_error = false;
        string last_error = "";
        foreach (var uri in uris) {
            var src = File.new_for_uri(uri);
            try {
                var name = src.get_basename();
                if (name == null) continue;
                var parent = src.get_parent();
                if (parent != null && parent.equal(dest_dir)) continue;
                var dest = dest_dir.get_child(name);
                src.move(dest, FileCopyFlags.OVERWRITE, null, null);
            } catch (Error e) {
                had_error = true;
                last_error = e.message;
                continue;
            }
        }

        if (had_error) {
            show_error("Unable to move some files", last_error);
        }
        reload_current_dir_only();
        return !had_error;
    }

    private bool handle_tree_drag_drop (Gtk.TreeView view, int x, int y, Gtk.SelectionData selection) {
        var uris = extract_uris(selection);
        if (uris.length == 0) return false;

        Gtk.TreePath? path = null;
        Gtk.TreeViewDropPosition pos;
        if (!view.get_dest_row_at_pos(x, y, out path, out pos)) {
            return false;
        }
        if (path == null) return false;

        Gtk.TreeIter iter;
        if (!tree_store.get_iter(out iter, path)) return false;
        File? dest_dir;
        tree_store.get(iter, TREE_COL_FILE, out dest_dir);
        if (dest_dir == null) return false;

        bool had_error = false;
        string last_error = "";
        foreach (var uri in uris) {
            var src = File.new_for_uri(uri);
            try {
                var name = src.get_basename();
                if (name == null) continue;
                var parent = src.get_parent();
                if (parent != null && parent.equal(dest_dir)) continue;
                var dest = dest_dir.get_child(name);
                src.move(dest, FileCopyFlags.OVERWRITE, null, null);
            } catch (Error e) {
                had_error = true;
                last_error = e.message;
                continue;
            }
        }

        if (had_error) {
            show_error("Unable to move some files", last_error);
        }
        reload_current_dir_only();
        return !had_error;
    }

    private string[] extract_uris (Gtk.SelectionData selection) {
        string[] out_uris = {};
        var uris = selection.get_uris();
        if (uris != null && uris.length > 0) return uris;
        var raw = (string) selection.get_data();
        if (raw == null) return out_uris;
        foreach (var line in raw.split("\n")) {
            var trimmed = line.strip();
            if (trimmed.length == 0) continue;
            if (trimmed.has_prefix("#")) continue;
            out_uris += trimmed;
        }
        return out_uris;
    }

    private void show_error (string title, string detail) {
        var dialog = new Gtk.MessageDialog(this, Gtk.DialogFlags.MODAL, Gtk.MessageType.ERROR, Gtk.ButtonsType.CLOSE, "%s", title);
        dialog.format_secondary_text(detail);
        dialog.run();
        dialog.destroy();
    }

    private void update_bookmark_button () {
        if (current_dir == null) return;
        var active = is_bookmarked(current_dir);
        if (act_bookmark_add != null) act_bookmark_add.set_enabled(!active);
        if (act_bookmark_remove != null) act_bookmark_remove.set_enabled(active);
        if (bookmark_btn != null) {
            updating_bookmark_toggle = true;
            bookmark_btn.active = active;
            bookmark_btn.tooltip_text = active ? "Remove bookmark" : "Add bookmark";
            updating_bookmark_toggle = false;
        }
    }


    private bool is_bookmarked (File dir) {
        var uri = dir.get_uri();
        var items = read_gtk_bookmarks();
        foreach (var b in items) {
            if (b.uri == uri) return true;
        }
        return false;
    }

    private void add_current_bookmark () {
        if (current_dir == null) return;
        if (is_bookmarked(current_dir)) return;
        var uri = current_dir.get_uri();
        var items = read_gtk_bookmarks();
        var name = current_dir.get_basename();
        if (name == null || name.length == 0) {
            name = current_dir.get_path() ?? uri;
        }
        BookmarkItem[] out_items = {};
        foreach (var b in items) out_items += b;
        out_items += BookmarkItem(current_dir, name, true, null, uri);
        write_gtk_bookmarks(out_items);
        init_tree_roots();
        update_bookmark_button();
    }

    private void remove_current_bookmark () {
        if (current_dir == null) return;
        var uri = current_dir.get_uri();
        var items = read_gtk_bookmarks();
        BookmarkItem[] out_items = {};
        foreach (var b in items) {
            if (b.uri == uri) continue;
            out_items += b;
        }
        write_gtk_bookmarks(out_items);
        init_tree_roots();
        update_bookmark_button();
    }

    private void toggle_current_bookmark () {
        if (current_dir == null) return;
        if (is_bookmarked(current_dir)) {
            remove_current_bookmark();
        } else {
            add_current_bookmark();
        }
    }

}

private struct SelectionItem {
    public File file;
    public string name;
    public bool is_dir;

    public SelectionItem (File file, string name, bool is_dir) {
        this.file = file;
        this.name = name;
        this.is_dir = is_dir;
    }
}

private struct BookmarkItem {
    public File file;
    public string name;
    public bool is_dir;
    public Icon? icon;
    public string uri;

    public BookmarkItem (File file, string name, bool is_dir, Icon? icon, string uri) {
        this.file = file;
        this.name = name;
        this.is_dir = is_dir;
        this.icon = icon;
        this.uri = uri;
    }
}
