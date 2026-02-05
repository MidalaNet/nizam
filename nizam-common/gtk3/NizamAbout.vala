using Gtk;

namespace NizamGtk3 {
    public class NizamAbout : Object {
        public static void show (
            Gtk.Window? parent,
            string program_name,
            string version,
            string comments,
            string logo_icon_name,
            string? website = null
        ) {
            var dlg = new Gtk.AboutDialog();
            if (parent != null) {
                dlg.transient_for = parent;
            }
            dlg.modal = true;
            dlg.program_name = program_name;
            dlg.version = version;
            dlg.comments = comments;

            if (website != null && website.strip().length > 0) {
                dlg.website = website;
            }

            
            var theme = Gtk.IconTheme.get_default();
            string chosen_icon = logo_icon_name;
            if (!theme.has_icon(chosen_icon)) {
                chosen_icon = "application-x-executable";
            }
            dlg.logo_icon_name = chosen_icon;
            try {
                dlg.logo = theme.load_icon(chosen_icon, 96, 0);
                if (dlg.logo != null) {
                    dlg.set_icon(dlg.logo);
                }
            } catch (Error e) {
                
            }

            dlg.run();
            dlg.destroy();
        }
    }
}
