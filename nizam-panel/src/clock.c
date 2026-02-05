#include "panel_shared.h"

void clock_update_text(void) {
    time_t now = time(NULL);
    if (now == last_clock_tick) return;
    last_clock_tick = now;

    struct tm tm_now;
    if (!strcasecmp(settings.clock_timezone, "utc")) {
        gmtime_r(&now, &tm_now);
    } else {
        localtime_r(&now, &tm_now);
    }
    strftime(clock_text, sizeof(clock_text), settings.clock_format, &tm_now);
}

void clock_draw(void) {
    if (!settings.clock_enabled) return;
    draw_text_role(PANEL_TEXT_CLOCK, clock_text, clock_rect.x, clock_rect.y, clock_rect.w, clock_rect.h, color_fg, 1, 1);
}
