using GLib;

namespace NizamSettings {
    public class DesktopEntryImporter : Object {
        private string sys_dir = "/usr/share/applications";

        public void import_system_apps () throws Error {
            var local_dir = DesktopEntryScanner.get_local_apps_dir();
            DirUtils.create_with_parents(local_dir, 0755);

            if (!FileUtils.test(sys_dir, FileTest.IS_DIR)) return;
            var d = Dir.open(sys_dir, 0);
            while (true) {
                var name = d.read_name();
                if (name == null) break;
                if (!name.has_suffix(".desktop")) continue;

                var src_path = Path.build_filename(sys_dir, name);
                var dst_path = Path.build_filename(local_dir, name);

                if (FileUtils.test(dst_path, FileTest.IS_REGULAR)) {
                    var dst_file = File.new_for_path(dst_path);
                    var existing = DesktopEntryIO.read(dst_file);
                    if (existing != null && existing.managed) {
                        continue; 
                    }
                    if (existing == null) {
                        
                        continue;
                    }
                    continue;
                }

                var src_file = File.new_for_path(src_path);
                var entry = DesktopEntryIO.read(src_file);
                if (entry == null) continue;

                entry.managed = true;
                entry.source = src_path;

                var dst_file = File.new_for_path(dst_path);
                DesktopEntryIO.write(dst_file, entry, false);

                
                try {
                    var kf = new KeyFile();
                    kf.load_from_file(dst_path, KeyFileFlags.NONE);
                    kf.set_string("Desktop Entry", "X-Nizam-Imported-At", ((int64) (new DateTime.now_utc()).to_unix()).to_string());
                    size_t len = 0;
                    var data = kf.to_data(out len);
                    FileUtils.set_contents(dst_path, data, (ssize_t) len);
                } catch (Error e) {
                    
                }
            }
        }
    }
}
