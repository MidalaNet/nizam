using GLib;

int main (string[] args) {
    var req = NizamCommon.NizamGSettings.check_requirements();

    if (!req.schema_installed) {
        stderr.printf("Missing schema: %s\n", req.schema_id);
        stderr.printf("Install (Debian/Ubuntu): gsettings-desktop-schemas dconf-gsettings-backend dconf-service\n");
        return 1;
    }

    var gs = new NizamCommon.NizamGSettings();
    if (!gs.init_gtk_interface()) {
        stderr.printf("Failed to init GSettings for %s\n", req.schema_id);
        return 2;
    }

    
    stdout.printf("GLib: %s\n", req.glib_version);
    stdout.printf("Backend: %s\n", req.backend_hint);
    if (req.gsettings_cli_version.strip().length > 0) stdout.printf("gsettings: %s\n", req.gsettings_cli_version);
    if (req.dconf_cli_version.strip().length > 0) stdout.printf("dconf: %s\n", req.dconf_cli_version);

    stdout.printf("gtk-theme: %s\n", gs.get_gtk_theme());
    stdout.printf("icon-theme: %s\n", gs.get_icon_theme());
    stdout.printf("font-name: %s\n", gs.get_font_name());
    stdout.printf("cursor-theme: %s\n", gs.get_cursor_theme());
    stdout.printf("cursor-size: %d\n", gs.get_cursor_size());
    stdout.printf("enable-animations: %s\n", gs.get_enable_animations() ? "true" : "false");

    return 0;
}
