using Gtk;
using Vte;
using GLib;
using Pango;

public class TerminalTab : Gtk.Box {
  public Vte.Terminal term { get; private set; }
  public string title { get; private set; }
  public string? current_dir_full { get; private set; }

  private Gtk.Overlay overlay;
  private Gtk.DrawingArea bg_area;

  private Gtk.Menu context_menu;
  private Gtk.MenuItem mi_new_session;
  private Gtk.MenuItem mi_copy;
  private Gtk.MenuItem mi_paste;
  private Gtk.MenuItem mi_close;

  private Gdk.Pixbuf? root_bg;
  private static Gdk.Pixbuf? shared_root_bg = null;
  private static int64 shared_root_bg_ms = 0;

  
  
  private double tint_alpha = 0.9;
  private bool pseudo_transparency = true;

  public signal void request_close (TerminalTab tab);
  public signal void request_new_session (TerminalTab tab);
  public signal void title_changed (TerminalTab tab);

  public TerminalTab (string? cwd = null) {
    Object (orientation: Orientation.VERTICAL, spacing: 0);

    
    var initial_dir = cwd ?? Environment.get_current_dir ();
    if (initial_dir != null && initial_dir.strip ().length > 0) {
      current_dir_full = initial_dir;
      title = Path.get_basename (initial_dir);
      if (title == null || title.strip ().length == 0) {
        title = "Terminal";
      }
    } else {
      title = "Terminal";
    }

    overlay = new Gtk.Overlay ();
    overlay.hexpand = true;
    overlay.vexpand = true;

    bg_area = new Gtk.DrawingArea ();
    bg_area.hexpand = true;
    bg_area.vexpand = true;
    bg_area.draw.connect (on_bg_draw);

    term = new Vte.Terminal ();
    term.hexpand = true;
    term.vexpand = true;

    
    
    term.set_font (Pango.FontDescription.from_string ("DejaVu Sans Mono 11"));

    
    
    {
      var opts = new Cairo.FontOptions ();
      opts.set_antialias (Cairo.Antialias.SUBPIXEL);
      opts.set_subpixel_order (Cairo.SubpixelOrder.RGB);
      opts.set_hint_style (Cairo.HintStyle.SLIGHT);
      opts.set_hint_metrics (Cairo.HintMetrics.ON);
      term.set_font_options (opts);
    }

    term.margin_top = 6;
    term.margin_bottom = 6;
    term.margin_start = 8;
    term.margin_end = 8;

    
    term.set_scrollback_lines (3000);
    term.set_audible_bell (false);
    term.set_mouse_autohide (true);
    
    term.set_enable_bidi (false);
    term.set_enable_shaping (false);
    term.set_allow_hyperlink (false);

    apply_terminal_theme ();

    apply_terminal_background_mode ();

    overlay.add (bg_area);
    overlay.add_overlay (term);

    this.pack_start (overlay, true, true, 0);

    setup_context_menu ();
    setup_title_tracking ();

    
    reload_root_background ();

    
    this.configure_event.connect (on_configure_event);

    spawn_shell (cwd);
    this.show_all ();
  }

  private static Gdk.RGBA rgba (string hex, double alpha = 1.0) {
    var c = Gdk.RGBA ();
    if (!c.parse (hex)) {
      c.red = 1.0;
      c.green = 1.0;
      c.blue = 1.0;
    }
    c.alpha = alpha;
    return c;
  }

  private void apply_terminal_theme () {
    
    var fg = rgba ("#eaeaea");
    
    var bg = rgba ("#000000", 0.0);

    
    Gdk.RGBA[] pal = {
      rgba ("#2e3436"), 
      rgba ("#ef2929"), 
      rgba ("#8ae234"), 
      rgba ("#fce94f"), 
      rgba ("#729fcf"), 
      rgba ("#ad7fa8"), 
      rgba ("#34e2e2"), 
      rgba ("#eeeeec"), 
      rgba ("#555753"), 
      rgba ("#ff5555"), 
      rgba ("#9aff6a"), 
      rgba ("#fff79a"), 
      rgba ("#8fc9ff"), 
      rgba ("#d7a7ff"), 
      rgba ("#7ffbff"), 
      rgba ("#ffffff")  
    };

    term.set_colors (fg, bg, pal);
    term.set_color_cursor (rgba ("#ffffff"));
    term.set_color_cursor_foreground (rgba ("#000000"));
    term.set_color_highlight (rgba ("#3a3a3a"));
    term.set_color_highlight_foreground (rgba ("#ffffff"));
  }

  private void setup_title_tracking () {
    
    term.termprop_changed.connect (on_termprop_changed);

    update_title_from_termprops_safe ();

    
    Timeout.add (1000, () => {
      if (title == "Terminal") title_changed (this);
      return false;
    });
  }

  private void on_termprop_changed (Vte.Terminal terminal, string prop) {
    if (terminal != term) {
      return;
    }

    if (prop == Vte.TERMPROP_CURRENT_DIRECTORY_URI || prop == Vte.TERMPROP_XTERM_TITLE) {
      update_title_from_termprops_safe ();
    }
  }

  private static string basename_from_path (string p) {
    var b = Path.get_basename (p);
    if (b == null) return "Terminal";
    b = b.strip ();
    return (b.length > 0) ? b : "Terminal";
  }

  private static string? basename_from_title_hint (string s) {
    
    
    int idx = s.last_index_of ("/");
    if (idx >= 0 && idx + 1 < s.length) {
      return basename_from_path (s.substring (idx + 1));
    }
    var cleaned = s.strip ();
    return cleaned.length > 0 ? cleaned : null;
  }

  private string? get_termprop_string_safe (string prop) {
    GLib.Value v;
    if (!term.get_termprop_value (prop, out v)) {
      return null;
    }
    if (v.holds (typeof (string))) {
      unowned string? s = v.get_string ();
      if (s != null && s.strip ().length > 0) {
        return s;
      }
    }
    return null;
  }

  private void update_title_from_termprops_safe () {
    
    {
      var uri = get_termprop_string_safe (Vte.TERMPROP_CURRENT_DIRECTORY_URI);
      if (uri != null) {
        var f = File.new_for_uri (uri);
        var p = f.get_path ();
        if (p != null && p.strip ().length > 0) {
          current_dir_full = p;
          title = basename_from_path (p);
          title_changed (this);
          return;
        }
      }
    }

    
    {
      var t = get_termprop_string_safe (Vte.TERMPROP_XTERM_TITLE);
      if (t != null) {
        var b = basename_from_title_hint (t);
        if (b != null) {
          title = b;
          title_changed (this);
          return;
        }
      }
    }

    
    title_changed (this);
  }

  private void setup_context_menu () {
    context_menu = new Gtk.Menu ();

    mi_new_session = new Gtk.MenuItem.with_label ("New Session");
    mi_copy = new Gtk.MenuItem.with_label ("Copy");
    mi_paste = new Gtk.MenuItem.with_label ("Paste");
    mi_close = new Gtk.MenuItem.with_label ("Close Session");

    mi_new_session.activate.connect (on_menu_new_session_activate);
    mi_copy.activate.connect (on_menu_copy_activate);
    mi_paste.activate.connect (on_menu_paste_activate);
    mi_close.activate.connect (on_menu_close_activate);

    context_menu.add (mi_new_session);
    context_menu.add (new Gtk.SeparatorMenuItem ());
    context_menu.add (mi_copy);
    context_menu.add (mi_paste);
    context_menu.add (new Gtk.SeparatorMenuItem ());
    context_menu.add (mi_close);

    context_menu.show_all ();

    term.button_press_event.connect (on_term_button_press);
  }

  private void on_menu_new_session_activate (Gtk.MenuItem item) {
    if (item != mi_new_session) {
      return;
    }
    request_new_session (this);
  }

  private void on_menu_copy_activate (Gtk.MenuItem item) {
    if (item != mi_copy) {
      return;
    }
    term.copy_clipboard_format (Vte.Format.TEXT);
  }

  private void on_menu_paste_activate (Gtk.MenuItem item) {
    if (item != mi_paste) {
      return;
    }
    term.paste_clipboard ();
  }

  private void on_menu_close_activate (Gtk.MenuItem item) {
    if (item != mi_close) {
      return;
    }
    request_close (this);
  }

  private bool on_term_button_press (Gtk.Widget widget, Gdk.EventButton ev) {
    if (widget != term) {
      return false;
    }

    if (ev.button == 3) {
      mi_copy.sensitive = term.get_has_selection ();
      context_menu.popup_at_pointer (ev);
      return true;
    }

    return false;
  }

  private void spawn_shell (string? cwd) {
    string shell = Environment.get_variable ("SHELL") ?? "/bin/bash";
    string[] argv = { shell, null };

    term.spawn_async (
      Vte.PtyFlags.DEFAULT,
      cwd,
      argv,
      null,
      (SpawnFlags) 0,
      null,
      -1,
      null,
      on_spawn_finished
    );
  }

  private void on_spawn_finished (Vte.Terminal terminal, GLib.Pid pid, GLib.Error? err) {
    if (terminal != term) {
      return;
    }

    if (err != null) {
      warning ("spawn error: %s", err.message);
      return;
    }

    if (pid != 0) {
    }
  }

  public void set_pseudo_transparency (bool enabled) {
    pseudo_transparency = enabled;
    apply_terminal_background_mode ();
    reload_root_background ();
    bg_area.queue_draw ();
  }

  
  public void set_opacity_percent (double percent) {
    if (percent < 0.0) percent = 0.0;
    if (percent > 1.0) percent = 1.0;

    tint_alpha = percent;
    bg_area.queue_draw ();
  }

  
  public void set_transparency_percent (double percent) {
    
    set_opacity_percent (percent);
  }

  public void reload_root_background () {
    if (!pseudo_transparency) {
      root_bg = null;
      return;
    }

    if (!NizamX11.is_x11 ()) {
      root_bg = null;
      return;
    }

    root_bg = get_root_background_cached ();
  }

  private static Gdk.Pixbuf? get_root_background_cached () {
    int64 now_ms = (int64)(GLib.get_monotonic_time () / 1000);
    if (shared_root_bg != null && (now_ms - shared_root_bg_ms) < 1000) {
      return shared_root_bg;
    }
    shared_root_bg = NizamX11.get_root_background ();
    shared_root_bg_ms = now_ms;
    return shared_root_bg;
  }

  private void apply_terminal_background_mode () {
    var bg = Gdk.RGBA();
    bg.red = 0.0;
    bg.green = 0.0;
    bg.blue = 0.0;
    
    
    bg.alpha = pseudo_transparency ? 0.0 : 1.0;
    term.set_color_background (bg);

    
    
    term.set_clear_background (!pseudo_transparency);
  }

  private bool on_bg_draw (Gtk.Widget widget, Cairo.Context cr) {
    int w = widget.get_allocated_width ();
    int h = widget.get_allocated_height ();

    
    cr.set_source_rgb (0, 0, 0);
    cr.rectangle (0, 0, w, h);
    cr.fill ();

    
    if (pseudo_transparency && root_bg != null) {
      int ox = 0;
      int oy = 0;
      var win = widget.get_window ();
      if (win != null) {
        win.get_origin (out ox, out oy);
      }

      cr.save ();
      cr.rectangle (0, 0, w, h);
      cr.clip ();
      Gdk.cairo_set_source_pixbuf (cr, root_bg, -ox, -oy);
      cr.paint ();
      cr.restore ();
    }

    
    cr.set_source_rgba (0, 0, 0, tint_alpha);
    cr.rectangle (0, 0, w, h);
    cr.fill ();

    return true;
  }

  private bool on_configure_event (Gtk.Widget widget, Gdk.EventConfigure event) {
    if (widget != this) {
      return false;
    }
    if (event.width > 0 && event.height > 0) {
      bg_area.queue_draw ();
    }
    return false;
  }
}
