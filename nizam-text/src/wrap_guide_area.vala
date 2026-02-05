using Gtk;
using Pango;
using Gdk;

namespace NizamText {
    public class WrapGuideArea : Gtk.DrawingArea {
        private Gtk.TextView view;
        private int wrap_cols = 72;

        public WrapGuideArea (Gtk.TextView view) {
            this.view = view;
            set_halign(Gtk.Align.FILL);
            set_valign(Gtk.Align.FILL);
            set_hexpand(true);
            set_vexpand(true);
        }

        public void set_view (Gtk.TextView view) {
            this.view = view;
            queue_draw();
        }

        public void set_wrap_cols (int cols) {
            wrap_cols = cols;
            queue_draw();
        }

        private int char_width_px () {
            var ctx = view.get_pango_context();
            var layout = new Pango.Layout(ctx);
            layout.set_text("M", -1);
            int cw = 0, ch = 0;
            layout.get_pixel_size(out cw, out ch);
            return cw > 0 ? cw : 8;
        }

        private int cols_width_px (int cols) {
            if (view == null) return cols * 8;
            var ctx = view.get_pango_context();
            var layout = new Pango.Layout(ctx);
            layout.set_text(string.nfill(cols, 'M'), -1);
            int w = 0, h = 0;
            layout.get_pixel_size(out w, out h);
            if (w > 0) return w;
            return cols * char_width_px();
        }

        public override bool draw (Cairo.Context cr) {
            if (view == null) return false;
            var style = get_style_context();
            var fg = style.get_color(Gtk.StateFlags.NORMAL);

            var vstyle = view.get_style_context();
            Gtk.Border padding = vstyle.get_padding(Gtk.StateFlags.NORMAL);
            Gtk.Border border = vstyle.get_border(Gtk.StateFlags.NORMAL);

            int x = view.get_left_margin() + padding.left + border.left + cols_width_px(wrap_cols);

            Gtk.Allocation alloc;
            get_allocation(out alloc);
            cr.set_source_rgba(fg.red, fg.green, fg.blue, 0.35);
            cr.set_line_width(1.0);
            cr.move_to(x + 0.5, 0);
            cr.line_to(x + 0.5, alloc.height);
            cr.stroke();
            return true;
        }
    }
}
