#include "complications.h"

void complications_init(void) {
    // Register battery state handler
    complications_update_battery();
    complications_update_health();
}

void complications_update_battery(void) {
    AppState *state = app_state_get();
    BatteryChargeState batt = battery_state_service_peek();
    state->comp.watch_battery = batt.charge_percent;
    state->comp.watch_charging = batt.is_charging;
}

void complications_update_health(void) {
#if defined(PBL_HEALTH)
    AppState *state = app_state_get();
    state->comp.steps = (int32_t)health_service_sum_today(HealthMetricStepCount);
    HealthValue hr = health_service_peek_current_value(HealthMetricHeartRateBPM);
    state->comp.heart_rate = (hr > 0) ? (int16_t)hr : 0;
#endif
}

void complications_apply_message(DictionaryIterator *iter, AppState *state) {
    Tuple *t;

    t = dict_find(iter, KEY_BATTERY_PHONE);
    if (t) state->comp.phone_battery = (int8_t)t->value->int32;

    t = dict_find(iter, KEY_WEATHER_TEMP);
    if (t) state->comp.weather_temp = (int16_t)t->value->int32;

    t = dict_find(iter, KEY_WEATHER_ICON);
    if (t) {
        strncpy(state->comp.weather_icon, t->value->cstring, sizeof(state->comp.weather_icon) - 1);
    }

    t = dict_find(iter, KEY_STEPS);
    if (t) state->comp.steps = t->value->int32;

    t = dict_find(iter, KEY_HEART_RATE);
    if (t) state->comp.heart_rate = (int16_t)t->value->int32;
}

// Draws a compact complications bar
void complications_draw_bar(GContext *ctx, GRect area, AppState *state, TrioConfig *config) {
    (void)config;

    char buf[64];
    int x = area.origin.x + 2;
    int y = area.origin.y;
    int section_w = area.size.w / 4;

    GFont font = fonts_get_system_font(FONT_KEY_GOTHIC_14);

#ifdef PBL_COLOR
    GColor fg = (config->color_scheme == COLOR_SCHEME_LIGHT) ? GColorDarkGray : GColorLightGray;
#else
    GColor fg = GColorWhite;
#endif

    graphics_context_set_text_color(ctx, fg);

    // Watch battery
    if (state->comp.watch_charging) {
        snprintf(buf, sizeof(buf), "%d%%+", state->comp.watch_battery);
    } else {
        snprintf(buf, sizeof(buf), "%d%%", state->comp.watch_battery);
    }
    graphics_draw_text(ctx, buf, font, GRect(x, y, section_w, 16),
                       GTextOverflowModeTrailingEllipsis, GTextAlignmentLeft, NULL);

    // Steps
    if (state->comp.steps > 0) {
        if (state->comp.steps >= 10000) {
            snprintf(buf, sizeof(buf), "%dk", (int)(state->comp.steps / 1000));
        } else {
            snprintf(buf, sizeof(buf), "%d", (int)state->comp.steps);
        }
        graphics_draw_text(ctx, buf, font, GRect(x + section_w, y, section_w, 16),
                           GTextOverflowModeTrailingEllipsis, GTextAlignmentCenter, NULL);
    }

    // Heart rate
    if (state->comp.heart_rate > 0) {
        snprintf(buf, sizeof(buf), "%dbpm", state->comp.heart_rate);
        graphics_draw_text(ctx, buf, font, GRect(x + section_w * 2, y, section_w, 16),
                           GTextOverflowModeTrailingEllipsis, GTextAlignmentCenter, NULL);
    }

    // Weather
    if (state->comp.weather_temp != 0) {
        snprintf(buf, sizeof(buf), "%d°", state->comp.weather_temp);
        graphics_draw_text(ctx, buf, font, GRect(x + section_w * 3, y, section_w - 2, 16),
                           GTextOverflowModeTrailingEllipsis, GTextAlignmentRight, NULL);
    }
}
