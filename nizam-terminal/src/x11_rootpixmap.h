#pragma once

#include <stdbool.h>
#include <gdk/gdk.h>
#include <gdk-pixbuf/gdk-pixbuf.h>

#ifdef __cplusplus
extern "C" {
#endif



GdkPixbuf* nizam_x11_get_root_background(void);


bool nizam_gdk_is_x11(void);

#ifdef __cplusplus
}
#endif
