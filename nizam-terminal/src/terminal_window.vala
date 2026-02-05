using Gtk;
using GLib;
using Vte;

public class TerminalWindow : NizamGtk3.NizamAppWindow {
  private Gtk.ListBox sessions_list;
  private Gtk.Stack sessions_stack;
  private Gtk.Widget terminal_area;
  private string vte_version_text;

  private uint next_session_id = 1;

  private Gtk.Button tb_new_session;
  private Gtk.Button tb_close_session;
  private Gtk.Button tb_copy;
  private Gtk.Button tb_paste;

  public TerminalWindow (Gtk.Application app) {
    base (app, "Nizam Terminal", 900, 600);

    
    this.icon_name = "nizam";

    set_about_info(
      "Nizam Terminal",
      APP_VERSION,
      "GTK3 + VTE terminal for Nizam.",
      "nizam"
    );

    var toolbar = build_toolbar_box ();
    set_toolbar (toolbar);

    
    sessions_stack = new Gtk.Stack();
    sessions_stack.hexpand = true;
    sessions_stack.vexpand = true;
    sessions_stack.transition_type = Gtk.StackTransitionType.NONE;
    sessions_stack.notify["visible-child"].connect(() => {
      update_statusbar();
    });

    
    sessions_list = build_sessions_sidebar(sessions_stack);
    set_sidebar(sessions_list);

    terminal_area = sessions_stack;
    terminal_area.get_style_context ().add_class ("nizam-terminal");
    
    set_content (terminal_area, false);

    set_status_right ("Nizam Terminal " + APP_VERSION);

    vte_version_text = "VTE %u.%u.%u".printf (
      Vte.get_major_version (),
      Vte.get_minor_version (),
      Vte.get_micro_version ()
    );

    setup_actions ();

    
    new_session (null);

    update_statusbar ();

    show_all ();
  }

  private Gtk.Widget build_toolbar_box () {
    var toolbar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
    toolbar.margin_start = 8;
    toolbar.margin_end = 8;
    toolbar.margin_top = 6;
    toolbar.margin_bottom = 6;

    tb_new_session = make_toolbar_button ("tab-new-symbolic", "New Session");
    tb_new_session.clicked.connect (() => { this.activate_action ("new-session", null); });

    tb_close_session = make_toolbar_button ("window-close-symbolic", "Close Session");
    tb_close_session.clicked.connect (() => { this.activate_action ("close-session", null); });

    tb_copy = make_toolbar_button ("edit-copy-symbolic", "Copy");
    tb_copy.clicked.connect (() => { on_toolbar_copy (); });

    tb_paste = make_toolbar_button ("edit-paste-symbolic", "Paste");
    tb_paste.clicked.connect (() => { on_toolbar_paste (); });

    toolbar.pack_start (tb_new_session, false, false, 0);
    toolbar.pack_start (tb_close_session, false, false, 0);

    var sep = new Gtk.Separator (Gtk.Orientation.VERTICAL);
    sep.get_style_context ().add_class ("nizam-sep");
    toolbar.pack_start (sep, false, false, 6);

    toolbar.pack_start (tb_copy, false, false, 0);
    toolbar.pack_start (tb_paste, false, false, 0);

    return toolbar;
  }

  private Gtk.Button make_toolbar_button (string icon_name, string tooltip) {
    var btn = new Gtk.Button ();
    btn.relief = Gtk.ReliefStyle.NONE;
    btn.tooltip_text = tooltip;
    var img = new Gtk.Image.from_icon_name (icon_name, Gtk.IconSize.LARGE_TOOLBAR);
    img.set_pixel_size (20);
    btn.add (img);
    return btn;
  }

  private TerminalTab? get_current_tab () {
    var child = sessions_stack.get_visible_child();
    return (child is TerminalTab) ? (TerminalTab) child : null;
  }

  private void on_toolbar_copy () {
    var tab = get_current_tab ();
    if (tab == null) return;
    tab.term.copy_clipboard_format (Vte.Format.TEXT);
  }

  private void on_toolbar_paste () {
    var tab = get_current_tab ();
    if (tab == null) return;
    tab.term.paste_clipboard ();
  }

  private void update_statusbar () {
    
    set_status_left (vte_version_text);
  }

  private void setup_actions () {
    var act_new_session = new GLib.SimpleAction ("new-session", null);
    act_new_session.activate.connect (on_action_new_session);
    add_action (act_new_session);

    var act_close_session = new GLib.SimpleAction ("close-session", null);
    act_close_session.activate.connect (on_action_close_session);
    add_action (act_close_session);

    var act_prev = new GLib.SimpleAction ("prev-session", null);
    act_prev.activate.connect (on_action_prev_session);
    add_action (act_prev);

    var act_next = new GLib.SimpleAction ("next-session", null);
    act_next.activate.connect (on_action_next_session);
    add_action (act_next);
  }

  private void on_action_new_session (GLib.SimpleAction action, GLib.Variant? param) {
    if (param != null) {
      
    }
    new_session (null);
  }

  private void on_action_close_session (GLib.SimpleAction action, GLib.Variant? param) {
    if (param != null) {
    }
    close_current_session ();
  }

  private void on_action_prev_session (GLib.SimpleAction action, GLib.Variant? param) {
    if (param != null) {
    }
    prev_session ();
  }

  private void on_action_next_session (GLib.SimpleAction action, GLib.Variant? param) {
    if (param != null) {
    }
    next_session ();
  }

  private void prev_session () {
    var rows = sessions_list.get_children();
    if (rows == null) return;

    int n = 0;
    int cur = -1;
    int i = 0;
    foreach (var w in rows) {
      if (!(w is Gtk.ListBoxRow)) continue;
      var r = (Gtk.ListBoxRow) w;
      if (!r.get_selectable()) continue;
      if (sessions_list.get_selected_row() == r) cur = n;
      n++;
      i++;
    }
    if (n <= 1) return;
    int next_idx = (cur <= 0) ? (n - 1) : (cur - 1);
    select_session_by_index(next_idx);
  }

  private void next_session () {
    var rows = sessions_list.get_children();
    if (rows == null) return;

    int n = 0;
    int cur = -1;
    foreach (var w in rows) {
      if (!(w is Gtk.ListBoxRow)) continue;
      var r = (Gtk.ListBoxRow) w;
      if (!r.get_selectable()) continue;
      if (sessions_list.get_selected_row() == r) cur = n;
      n++;
    }
    if (n <= 1) return;
    int next_idx = (cur < 0) ? 0 : ((cur + 1) % n);
    select_session_by_index(next_idx);
  }


  private Gtk.ListBox build_sessions_sidebar (Gtk.Stack stack) {
    var list = new Gtk.ListBox();
    list.selection_mode = Gtk.SelectionMode.SINGLE;
    list.activate_on_single_click = true;
    list.row_selected.connect(on_session_row_selected);
    return list;
  }

  private void on_session_row_selected (Gtk.ListBoxRow? row) {
    if (row == null) return;
    var page = row.get_data<string>("page");
    if (page == null || page.strip().length == 0) return;
    sessions_stack.set_visible_child_name(page);
    var tab = sessions_stack.get_visible_child();
    if (tab is TerminalTab) {
      ((TerminalTab) tab).term.grab_focus();
    }
  }

  private void select_session_by_index (int idx) {
    if (idx < 0) return;
    int cur = 0;
    foreach (var w in sessions_list.get_children()) {
      if (!(w is Gtk.ListBoxRow)) continue;
      var r = (Gtk.ListBoxRow) w;
      if (!r.get_selectable()) continue;
      if (cur == idx) {
        sessions_list.select_row(r);
        return;
      }
      cur++;
    }
  }

  public void new_session (string? cwd) {
    var tab = new TerminalTab (cwd);

    tab.request_close.connect ((t) => { close_session (t); });
    tab.request_new_session.connect ((t) => { new_session (null); });
    tab.title_changed.connect ((t) => {
      update_session_row_title(t);
      update_statusbar();
    });

    var page = "s%u".printf(next_session_id++);
    sessions_stack.add_named(tab, page);

    var row = build_session_row(tab, page);
    sessions_list.add(row);
    sessions_list.show_all();

    sessions_stack.set_visible_child_name(page);
    sessions_list.select_row(row);
    update_statusbar();
    tab.term.grab_focus();
  }

  private Gtk.ListBoxRow build_session_row (TerminalTab tab, string page) {
    var row = new Gtk.ListBoxRow();
    row.set_data("page", page);
    row.set_data("tab", tab);

    var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
    box.margin_top = 6;
    box.margin_bottom = 6;
    box.margin_start = 8;
    box.margin_end = 8;

    var icon = new Gtk.Image.from_icon_name("utilities-terminal-symbolic", Gtk.IconSize.MENU);
    icon.set_pixel_size(16);
    box.pack_start(icon, false, false, 0);

    var lbl = new Gtk.Label(tab.title);
    lbl.halign = Gtk.Align.START;
    lbl.xalign = 0.0f;
    lbl.hexpand = true;
    lbl.ellipsize = Pango.EllipsizeMode.END;
    box.pack_start(lbl, true, true, 0);
    row.set_data("title_label", lbl);

    var close_btn = new Gtk.Button.from_icon_name("window-close-symbolic", Gtk.IconSize.MENU);
    close_btn.relief = Gtk.ReliefStyle.NONE;
    close_btn.tooltip_text = "Close Session";
    close_btn.set_data("tab", tab);
    close_btn.clicked.connect(on_close_session_clicked);
    box.pack_end(close_btn, false, false, 0);

    row.add(box);
    row.show_all();
    return row;
  }

  private void on_close_session_clicked (Gtk.Button btn) {
    var tab = btn.get_data<TerminalTab>("tab");
    if (tab != null) close_session(tab);
  }

  private void update_session_row_title (TerminalTab tab) {
    foreach (var w in sessions_list.get_children()) {
      if (!(w is Gtk.ListBoxRow)) continue;
      var row = (Gtk.ListBoxRow) w;
      var t = row.get_data<TerminalTab>("tab");
      if (t != tab) continue;
      var lbl = row.get_data<Gtk.Label>("title_label");
      if (lbl != null) lbl.label = tab.title;
      return;
    }
  }

  private void close_current_session () {
    var tab = get_current_tab();
    if (tab == null) return;
    close_session(tab);
  }

  private void close_session (TerminalTab tab) {
    Gtk.ListBoxRow? row_to_remove = null;
    foreach (var w in sessions_list.get_children()) {
      if (!(w is Gtk.ListBoxRow)) continue;
      var row = (Gtk.ListBoxRow) w;
      var t = row.get_data<TerminalTab>("tab");
      if (t == tab) {
        row_to_remove = row;
        break;
      }
    }

    sessions_stack.remove(tab);
    if (row_to_remove != null) {
      sessions_list.remove(row_to_remove);
    }

    
    bool any = false;
    foreach (var child in sessions_stack.get_children()) {
      any = true;
      break;
    }
    if (!any) {
      this.close();
      return;
    }

    
    select_session_by_index(0);
  }
}
