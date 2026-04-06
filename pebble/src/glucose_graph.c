#include "glucose_graph.h"

static int s_graph_values[MAX_GRAPH_POINTS];
static int s_graph_count = 0;

#define TARGET_LOW   70
#define TARGET_HIGH  180
#define GRAPH_MIN    40
#define GRAPH_MAX    400

void glucose_graph_init(void) {
    s_graph_count = 0;
    memset(s_graph_values, 0, sizeof(s_graph_values));
}

void glucose_graph_deinit(void) {
    s_graph_count = 0;
}

void glucose_graph_set_data(int *values, int count) {
    if (count > MAX_GRAPH_POINTS) count = MAX_GRAPH_POINTS;
    s_graph_count = count;
    memcpy(s_graph_values, values, count * sizeof(int));
}

static int map_glucose_to_y(int glucose, int height) {
    if (glucose < GRAPH_MIN) glucose = GRAPH_MIN;
    if (glucose > GRAPH_MAX) glucose = GRAPH_MAX;
    int range = GRAPH_MAX - GRAPH_MIN;
    return height - ((glucose - GRAPH_MIN) * height / range);
}

static GColor color_for_glucose(int glucose) {
#ifdef PBL_COLOR
    if (glucose <= TARGET_LOW) return GColorRed;
    if (glucose >= TARGET_HIGH) return GColorOrange;
    return GColorGreen;
#else
    (void)glucose;
    return GColorWhite;
#endif
}

void glucose_graph_draw(Layer *layer, GContext *ctx) {
    GRect bounds = layer_get_bounds(layer);
    int w = bounds.size.w;
    int h = bounds.size.h;

    // Target range band
    int y_high = map_glucose_to_y(TARGET_HIGH, h);
    int y_low  = map_glucose_to_y(TARGET_LOW, h);

#ifdef PBL_COLOR
    graphics_context_set_fill_color(ctx, GColorDarkGreen);
#else
    graphics_context_set_fill_color(ctx, GColorDarkGray);
#endif
    graphics_fill_rect(ctx, GRect(0, y_high, w, y_low - y_high), 0, GCornerNone);

    if (s_graph_count < 2) return;

    int spacing = w / (s_graph_count - 1);
    if (spacing < 1) spacing = 1;

    for (int i = 1; i < s_graph_count; i++) {
        int x0 = (i - 1) * spacing;
        int y0 = map_glucose_to_y(s_graph_values[i - 1], h);
        int x1 = i * spacing;
        int y1 = map_glucose_to_y(s_graph_values[i], h);

        GColor seg_color = color_for_glucose(s_graph_values[i]);
        graphics_context_set_stroke_color(ctx, seg_color);
        graphics_context_set_stroke_width(ctx, 2);
        graphics_draw_line(ctx, GPoint(x0, y0), GPoint(x1, y1));
    }

    // Draw dots at each point
    for (int i = 0; i < s_graph_count; i++) {
        int x = i * spacing;
        int y = map_glucose_to_y(s_graph_values[i], h);
        GColor dot_color = color_for_glucose(s_graph_values[i]);
        graphics_context_set_fill_color(ctx, dot_color);
        graphics_fill_circle(ctx, GPoint(x, y), 2);
    }
}
