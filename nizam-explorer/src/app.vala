using Gtk;
using GLib;

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

public class ExplorerApp : Gtk.Application {
    public ExplorerApp () {
        Object(application_id: "io.nizam.Explorer", flags: ApplicationFlags.DEFAULT_FLAGS);
    }

    protected override void startup () {
        base.startup ();

        
        var icons_dir = detect_nizam_common_icons_dir ();
        if (icons_dir != null) {
            Gtk.IconTheme.get_default ().append_search_path (icons_dir);
        }
    }

    protected override void activate () {
        Gtk.Window.set_default_icon_name("nizam");
        if (this.active_window == null) {
            new ExplorerWindow(this);
        }
        this.active_window.present();
    }
}

public int main (string[] args) {
    var app = new ExplorerApp();
    return app.run(args);
}
