// Face: Dashboard
// Information-dense layout showing all data in organized quadrants.
// Top-left: Glucose+trend+delta, Top-right: Time+date
// Center: Compact graph, Bottom: IOB/COB/Loop/Pump + complications

#include "face_dashboard.h"
#include "../modules/graph.h"
#include "../modules/complications.h"

static TextLayer *s_glucose, *s_trend, *s_delta, *s_time, *s_date;
static TextLayer *s_iob, *s_cob, *s_loop, *s_pump;
static Layer *s_graph_layer, *s_comp_layer, *s_divider_layer;
static char s_time_buf[8], s_date_buf[16], s_glucose_buf[16];
static char s_pump_buf[32];

static void graph_proc(Layer *layer, GContext *ctx) {
    graph_draw(layer, ctx, config_get());
}

static void comp_proc(Layer *layer, GContext *ctx) {
    GRect bounds = layer_get_bounds(layer);
    complications_draw_bar(ctx, bounds, app_state_get(), config_get());
}

static void divider_proc(Layer *layer, GContext *ctx) {
    GRect bounds = layer_get_bounds(layer);
    bool light = config_get()->color_scheme == COLOR_SCHEME_LIGHT;
#ifdef PBL_COLOR
    GColor line_color = light ? GColorLightGray : GColorDarkGray;
#else
    GColor line_color = GColorWhite;
    (void)light;
#endif
    graphics_context_set_stroke_color(ctx, line_color);
    // Horizontal line below glucose area
    graphics_draw_line(ctx, GPoint(0, 0), GPoint(bounds.size.w, 0));
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

void face_dashboard_load(Window *window, Layer *root, GRect bounds) {
    (void)window;
    int w = bounds.size.w;
    int h = bounds.size.h;
    bool light = config_get()->color_scheme == COLOR_SCHEME_LIGHT;
    GColor fg = light ? GColorBlack : GColorWhite;
    GColor fg2 = light ? GColorDarkGray : GColorLightGray;

    // Top-left: Glucose
    s_glucose = make_text(root, GRect(2, -4, w / 2, 38), FONT_KEY_BITHAM_30_BLACK, GTextAlignmentLeft, fg);
    text_layer_set_text(s_glucose, "--");

    s_trend = make_text(root, GRect(2, 28, w / 4, 16), FONT_KEY_GOTHIC_14_BOLD, GTextAlignmentLeft, fg2);
    s_delta = make_text(root, GRect(w / 4, 28, w / 4, 16), FONT_KEY_GOTHIC_14, GTextAlignmentLeft, fg2);

    // Top-right: Time & Date
    s_time = make_text(root, GRect(w / 2, 0, w / 2 - 4, 24), FONT_KEY_GOTHIC_24_BOLD, GTextAlignmentRight, fg);
    s_date = make_text(root, GRect(w / 2, 24, w / 2 - 4, 18), FONT_KEY_GOTHIC_14, GTextAlignmentRight, fg2);

    // Divider
    s_divider_layer = layer_create(GRect(0, 44, w, 1));
    layer_set_update_proc(s_divider_layer, divider_proc);
    layer_add_child(root, s_divider_layer);

    // Graph - center
    int graph_top = 46;
    int graph_h = h - graph_top - 50;
    s_graph_layer = layer_create(GRect(2, graph_top, w - 4, graph_h));
    layer_set_update_proc(s_graph_layer, graph_proc);
    layer_add_child(root, s_graph_layer);

    // Bottom data row
    int data_y = h - 50;
#ifdef PBL_COLOR
    s_iob = make_text(root, GRect(0, data_y, w / 2, 16), FONT_KEY_GOTHIC_14, GTextAlignmentCenter, GColorCyan);
    s_cob = make_text(root, GRect(w / 2, data_y, w / 2, 16), FONT_KEY_GOTHIC_14, GTextAlignmentCenter, GColorOrange);
#else
    s_iob = make_text(root, GRect(0, data_y, w / 2, 16), FONT_KEY_GOTHIC_14, GTextAlignmentCenter, fg);
    s_cob = make_text(root, GRect(w / 2, data_y, w / 2, 16), FONT_KEY_GOTHIC_14, GTextAlignmentCenter, fg);
#endif
    s_loop = make_text(root, GRect(0, data_y + 14, w / 2, 16), FONT_KEY_GOTHIC_14, GTextAlignmentCenter, fg2);
    s_pump = make_text(root, GRect(w / 2, data_y + 14, w / 2, 16), FONT_KEY_GOTHIC_14, GTextAlignmentCenter, fg2);

    // Complications bar at very bottom
    s_comp_layer = layer_create(GRect(0, h - 18, w, 18));
    layer_set_update_proc(s_comp_layer, comp_proc);
    layer_add_child(root, s_comp_layer);
}

void face_dashboard_unload(void) {
    text_layer_destroy(s_glucose);
    text_layer_destroy(s_trend);
    text_layer_destroy(s_delta);
    text_layer_destroy(s_time);
    text_layer_destroy(s_date);
    text_layer_destroy(s_iob);
    text_layer_destroy(s_cob);
    text_layer_destroy(s_loop);
    text_layer_destroy(s_pump);
    layer_destroy(s_graph_layer);
    layer_destroy(s_comp_layer);
    layer_destroy(s_divider_layer);
}

void face_dashboard_update(AppState *state) {
    time_t now = time(NULL);
    struct tm *t = localtime(&now);
    strftime(s_time_buf, sizeof(s_time_buf), "%H:%M", t);
    strftime(s_date_buf, sizeof(s_date_buf), "%a %b %d", t);
    text_layer_set_text(s_time, s_time_buf);
    text_layer_set_text(s_date, s_date_buf);

    snprintf(s_glucose_buf, sizeof(s_glucose_buf), "%s",
             state->cgm.glucose > 0 ? "" : "--");
    if (state->cgm.glucose > 0)
        snprintf(s_glucose_buf, sizeof(s_glucose_buf), "%d", state->cgm.glucose);
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
    text_layer_set_text(s_iob, state->loop.iob);
    text_layer_set_text(s_cob, state->loop.cob);
    text_layer_set_text(s_loop, state->loop.last_loop_time);

    snprintf(s_pump_buf, sizeof(s_pump_buf), "%s %s", state->loop.pump_status, state->loop.sensor_age);
    text_layer_set_text(s_pump, s_pump_buf);

    layer_mark_dirty(s_graph_layer);
    layer_mark_dirty(s_comp_layer);
}
