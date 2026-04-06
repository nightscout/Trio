#include "graph.h"

static int16_t s_values[MAX_GRAPH_POINTS];
static int s_count = 0;
static int16_t s_predictions[MAX_PREDICTIONS];
static int s_pred_count = 0;

#define GRAPH_MIN 40
#define GRAPH_MAX 400

void graph_init(void) {
    s_count = 0;
    s_pred_count = 0;
    memset(s_values, 0, sizeof(s_values));
    memset(s_predictions, 0, sizeof(s_predictions));
}

void graph_deinit(void) {
    s_count = 0;
    s_pred_count = 0;
}

void graph_set_data(int16_t *values, int count) {
    if (count > MAX_GRAPH_POINTS) count = MAX_GRAPH_POINTS;
    s_count = count;
    memcpy(s_values, values, count * sizeof(int16_t));
}

void graph_set_predictions(int16_t *values, int count) {
    if (count > MAX_PREDICTIONS) count = MAX_PREDICTIONS;
    s_pred_count = count;
    memcpy(s_predictions, values, count * sizeof(int16_t));
}

static int map_y(int glucose, int height) {
    int clamped = glucose;
    if (clamped < GRAPH_MIN) clamped = GRAPH_MIN;
    if (clamped > GRAPH_MAX) clamped = GRAPH_MAX;
    return height - ((clamped - GRAPH_MIN) * height / (GRAPH_MAX - GRAPH_MIN));
}

static GColor glucose_color(int glucose, TrioConfig *config) {
#ifdef PBL_COLOR
    if (glucose <= config->urgent_low) return GColorRed;
    if (glucose <= config->low_threshold) return GColorRed;
    if (glucose >= config->high_threshold + 60) return GColorRed;
    if (glucose >= config->high_threshold) return GColorOrange;
    return GColorGreen;
#else
    (void)glucose; (void)config;
    return GColorWhite;
#endif
}

static GColor bg_color(TrioConfig *config) {
    switch (config->color_scheme) {
        case COLOR_SCHEME_LIGHT: return GColorWhite;
        case COLOR_SCHEME_HIGH_CONTRAST: return GColorBlack;
        default: return GColorBlack;
    }
}

static GColor grid_color(TrioConfig *config) {
#ifdef PBL_COLOR
    switch (config->color_scheme) {
        case COLOR_SCHEME_LIGHT: return GColorLightGray;
        case COLOR_SCHEME_HIGH_CONTRAST: return GColorDarkGray;
        default: return GColorDarkGray;
    }
#else
    (void)config;
    return GColorDarkGray;
#endif
}

void graph_draw(Layer *layer, GContext *ctx, TrioConfig *config) {
    GRect bounds = layer_get_bounds(layer);
    int w = bounds.size.w;
    int h = bounds.size.h;

    // Background
    graphics_context_set_fill_color(ctx, bg_color(config));
    graphics_fill_rect(ctx, bounds, 0, GCornerNone);

    // Target range band
    int y_high = map_y(config->high_threshold, h);
    int y_low  = map_y(config->low_threshold, h);

#ifdef PBL_COLOR
    GColor range_color;
    switch (config->color_scheme) {
        case COLOR_SCHEME_LIGHT: range_color = GColorMintGreen; break;
        case COLOR_SCHEME_HIGH_CONTRAST: range_color = GColorDarkGreen; break;
        default: range_color = GColorIslamicGreen; break;
    }
    graphics_context_set_fill_color(ctx, range_color);
#else
    graphics_context_set_fill_color(ctx, GColorDarkGray);
#endif
    int band_h = y_low - y_high;
    if (band_h > 0) {
        graphics_fill_rect(ctx, GRect(0, y_high, w, band_h), 0, GCornerNone);
    }

    // Threshold lines (dashed effect via short segments)
    graphics_context_set_stroke_color(ctx, grid_color(config));
    for (int x = 0; x < w; x += 6) {
        graphics_draw_line(ctx, GPoint(x, y_high), GPoint(x + 3, y_high));
        graphics_draw_line(ctx, GPoint(x, y_low), GPoint(x + 3, y_low));
    }

    // Urgent low line
    int y_urgent = map_y(config->urgent_low, h);
#ifdef PBL_COLOR
    graphics_context_set_stroke_color(ctx, GColorRed);
#else
    graphics_context_set_stroke_color(ctx, GColorWhite);
#endif
    for (int x = 0; x < w; x += 4) {
        graphics_draw_line(ctx, GPoint(x, y_urgent), GPoint(x + 2, y_urgent));
    }

    // Hour markers on X axis
    graphics_context_set_stroke_color(ctx, grid_color(config));
    if (s_count > 12) {
        for (int hr = 12; hr < s_count; hr += 12) {
            int x = (hr * w) / (s_count > 1 ? s_count - 1 : 1);
            for (int y = 0; y < h; y += 6) {
                graphics_draw_pixel(ctx, GPoint(x, y));
            }
        }
    }

    if (s_count < 2) return;

    int spacing = (s_count > 1) ? w / (s_count - 1) : w;
    if (spacing < 1) spacing = 1;

    // Draw glucose line segments with color coding
    for (int i = 1; i < s_count; i++) {
        int x0 = (i - 1) * spacing;
        int y0 = map_y(s_values[i - 1], h);
        int x1 = i * spacing;
        int y1 = map_y(s_values[i], h);

        GColor seg = glucose_color(s_values[i], config);
        graphics_context_set_stroke_color(ctx, seg);
        graphics_context_set_stroke_width(ctx, 2);
        graphics_draw_line(ctx, GPoint(x0, y0), GPoint(x1, y1));
    }

    // Draw data points
    for (int i = 0; i < s_count; i++) {
        int x = i * spacing;
        int y = map_y(s_values[i], h);
        GColor dot = glucose_color(s_values[i], config);
        graphics_context_set_fill_color(ctx, dot);
        graphics_fill_circle(ctx, GPoint(x, y), 2);
    }

    // Draw predictions (dashed, different style)
    if (s_pred_count >= 2) {
        int pred_start_x = (s_count > 0) ? (s_count - 1) * spacing : 0;
        int pred_spacing = (w - pred_start_x) / (s_pred_count > 1 ? s_pred_count - 1 : 1);
        if (pred_spacing < 1) pred_spacing = 1;

#ifdef PBL_COLOR
        graphics_context_set_stroke_color(ctx, GColorCyan);
#else
        graphics_context_set_stroke_color(ctx, GColorLightGray);
#endif
        graphics_context_set_stroke_width(ctx, 1);

        for (int i = 1; i < s_pred_count; i++) {
            int x0 = pred_start_x + (i - 1) * pred_spacing;
            int y0 = map_y(s_predictions[i - 1], h);
            int x1 = pred_start_x + i * pred_spacing;
            int y1 = map_y(s_predictions[i], h);
            // Dashed: draw every other segment
            if (i % 2 == 0) {
                graphics_draw_line(ctx, GPoint(x0, y0), GPoint(x1, y1));
            }
        }
    }

    // Current value indicator line (rightmost point, horizontal)
    if (s_count > 0) {
        int last_y = map_y(s_values[s_count - 1], h);
        GColor last_color = glucose_color(s_values[s_count - 1], config);
        graphics_context_set_stroke_color(ctx, last_color);
        graphics_context_set_stroke_width(ctx, 1);
        graphics_draw_line(ctx, GPoint(w - 20, last_y), GPoint(w, last_y));
    }
}
