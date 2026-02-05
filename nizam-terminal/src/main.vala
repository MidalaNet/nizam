using Gtk;

private static string? detect_nizam_common_icons_dir () {
  
  var common_dir = GLib.Environment.get_variable ("NIZAM_COMMON_DIR");
  if (common_dir != null && common_dir != "") {
    var icons_dir = GLib.Path.build_filename (common_dir, "icons");
    if (GLib.FileUtils.test (icons_dir, GLib.FileTest.IS_DIR)) {
      return icons_dir;
    }
  }

  
  try {
    var exe = GLib.FileUtils.read_link ("/proc/self/exe");
    var dir = GLib.Path.get_dirname (exe);          
    dir = GLib.Path.get_dirname (dir);              
    dir = GLib.Path.get_dirname (dir);              
    dir = GLib.Path.get_dirname (dir);              
    var icons_dir = GLib.Path.build_filename (dir, "nizam-common", "icons");
    if (GLib.FileUtils.test (icons_dir, GLib.FileTest.IS_DIR)) {
      return icons_dir;
    }
  } catch (Error e) {
    
  }

  
  var cwd = GLib.Environment.get_current_dir ();
  var cwd_icons_dir = GLib.Path.build_filename (cwd, "nizam-common", "icons");
  if (GLib.FileUtils.test (cwd_icons_dir, GLib.FileTest.IS_DIR)) {
    return cwd_icons_dir;
  }

  return null;
}

public class NizamTerminalApp : Gtk.Application {
  public NizamTerminalApp () {
    Object (
      application_id: "org.nizam.Terminal",
      flags: ApplicationFlags.DEFAULT_FLAGS
    );
  }

  protected override void startup () {
    base.startup ();

    
    
    var icons_dir = detect_nizam_common_icons_dir ();
    if (icons_dir != null) {
      Gtk.IconTheme.get_default ().append_search_path (icons_dir);
    }

    
    Gtk.Window.set_default_icon_name ("nizam");
  }

  protected override void activate () {
    var win = new TerminalWindow (this);

    const string[] accel_new_session = { "<Primary><Shift>t", null };
    const string[] accel_close_session = { "<Primary><Shift>w", null };
    const string[] accel_prev_session = { "<Primary>Page_Up", null };
    const string[] accel_next_session = { "<Primary>Page_Down", null };

    this.set_accels_for_action ("win.new-session", accel_new_session);
    this.set_accels_for_action ("win.close-session", accel_close_session);
    this.set_accels_for_action ("win.prev-session", accel_prev_session);
    this.set_accels_for_action ("win.next-session", accel_next_session);

    win.present ();
  }
}

int main (string[] args) {
  Gtk.init (ref args);
  return new NizamTerminalApp ().run (args);
}
