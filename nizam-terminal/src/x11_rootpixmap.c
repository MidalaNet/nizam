#include "x11_rootpixmap.h"

#include <X11/Xlib.h>
#include <X11/Xatom.h>

#include <cairo/cairo-xlib.h>

#include <gdk/gdkx.h>
#include <gdk/gdk.h>

bool nizam_gdk_is_x11(void) {
  GdkDisplay *dpy = gdk_display_get_default();
  if (!dpy) return false;
  return GDK_IS_X11_DISPLAY(dpy);
}

static Pixmap get_root_pixmap(Display *dpy, Window root) {
  Atom a_root = XInternAtom(dpy, "_XROOTPMAP_ID", True);
  Atom a_eset = XInternAtom(dpy, "ESETROOT_PMAP_ID", True);
  Atom type;
  int format;
  unsigned long nitems, bytes_after;
  unsigned char *data = NULL;

  Atom props[2];
  int prop_count = 0;
  if (a_root) props[prop_count++] = a_root;
  if (a_eset) props[prop_count++] = a_eset;

  for (int i = 0; i < prop_count; i++) {
    if (XGetWindowProperty(dpy, root, props[i], 0, 1, False, XA_PIXMAP,
                           &type, &format, &nitems, &bytes_after, &data) == Success) {
      if (type == XA_PIXMAP && format == 32 && nitems == 1 && data) {
        Pixmap pm = *(Pixmap*)data;
        XFree(data);
        return pm;
      }
    }
    if (data) {
      XFree(data);
      data = NULL;
    }
  }
  return None;
}

GdkPixbuf* nizam_x11_get_root_background(void) {
  if (!nizam_gdk_is_x11()) return NULL;

  GdkDisplay *gdk_dpy = gdk_display_get_default();
  Display *dpy = gdk_x11_display_get_xdisplay(gdk_dpy);
  if (!dpy) return NULL;

  int screen = DefaultScreen(dpy);
  Window root = RootWindow(dpy, screen);

  Pixmap pm = get_root_pixmap(dpy, root);
  if (pm != None) {
    Window dummy_root = None;
    int x = 0, y = 0;
    unsigned int w = 0, h = 0;
    unsigned int border = 0;
    unsigned int depth = 0;
    if (XGetGeometry(dpy, pm, &dummy_root, &x, &y, &w, &h, &border, &depth) &&
        w > 0 && h > 0) {
      Visual *visual = DefaultVisual(dpy, screen);
      cairo_surface_t *surface = cairo_xlib_surface_create(dpy, pm, visual, (int)w, (int)h);
      if (surface && cairo_surface_status(surface) == CAIRO_STATUS_SUCCESS) {
        GdkPixbuf *pb = gdk_pixbuf_get_from_surface(surface, 0, 0, (int)w, (int)h);
        cairo_surface_destroy(surface);
        if (pb) {
          return pb;
        }
      } else if (surface) {
        cairo_surface_destroy(surface);
      }
    }
  }

  XWindowAttributes attr;
  if (!XGetWindowAttributes(dpy, root, &attr)) return NULL;

  int w = attr.width;
  int h = attr.height;
  if (w <= 0 || h <= 0) return NULL;

  
  
  GdkWindow *root_win = gdk_get_default_root_window();
  if (!root_win) return NULL;

  
  GdkPixbuf *pb = gdk_pixbuf_get_from_window(root_win, 0, 0, w, h);
  return pb;
}
