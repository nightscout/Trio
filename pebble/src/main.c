#include <pebble.h>
#include "glucose_graph.h"

// AppMessage keys - must match package.json messageKeys
#define KEY_GLUCOSE        0
#define KEY_TREND          1
#define KEY_DELTA          2
#define KEY_IOB            3
#define KEY_COB            4
#define KEY_LAST_LOOP      5
#define KEY_GLUCOSE_STALE  6
#define KEY_CMD_TYPE       7
#define KEY_CMD_AMOUNT     8
#define KEY_CMD_STATUS     9
#define KEY_GRAPH_DATA    10
#define KEY_GRAPH_COUNT   11
#define KEY_LOOP_STATUS   12
#define KEY_UNITS         13
#define KEY_PUMP_STATUS   14
#define KEY_RESERVOIR     15

// Menu states
#define MENU_NONE    0
#define MENU_MAIN    1
#define MENU_BOLUS   2
#define MENU_CARBS   3

static Window *s_main_window;
static TextLayer *s_time_layer;
static TextLayer *s_glucose_layer;
static TextLayer *s_trend_layer;
static TextLayer *s_iob_layer;
static TextLayer *s_cob_layer;
static TextLayer *s_delta_layer;
static TextLayer *s_loop_status_layer;
static TextLayer *s_hint_layer;
static Layer *s_graph_layer;

static char s_glucose_buffer[16];
static char s_trend_buffer[8];
static char s_iob_buffer[32];
static char s_cob_buffer[32];
static char s_delta_buffer[16];
static char s_loop_buffer[32];
static char s_time_buffer[8];
static char s_hint_buffer[64];

static int s_menu_state = MENU_NONE;
static int s_bolus_tenths = 5;  // 0.5U default
static int s_carb_grams = 15;

static bool s_glucose_stale = true;

// Glucose alert thresholds (mg/dL)
#define ALERT_LOW   70
#define ALERT_HIGH  250

static void update_time() {
    time_t now = time(NULL);
    struct tm *t = localtime(&now);
    strftime(s_time_buffer, sizeof(s_time_buffer), "%H:%M", t);
    text_layer_set_text(s_time_layer, s_time_buffer);
}

static void trigger_glucose_alert(int glucose) {
    if (glucose > 0 && (glucose <= ALERT_LOW || glucose >= ALERT_HIGH)) {
        static const uint32_t vibe_pattern[] = {200, 100, 200, 100, 400};
        VibePattern pat = {
            .durations = vibe_pattern,
            .num_segments = ARRAY_LENGTH(vibe_pattern),
        };
        vibes_enact_custom_pattern(pat);
    }
}

static void update_hint_text() {
    switch (s_menu_state) {
        case MENU_NONE:
            snprintf(s_hint_buffer, sizeof(s_hint_buffer), "SELECT: menu");
            break;
        case MENU_MAIN:
            snprintf(s_hint_buffer, sizeof(s_hint_buffer), "UP:bolus DOWN:carbs BACK:exit");
            break;
        case MENU_BOLUS:
            snprintf(s_hint_buffer, sizeof(s_hint_buffer), "Bolus: %d.%dU  UP/DN:adj SEL:send",
                     s_bolus_tenths / 10, s_bolus_tenths % 10);
            break;
        case MENU_CARBS:
            snprintf(s_hint_buffer, sizeof(s_hint_buffer), "Carbs: %dg  UP/DN:adj SEL:send",
                     s_carb_grams);
            break;
    }
    text_layer_set_text(s_hint_layer, s_hint_buffer);
}

static void send_command(int type, int amount) {
    DictionaryIterator *iter;
    AppMessageResult result = app_message_outbox_begin(&iter);
    if (result == APP_MSG_OK) {
        dict_write_int32(iter, KEY_CMD_TYPE, type);
        dict_write_int32(iter, KEY_CMD_AMOUNT, amount);
        app_message_outbox_send();
        snprintf(s_hint_buffer, sizeof(s_hint_buffer), "Sent! Confirm on iPhone");
        text_layer_set_text(s_hint_layer, s_hint_buffer);
    }
}

static void select_click_handler(ClickRecognizerRef recognizer, void *context) {
    (void)recognizer; (void)context;
    switch (s_menu_state) {
        case MENU_NONE:
            s_menu_state = MENU_MAIN;
            break;
        case MENU_MAIN:
            break;
        case MENU_BOLUS:
            send_command(1, s_bolus_tenths);
            s_menu_state = MENU_NONE;
            break;
        case MENU_CARBS:
            send_command(2, s_carb_grams);
            s_menu_state = MENU_NONE;
            break;
    }
    update_hint_text();
}

static void up_click_handler(ClickRecognizerRef recognizer, void *context) {
    (void)recognizer; (void)context;
    switch (s_menu_state) {
        case MENU_MAIN:
            s_menu_state = MENU_BOLUS;
            break;
        case MENU_BOLUS:
            if (s_bolus_tenths < 100) s_bolus_tenths += 5;
            break;
        case MENU_CARBS:
            if (s_carb_grams < 150) s_carb_grams += 5;
            break;
        default:
            break;
    }
    update_hint_text();
}

static void down_click_handler(ClickRecognizerRef recognizer, void *context) {
    (void)recognizer; (void)context;
    switch (s_menu_state) {
        case MENU_MAIN:
            s_menu_state = MENU_CARBS;
            break;
        case MENU_BOLUS:
            if (s_bolus_tenths > 5) s_bolus_tenths -= 5;
            break;
        case MENU_CARBS:
            if (s_carb_grams > 5) s_carb_grams -= 5;
            break;
        default:
            break;
    }
    update_hint_text();
}

static void back_click_handler(ClickRecognizerRef recognizer, void *context) {
    (void)recognizer; (void)context;
    if (s_menu_state != MENU_NONE) {
        s_menu_state = MENU_NONE;
        update_hint_text();
    } else {
        window_stack_pop(true);
    }
}

static void click_config_provider(void *context) {
    (void)context;
    window_single_click_subscribe(BUTTON_ID_SELECT, select_click_handler);
    window_single_click_subscribe(BUTTON_ID_UP, up_click_handler);
    window_single_click_subscribe(BUTTON_ID_DOWN, down_click_handler);
    window_single_click_subscribe(BUTTON_ID_BACK, back_click_handler);
}

static void graph_update_proc(Layer *layer, GContext *ctx) {
    glucose_graph_draw(layer, ctx);
}

static void inbox_received_callback(DictionaryIterator *iterator, void *context) {
    (void)context;

    Tuple *glucose_tuple = dict_find(iterator, KEY_GLUCOSE);
    if (glucose_tuple) {
        int glucose = glucose_tuple->value->int32;
        snprintf(s_glucose_buffer, sizeof(s_glucose_buffer), "%d", glucose);
        text_layer_set_text(s_glucose_layer, s_glucose_buffer);
        trigger_glucose_alert(glucose);
    }

    Tuple *trend_tuple = dict_find(iterator, KEY_TREND);
    if (trend_tuple) {
        snprintf(s_trend_buffer, sizeof(s_trend_buffer), "%s", trend_tuple->value->cstring);
        text_layer_set_text(s_trend_layer, s_trend_buffer);
    }

    Tuple *delta_tuple = dict_find(iterator, KEY_DELTA);
    if (delta_tuple) {
        snprintf(s_delta_buffer, sizeof(s_delta_buffer), "%s", delta_tuple->value->cstring);
        text_layer_set_text(s_delta_layer, s_delta_buffer);
    }

    Tuple *iob_tuple = dict_find(iterator, KEY_IOB);
    if (iob_tuple) {
        snprintf(s_iob_buffer, sizeof(s_iob_buffer), "IOB:%s", iob_tuple->value->cstring);
        text_layer_set_text(s_iob_layer, s_iob_buffer);
    }

    Tuple *cob_tuple = dict_find(iterator, KEY_COB);
    if (cob_tuple) {
        snprintf(s_cob_buffer, sizeof(s_cob_buffer), "COB:%s", cob_tuple->value->cstring);
        text_layer_set_text(s_cob_layer, s_cob_buffer);
    }

    Tuple *loop_tuple = dict_find(iterator, KEY_LAST_LOOP);
    if (loop_tuple) {
        snprintf(s_loop_buffer, sizeof(s_loop_buffer), "Loop:%s", loop_tuple->value->cstring);
        text_layer_set_text(s_loop_status_layer, s_loop_buffer);
    }

    Tuple *stale_tuple = dict_find(iterator, KEY_GLUCOSE_STALE);
    if (stale_tuple) {
        s_glucose_stale = stale_tuple->value->int32 != 0;
    }

    Tuple *graph_data_tuple = dict_find(iterator, KEY_GRAPH_DATA);
    Tuple *graph_count_tuple = dict_find(iterator, KEY_GRAPH_COUNT);
    if (graph_data_tuple && graph_count_tuple) {
        int count = graph_count_tuple->value->int32;
        uint8_t *raw = graph_data_tuple->value->data;
        int values[MAX_GRAPH_POINTS];
        int actual_count = count < MAX_GRAPH_POINTS ? count : MAX_GRAPH_POINTS;
        for (int i = 0; i < actual_count; i++) {
            values[i] = (int)raw[i * 2] | ((int)raw[i * 2 + 1] << 8);
        }
        glucose_graph_set_data(values, actual_count);
        layer_mark_dirty(s_graph_layer);
    }

    Tuple *cmd_status_tuple = dict_find(iterator, KEY_CMD_STATUS);
    if (cmd_status_tuple) {
        snprintf(s_hint_buffer, sizeof(s_hint_buffer), "%s", cmd_status_tuple->value->cstring);
        text_layer_set_text(s_hint_layer, s_hint_buffer);
    }
}

static void inbox_dropped_callback(AppMessageResult reason, void *context) {
    (void)context;
    APP_LOG(APP_LOG_LEVEL_ERROR, "Message dropped: %d", reason);
}

static void outbox_sent_callback(DictionaryIterator *iterator, void *context) {
    (void)iterator; (void)context;
    APP_LOG(APP_LOG_LEVEL_INFO, "Outbox send success");
}

static void outbox_failed_callback(DictionaryIterator *iterator, AppMessageResult reason, void *context) {
    (void)iterator; (void)context;
    APP_LOG(APP_LOG_LEVEL_ERROR, "Outbox send failed: %d", reason);
}

static TextLayer *create_text_layer(GRect frame, const char *font_key, GTextAlignment align, GColor bg, GColor fg) {
    TextLayer *layer = text_layer_create(frame);
    text_layer_set_background_color(layer, bg);
    text_layer_set_text_color(layer, fg);
    text_layer_set_font(layer, fonts_get_system_font(font_key));
    text_layer_set_text_alignment(layer, align);
    return layer;
}

static void main_window_load(Window *window) {
    Layer *root = window_get_root_layer(window);
    GRect bounds = layer_get_bounds(root);
    int w = bounds.size.w;

    window_set_background_color(window, GColorBlack);

    // Time - top right
    s_time_layer = create_text_layer(GRect(w - 55, 0, 55, 20), FONT_KEY_GOTHIC_18, GTextAlignmentRight, GColorBlack, GColorWhite);
    layer_add_child(root, text_layer_get_layer(s_time_layer));

    // Glucose - large, center top
    s_glucose_layer = create_text_layer(GRect(0, 0, w - 55, 38), FONT_KEY_BITHAM_34_MEDIUM_NUMBERS, GTextAlignmentCenter, GColorBlack, GColorWhite);
    layer_add_child(root, text_layer_get_layer(s_glucose_layer));
    text_layer_set_text(s_glucose_layer, "--");

    // Trend arrow
    s_trend_layer = create_text_layer(GRect(w - 30, 18, 30, 22), FONT_KEY_GOTHIC_18, GTextAlignmentCenter, GColorBlack, GColorLightGray);
    layer_add_child(root, text_layer_get_layer(s_trend_layer));

    // Delta
    s_delta_layer = create_text_layer(GRect(0, 36, w / 3, 18), FONT_KEY_GOTHIC_14, GTextAlignmentCenter, GColorBlack, GColorLightGray);
    layer_add_child(root, text_layer_get_layer(s_delta_layer));

    // IOB
    s_iob_layer = create_text_layer(GRect(w / 3, 36, w / 3, 18), FONT_KEY_GOTHIC_14, GTextAlignmentCenter, GColorBlack, GColorCyan);
    layer_add_child(root, text_layer_get_layer(s_iob_layer));

    // COB
    s_cob_layer = create_text_layer(GRect(2 * w / 3, 36, w / 3, 18), FONT_KEY_GOTHIC_14, GTextAlignmentCenter, GColorBlack, GColorOrange);
    layer_add_child(root, text_layer_get_layer(s_cob_layer));

    // Graph layer
    int graph_y = 56;
    int graph_h = bounds.size.h - graph_y - 32;
    s_graph_layer = layer_create(GRect(2, graph_y, w - 4, graph_h));
    layer_set_update_proc(s_graph_layer, graph_update_proc);
    layer_add_child(root, s_graph_layer);
    glucose_graph_init();

    // Loop status
    s_loop_status_layer = create_text_layer(GRect(0, bounds.size.h - 32, w, 16), FONT_KEY_GOTHIC_14, GTextAlignmentCenter, GColorBlack, GColorLightGray);
    layer_add_child(root, text_layer_get_layer(s_loop_status_layer));

    // Hint / menu text
    s_hint_layer = create_text_layer(GRect(0, bounds.size.h - 16, w, 16), FONT_KEY_GOTHIC_14, GTextAlignmentCenter, GColorBlack, GColorDarkGray);
    layer_add_child(root, text_layer_get_layer(s_hint_layer));

    update_time();
    update_hint_text();
}

static void main_window_unload(Window *window) {
    (void)window;
    text_layer_destroy(s_time_layer);
    text_layer_destroy(s_glucose_layer);
    text_layer_destroy(s_trend_layer);
    text_layer_destroy(s_iob_layer);
    text_layer_destroy(s_cob_layer);
    text_layer_destroy(s_delta_layer);
    text_layer_destroy(s_loop_status_layer);
    text_layer_destroy(s_hint_layer);
    glucose_graph_deinit();
    layer_destroy(s_graph_layer);
}

static void tick_handler(struct tm *tick_time, TimeUnits units_changed) {
    (void)units_changed;
    update_time();
    // Request fresh data every minute
    DictionaryIterator *iter;
    if (app_message_outbox_begin(&iter) == APP_MSG_OK) {
        dict_write_uint8(iter, 0, 0);
        app_message_outbox_send();
    }
}

static void init(void) {
    s_main_window = window_create();
    window_set_click_config_provider(s_main_window, click_config_provider);
    window_set_window_handlers(s_main_window, (WindowHandlers){
        .load = main_window_load,
        .unload = main_window_unload,
    });
    window_stack_push(s_main_window, true);

    app_message_register_inbox_received(inbox_received_callback);
    app_message_register_inbox_dropped(inbox_dropped_callback);
    app_message_register_outbox_sent(outbox_sent_callback);
    app_message_register_outbox_failed(outbox_failed_callback);

    const int inbox_size = 2048;
    const int outbox_size = 256;
    app_message_open(inbox_size, outbox_size);

    tick_timer_service_subscribe(MINUTE_UNIT, tick_handler);
}

static void deinit(void) {
    window_destroy(s_main_window);
}

int main(void) {
    init();
    app_event_loop();
    deinit();
}
