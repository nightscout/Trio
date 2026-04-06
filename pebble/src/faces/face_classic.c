// Face: Classic
// Layout: Time top-right, large glucose center-top, trend+delta,
//         IOB/COB row, graph center, loop status, complications bar bottom.

#include "face_classic.h"
#include "../modules/graph.h"
#include "../modules/complications.h"

static TextLayer *s_time, *s_glucose, *s_trend, *s_delta;
static TextLayer *s_iob, *s_cob, *s_loop;
static Layer *s_graph_layer, *s_comp_layer;
static char s_time_buf[8], s_glucose_buf[16];

static void graph_proc(Layer *layer, GContext *ctx) {
    graph_draw(layer, ctx, config_get());
}

static void comp_proc(Layer *layer, GContext *ctx) {
    GRect bounds = layer_get_bounds(layer);
    complications_draw_bar(ctx, bounds, app_state_get(), config_get());
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

void face_classic_load(Window *window, Layer *root, GRect bounds) {
    (void)window;
    int w = bounds.size.w;
    int h = bounds.size.h;
    bool light = config_get()->color_scheme == COLOR_SCHEME_LIGHT;
    GColor fg = light ? GColorBlack : GColorWhite;
    GColor fg2 = light ? GColorDarkGray : GColorLightGray;

    // Row 0: Time (top-right)
    s_time = make_text(root, GRect(w - 58, 0, 56, 20), FONT_KEY_GOTHIC_18_BOLD, GTextAlignmentRight, fg2);

    // Row 0: Glucose (large, top-left)
    s_glucose = make_text(root, GRect(0, -4, w - 60, 42), FONT_KEY_BITHAM_34_MEDIUM_NUMBERS, GTextAlignmentCenter, fg);
    text_layer_set_text(s_glucose, "--");

    // Row 0: Trend (next to time)
    s_trend = make_text(root, GRect(w - 58, 18, 56, 22), FONT_KEY_GOTHIC_18, GTextAlignmentRight, fg2);

    // Row 1: Delta
    s_delta = make_text(root, GRect(0, 36, w / 2, 16), FONT_KEY_GOTHIC_14, GTextAlignmentCenter, fg2);

    // Row 1: IOB & COB
#ifdef PBL_COLOR
    s_iob = make_text(root, GRect(w / 2, 36, w / 4, 16), FONT_KEY_GOTHIC_14, GTextAlignmentCenter, GColorCyan);
    s_cob = make_text(root, GRect(3 * w / 4, 36, w / 4, 16), FONT_KEY_GOTHIC_14, GTextAlignmentCenter, GColorOrange);
#else
    s_iob = make_text(root, GRect(w / 2, 36, w / 4, 16), FONT_KEY_GOTHIC_14, GTextAlignmentCenter, fg);
    s_cob = make_text(root, GRect(3 * w / 4, 36, w / 4, 16), FONT_KEY_GOTHIC_14, GTextAlignmentCenter, fg);
#endif

    // Graph
    int graph_top = 54;
    int graph_h = h - graph_top - 34;
    s_graph_layer = layer_create(GRect(2, graph_top, w - 4, graph_h));
    layer_set_update_proc(s_graph_layer, graph_proc);
    layer_add_child(root, s_graph_layer);

    // Loop status
    s_loop = make_text(root, GRect(0, h - 34, w, 16), FONT_KEY_GOTHIC_14, GTextAlignmentCenter, fg2);

    // Complications bar
    s_comp_layer = layer_create(GRect(0, h - 18, w, 18));
    layer_set_update_proc(s_comp_layer, comp_proc);
    layer_add_child(root, s_comp_layer);
}

void face_classic_unload(void) {
    text_layer_destroy(s_time);
    text_layer_destroy(s_glucose);
    text_layer_destroy(s_trend);
    text_layer_destroy(s_delta);
    text_layer_destroy(s_iob);
    text_layer_destroy(s_cob);
    text_layer_destroy(s_loop);
    layer_destroy(s_graph_layer);
    layer_destroy(s_comp_layer);
}

void face_classic_update(AppState *state) {
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

    // Color glucose based on range
#ifdef PBL_COLOR
    if (state->cgm.glucose > 0) {
        TrioConfig *cfg = &state->config;
        GColor gc;
        if (state->cgm.glucose <= cfg->urgent_low) gc = GColorRed;
        else if (state->cgm.glucose <= cfg->low_threshold) gc = GColorRed;
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

    layer_mark_dirty(s_graph_layer);
    layer_mark_dirty(s_comp_layer);
}
