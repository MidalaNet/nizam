using GLib;
using Gtk;
using Gdk;

namespace NizamSettings {
    [CCode (cname = "nizam_gtk_dialog_get_content_area_box")]
    private extern unowned Gtk.Box nizam_gtk_dialog_get_content_area_box (Gtk.Dialog dlg);

    public class PekwmPage : Gtk.Box {
        private SettingsStore store;
        private Gtk.Label status;
        private Gtk.Label warning;
        private Gtk.Label tech_version;

        private Gtk.Entry wallpaper_path;
        private Gtk.ComboBoxText wallpaper_mode;
        private Gtk.Label feh_version;

        private Gtk.ListBox autostart_list;
        private Gtk.Label autostart_hint;

        public PekwmPage (SettingsStore store) {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 12);
            this.store = store;

            var content = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
            content.margin_top = 12;
            content.margin_bottom = 12;
            content.margin_start = 12;
            content.margin_end = 12;
            content.set_hexpand(true);
            
            content.set_vexpand(false);
            this.pack_start(content, false, false, 0);

            
            var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
            header.halign = Gtk.Align.START;
            header.valign = Gtk.Align.START;
            content.pack_start(header, false, false, 0);

            var logo = build_logo_image();
            header.pack_start(logo, false, false, 0);

            var header_text = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
            header_text.hexpand = true;
            header.pack_start(header_text, true, true, 0);

            var title = new Gtk.Label("Window Manager");
            title.halign = Gtk.Align.START;
            title.set_xalign(0.0f);
            title.get_style_context().add_class("title-1");
            header_text.pack_start(title, false, false, 0);

            var subtitle = new Gtk.Label("Set up pekwm, a lightweight and configurable window manager for X11.");
            subtitle.halign = Gtk.Align.START;
            subtitle.set_xalign(0.0f);
            subtitle.wrap = true;
            subtitle.get_style_context().add_class("dim-label");
            header_text.pack_start(subtitle, false, false, 0);

            warning = new Gtk.Label("On Apply, Nizam configures ~/.xinitrc to start pekwm with Nizam's theme and settings.");
            warning.halign = Gtk.Align.START;
            warning.set_xalign(0.0f);
            warning.wrap = true;
            warning.margin_top = 8;
            warning.get_style_context().add_class("dim-label");
            content.pack_start(warning, false, false, 0);

            var reload_hint = new Gtk.Label("After setup: start X with startx (or relogin), then you can restart from pekwm itself: right-click desktop → Restart.");
            reload_hint.halign = Gtk.Align.START;
            reload_hint.set_xalign(0.0f);
            reload_hint.wrap = true;
            reload_hint.margin_top = 4;
            reload_hint.get_style_context().add_class("dim-label");
            content.pack_start(reload_hint, false, false, 0);

            
            var about_frame = new Gtk.Frame("About");
            var about_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
            about_box.margin_top = 10;
            about_box.margin_bottom = 10;
            about_box.margin_start = 10;
            about_box.margin_end = 10;

            var about_1 = new Gtk.Label(
                "In an X11 desktop, the <b>window manager</b> is responsible for placing and decorating windows, handling focus, workspaces, and key bindings. It defines how the desktop feels day-to-day."
            );
            about_1.halign = Gtk.Align.START;
            about_1.set_xalign(0.0f);
            about_1.wrap = true;
            about_1.use_markup = true;
            about_box.pack_start(about_1, false, false, 0);

            var about_2 = new Gtk.Label(
                "Nizam uses <b>pekwm</b> because it is lightweight and predictable, works well without a compositor, and is easy to configure. This keeps the system responsive and consistent."
            );
            about_2.halign = Gtk.Align.START;
            about_2.set_xalign(0.0f);
            about_2.wrap = true;
            about_2.use_markup = true;
            about_2.get_style_context().add_class("dim-label");
            about_box.pack_start(about_2, false, false, 0);

            about_frame.add(about_box);
            content.pack_start(about_frame, false, false, 0);

            
            var start_frame = new Gtk.Frame("Start file");
            var start_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 10);
            start_box.margin_top = 10;
            start_box.margin_bottom = 10;
            start_box.margin_start = 10;
            start_box.margin_end = 10;

            var start_hint = new Gtk.Label("This controls wallpaper (via feh) and autostart commands executed by pekwm. If no wallpaper is set, Nizam uses the built-in default wallpaper.");
            start_hint.halign = Gtk.Align.START;
            start_hint.set_xalign(0.0f);
            start_hint.wrap = true;
            start_hint.get_style_context().add_class("dim-label");
            start_box.pack_start(start_hint, false, false, 0);

            

            var wp_grid = new Gtk.Grid();
            wp_grid.column_spacing = 10;
            wp_grid.row_spacing = 8;
            wp_grid.margin_top = 6;

            var wp_path_lbl = new Gtk.Label("Image path");
            wp_path_lbl.halign = Gtk.Align.START;
            wp_path_lbl.set_xalign(0.0f);
            wp_grid.attach(wp_path_lbl, 0, 0, 1, 1);

            wallpaper_path = new Gtk.Entry();
            wallpaper_path.hexpand = true;
            wallpaper_path.placeholder_text = "Leave empty to use the Nizam fallback wallpaper";
            wp_grid.attach(wallpaper_path, 1, 0, 1, 1);

            var browse_btn = new Gtk.Button.with_label("Browse");
            browse_btn.clicked.connect(() => {
                var dlg = new Gtk.FileChooserDialog("Select wallpaper", (Gtk.Window) get_toplevel(), Gtk.FileChooserAction.OPEN,
                    "Cancel", Gtk.ResponseType.CANCEL,
                    "Open", Gtk.ResponseType.ACCEPT);
                dlg.set_modal(true);
                var res = dlg.run();
                if (res == Gtk.ResponseType.ACCEPT) {
                    var fname = dlg.get_filename();
                    if (fname != null) wallpaper_path.set_text(fname);
                }
                dlg.destroy();
            });
            wp_grid.attach(browse_btn, 2, 0, 1, 1);

            var wp_mode_lbl = new Gtk.Label("Mode");
            wp_mode_lbl.halign = Gtk.Align.START;
            wp_mode_lbl.set_xalign(0.0f);
            wp_grid.attach(wp_mode_lbl, 0, 1, 1, 1);

            wallpaper_mode = new Gtk.ComboBoxText();
            wallpaper_mode.append_text("Scale (--bg-scale)");
            wallpaper_mode.append_text("Fill (--bg-fill)");
            wallpaper_mode.append_text("Center (--bg-center)");
            wallpaper_mode.append_text("Max (--bg-max)");
            wp_grid.attach(wallpaper_mode, 1, 1, 2, 1);

            feh_version = new Gtk.Label("");
            feh_version.halign = Gtk.Align.START;
            feh_version.set_xalign(0.0f);
            feh_version.get_style_context().add_class("nizam-status-text");
            wp_grid.attach(feh_version, 0, 2, 3, 1);

            start_box.pack_start(wp_grid, false, false, 0);

            
            var auto_header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            var auto_lbl = new Gtk.Label("Autostart");
            auto_lbl.halign = Gtk.Align.START;
            auto_lbl.set_xalign(0.0f);
            auto_lbl.get_style_context().add_class("nizam-app-title");
            auto_header.pack_start(auto_lbl, false, false, 0);

            autostart_hint = new Gtk.Label("Commands are stored in the database. Changes are applied when you press Apply.");
            autostart_hint.halign = Gtk.Align.START;
            autostart_hint.set_xalign(0.0f);
            autostart_hint.get_style_context().add_class("dim-label");
            autostart_hint.wrap = true;
            start_box.pack_start(auto_header, false, false, 0);
            start_box.pack_start(autostart_hint, false, false, 0);

            autostart_list = new Gtk.ListBox();
            autostart_list.selection_mode = Gtk.SelectionMode.NONE;
            autostart_list.set_header_func((row, before) => {
                row.set_margin_top(0);
                row.set_margin_bottom(0);
            });

            var auto_frame = new Gtk.Frame(null);
            auto_frame.set_shadow_type(Gtk.ShadowType.IN);
            auto_frame.add(autostart_list);
            start_box.pack_start(auto_frame, false, false, 0);

            var auto_actions = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            auto_actions.halign = Gtk.Align.END;
            var add_btn = new Gtk.Button.with_label("Add");
            add_btn.always_show_image = true;
            add_btn.image = new Gtk.Image.from_icon_name("list-add-symbolic", Gtk.IconSize.BUTTON);
            add_btn.clicked.connect(() => { on_autostart_add(); });
            auto_actions.pack_end(add_btn, false, false, 0);
            start_box.pack_start(auto_actions, false, false, 0);

            start_frame.add(start_box);
            content.pack_start(start_frame, false, false, 0);

            
            var footer = new Gtk.Box(Gtk.Orientation.VERTICAL, 10);
            footer.margin_top = 0;
            content.pack_start(footer, false, false, 0);

            status = new Gtk.Label("");
            status.halign = Gtk.Align.START;
            status.set_xalign(0.0f);
            status.wrap = true;
            status.get_style_context().add_class("nizam-status-text");
            
            status.no_show_all = true;
            status.hide();
            footer.pack_start(status, false, false, 0);

            var tech_frame = new Gtk.Frame("Technical");
            var tech_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
            tech_box.margin_top = 10;
            tech_box.margin_bottom = 10;
            tech_box.margin_start = 10;
            tech_box.margin_end = 10;

            tech_version = new Gtk.Label("");
            tech_version.halign = Gtk.Align.START;
            tech_version.set_xalign(0.0f);
            tech_version.get_style_context().add_class("nizam-status-text");
            tech_box.pack_start(tech_version, false, false, 0);

            tech_frame.add(tech_box);
            footer.pack_start(tech_frame, false, false, 0);

            var action_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            action_row.halign = Gtk.Align.END;

            var apply_btn = new Gtk.Button.with_label("Apply");
            apply_btn.always_show_image = true;
            apply_btn.image = new Gtk.Image.from_icon_name(pick_apply_icon_name(), Gtk.IconSize.BUTTON);
            apply_btn.get_style_context().add_class("suggested-action");
            apply_btn.clicked.connect(() => {
                apply_btn.sensitive = false;
                string msg;
                
                try {
                    var start_store = new PekwmStartStore(store.get_db());
                    var cfg = new PekwmStartConfig();
                    cfg.wallpaper_path = wallpaper_path.get_text();
                    cfg.wallpaper_mode = mode_to_flag(wallpaper_mode.get_active_text());
                    cfg.feh_version = PekwmStartStore.detect_feh_version();
                    start_store.save(cfg);
                } catch (Error e) {
                    set_status_text("Failed to save start settings: %s".printf(e.message));
                }

                var st = PekwmBackend.apply_from_common(out msg, store.get_db());
                if (st == PekwmApplyStatus.OK) {
                    set_status_text(msg);
                } else {
                    set_status_text("Failed: %s".printf(msg));
                }
                refresh_technical_info();
                apply_btn.sensitive = true;
            });
            action_row.pack_end(apply_btn, false, false, 0);
            footer.pack_start(action_row, false, false, 0);

            refresh_technical_info();
            load_start_settings();
            reload_autostart_list();
        }

        private static string mode_to_flag (string? mode_label) {
            var m = (mode_label ?? "").strip();
            if (m.contains("--bg-fill")) return "--bg-fill";
            if (m.contains("--bg-center")) return "--bg-center";
            if (m.contains("--bg-max")) return "--bg-max";
            return "--bg-scale";
        }

        private static int flag_to_mode_index (string flag) {
            var f = (flag ?? "").strip();
            if (f == "--bg-fill") return 1;
            if (f == "--bg-center") return 2;
            if (f == "--bg-max") return 3;
            return 0;
        }

        private void load_start_settings () {
            try {
                var start_store = new PekwmStartStore(store.get_db());
                var cfg = start_store.load();
                wallpaper_path.set_text(cfg.wallpaper_path);
                wallpaper_mode.set_active(flag_to_mode_index(cfg.wallpaper_mode));

                var fv = PekwmStartStore.detect_feh_version();
                feh_version.set_text("feh: %s".printf(fv));
            } catch (Error e) {
                feh_version.set_text("feh: unknown");
            }
        }

        private void reload_autostart_list () {
            foreach (var child in autostart_list.get_children()) {
                autostart_list.remove(child);
            }

            try {
                var s = new PekwmAutostartStore(store.get_db());
                var items = s.list_items();
                for (uint i = 0; i < items.length; i++) {
                    var item = (PekwmAutostartItem) items.get(i);
                    autostart_list.add(build_autostart_row(item));
                }
            } catch (Error e) {
                
            }

            autostart_list.show_all();
        }

        private Gtk.ListBoxRow build_autostart_row (PekwmAutostartItem item) {
            var row = new Gtk.ListBoxRow();
            row.selectable = false;

            var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            box.margin_top = 6;
            box.margin_bottom = 6;
            box.margin_start = 8;
            box.margin_end = 8;

            var enabled = new Gtk.CheckButton();
            enabled.active = item.enabled;
            enabled.toggled.connect(() => {
                try {
                    var s = new PekwmAutostartStore(store.get_db());
                    s.set_enabled(item.id, enabled.active);
                } catch (Error e) {
                    set_status_text("Failed to update autostart: %s".printf(e.message));
                }
            });
            box.pack_start(enabled, false, false, 0);

            var label = new Gtk.Label(item.command);
            label.halign = Gtk.Align.START;
            label.set_xalign(0.0f);
            label.hexpand = true;
            label.ellipsize = Pango.EllipsizeMode.END;
            box.pack_start(label, true, true, 0);

            var edit_btn = new Gtk.Button.from_icon_name("document-edit-symbolic", Gtk.IconSize.BUTTON);
            edit_btn.relief = Gtk.ReliefStyle.NONE;
            edit_btn.clicked.connect(() => { on_autostart_edit(item); });
            box.pack_end(edit_btn, false, false, 0);

            var del_btn = new Gtk.Button.from_icon_name("user-trash-symbolic", Gtk.IconSize.BUTTON);
            del_btn.relief = Gtk.ReliefStyle.NONE;
            del_btn.get_style_context().add_class("destructive-action");
            del_btn.clicked.connect(() => { on_autostart_delete(item); });
            box.pack_end(del_btn, false, false, 0);

            row.add(box);
            return row;
        }

        private void on_autostart_add () {
            var dlg = new Gtk.Dialog.with_buttons("Add autostart", (Gtk.Window) get_toplevel(), Gtk.DialogFlags.MODAL,
                "Cancel", Gtk.ResponseType.CANCEL,
                "Add", Gtk.ResponseType.OK);

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
            box.margin_top = 10;
            box.margin_bottom = 10;
            box.margin_start = 10;
            box.margin_end = 10;

            var entry = new Gtk.Entry();
            entry.placeholder_text = "Command (shell)";
            entry.hexpand = true;

            var enabled = new Gtk.CheckButton.with_label("Enabled");
            enabled.active = true;

            box.pack_start(entry, false, false, 0);
            box.pack_start(enabled, false, false, 0);
            nizam_gtk_dialog_get_content_area_box(dlg).add(box);
            dlg.show_all();

            var resp = dlg.run();
            if (resp == Gtk.ResponseType.OK) {
                try {
                    var s = new PekwmAutostartStore(store.get_db());
                    s.add_item(entry.get_text(), enabled.active);
                    reload_autostart_list();
                } catch (Error e) {
                    set_status_text("Failed to add autostart: %s".printf(e.message));
                }
            }
            dlg.destroy();
        }

        private void on_autostart_edit (PekwmAutostartItem item) {
            var dlg = new Gtk.Dialog.with_buttons("Edit autostart", (Gtk.Window) get_toplevel(), Gtk.DialogFlags.MODAL,
                "Cancel", Gtk.ResponseType.CANCEL,
                "Save", Gtk.ResponseType.OK);

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
            box.margin_top = 10;
            box.margin_bottom = 10;
            box.margin_start = 10;
            box.margin_end = 10;

            var entry = new Gtk.Entry();
            entry.hexpand = true;
            entry.set_text(item.command);

            var enabled = new Gtk.CheckButton.with_label("Enabled");
            enabled.active = item.enabled;

            box.pack_start(entry, false, false, 0);
            box.pack_start(enabled, false, false, 0);
            nizam_gtk_dialog_get_content_area_box(dlg).add(box);
            dlg.show_all();

            var resp = dlg.run();
            if (resp == Gtk.ResponseType.OK) {
                try {
                    var s = new PekwmAutostartStore(store.get_db());
                    s.update_item(item.id, entry.get_text(), enabled.active);
                    reload_autostart_list();
                } catch (Error e) {
                    set_status_text("Failed to update autostart: %s".printf(e.message));
                }
            }
            dlg.destroy();
        }

        private void on_autostart_delete (PekwmAutostartItem item) {
            var confirm = new Gtk.MessageDialog((Gtk.Window) get_toplevel(), Gtk.DialogFlags.MODAL,
                Gtk.MessageType.WARNING, Gtk.ButtonsType.OK_CANCEL,
                "Delete autostart entry?");
            confirm.format_secondary_text(item.command);
            var resp = confirm.run();
            confirm.destroy();
            if (resp != Gtk.ResponseType.OK) return;

            try {
                var s = new PekwmAutostartStore(store.get_db());
                s.delete_item(item.id);
                reload_autostart_list();
            } catch (Error e) {
                set_status_text("Failed to delete autostart: %s".printf(e.message));
            }
        }

        private void set_status_text (string text) {
            var t = (text ?? "").strip();
            status.set_text(t);
            if (t.length == 0) {
                status.no_show_all = true;
                status.hide();
            } else {
                status.no_show_all = false;
                status.show();
            }
        }

        private static string pick_apply_icon_name () {
            var theme = Gtk.IconTheme.get_default();
            if (theme != null && theme.has_icon("object-select-symbolic")) return "object-select-symbolic";
            if (theme != null && theme.has_icon("gtk-apply")) return "gtk-apply";
            return "document-save-symbolic";
        }

        private void refresh_technical_info () {
            tech_version.set_text("%s".printf(get_pekwm_version_string()));
        }

        private Gtk.Image build_logo_image () {
            
            try {
                var path = Assets.find_ui_file("pekwm-logo.png");
                var pix = new Pixbuf.from_file_at_scale(path, 64, 64, true);
                return new Gtk.Image.from_pixbuf(pix);
            } catch (Error e) {
                
                var img = new Gtk.Image.from_icon_name("preferences-system-windows", Gtk.IconSize.DIALOG);
                img.set_pixel_size(64);
                return img;
            }
        }

        private static string get_pekwm_version_string () {
            string? out_text = null;
            string? err_text = null;
            int status = 0;

            try {
                Process.spawn_sync(null, new string[] { "pekwm", "--version" }, null, SpawnFlags.SEARCH_PATH, null, out out_text, out err_text, out status);
                if (status == 0) {
                    var s = (out_text ?? "").strip();
                    if (s.length > 0) return s.split("\n")[0].strip();
                }
            } catch (Error e) {
                
            }

            var in_path = Environment.find_program_in_path("pekwm");
            if (in_path == null || in_path.strip().length == 0) return "not installed";
            return "installed (version unknown)";
        }

    }
}
