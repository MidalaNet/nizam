using Gtk;
using Pango;
using Gdk;

namespace NizamText {
    public class LineNumberArea : Gtk.DrawingArea {
        private Gtk.TextView view;
        private Gtk.ScrolledWindow scroller;
        private Pango.Layout layout;
        private int last_digits = 0;
        private Gtk.TextBuffer? buffer = null;
        private ulong buffer_changed_id = 0;
        private bool align_right = true;

        public LineNumberArea (Gtk.TextView view, Gtk.ScrolledWindow scroller, bool align_right = true) {
            this.view = view;
            this.scroller = scroller;
            this.align_right = align_right;
            this.layout = create_pango_layout("");

            var adj = scroller.get_vadjustment();
            if (adj != null) {
                adj.value_changed.connect(() => { queue_draw(); });
            }

            attach_buffer(view.buffer);

            update_width();
        }

        public void set_view (Gtk.TextView view) {
            this.view = view;
            this.layout = create_pango_layout("");
            attach_buffer(view.buffer);
            update_width();
            queue_draw();
        }

        public void set_align_right (bool align_right) {
            this.align_right = align_right;
            queue_draw();
        }

        private void attach_buffer (Gtk.TextBuffer buf) {
            if (buffer != null && buffer_changed_id != 0) {
                buffer.disconnect(buffer_changed_id);
            }
            buffer = buf;
            buffer_changed_id = buffer.changed.connect(() => {
                update_width();
                queue_draw();
            });
        }

        private void update_width () {
            var buf = view.buffer;
            int lines = buf.get_line_count();
            int digits = lines.to_string().length;
            if (digits < 2) digits = 2;
            if (digits == last_digits) return;
            last_digits = digits;

            var sb = new StringBuilder();
            for (int i = 0; i < digits; i++) sb.append("0");
            layout.set_text(sb.str, -1);
            int w = 0, h = 0;
            layout.get_pixel_size(out w, out h);
            set_size_request(w + 12, -1);
        }

        public override bool draw (Cairo.Context cr) {
            var style = get_style_context();
            Gtk.Allocation alloc;
            get_allocation(out alloc);
            style.render_background(cr, 0, 0, alloc.width, alloc.height);

            Gdk.Rectangle visible;
            view.get_visible_rect(out visible);

            Gtk.TextIter iter;
            view.get_iter_at_location(out iter, visible.x, visible.y);

            while (true) {
                int line = iter.get_line();
                int line_y = 0;
                int line_h = 0;
                view.get_line_yrange(iter, out line_y, out line_h);
                if (line_y > visible.y + visible.height) break;

                layout.set_text((line + 1).to_string(), -1);
                int tw = 0, th = 0;
                layout.get_pixel_size(out tw, out th);

                int draw_y = line_y - visible.y + (line_h - th) / 2;
                int draw_x = align_right ? (alloc.width - tw - 6) : 6;

                style.render_layout(cr, draw_x, draw_y, layout);

                if (!iter.forward_line()) break;
                if (line_y + line_h > visible.y + visible.height) break;
            }

            return true;
        }
    }
}
