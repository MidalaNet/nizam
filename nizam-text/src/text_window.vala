using Gtk;
using GLib;
using Pango;
using Gdk;

namespace NizamText {
    public class TextWindow : NizamGtk3.NizamAppWindow {
        
        [CCode (cname = "gtk_menu_shell_append")]
        private static extern void gtk_menu_shell_append_widget (Gtk.MenuShell shell, Gtk.Widget child);

        [CCode (cname = "gtk_application_set_accels_for_action")]
        private static extern void gtk_application_set_accels_for_action_const (
            Gtk.Application app,
            string detailed_action_name,
            [CCode (array_length = false, array_null_terminated = true, type = "const gchar * const*")] string[] accels
        );

        [CCode (cname = "gtk_dialog_get_content_area")]
        private static extern unowned Gtk.Widget dialog_get_content_area_widget (Gtk.Dialog dlg);

        private Gtk.ListBox files_list;
        private Gtk.ListBoxRow? files_header = null;
        private Gtk.TextView text_view;
        private Gtk.ScrolledWindow text_scroller;
        private LineNumberArea line_numbers;
        private WrapGuideArea wrap_guide;

        private Gtk.Button tb_open;
        private Gtk.Button tb_save;
        private Gtk.Button tb_save_as;
        private Gtk.Button tb_find;
        private Gtk.ToggleButton tb_spell;

        private GLib.SimpleAction act_copy;
        private GLib.SimpleAction act_cut;
        private GLib.SimpleAction act_paste;
        private GLib.SimpleAction act_select_all;

        private List<TextDocument>? docs = null;
        private TextDocument? current_doc = null;

        private HashTable<string, bool>? spell_dict = null;
        private bool spell_enabled = true;

        private Gtk.Dialog? find_dialog = null;
        private Gtk.Entry find_entry;
        private Gtk.Entry replace_entry;
        private Gtk.CheckButton? find_match_case = null;
        private Gtk.CheckButton? find_whole_word = null;
        private Gtk.TextBuffer? buffer_connected = null;
        private ulong buffer_changed_id = 0;
        private ulong buffer_cursor_notify_id = 0;

        private uint status_message_timeout_id = 0;
        private string? status_message_override = null;

        private const int STATUS_MESSAGE_MS = 3000;
        

        public TextWindow (Gtk.Application app) {
            base (app, "Nizam Text", 900, 600);
            this.icon_name = "nizam";

            set_about_info(
                "Nizam Text",
                APP_VERSION,
                "Simple text editor for plain .txt files.",
                "nizam"
            );
            this.icon_name = "nizam";

            var toolbar = build_toolbar_box();
            set_toolbar(toolbar);

            files_list = new Gtk.ListBox();
            files_list.selection_mode = Gtk.SelectionMode.SINGLE;
            files_list.activate_on_single_click = true;
            files_list.get_style_context().add_class("nizam-list");
            files_list.row_selected.connect((row) => {
                if (row == null) return;
                var doc = row.get_data<TextDocument>("doc");
                if (doc != null) set_current_document(doc);
            });
            files_list.set_size_request(240, -1);
            set_sidebar(files_list);

            text_view = new Gtk.TextView();
            text_view.set_editable(true);
            text_view.set_cursor_visible(true);
            text_view.set_can_focus(true);
            
            text_view.add_events(
                Gdk.EventMask.BUTTON_PRESS_MASK |
                Gdk.EventMask.BUTTON_RELEASE_MASK |
                Gdk.EventMask.POINTER_MOTION_MASK |
                Gdk.EventMask.BUTTON_MOTION_MASK
            );
            
            text_view.wrap_mode = Gtk.WrapMode.NONE;
            text_view.set_left_margin(12);
            text_view.set_right_margin(12);
            text_view.set_top_margin(8);
            text_view.set_bottom_margin(8);
            text_view.monospace = true;
            apply_editor_font();
            text_view.get_style_context().add_class("nizam-textview");
            text_view.set_focus_on_click(true);
            text_view.populate_popup.connect((menu) => {
                var m = menu as Gtk.Menu;
                if (m != null) {
                    populate_context_menu(m);
                }
            });
            text_view.key_press_event.connect((ev) => { return on_text_key_press(ev); });
            text_view.style_updated.connect(() => { update_wrap_width(); });
            text_view.realize.connect(() => { update_wrap_width(); });

            text_scroller = new Gtk.ScrolledWindow(null, null);
            text_scroller.hscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
            text_scroller.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
            text_scroller.add(text_view);

            update_wrap_width();

            var editor_overlay = new Gtk.Overlay();
            editor_overlay.hexpand = true;
            editor_overlay.vexpand = true;
            editor_overlay.add(text_scroller);

            wrap_guide = new WrapGuideArea(text_view);
            wrap_guide.set_wrap_cols(72);
            wrap_guide.set_sensitive(false);
            wrap_guide.set_can_focus(false);
            wrap_guide.set_has_window(false);
            editor_overlay.add_overlay(wrap_guide);
            editor_overlay.set_overlay_pass_through(wrap_guide, true);

            line_numbers = new LineNumberArea(text_view, text_scroller, true);
            line_numbers.get_style_context().add_class("nizam-linenos");
            line_numbers.set_has_window(false);

            var editor_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            editor_row.pack_start(editor_overlay, true, true, 0);
            editor_row.pack_start(line_numbers, false, false, 0);

            set_content(editor_row, false);

            text_scroller.size_allocate.connect((_alloc) => { update_wrap_width(); });

            
            
            text_view.button_press_event.connect((ev) => {
                if (ev.button == 3) {
                    var menu = new Gtk.Menu();
                    populate_context_menu(menu);
                    menu.popup_at_pointer(ev);
                    return true;
                }
                return false;
            });

            install_editor_actions_and_accels(app);

            create_empty_document();
            update_status();

            show_all();
        }

        private void install_editor_actions_and_accels (Gtk.Application app) {
            act_copy = new GLib.SimpleAction("copy", null);
            act_copy.activate.connect(() => { copy_selection(); });
            add_action(act_copy);

            act_cut = new GLib.SimpleAction("cut", null);
            act_cut.activate.connect(() => { cut_selection(); });
            add_action(act_cut);

            act_paste = new GLib.SimpleAction("paste", null);
            act_paste.activate.connect(() => { paste_clipboard(); });
            add_action(act_paste);

            act_select_all = new GLib.SimpleAction("select-all", null);
            act_select_all.activate.connect(() => {
                if (text_view == null || text_view.buffer == null) return;
                Gtk.TextIter start, end;
                text_view.buffer.get_bounds(out start, out end);
                text_view.buffer.select_range(start, end);
                text_view.grab_focus();
            });
            add_action(act_select_all);

            
            gtk_application_set_accels_for_action_const(app, "win.copy", { "<Primary>c", null });
            gtk_application_set_accels_for_action_const(app, "win.cut", { "<Primary>x", null });
            gtk_application_set_accels_for_action_const(app, "win.paste", { "<Primary>v", null });
            gtk_application_set_accels_for_action_const(app, "win.select-all", { "<Primary>a", null });
        }

        private bool on_text_key_press (Gdk.EventKey ev) {
            
            return false;
        }

        private void apply_editor_font () {
            var provider = new Gtk.CssProvider();
            try {
                provider.load_from_data(".nizam-text-editor { font-family: Monospace; font-size: 11pt; }");
            } catch (Error e) {
                show_status_message("Failed to set editor font: %s".printf(e.message));
            }
            var ctx = text_view.get_style_context();
            ctx.add_provider(provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
            ctx.add_class("nizam-text-editor");
        }

        private Gtk.Widget build_toolbar_box () {
            var toolbar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            toolbar.margin_start = 8;
            toolbar.margin_end = 8;
            toolbar.margin_top = 6;
            toolbar.margin_bottom = 6;

            tb_open = make_toolbar_button("document-open-symbolic", "Open text file");
            tb_open.clicked.connect(() => { open_file_dialog(); });
            toolbar.pack_start(tb_open, false, false, 0);

            tb_save = make_toolbar_button("document-save-symbolic", "Save");
            tb_save.clicked.connect(() => { save_current(); });
            toolbar.pack_start(tb_save, false, false, 0);

            tb_save_as = make_toolbar_button("document-save-as-symbolic", "Save As");
            tb_save_as.clicked.connect(() => { save_as_current(); });
            toolbar.pack_start(tb_save_as, false, false, 0);

            var sep0 = new Gtk.Separator(Gtk.Orientation.VERTICAL);
            sep0.get_style_context().add_class("nizam-sep");
            toolbar.pack_start(sep0, false, false, 6);

            tb_find = make_toolbar_button("edit-find-replace-symbolic", "Find/Replace");
            tb_find.clicked.connect(() => { show_find_replace(); });
            toolbar.pack_start(tb_find, false, false, 0);

            var sep = new Gtk.Separator(Gtk.Orientation.VERTICAL);
            sep.get_style_context().add_class("nizam-sep");
            toolbar.pack_start(sep, false, false, 6);

            tb_spell = new Gtk.ToggleButton();
            tb_spell.tooltip_text = "Toggle spell checker";
            var img = new Gtk.Image.from_icon_name("tools-check-spelling-symbolic", Gtk.IconSize.LARGE_TOOLBAR);
            img.set_pixel_size(20);
            tb_spell.add(img);
            tb_spell.active = true;
            tb_spell.toggled.connect(() => {
                spell_enabled = tb_spell.active;
                apply_spellcheck_current();
                update_status();
            });
            toolbar.pack_start(tb_spell, false, false, 0);

            return toolbar;
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

        private void update_status () {
            set_status_right("Nizam Text Editor v. %s".printf(APP_VERSION));

            if (status_message_override != null) {
                set_status_left(status_message_override);
                return;
            }

            if (current_doc == null || current_doc.buffer == null) {
                set_status_left("Line: - Col: -");
                return;
            }

            Gtk.TextIter iter;
            current_doc.buffer.get_iter_at_mark(out iter, current_doc.buffer.get_insert());
            int line = iter.get_line() + 1;
            int col = iter.get_line_offset() + 1;
            set_status_left("Line: %d Col: %d".printf(line, col));
        }

        private void show_status_message (string msg, uint ms = 3000) {
            status_message_override = msg;
            update_status();

            if (status_message_timeout_id != 0) {
                Source.remove(status_message_timeout_id);
                status_message_timeout_id = 0;
            }
            status_message_timeout_id = Timeout.add(ms, () => {
                status_message_override = null;
                status_message_timeout_id = 0;
                update_status();
                return false;
            });
        }

        private void create_empty_document () {
            var buffer = new Gtk.TextBuffer(null);
            var doc = new TextDocument(null, buffer);
            add_document(doc);
        }

        private void add_document (TextDocument doc) {
            if (docs == null) {
                docs = new List<TextDocument>();
            }
            ensure_files_header();
            docs.append(doc);
            var row = new Gtk.ListBoxRow();
            var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            box.margin_top = 6;
            box.margin_bottom = 6;
            box.margin_start = 8;
            box.margin_end = 8;

            var icon = new Gtk.Image.from_icon_name("text-x-generic-symbolic", Gtk.IconSize.MENU);
            icon.set_pixel_size(16);
            box.pack_start(icon, false, false, 0);

            var label = new Gtk.Label(doc.title);
            label.halign = Gtk.Align.START;
            label.xalign = 0.0f;
            label.hexpand = true;
            label.ellipsize = Pango.EllipsizeMode.END;
            box.pack_start(label, true, true, 0);

            var btn_close = new Gtk.Button();
            btn_close.relief = Gtk.ReliefStyle.NONE;
            btn_close.focus_on_click = false;
            btn_close.tooltip_text = "Close";
            btn_close.set_data("doc", doc);
            var close_img = new Gtk.Image.from_icon_name("window-close-symbolic", Gtk.IconSize.MENU);
            close_img.set_pixel_size(16);
            btn_close.add(close_img);
            btn_close.clicked.connect(on_close_doc_clicked);
            box.pack_end(btn_close, false, false, 0);

            row.set_data("title_label", label);
            row.add(box);
            row.set_data("doc", doc);
            files_list.add(row);
            files_list.show_all();
            files_list.select_row(row);
            set_current_document(doc);
        }

        private void ensure_files_header () {
            if (files_header != null) return;
            var row = new Gtk.ListBoxRow();
            row.set_selectable(false);
            row.set_activatable(false);

            var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            box.margin_top = 6;
            box.margin_bottom = 6;
            box.margin_start = 8;
            box.margin_end = 8;

            var lbl = new Gtk.Label("Files");
            lbl.halign = Gtk.Align.START;
            lbl.xalign = 0.0f;
            lbl.hexpand = true;
            lbl.get_style_context().add_class("dim-label");
            box.pack_start(lbl, true, true, 0);

            row.add(box);
            files_list.add(row);
            files_header = row;
        }

        private void on_close_doc_clicked (Gtk.Button btn) {
            var doc = btn.get_data<TextDocument>("doc");
            if (doc == null) return;
            close_document(doc);
        }

        private void set_current_document (TextDocument doc) {
            current_doc = doc;
            text_view.buffer = doc.buffer;
            attach_buffer(doc.buffer);
            line_numbers.set_view(text_view);
            update_wrap_width();
            apply_spellcheck_current();
            update_status();
            text_view.grab_focus();
        }

        private void attach_buffer (Gtk.TextBuffer buf) {
            if (buffer_connected != null && buffer_changed_id != 0) {
                buffer_connected.disconnect(buffer_changed_id);
            }
            if (buffer_connected != null && buffer_cursor_notify_id != 0) {
                buffer_connected.disconnect(buffer_cursor_notify_id);
            }
            buffer_connected = buf;
            
            
            buffer_changed_id = buf.changed.connect(() => {
                apply_spellcheck_current();
                update_status();
            });

            buffer_cursor_notify_id = buf.notify["cursor-position"].connect(() => {
                update_status();
            });
        }

        private void open_file_dialog () {
            var dlg = new Gtk.FileChooserDialog(
                "Open Text File",
                this,
                Gtk.FileChooserAction.OPEN,
                "_Cancel", Gtk.ResponseType.CANCEL,
                "_Open", Gtk.ResponseType.OK
            );
            dlg.set_select_multiple(true);

            var filter_text = new Gtk.FileFilter();
            filter_text.set_name("Text files");
            filter_text.add_mime_type("text/plain");
            dlg.add_filter(filter_text);

            var filter_all = new Gtk.FileFilter();
            filter_all.set_name("All files");
            filter_all.add_pattern("*");
            dlg.add_filter(filter_all);
            dlg.set_filter(filter_text);

            if (dlg.run() == Gtk.ResponseType.OK) {
                var files = dlg.get_filenames();
                foreach (var path in files) {
                    if (path == null) continue;
                    open_file(path);
                }
            }
            dlg.destroy();
        }

        private bool load_plain_text_utf8 (string path, out string contents) {
            contents = "";
            try {
                var file = File.new_for_path(path);
                var info = file.query_info("standard::content-type", FileQueryInfoFlags.NONE);
                var ct = info.get_content_type();
                if (ct == null) return false;
                
                if (!ct.has_prefix("text/")) return false;

                size_t len = 0;
                if (!FileUtils.get_contents(path, out contents, out len)) return false;

                
                if ((size_t) contents.length != len) return false;
                if (!contents.validate((ssize_t) len)) return false;
                return true;
            } catch (Error e) {
                return false;
            }
        }

        private void open_file (string path) {
            string contents;
            if (!load_plain_text_utf8(path, out contents)) {
                show_status_message("Not a UTF-8 plain text file: %s".printf(Path.get_basename(path)));
                return;
            }

            if (docs != null) {
                foreach (var doc in docs) {
                    if (doc.path != null && doc.path == path) {
                        set_current_document(doc);
                        return;
                    }
                }
            }

            var buffer = new Gtk.TextBuffer(null);
            buffer.set_text(contents, contents.length);
            buffer.set_modified(false);

            var doc = new TextDocument(path, buffer);
            add_document(doc);
        }

        private void save_current () {
            if (current_doc == null) return;
            if (current_doc.path == null) {
                save_as_current();
                return;
            }
            save_to_path(current_doc.path);
        }

        private void save_as_current () {
            if (current_doc == null) return;
            var dlg = new Gtk.FileChooserDialog(
                "Save Text File",
                this,
                Gtk.FileChooserAction.SAVE,
                "_Cancel", Gtk.ResponseType.CANCEL,
                "_Save", Gtk.ResponseType.OK
            );
            dlg.set_do_overwrite_confirmation(true);
            dlg.set_current_name("untitled.txt");

            if (dlg.run() == Gtk.ResponseType.OK) {
                var path = dlg.get_filename();
                if (path != null) {
                    save_to_path(path);
                    current_doc.update_path(path);
                    update_sidebar_titles();
                }
            }
            dlg.destroy();
        }

        private void save_to_path (string path) {
            if (current_doc == null) return;
            Gtk.TextIter start, end;
            current_doc.buffer.get_bounds(out start, out end);
            var text = current_doc.buffer.get_text(start, end, false);
            try {
                FileUtils.set_contents(path, text);
                current_doc.buffer.set_modified(false);
                show_status_message("Saved: %s".printf(Path.get_basename(path)));
            } catch (Error e) {
                show_status_message("Save failed: %s".printf(e.message));
            }
        }

        private void update_sidebar_titles () {
            foreach (Gtk.Widget child in files_list.get_children()) {
                var row = child as Gtk.ListBoxRow;
                if (row == null) continue;
                var doc = row.get_data<TextDocument>("doc");
                if (doc == null) continue;
                var label = row.get_data<Gtk.Label>("title_label");
                if (label != null) label.set_text(doc.title);
            }
        }

        private Gtk.ListBoxRow? find_row_for_doc (TextDocument doc) {
            foreach (Gtk.Widget child in files_list.get_children()) {
                var row = child as Gtk.ListBoxRow;
                if (row == null) continue;
                var d = row.get_data<TextDocument>("doc");
                if (d == doc) return row;
            }
            return null;
        }

        private bool save_document_to_path (TextDocument doc, string path) {
            Gtk.TextIter start, end;
            doc.buffer.get_bounds(out start, out end);
            var text = doc.buffer.get_text(start, end, false);
            try {
                FileUtils.set_contents(path, text);
                doc.buffer.set_modified(false);
                doc.update_path(path);
                update_sidebar_titles();
                show_status_message("Saved: %s".printf(Path.get_basename(path)), STATUS_MESSAGE_MS);
                return true;
            } catch (Error e) {
                show_status_message("Save failed: %s".printf(e.message), STATUS_MESSAGE_MS);
                return false;
            }
        }

        private bool save_document_as (TextDocument doc) {
            var dlg = new Gtk.FileChooserDialog(
                "Save Text File",
                this,
                Gtk.FileChooserAction.SAVE,
                "_Cancel", Gtk.ResponseType.CANCEL,
                "_Save", Gtk.ResponseType.OK
            );
            dlg.set_do_overwrite_confirmation(true);
            dlg.set_current_name(doc.path != null ? Path.get_basename(doc.path) : "untitled.txt");

            bool ok = false;
            if (dlg.run() == Gtk.ResponseType.OK) {
                var path = dlg.get_filename();
                if (path != null) {
                    ok = save_document_to_path(doc, path);
                }
            }
            dlg.destroy();
            return ok;
        }

        private bool ensure_document_saved_or_discarded (TextDocument doc) {
            if (!doc.buffer.get_modified()) return true;

            var title = doc.title;
            var md = new Gtk.MessageDialog(
                this,
                Gtk.DialogFlags.MODAL,
                Gtk.MessageType.QUESTION,
                Gtk.ButtonsType.NONE,
                "Save changes to '%s'?".printf(title)
            );
            md.secondary_text = "Your changes will be lost if you don't save them.";
            md.add_button("_Cancel", Gtk.ResponseType.CANCEL);
            md.add_button("_Discard", Gtk.ResponseType.REJECT);
            md.add_button("_Save", Gtk.ResponseType.ACCEPT);
            md.set_default_response(Gtk.ResponseType.ACCEPT);

            var resp = md.run();
            md.destroy();

            if (resp == Gtk.ResponseType.CANCEL || resp == Gtk.ResponseType.DELETE_EVENT) {
                return false;
            }
            if (resp == Gtk.ResponseType.REJECT) {
                return true;
            }
            
            if (doc.path == null) {
                return save_document_as(doc);
            }
            return save_document_to_path(doc, doc.path);
        }

        private void close_document (TextDocument doc) {
            if (!ensure_document_saved_or_discarded(doc)) return;

            var row = find_row_for_doc(doc);

            
            Gtk.ListBoxRow? row_to_select = null;
            if (row != null && current_doc == doc) {
                var children = files_list.get_children();
                int idx = 0;
                int row_idx = -1;
                foreach (Gtk.Widget child in children) {
                    if ((child as Gtk.ListBoxRow) == row) {
                        row_idx = idx;
                        break;
                    }
                    idx++;
                }

                if (row_idx >= 0) {
                    
                    int j = row_idx + 1;
                    idx = 0;
                    foreach (Gtk.Widget child in children) {
                        if (idx == j) {
                            var r = child as Gtk.ListBoxRow;
                            if (r != null && r.get_data<TextDocument>("doc") != null) {
                                row_to_select = r;
                            }
                            break;
                        }
                        idx++;
                    }
                    
                    if (row_to_select == null) {
                        j = row_idx - 1;
                        idx = 0;
                        foreach (Gtk.Widget child in children) {
                            if (idx == j) {
                                var r = child as Gtk.ListBoxRow;
                                if (r != null && r.get_data<TextDocument>("doc") != null) {
                                    row_to_select = r;
                                }
                                break;
                            }
                            idx++;
                        }
                    }
                }
            }

            if (docs != null) {
                docs.remove(doc);
            }
            if (row != null) {
                files_list.remove(row);
            }

            if (docs == null || docs.length() == 0) {
                current_doc = null;
                create_empty_document();
                return;
            }

            if (row_to_select != null) {
                files_list.select_row(row_to_select);
            } else if (current_doc == doc) {
                
                foreach (Gtk.Widget child in files_list.get_children()) {
                    var r = child as Gtk.ListBoxRow;
                    if (r != null && r.get_data<TextDocument>("doc") != null) {
                        files_list.select_row(r);
                        break;
                    }
                }
            }
        }

        private void update_wrap_width () {
            if (text_view == null) return;
            
            if (wrap_guide != null) {
                wrap_guide.queue_draw();
            }
        }

        private bool ensure_dictionary () {
            if (spell_dict != null) return true;
            string[] candidates = {
                "/usr/share/dict/words",
                "/usr/share/dict/american-english",
                "/usr/share/dict/british-english"
            };

            string? path = null;
            foreach (var cand in candidates) {
                if (FileUtils.test(cand, FileTest.IS_REGULAR)) {
                    path = cand;
                    break;
                }
            }
            if (path == null) return false;

            var dict = new HashTable<string, bool>(str_hash, str_equal);
            try {
                string contents;
                if (!FileUtils.get_contents(path, out contents)) return false;
                foreach (var line in contents.split("\n")) {
                    var w = line.strip().down();
                    if (w.length == 0) continue;
                    dict.insert(w, true);
                }
            } catch (Error e) {
                return false;
            }

            spell_dict = dict;
            return true;
        }

        private bool word_ok (string word) {
            if (spell_dict == null) return true;
            var w = word.strip().down();
            if (w.length == 0) return true;
            for (int i = 0; i < w.length; i++) {
                unichar c = w.get_char(i);
                if (c == 0) break;
                if (!c.isalpha()) return true;
            }
            return spell_dict.lookup(w);
        }

        private Gtk.TextTag ensure_spell_tag (Gtk.TextBuffer buf) {
            var tag = buf.get_tag_table().lookup("misspelled");
            if (tag == null) {
                tag = new Gtk.TextTag("misspelled");
                tag.underline = Pango.Underline.ERROR;
                buf.get_tag_table().add(tag);
            }
            return tag;
        }

        private void apply_spellcheck_current () {
            if (current_doc == null) return;
            if (current_doc.spell_timeout_id != 0) {
                Source.remove(current_doc.spell_timeout_id);
                current_doc.spell_timeout_id = 0;
            }

            if (!spell_enabled) {
                clear_spellcheck(current_doc);
                return;
            }
            current_doc.spell_timeout_id = Timeout.add(400, () => {
                current_doc.spell_timeout_id = 0;
                apply_spellcheck(current_doc);
                return false;
            });
        }

        private void clear_spellcheck (TextDocument doc) {
            Gtk.TextIter start, end;
            doc.buffer.get_bounds(out start, out end);
            var tag = ensure_spell_tag(doc.buffer);
            doc.buffer.remove_tag(tag, start, end);
        }

        private void apply_spellcheck (TextDocument doc) {
            if (!ensure_dictionary()) {
                show_status_message("Spellcheck dictionary not found");
                return;
            }
            Gtk.TextIter start, end;
            doc.buffer.get_bounds(out start, out end);
            var tag = ensure_spell_tag(doc.buffer);
            doc.buffer.remove_tag(tag, start, end);

            Gtk.TextIter iter = start;
            while (!iter.is_end()) {
                if (!iter.starts_word()) {
                    iter.forward_char();
                    continue;
                }
                Gtk.TextIter word_end = iter;
                if (!word_end.forward_word_end()) break;
                var word = doc.buffer.get_text(iter, word_end, false);
                if (!word_ok(word)) {
                    doc.buffer.apply_tag(tag, iter, word_end);
                }
                iter = word_end;
            }
        }

        private void populate_context_menu (Gtk.Menu menu) {
            foreach (Gtk.Widget child in menu.get_children()) {
                menu.remove(child);
            }

            var item_copy = new Gtk.MenuItem.with_label("Copy");
            item_copy.activate.connect(() => { copy_selection(); });
            gtk_menu_shell_append_widget(menu, (Gtk.Widget) item_copy);

            var item_cut = new Gtk.MenuItem.with_label("Cut");
            item_cut.activate.connect(() => { cut_selection(); });
            gtk_menu_shell_append_widget(menu, (Gtk.Widget) item_cut);

            var item_paste = new Gtk.MenuItem.with_label("Paste");
            item_paste.activate.connect(() => { paste_clipboard(); });
            gtk_menu_shell_append_widget(menu, (Gtk.Widget) item_paste);

            gtk_menu_shell_append_widget(menu, new Gtk.SeparatorMenuItem());

            var item_find = new Gtk.MenuItem.with_label("Find/Replace");
            item_find.activate.connect(() => { show_find_replace(); });
            gtk_menu_shell_append_widget(menu, (Gtk.Widget) item_find);

            var item_spell = new Gtk.MenuItem.with_label(spell_enabled ? "Disable Spellcheck" : "Enable Spellcheck");
            item_spell.activate.connect(() => {
                spell_enabled = !spell_enabled;
                tb_spell.active = spell_enabled;
                apply_spellcheck_current();
                update_status();
            });
            gtk_menu_shell_append_widget(menu, (Gtk.Widget) item_spell);

            menu.show_all();
        }

        private void copy_selection () {
            var clip = Gtk.Clipboard.get_default(get_display());
            text_view.buffer.copy_clipboard(clip);
        }

        private void cut_selection () {
            var clip = Gtk.Clipboard.get_default(get_display());
            text_view.buffer.cut_clipboard(clip, true);
        }

        private void paste_clipboard () {
            var clip = Gtk.Clipboard.get_default(get_display());
            text_view.buffer.paste_clipboard(clip, null, true);
        }

        private void show_find_replace () {
            if (find_dialog != null) {
                find_dialog.present();
                return;
            }

            find_dialog = new Gtk.Dialog.with_buttons(
                "Find/Replace",
                this,
                Gtk.DialogFlags.MODAL,
                "_Close", Gtk.ResponseType.CLOSE
            );
            find_dialog.set_default_size(420, 160);

            Gtk.Widget content_widget = dialog_get_content_area_widget(find_dialog);
            var content = content_widget as Gtk.Box;
            var grid = new Gtk.Grid();
            grid.margin = 12;
            grid.row_spacing = 8;
            grid.column_spacing = 8;

            var find_label = new Gtk.Label("Find");
            find_label.halign = Gtk.Align.END;
            grid.attach(find_label, 0, 0, 1, 1);

            find_entry = new Gtk.Entry();
            grid.attach(find_entry, 1, 0, 2, 1);

            var replace_label = new Gtk.Label("Replace");
            replace_label.halign = Gtk.Align.END;
            grid.attach(replace_label, 0, 1, 1, 1);

            replace_entry = new Gtk.Entry();
            grid.attach(replace_entry, 1, 1, 2, 1);

            var opts = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
            find_match_case = new Gtk.CheckButton.with_label("Match case");
            find_match_case.active = false;
            opts.pack_start(find_match_case, false, false, 0);

            find_whole_word = new Gtk.CheckButton.with_label("Whole word");
            find_whole_word.active = false;
            opts.pack_start(find_whole_word, false, false, 0);

            grid.attach(opts, 1, 2, 2, 1);

            var btn_find = new Gtk.Button.with_label("Find Next");
            btn_find.clicked.connect(() => { find_next(); });
            grid.attach(btn_find, 1, 3, 1, 1);

            var btn_replace = new Gtk.Button.with_label("Replace");
            btn_replace.clicked.connect(() => { replace_one(); });
            grid.attach(btn_replace, 2, 3, 1, 1);

            var btn_replace_all = new Gtk.Button.with_label("Replace All");
            btn_replace_all.clicked.connect(() => { replace_all(); });
            grid.attach(btn_replace_all, 1, 4, 2, 1);

            content.pack_start(grid, true, true, 0);

            find_dialog.response.connect((_resp) => {
                find_dialog.hide();
            });
            find_dialog.show_all();
        }

        private bool is_match_case () {
            return find_match_case != null && find_match_case.active;
        }

        private bool is_whole_word () {
            return find_whole_word != null && find_whole_word.active;
        }

        private Gtk.TextSearchFlags get_search_flags () {
            Gtk.TextSearchFlags flags = Gtk.TextSearchFlags.TEXT_ONLY;
            if (!is_match_case()) {
                flags |= Gtk.TextSearchFlags.CASE_INSENSITIVE;
            }
            return flags;
        }

        private bool match_is_whole_word (Gtk.TextIter match_start, Gtk.TextIter match_end) {
            if (!is_whole_word()) return true;
            
            return match_start.starts_word() && match_end.ends_word();
        }

        private bool selection_matches_needle (Gtk.TextIter sel_start, Gtk.TextIter sel_end, string needle) {
            var selected = current_doc.buffer.get_text(sel_start, sel_end, false);
            if (selected == null) return false;
            if (is_match_case()) {
                if (selected != needle) return false;
            } else {
                if (selected.down() != needle.down()) return false;
            }
            if (!match_is_whole_word(sel_start, sel_end)) return false;
            return true;
        }

        private static string regex_escape_replacement_literal (string replacement) {
            
            
            return replacement.replace("\\", "\\\\").replace("$", "\\$");
        }

        private bool find_next () {
            if (current_doc == null) return false;
            var needle = find_entry.get_text();
            if (needle == null || needle.length == 0) return false;
            Gtk.TextIter start, end;
            if (current_doc.buffer.get_selection_bounds(out start, out end)) {
                start = end;
            } else {
                current_doc.buffer.get_start_iter(out start);
            }
            Gtk.TextIter match_start, match_end;
            var flags = get_search_flags();
            while (start.forward_search(needle, flags, out match_start, out match_end, null)) {
                if (!match_is_whole_word(match_start, match_end)) {
                    start = match_end;
                    continue;
                }
                current_doc.buffer.select_range(match_start, match_end);
                text_view.scroll_to_iter(match_start, 0.1, false, 0, 0);
                return true;
            }
            return false;
        }

        private void replace_one () {
            if (current_doc == null) return;
            var needle = find_entry.get_text();
            if (needle == null || needle.length == 0) return;
            Gtk.TextIter sel_start, sel_end;
            if (!current_doc.buffer.get_selection_bounds(out sel_start, out sel_end) ||
                !selection_matches_needle(sel_start, sel_end, needle)) {
                if (!find_next()) return;
                if (!current_doc.buffer.get_selection_bounds(out sel_start, out sel_end)) return;
            }
            var repl = replace_entry.get_text();
            current_doc.buffer.delete(ref sel_start, ref sel_end);
            current_doc.buffer.insert(ref sel_start, repl, repl.length);
            find_next();
        }

        private void replace_all () {
            if (current_doc == null) return;
            var needle = find_entry.get_text();
            if (needle == null || needle.length == 0) return;
            var repl = replace_entry.get_text();

            
            
            Gtk.TextIter start, end;
            current_doc.buffer.get_bounds(out start, out end);
            var original = current_doc.buffer.get_text(start, end, false);
            if (original == null) return;

            string replaced;
            try {
                if (is_match_case() && !is_whole_word()) {
                    replaced = original.replace(needle, repl);
                } else {
                    string pat = Regex.escape_string(needle);
                    if (is_whole_word()) {
                        pat = "\\b" + pat + "\\b";
                    }
                    RegexCompileFlags cflags = RegexCompileFlags.MULTILINE;
                    if (!is_match_case()) {
                        cflags |= RegexCompileFlags.CASELESS;
                    }
                    var rx = new Regex(pat, cflags, 0);
                    replaced = rx.replace(original, original.length, 0, regex_escape_replacement_literal(repl), 0);
                }
            } catch (Error e) {
                show_status_message("Replace failed: %s".printf(e.message));
                return;
            }

            if (replaced == original) return;

            
            Gtk.TextIter insert_iter;
            current_doc.buffer.get_iter_at_mark(out insert_iter, current_doc.buffer.get_insert());
            int insert_offset = insert_iter.get_offset();

            current_doc.buffer.begin_user_action();
            current_doc.buffer.set_text(replaced, replaced.length);
            Gtk.TextIter new_insert;
            int new_off = insert_offset;
            if (new_off < 0) new_off = 0;
            if (new_off > replaced.length) new_off = replaced.length;
            current_doc.buffer.get_iter_at_offset(out new_insert, new_off);
            current_doc.buffer.place_cursor(new_insert);
            current_doc.buffer.end_user_action();

            apply_spellcheck_current();
        }
    }
}
