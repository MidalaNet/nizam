using Gtk;
using GLib;

namespace NizamText {
    public class TextDocument : Object {
        public string? path { get; private set; }
        public string title { get; private set; }
        public Gtk.TextBuffer buffer { get; private set; }
        public bool modified { get; private set; default = false; }
        public uint spell_timeout_id { get; set; default = 0; }

        public TextDocument (string? path, Gtk.TextBuffer buffer) {
            this.path = path;
            this.buffer = buffer;
            this.title = path != null ? Path.get_basename(path) : "Untitled";

            buffer.changed.connect(on_buffer_changed);
        }

        private void on_buffer_changed () {
            modified = buffer.get_modified();
        }

        public void update_path (string? new_path) {
            path = new_path;
            title = new_path != null ? Path.get_basename(new_path) : "Untitled";
        }
    }
}
