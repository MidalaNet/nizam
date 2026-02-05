#include <glib.h>
#include <gtk/gtk.h>

void nizam_glist_free_full(gpointer list, GDestroyNotify destroy)
{
    g_list_free_full((GList *) list, destroy);
}

GSubprocess* nizam_g_subprocess_newv(const gchar * const *argv, GSubprocessFlags flags, GError **error)
{
    return g_subprocess_newv(argv, flags, error);
}

void nizam_glist_free_fileinfo(gpointer list)
{
    g_list_free_full((GList *) list, g_object_unref);
}

void nizam_glist_free_treepath(gpointer list)
{
    g_list_free_full((GList *) list, (GDestroyNotify) gtk_tree_path_free);
}
