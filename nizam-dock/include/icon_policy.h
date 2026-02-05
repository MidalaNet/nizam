#ifndef NIZAM_DOCK_ICON_POLICY_H
#define NIZAM_DOCK_ICON_POLICY_H

#include <stddef.h>

#define NIZAM_DOCK_ICON_PX 48
#define NIZAM_DOCK_ICON_SCALE 1
#define NIZAM_DOCK_ICON_CACHE_CAP 64

void nizam_dock_icon_normalize(const char *in, char *out, size_t out_len);

#endif
