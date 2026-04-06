// Face: Minimal
// Clean, elegant display with just glucose, trend, time.
// Perfect for everyday wear when you want a watch that
// happens to show glucose. Subtle and non-medical looking.

#include "face_minimal.h"
#include "../modules/graph.h"

static TextLayer *s_time, *s_glucose, *s_trend, *s_delta;
static Layer *s_sparkline_layer;
static char s_time_buf[8], s_glucose_buf[16];

static void sparkline_proc(Layer *layer, GContext *ctx) {
    // Draw a thin sparkline (last 12 points only)
    graph_draw(layer, ctx, config_get());
}

static TextLayer *make_text(Layer *root, GRect frame, const char *font_key, GTextAlignment align, GColor fg) {
    TextLayer *tl = text_layer_create(frame);
    text_layer_set_background_color(tl, GColorClear);
    text_layer_set_text_color(tl, fg);
    text_layer_set_font(tl, fonts_get_system_font(font_key));
    text_layer_set_text_alignment(tl, align);
    layer_add_child(root, text_layer_get_layer(tl));
    return tl;
}

void face_minimal_load(Window *window, Layer *root, GRect bounds) {
    (void)window;
    int w = bounds.size.w;
    int h = bounds.size.h;
    bool light = config_get()->color_scheme == COLOR_SCHEME_LIGHT;
    GColor fg = light ? GColorBlack : GColorWhite;
    GColor fg2 = light ? GColorDarkGray : GColorLightGray;

    // Large centered time
    s_time = make_text(root, GRect(0, h / 2 - 30, w, 40), FONT_KEY_BITHAM_34_MEDIUM_NUMBERS, GTextAlignmentCenter, fg);

    // Glucose above time, prominent but not huge
    s_glucose = make_text(root, GRect(0, h / 2 - 60, w, 30), FONT_KEY_GOTHIC_28_BOLD, GTextAlignmentCenter, fg);
    text_layer_set_text(s_glucose, "--");

    // Trend + delta below time
    s_trend = make_text(root, GRect(0, h / 2 + 10, w / 2, 20), FONT_KEY_GOTHIC_18, GTextAlignmentRight, fg2);
    s_delta = make_text(root, GRect(w / 2, h / 2 + 10, w / 2, 20), FONT_KEY_GOTHIC_18, GTextAlignmentLeft, fg2);

    // Thin sparkline at bottom
    s_sparkline_layer = layer_create(GRect(10, h - 30, w - 20, 24));
    layer_set_update_proc(s_sparkline_layer, sparkline_proc);
    layer_add_child(root, s_sparkline_layer);
}

void face_minimal_unload(void) {
    text_layer_destroy(s_time);
    text_layer_destroy(s_glucose);
    text_layer_destroy(s_trend);
    text_layer_destroy(s_delta);
    layer_destroy(s_sparkline_layer);
}

void face_minimal_update(AppState *state) {
    time_t now = time(NULL);
    struct tm *t = localtime(&now);
    strftime(s_time_buf, sizeof(s_time_buf), "%H:%M", t);
    text_layer_set_text(s_time, s_time_buf);

    if (state->cgm.glucose > 0) {
        snprintf(s_glucose_buf, sizeof(s_glucose_buf), "%d", state->cgm.glucose);
    } else {
        snprintf(s_glucose_buf, sizeof(s_glucose_buf), "--");
    }
    text_layer_set_text(s_glucose, s_glucose_buf);

#ifdef PBL_COLOR
    if (state->cgm.glucose > 0) {
        TrioConfig *cfg = &state->config;
        GColor gc;
        if (state->cgm.glucose <= cfg->low_threshold) gc = GColorRed;
        else if (state->cgm.glucose >= cfg->high_threshold) gc = GColorOrange;
        else gc = GColorGreen;
        text_layer_set_text_color(s_glucose, gc);
    }
#endif

    text_layer_set_text(s_trend, state->cgm.trend_str);
    text_layer_set_text(s_delta, state->cgm.delta_str);

    layer_mark_dirty(s_sparkline_layer);
}
