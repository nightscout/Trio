#include "tap_framework.h"

#define MAX_TAP_ZONES 8

static TapZone s_zones[MAX_TAP_ZONES];
static int s_zone_count = 0;

void tap_framework_init(void) {
    s_zone_count = 0;
    memset(s_zones, 0, sizeof(s_zones));
}

void tap_framework_register_zone(GRect zone, TapAction action, const char *label) {
    if (s_zone_count >= MAX_TAP_ZONES) return;
    s_zones[s_zone_count].zone = zone;
    s_zones[s_zone_count].action = action;
    s_zones[s_zone_count].label = label;
    s_zone_count++;
}

// Current: uses accelerometer tap as a stand-in for touch
// Cycles through: refresh -> toggle face on repeated taps
void tap_framework_handle_tap(AccelAxisType axis, int32_t direction) {
    (void)axis; (void)direction;
    // For now, a wrist flick triggers a data refresh
    tap_framework_send_action(TAP_ACTION_REFRESH);
}

// Future: resolves a touch point to an action
TapZone *tap_framework_find_zone(GPoint point) {
    for (int i = 0; i < s_zone_count; i++) {
        if (grect_contains_point(&s_zones[i].zone, &point)) {
            return &s_zones[i];
        }
    }
    return NULL;
}

TapAction tap_framework_resolve(GPoint touch_point) {
    TapZone *zone = tap_framework_find_zone(touch_point);
    return zone ? zone->action : TAP_ACTION_NONE;
}

void tap_framework_send_action(TapAction action) {
    if (action == TAP_ACTION_NONE) return;

    DictionaryIterator *iter;
    AppMessageResult result = app_message_outbox_begin(&iter);
    if (result == APP_MSG_OK) {
        dict_write_int32(iter, KEY_TAP_ACTION, (int32_t)action);
        app_message_outbox_send();
    }
}
