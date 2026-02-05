#include "panel_shared.h"

static void free_client_icons(void) {
    for (int i = 0; i < client_count; i++) {
        if (clients[i].icon) {
            cairo_surface_destroy(clients[i].icon);
            clients[i].icon = NULL;
        }
    }
}

static int get_wm_state(Window w, long *out_state) {
    Atom type;
    int fmt;
    unsigned long nitems, bytes;
    unsigned char *data = NULL;
    if (XGetWindowProperty(dpy, w, A_WM_STATE, 0, 2, False, A_WM_STATE,
                           &type, &fmt, &nitems, &bytes, &data) != Success) {
        return 0;
    }
    int ok = 0;
    if (data && type == A_WM_STATE && fmt == 32 && nitems >= 1) {
        *out_state = ((long *)data)[0];
        ok = 1;
    }
    if (data) XFree(data);
    return ok;
}

static int should_include_window(Window w) {
    XWindowAttributes attr;
    if (!XGetWindowAttributes(dpy, w, &attr)) return 0;
    if (attr.override_redirect) return 0;

    if (window_is_type(w, A_NET_WM_WINDOW_TYPE_DOCK) || window_is_type(w, A_NET_WM_WINDOW_TYPE_DESKTOP)) return 0;
    if (window_has_state(w, A_NET_WM_STATE_SKIP_TASKBAR)) return 0;

    long wm_state = 0;
    if (!get_wm_state(w, &wm_state)) return 0;
    if (wm_state != NormalState && wm_state != IconicState) return 0;

    return 1;
}

static int has_client_window(Window w) {
    for (int i = 0; i < client_count; i++) {
        if (clients[i].win == w) return 1;
    }
    return 0;
}

static Window find_client_window(Window w) {
    long wm_state = 0;
    if (get_wm_state(w, &wm_state)) {
        return w;
    }

    Window root_ret, parent_ret;
    Window *children = NULL;
    unsigned int nchildren = 0;
    if (!XQueryTree(dpy, w, &root_ret, &parent_ret, &children, &nchildren)) {
        return None;
    }
    Window found = None;
    for (unsigned int i = 0; i < nchildren; i++) {
        if (get_wm_state(children[i], &wm_state)) {
            found = children[i];
            break;
        }
    }
    if (children) XFree(children);
    return found;
}

static void add_client(Window w) {
    if (client_count >= MAX_WINDOWS) return;
    Window cw = find_client_window(w);
    if (cw == None) return;
    if (has_client_window(cw)) return;
    if (!should_include_window(cw)) return;

    XSelectInput(dpy, cw, PropertyChangeMask);

    ClientItem *c = &clients[client_count++];
    c->win = cw;
    c->is_active = 0;
    c->skip_taskbar = 0;
    c->icon = load_window_icon(cw, NIZAM_PANEL_ICON_PX);
    if (!c->icon) c->icon = load_window_icon_hint(cw, NIZAM_PANEL_ICON_PX);
    if (!c->icon) {
        char inst[64], klass[64], icon_name[256];
        get_window_class(cw, inst, sizeof(inst), klass, sizeof(klass));
        if (find_desktop_icon_for_class(inst, klass, icon_name, sizeof(icon_name))) {
            c->icon = load_icon_from_name(icon_name, NIZAM_PANEL_ICON_PX);
        }
    }
    get_window_title(cw, c->title, sizeof(c->title));
    if (c->title[0] == '\0') strcpy(c->title, "(untitled)");
}

static void append_clients_from_tree(void) {
    Window root_ret, parent_ret;
    Window *children = NULL;
    unsigned int nchildren = 0;
    if (!XQueryTree(dpy, root, &root_ret, &parent_ret, &children, &nchildren)) {
        return;
    }
    for (unsigned int i = 0; i < nchildren && client_count < MAX_WINDOWS; i++) {
        add_client(children[i]);
    }
    if (children) XFree(children);
}

void tasklist_update_clients(void) {
    free_client_icons();
    client_count = 0;
    

    Atom type;
    int fmt;
    unsigned long nitems, bytes;
    unsigned char *data = NULL;
    if (XGetWindowProperty(dpy, root, A_NET_CLIENT_LIST, 0, 4096, False, XA_WINDOW,
                           &type, &fmt, &nitems, &bytes, &data) != Success) {
        return;
    }
    if (!data || type != XA_WINDOW) {
        if (data) XFree(data);
        return;
    }

    Window *wins = (Window *)data;
    for (unsigned long i = 0; i < nitems && client_count < MAX_WINDOWS; i++) {
        add_client(wins[i]);
    }
    XFree(data);

    append_clients_from_tree();

    
    data = NULL;
    if (XGetWindowProperty(dpy, root, A_NET_ACTIVE_WINDOW, 0, 1, False, XA_WINDOW,
                           &type, &fmt, &nitems, &bytes, &data) == Success) {
        if (data && nitems == 1) {
            Window aw = *((Window *)data);
            if (aw != None && aw != 0) {
                for (int i = 0; i < client_count; i++) {
                    if (clients[i].win == aw) clients[i].is_active = 1;
                }
            }
        }
    }
    if (data) XFree(data);
}

void tasklist_update_active(void) {
    for (int i = 0; i < client_count; i++) clients[i].is_active = 0;

    Atom type;
    int fmt;
    unsigned long nitems, bytes;
    unsigned char *data = NULL;
    if (XGetWindowProperty(dpy, root, A_NET_ACTIVE_WINDOW, 0, 1, False, XA_WINDOW,
                           &type, &fmt, &nitems, &bytes, &data) == Success) {
        if (data && nitems == 1) {
            Window aw = *((Window *)data);
            if (aw != None && aw != 0) {
                for (int i = 0; i < client_count; i++) {
                    if (clients[i].win == aw) clients[i].is_active = 1;
                }
            }
        }
    }
    if (data) XFree(data);
}

void tasklist_draw(void) {
    if (!settings.taskbar_enabled) return;

    for (int i = 0; i < client_count; i++) {
        if (task_rects[i].w <= 0) continue;
        const char *bg = clients[i].is_active ? color_active : color_bg;
        const char *fg = clients[i].is_active ? color_active_text : color_fg;
        (void)bg;
        if (clients[i].icon) {
            draw_icon(clients[i].icon, task_icon_rects[i].x, task_icon_rects[i].y, NIZAM_PANEL_ICON_PX);
            draw_text_role(PANEL_TEXT_TITLE, clients[i].title, task_rects[i].x + 26, task_rects[i].y,
                      task_rects[i].w - 32, task_rects[i].h, fg, 0, 0);
        } else {
            draw_text_role(PANEL_TEXT_TITLE, clients[i].title, task_rects[i].x + 6, task_rects[i].y,
                      task_rects[i].w - 10, task_rects[i].h, fg, 0, 0);
        }
    }
}

int tasklist_handle_click(int x, int y) {
    if (!settings.taskbar_enabled) return 0;

    for (int i = 0; i < client_count; i++) {
        if (task_rects[i].w <= 0) continue;
        if (!point_in_rect(x, y, task_rects[i])) continue;
        if (clients[i].is_active) {
            iconify_window(clients[i].win);
        } else {
            send_active_window(clients[i].win);
        }
        return 1;
    }
    return 0;
}
