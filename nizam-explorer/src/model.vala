using GLib;




public class FileItem : Object {
    public File file { get; construct; }
    public string name { get; construct; }
    public Icon? icon { get; construct; }
    public bool is_dir { get; construct; }
    public uint64 size { get; construct; }

    public FileItem (File file, string name, Icon? icon, bool is_dir, uint64 size) {
        Object(
            file: file,
            name: name,
            icon: icon,
            is_dir: is_dir,
            size: size
        );
    }
}

public class ExplorerModel : Object {
    public async FileItem[] list_children_async (File dir, bool dirs_only, bool show_hidden, Cancellable? cancellable) throws Error {
        FileItem[] items = {};
        var enumerator = yield dir.enumerate_children_async(
            "standard::name,standard::display-name,standard::type,standard::size,standard::icon",
            FileQueryInfoFlags.NONE,
            Priority.DEFAULT,
            cancellable
        );

        while (true) {
            var infos = yield enumerator.next_files_async(200, Priority.DEFAULT, cancellable);
            if (infos == null) break;
            for (unowned GLib.List<FileInfo>? l = infos; l != null; l = l.next) {
                var info = (FileInfo) l.data;
                var file_type = info.get_file_type();
                var is_dir = (file_type == FileType.DIRECTORY);
                if (dirs_only && !is_dir) continue;

                var raw_name = info.get_name();
                if (!show_hidden && raw_name != null && raw_name.has_prefix(".")) {
                    continue;
                }

                var name = info.get_display_name();
                if (name == null || name.length == 0) name = info.get_name();

                var child = dir.get_child(info.get_name());
                var icon = info.get_icon();
                var size = info.get_size();
                items += new FileItem(child, name, icon, is_dir, size);
            }
            
            infos = null;
        }

        enumerator.close(cancellable);
        sort_items(items);
        return items;
    }

    private static int compare_items (FileItem a, FileItem b) {
        if (a.is_dir != b.is_dir) return a.is_dir ? -1 : 1;
        return a.name.collate(b.name);
    }

    private static void sort_items (FileItem[] items) {
        for (int i = 0; i < items.length; i++) {
            for (int j = i + 1; j < items.length; j++) {
                if (compare_items(items[i], items[j]) > 0) {
                    var tmp = items[i];
                    items[i] = items[j];
                    items[j] = tmp;
                }
            }
        }
    }
}
