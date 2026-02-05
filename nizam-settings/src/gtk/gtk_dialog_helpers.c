#include <gtk/gtk.h>

GtkBox* nizam_gtk_dialog_get_content_area_box (GtkDialog* dlg) {
	return GTK_BOX (gtk_dialog_get_content_area (dlg));
}
