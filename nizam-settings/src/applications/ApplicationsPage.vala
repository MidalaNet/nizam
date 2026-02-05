using GLib;
using Gtk;
using Gdk;

namespace NizamSettings {
    public class ApplicationsPage : Gtk.Box {
        
        
        [CCode (cname = "gtk_info_bar_get_content_area")]
        private static extern unowned Gtk.Widget info_bar_get_content_area_widget (Gtk.InfoBar bar);

        [CCode (cname = "gtk_dialog_get_content_area")]
        private static extern unowned Gtk.Widget dialog_get_content_area_widget (Gtk.Dialog dlg);

        private SettingsStore store;
        private Gtk.Entry search;
        private Gtk.Button btn_sync;
        private Gtk.ListBox list_box;
        private Gtk.InfoBar infobar;
        private Gtk.Label infobar_label;
        private List<DesktopEntry>? entries = null;
        private Gtk.Label status;

        private const int RESP_DELETE = 1001;

        public ApplicationsPage (SettingsStore store) {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 12);
            this.store = store;

            var content = new Gtk.Box(Gtk.Orientation.VERTICAL, 10);
            content.margin_top = 12;
            content.margin_bottom = 12;
            content.margin_start = 12;
            content.margin_end = 12;
            content.set_hexpand(true);
            
            content.set_vexpand(false);
            content.get_style_context().add_class("nizam-content");
            this.pack_start(content, false, false, 0);

            
            infobar = new Gtk.InfoBar();
            infobar.no_show_all = true;
            infobar.set_show_close_button(true);
            infobar_label = new Gtk.Label("");
            infobar_label.halign = Gtk.Align.START;
            infobar_label.wrap = true;
            
            
            Gtk.Widget infobar_area_widget = info_bar_get_content_area_widget(infobar);
            ((Gtk.Container) infobar_area_widget).add(infobar_label);
            infobar.response.connect((_resp) => { infobar.hide(); });
            content.pack_start(infobar, false, false, 0);

            var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            header.margin_bottom = 12;
            content.pack_start(header, false, false, 0);

            search = new Gtk.Entry();
            search.placeholder_text = "Search";
            search.set_hexpand(true);
            header.pack_start(search, true, true, 0);

            btn_sync = new Gtk.Button.with_label("Sync");
            btn_sync.tooltip_text = "One-way sync from /usr/share/applications into the sqlite database";
            btn_sync.halign = Gtk.Align.END;
            btn_sync.always_show_image = true;
            btn_sync.image = new Gtk.Image.from_icon_name("view-refresh-symbolic", Gtk.IconSize.BUTTON);
            btn_sync.get_style_context().add_class("suggested-action");
            header.pack_start(btn_sync, false, false, 0);

            list_box = new Gtk.ListBox();
            list_box.selection_mode = Gtk.SelectionMode.SINGLE;
            list_box.activate_on_single_click = false;
            list_box.get_style_context().add_class("nizam-list");
            list_box.set_hexpand(true);
            list_box.set_vexpand(false);
            
            content.pack_start(list_box, true, true, 0);

            status = new Gtk.Label("");
            status.halign = Gtk.Align.START;
            status.wrap = true;
            status.get_style_context().add_class("nizam-status-text");
            content.pack_start(status, false, false, 0);

            wire_signals();
            reload_list_from_db();
        }

        private void wire_signals () {
            search.changed.connect(() => { rebuild_list(); });
            btn_sync.clicked.connect(() => { sync_from_system(); });

            list_box.row_activated.connect((row) => {
                if (row == null) return;
                var entry = row.get_data<DesktopEntry>("entry");
                if (entry == null) return;
                open_details_dialog(entry);
            });
        }

        private void reload_list_from_db () {
            try {
                var db = new DesktopEntryStore(store.get_db());
                entries = db.load_entries();
                if (entries == null || entries.length() == 0) {
                    status.set_text("No applications in database. Click Sync to import from /usr/share/applications.");
                }
            } catch (Error e) {
                show_message(Gtk.MessageType.ERROR, "Database error: %s".printf(e.message));
            }
            rebuild_list();
        }

        private void sync_from_system () {
            try {
                var scanner = new DesktopEntryScanner();
                var sys_entries = scanner.scan_system_apps();
                var db = new DesktopEntryStore(store.get_db());
                db.sync_system_entries(sys_entries);
                uint count = (sys_entries != null) ? (uint) sys_entries.length() : 0;
                show_message(Gtk.MessageType.INFO, "Synced %u entries".printf(count), 2500);
                store.queue_applications_changed_notify();
                reload_list_from_db();
            } catch (Error e) {
                show_message(Gtk.MessageType.ERROR, "Sync failed: %s".printf(e.message));
            }
        }

        private void show_message (Gtk.MessageType type, string text, int auto_hide_ms = 0) {
            infobar.message_type = type;
            infobar_label.set_text(text);
            infobar.show_all();
            if (auto_hide_ms > 0) {
                Timeout.add((uint) auto_hide_ms, () => {
                    infobar.hide();
                    return false;
                });
            }
        }

        private void rebuild_list () {
            foreach (Gtk.Widget child in list_box.get_children()) {
                list_box.remove(child);
            }

            if (entries == null) return;

            var q = search.get_text().strip().down();
            for (unowned List<DesktopEntry> it = entries; it != null; it = it.next) {
                var e = it.data;
                if (q.length > 0) {
                    var cat_label = DesktopEntryUtils.category_display_name(e.category);
                    var hit = e.name.down().contains(q) || e.exec.down().contains(q) ||
                              e.categories.down().contains(q) || e.category.down().contains(q) || cat_label.down().contains(q) ||
                              e.filename.down().contains(q);
                    if (!hit) continue;
                }

                var row = new Gtk.ListBoxRow();
                row.set_data("entry", e);
                row.set_size_request(-1, 56);

                var outer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
                outer.margin_top = 4;
                outer.margin_bottom = 4;

                var row_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
                row_box.margin_top = 6;
                row_box.margin_bottom = 6;
                row_box.margin_start = 6;
                row_box.margin_end = 6;
                outer.pack_start(row_box, true, true, 0);

                var icon_name = (e.icon.strip().length > 0) ? e.icon : "application-x-executable";
                Gtk.Image icon;
                if (icon_name.index_of("/") >= 0) {
                    try {
                        var pix = new Gdk.Pixbuf.from_file_at_scale(icon_name, 24, 24, true);
                        icon = new Gtk.Image.from_pixbuf(pix);
                    } catch (Error _e) {
                        icon = new Gtk.Image.from_icon_name("application-x-executable", Gtk.IconSize.DIALOG);
                        icon.set_pixel_size(24);
                    }
                } else {
                    icon = new Gtk.Image.from_icon_name(icon_name, Gtk.IconSize.DIALOG);
                    icon.set_pixel_size(24);
                }
                row_box.pack_start(icon, false, false, 0);

                if (!e.enabled) {
                    var disabled = new Gtk.Image.from_icon_name("process-stop-symbolic", Gtk.IconSize.MENU);
                    disabled.set_tooltip_text("Disabled");
                    disabled.set_pixel_size(24);
                    row_box.pack_start(disabled, false, false, 0);
                }

                if (e.has_overrides) {
                    var overridden = new Gtk.Image.from_icon_name("document-edit-symbolic", Gtk.IconSize.MENU);
                    overridden.set_tooltip_text("Has overrides");
                    overridden.set_pixel_size(24);
                    row_box.pack_start(overridden, false, false, 0);
                }

                var text_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
                var name = new Gtk.Label(e.name);
                name.halign = Gtk.Align.START;
                name.xalign = 0.0f;
                name.get_style_context().add_class("nizam-app-title");
                name.set_ellipsize(Pango.EllipsizeMode.END);

                var file = new Gtk.Label("");
                file.halign = Gtk.Align.START;
                file.xalign = 0.0f;
                file.get_style_context().add_class("nizam-app-meta");
                var sub = "%s • %s".printf(e.filename, DesktopEntryUtils.category_display_name(e.category));
                file.set_text(sub);
                file.set_ellipsize(Pango.EllipsizeMode.END);
                text_box.pack_start(name, false, false, 0);
                text_box.pack_start(file, false, false, 0);

                row_box.pack_start(text_box, true, true, 0);
                row.add(outer);
                row.show_all();
                list_box.add(row);
            }
        }

        private void open_details_dialog (DesktopEntry entry) {
            var parent = this.get_toplevel();
            Gtk.Window? parent_win = null;
            if (parent is Gtk.Window) parent_win = (Gtk.Window) parent;

            var dlg = new Gtk.Dialog.with_buttons(
                "Application",
                parent_win,
                Gtk.DialogFlags.MODAL | Gtk.DialogFlags.DESTROY_WITH_PARENT,
                "Delete",
                (Gtk.ResponseType) RESP_DELETE,
                "Close",
                Gtk.ResponseType.CLOSE,
                "Save",
                Gtk.ResponseType.OK
            );
            dlg.set_default_size(520, 360);
            dlg.set_resizable(true);
            dlg.set_default_response(Gtk.ResponseType.OK);

            var save_btn = dlg.get_widget_for_response(Gtk.ResponseType.OK);
            if (save_btn != null) {
                save_btn.get_style_context().add_class("suggested-action");
            }

            var del_widget = dlg.get_widget_for_response((Gtk.ResponseType) RESP_DELETE);
            if (del_widget is Gtk.Button) {
                var del_btn = (Gtk.Button) del_widget;
                del_btn.get_style_context().add_class("destructive-action");
                del_btn.always_show_image = true;
                del_btn.image = new Gtk.Image.from_icon_name(pick_trash_icon_name(), Gtk.IconSize.BUTTON);
            }

            
            var wrapper = new Gtk.Box(Gtk.Orientation.VERTICAL, 10);
            Gtk.Widget dlg_area_widget = dialog_get_content_area_widget(dlg);
            ((Gtk.Box) dlg_area_widget).pack_start(wrapper, true, true, 0);

            var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 16);
            wrapper.pack_start(header, false, false, 0);

            
            var icon_name = (entry.icon.strip().length > 0) ? entry.icon : "application-x-executable";
            Gtk.Image icon;
            if (icon_name.index_of("/") >= 0) {
                icon = new Gtk.Image.from_file(icon_name);
            } else {
                icon = new Gtk.Image.from_icon_name(icon_name, Gtk.IconSize.DIALOG);
            }
            icon.set_pixel_size(64);
            header.pack_start(icon, false, false, 0);

            var title_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
            title_box.set_hexpand(true);

            var title = new Gtk.Label(entry.name);
            title.halign = Gtk.Align.START;
            title.xalign = 0.0f;
            title.set_ellipsize(Pango.EllipsizeMode.END);
            title.get_style_context().add_class("nizam-dialog-title");
            title_box.pack_start(title, false, false, 0);

            var subtitle = new Gtk.Label(entry.filename);
            subtitle.halign = Gtk.Align.START;
            subtitle.xalign = 0.0f;
            subtitle.set_ellipsize(Pango.EllipsizeMode.END);
            subtitle.get_style_context().add_class("nizam-dialog-subtitle");
            title_box.pack_start(subtitle, false, false, 0);

            header.pack_start(title_box, true, true, 0);

            var sep = new Gtk.Separator(Gtk.Orientation.HORIZONTAL);
            wrapper.pack_start(sep, false, false, 0);

            var grid = new Gtk.Grid();
            grid.row_spacing = 12;
            grid.column_spacing = 12;
            grid.set_hexpand(true);
            wrapper.pack_start(grid, true, true, 0);

            var labels = new Gtk.SizeGroup(Gtk.SizeGroupMode.HORIZONTAL);
            int row = 0;

            var sw_enabled = new Gtk.Switch();
            sw_enabled.active = entry.enabled;
            attach_row(grid, labels, row++, "Enabled", sw_enabled);

            var sw_dock = new Gtk.Switch();
            sw_dock.active = entry.add_to_dock;
            attach_row(grid, labels, row++, "Add to dock", sw_dock);

            var en_name = new Gtk.Entry();
            en_name.set_hexpand(true);
            en_name.text = entry.name;
            en_name.placeholder_text = entry.system_name;
            en_name.activates_default = true;
            attach_row(grid, labels, row++, "Name", en_name);

            var en_exec = new Gtk.Entry();
            en_exec.set_hexpand(true);
            en_exec.text = entry.exec;
            en_exec.placeholder_text = entry.system_exec;
            en_exec.activates_default = true;
            attach_row(grid, labels, row++, "Exec", en_exec);

            var en_cats = new Gtk.Entry();
            en_cats.set_hexpand(true);
            en_cats.text = entry.categories;
            en_cats.placeholder_text = entry.system_categories;
            en_cats.activates_default = true;
            attach_row(grid, labels, row++, "Categories", en_cats);

            var en_category = new Gtk.Entry();
            en_category.set_hexpand(true);
            en_category.editable = false;
            en_category.can_focus = false;
            en_category.sensitive = false;
            attach_row(grid, labels, row++, "Category", en_category);

            update_category_preview(en_cats, en_category, entry);
            en_cats.changed.connect(() => { update_category_preview(en_cats, en_category, entry); });

            en_name.changed.connect(() => {
                var t = en_name.text.strip();
                title.set_text((t.length > 0) ? t : entry.name);
            });

            var info = new Gtk.Label("System metadata is synced one-way from /usr/share/applications. Name/Exec changes are stored as overrides.");
            info.halign = Gtk.Align.START;
            info.wrap = true;
            info.set_margin_top(16);
            info.get_style_context().add_class("nizam-help-text");
            wrapper.pack_start(info, false, false, 0);

            dlg.show_all();

            dlg.response.connect((resp) => {
                if (resp == (Gtk.ResponseType) RESP_DELETE) {
                    var confirm = new Gtk.MessageDialog(
                        dlg,
                        Gtk.DialogFlags.MODAL,
                        Gtk.MessageType.WARNING,
                        Gtk.ButtonsType.NONE,
                        "Delete this application entry?"
                    );
                    confirm.secondary_text = "This will remove it from the database and it will not be re-imported on Sync.";
                    confirm.add_button("Cancel", Gtk.ResponseType.CANCEL);
                    var b = confirm.add_button("Delete", Gtk.ResponseType.OK);
                    if (b != null) {
                        b.get_style_context().add_class("destructive-action");
                    }
                    var r = confirm.run();
                    confirm.destroy();
                    if (r != Gtk.ResponseType.OK) {
                        return;
                    }

                    try {
                        var db = new DesktopEntryStore(store.get_db());
                        db.delete_entry(entry.filename);
                        show_message(Gtk.MessageType.INFO, "Deleted", 2500);
                        store.queue_applications_changed_notify();
                        reload_list_from_db();
                        dlg.destroy();
                    } catch (Error e) {
                        show_message(Gtk.MessageType.ERROR, "Delete failed: %s".printf(e.message));
                    }
                    return;
                }

                if (resp == Gtk.ResponseType.OK) {
                    try {
                        var db = new DesktopEntryStore(store.get_db());

                        var new_name = en_name.text.strip();
                        var new_exec = en_exec.text.strip();
                        var new_categories = en_cats.text.strip();

                        string? name_override = null;
                        string? exec_override = null;
                        string? categories_override = null;
                        if (new_name.length > 0 && new_name != entry.system_name) name_override = new_name;
                        if (new_exec.length > 0 && new_exec != entry.system_exec) exec_override = new_exec;
                        if (new_categories.length > 0 && new_categories != entry.system_categories) categories_override = new_categories;

                        db.set_user_prefs(entry.filename, sw_enabled.active, sw_dock.active, name_override, exec_override, categories_override);

                        entry.enabled = sw_enabled.active;
                        entry.add_to_dock = sw_dock.active;
                        entry.user_name = (name_override != null) ? name_override : "";
                        entry.user_exec = (exec_override != null) ? exec_override : "";
                        entry.user_categories = (categories_override != null) ? categories_override : "";
                        entry.has_overrides = (entry.user_name.strip().length > 0) ||
                                             (entry.user_exec.strip().length > 0) ||
                                             (entry.user_categories.strip().length > 0);
                        entry.name = (name_override != null) ? name_override : entry.system_name;
                        entry.exec = (exec_override != null) ? exec_override : entry.system_exec;
                        entry.categories = (categories_override != null) ? categories_override : entry.system_categories;

                        show_message(Gtk.MessageType.INFO, "Saved", 2000);
                        store.queue_applications_changed_notify();
                        
                        reload_list_from_db();
                        dlg.destroy();
                    } catch (Error e) {
                        show_message(Gtk.MessageType.ERROR, "Save failed: %s".printf(e.message));
                        
                    }
                    return;
                }
                dlg.destroy();
            });
        }

        private static string pick_trash_icon_name () {
            var theme = Gtk.IconTheme.get_default();
            if (theme != null && theme.has_icon("user-trash-symbolic")) return "user-trash-symbolic";
            if (theme != null && theme.has_icon("edit-delete-symbolic")) return "edit-delete-symbolic";
            return "user-trash";
        }

        private static void attach_row (Gtk.Grid grid, Gtk.SizeGroup group, int row, string label, Gtk.Widget widget) {
            var l = new Gtk.Label(label);
            l.halign = Gtk.Align.END;
            l.valign = Gtk.Align.CENTER;
            l.xalign = 1.0f;
            group.add_widget(l);
            grid.attach(l, 0, row, 1, 1);

            if (widget is Gtk.Switch) {
                widget.halign = Gtk.Align.START;
                widget.valign = Gtk.Align.CENTER;
                var wrap = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
                wrap.pack_start(widget, false, false, 0);
                grid.attach(wrap, 1, row, 1, 1);
            } else {
                widget.set_hexpand(true);
                widget.halign = Gtk.Align.FILL;
                widget.valign = Gtk.Align.START;
                grid.attach(widget, 1, row, 1, 1);
            }
        }

        private static void update_category_preview (Gtk.Entry en_cats, Gtk.Entry en_category, DesktopEntry entry) {
            var cats = en_cats.text.strip();
            if (cats.length == 0) cats = entry.system_categories;
            var mapped = DesktopEntryUtils.pick_category_mapped(cats);
            en_category.text = mapped;
        }
    }
}
