#pragma once
#include "../trio_types.h"

// Future touch/tap action framework
// When Pebble touch support becomes available, this module
// will handle tap zones mapped to actions.

typedef struct {
    GRect zone;
    TapAction action;
    const char *label;
} TapZone;

void tap_framework_init(void);
void tap_framework_register_zone(GRect zone, TapAction action, const char *label);
void tap_framework_handle_tap(AccelAxisType axis, int32_t direction);
TapAction tap_framework_resolve(GPoint touch_point);
void tap_framework_send_action(TapAction action);
