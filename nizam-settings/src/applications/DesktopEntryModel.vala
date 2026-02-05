using GLib;

namespace NizamSettings {
    public class DesktopEntry : Object {
        public string filename = "";
        
        public string name = "";
        public string exec = "";
        public string categories = "";

        
        public string system_name = "";
        public string system_exec = "";
        public string system_categories = "";

        
        public string user_name = "";
        public string user_exec = "";
        public string user_categories = "";
        public bool has_overrides = false;
        
        public string category = "System";
        public string icon = "";
        public bool managed = true;
        public bool enabled = true;
        public bool add_to_dock = false;
        public string source = "";
    }
}
