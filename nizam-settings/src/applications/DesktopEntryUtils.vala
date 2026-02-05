using GLib;

namespace NizamSettings {
    public class DesktopEntryUtils : Object {
        public static string sanitize_exec (string input) {
            if (input == null) return "";
            var sb = new StringBuilder();
            var s = input;
            for (int i = 0; i < s.length; i++) {
                var ch = s.get_char(i);
                if (ch == '%') {
                    
                    if (i + 1 < s.length) i++;
                    continue;
                }
                sb.append_unichar(ch);
            }
            return sb.str.strip();
        }

        private static string? map_category_token (string tok) {
            if (tok == null) return null;
            var t = tok.strip();
            if (t.length == 0) return null;

            
            if (t.casefold() == "development" || t.casefold() == "ide" || t.casefold() == "programming" ||
                t.casefold() == "debugger" || t.casefold() == "profiling" || t.casefold() == "revisioncontrol" ||
                t.casefold() == "translation") {
                return "Development";
            }

            
            if (t.casefold() == "game" || t.casefold() == "games") {
                return "Games";
            }

            
            if (t.casefold() == "graphics" || t.casefold() == "2dgraphics" || t.casefold() == "3dgraphics" ||
                t.casefold() == "photography" || t.casefold() == "rastergraphics" || t.casefold() == "vectorgraphics") {
                return "Graphics";
            }

            
            if (t.casefold() == "audiovideo" || t.casefold() == "audio" || t.casefold() == "video" ||
                t.casefold() == "player" || t.casefold() == "recorder" || t.casefold() == "music" ||
                t.casefold() == "tv") {
                return "Multimedia";
            }

            
            if (t.casefold() == "education" || t.casefold() == "science" || t.casefold() == "math" ||
                t.casefold() == "astronomy" || t.casefold() == "biology" || t.casefold() == "chemistry" ||
                t.casefold() == "physics" || t.casefold() == "geography" || t.casefold() == "history" ||
                t.casefold() == "office" || t.casefold() == "wordprocessor" || t.casefold() == "spreadsheet" ||
                t.casefold() == "presentation") {
                return "Office";
            }

            
            if (t.casefold() == "utility" || t.casefold() == "utilities" || t.casefold() == "accessories") {
                return "Utilities";
            }

            
            if (t.casefold() == "system" || t.casefold() == "settings" || t.casefold() == "preferences" ||
                t.casefold() == "monitor" || t.casefold() == "security" || t.casefold() == "packagemanager") {
                return "System";
            }

            
            if (t.casefold() == "network" || t.casefold() == "webbrowser" || t.casefold() == "email" ||
                t.casefold() == "chat" || t.casefold() == "ircclient" || t.casefold() == "filetransfer" ||
                t.casefold() == "p2p" || t.casefold() == "instantmessaging" || t.casefold() == "remoteaccess") {
                return "Network";
            }

            return null;
        }

        public static string pick_category_mapped (string categories) {
            
            if (categories == null || categories.strip().length == 0) return "System";

            foreach (var part in categories.split(";")) {
                var token = part.strip();
                if (token.length == 0) continue;
                var mapped = map_category_token(token);
                if (mapped != null) return mapped;
            }

            return "System";
        }

        public static string category_display_name (string category) {
            if (category == null || category.strip().length == 0) return "System";
            var c = category.strip();
            if (c.casefold() == "development") return "Development";
            if (c.casefold() == "games") return "Games";
            if (c.casefold() == "graphics") return "Graphics";
            if (c.casefold() == "multimedia") return "Multimedia";
            if (c.casefold() == "office") return "Learning";
            if (c.casefold() == "system") return "System";
            if (c.casefold() == "network") return "Network";
            if (c.casefold() == "utilities") return "Accessories";
            return "System";
        }
    }
}
