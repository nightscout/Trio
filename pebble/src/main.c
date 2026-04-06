// ============================================================
// Trio Pebble v2.0 - Premium CGM Watchface
// ============================================================
// Multi-face, multi-source, configurable CGM watchface with
// alerts, complications, and a future touch action framework.

#include <pebble.h>
#include "trio_types.h"
#include "modules/config.h"
#include "modules/graph.h"
#include "modules/alerts.h"
#include "modules/complications.h"
#include "modules/tap_framework.h"
#include "faces/face_classic.h"
#include "faces/face_graph_focus.h"
#include "faces/face_compact.h"
#include "faces/face_dashboard.h"
#include "faces/face_minimal.h"

// ---------- Global State ----------
static AppState s_state;
static Window *s_main_window;
static FaceType s_active_face = FACE_CLASSIC;

AppState *app_state_get(void) { return &s_state; }

// ---------- Face Registry ----------
static FaceDefinition s_faces[FACE_COUNT] = {
    [FACE_CLASSIC]     = { "Classic",     face_classic_load,     face_classic_unload,     face_classic_update },
    [FACE_GRAPH_FOCUS] = { "Graph Focus", face_graph_focus_load, face_graph_focus_unload, face_graph_focus_update },
    [FACE_COMPACT]     = { "Compact",     face_compact_load,     face_compact_unload,     face_compact_update },
    [FACE_DASHBOARD]   = { "Dashboard",   face_dashboard_load,   face_dashboard_unload,   face_dashboard_update },
    [FACE_MINIMAL]     = { "Minimal",     face_minimal_load,     face_minimal_unload,     face_minimal_update },
};

// ---------- Face Management ----------
static void load_active_face(Window *window) {
    Layer *root = window_get_root_layer(window);
    GRect bounds = layer_get_bounds(root);

    TrioConfig *cfg = config_get();
    bool light = cfg->color_scheme == COLOR_SCHEME_LIGHT;
    window_set_background_color(window, light ? GColorWhite : GColorBlack);

    FaceType ft = cfg->face_type;
    if (ft >= FACE_COUNT) ft = FACE_CLASSIC;

    s_faces[ft].load(window, root, bounds);
    s_active_face = ft;

    // Register tap zones for future touch support
    tap_framework_register_zone(GRect(0, 0, bounds.size.w, bounds.size.h / 2),
                                TAP_ACTION_REFRESH, "Refresh");
    tap_framework_register_zone(GRect(0, bounds.size.h / 2, bounds.size.w, bounds.size.h / 2),
                                TAP_ACTION_TOGGLE_FACE, "Toggle Face");
}

static void unload_active_face(void) {
    if (s_active_face < FACE_COUNT) {
        s_faces[s_active_face].unload();
    }
}

static void update_active_face(void) {
    if (s_active_face < FACE_COUNT) {
        s_faces[s_active_face].update(&s_state);
    }
}

static void reload_face(void) {
    if (!s_main_window) return;
    unload_active_face();

    // Remove all child layers from root before reloading
    Layer *root = window_get_root_layer(s_main_window);
    Layer *child = layer_get_first_child(root);
    while (child) {
        Layer *next = layer_get_next_sibling(child);
        layer_remove_from_parent(child);
        child = next;
    }

    tap_framework_init();
    load_active_face(s_main_window);
    update_active_face();
}

// ---------- AppMessage Handlers ----------
static void inbox_received(DictionaryIterator *iter, void *context) {
    (void)context;

    // Check for config changes first
    Tuple *config_changed = dict_find(iter, KEY_CONFIG_CHANGED);
    if (config_changed) {
        config_apply_message(iter);
        reload_face();
        return;
    }

    // Apply config keys that might come with data
    config_apply_message(iter);

    // CGM data
    Tuple *t;

    t = dict_find(iter, KEY_GLUCOSE);
    if (t) {
        s_state.cgm.glucose = (int16_t)t->value->int32;
        s_state.cgm.last_reading_time = time(NULL);
    }

    t = dict_find(iter, KEY_TREND);
    if (t) strncpy(s_state.cgm.trend_str, t->value->cstring, sizeof(s_state.cgm.trend_str) - 1);

    t = dict_find(iter, KEY_DELTA);
    if (t) strncpy(s_state.cgm.delta_str, t->value->cstring, sizeof(s_state.cgm.delta_str) - 1);

    t = dict_find(iter, KEY_GLUCOSE_STALE);
    if (t) s_state.cgm.is_stale = t->value->int32 != 0;

    // Loop data
    t = dict_find(iter, KEY_IOB);
    if (t) strncpy(s_state.loop.iob, t->value->cstring, sizeof(s_state.loop.iob) - 1);

    t = dict_find(iter, KEY_COB);
    if (t) strncpy(s_state.loop.cob, t->value->cstring, sizeof(s_state.loop.cob) - 1);

    t = dict_find(iter, KEY_LAST_LOOP);
    if (t) strncpy(s_state.loop.last_loop_time, t->value->cstring, sizeof(s_state.loop.last_loop_time) - 1);

    t = dict_find(iter, KEY_LOOP_STATUS);
    if (t) strncpy(s_state.loop.loop_status, t->value->cstring, sizeof(s_state.loop.loop_status) - 1);

    t = dict_find(iter, KEY_PUMP_STATUS);
    if (t) strncpy(s_state.loop.pump_status, t->value->cstring, sizeof(s_state.loop.pump_status) - 1);

    t = dict_find(iter, KEY_RESERVOIR);
    if (t) s_state.loop.reservoir = (int8_t)t->value->int32;

    t = dict_find(iter, KEY_PUMP_BATTERY);
    if (t) s_state.loop.pump_battery = (int8_t)t->value->int32;

    t = dict_find(iter, KEY_SENSOR_AGE);
    if (t) strncpy(s_state.loop.sensor_age, t->value->cstring, sizeof(s_state.loop.sensor_age) - 1);

    // Graph data
    Tuple *graph_data = dict_find(iter, KEY_GRAPH_DATA);
    Tuple *graph_count = dict_find(iter, KEY_GRAPH_COUNT);
    if (graph_data && graph_count) {
        int count = graph_count->value->int32;
        uint8_t *raw = graph_data->value->data;
        int actual = count < MAX_GRAPH_POINTS ? count : MAX_GRAPH_POINTS;
        int16_t values[MAX_GRAPH_POINTS];
        for (int i = 0; i < actual; i++) {
            values[i] = (int16_t)((int)raw[i * 2] | ((int)raw[i * 2 + 1] << 8));
        }
        graph_set_data(values, actual);
        s_state.graph.count = actual;
        memcpy(s_state.graph.values, values, actual * sizeof(int16_t));
    }

    // Predictions
    Tuple *pred_data = dict_find(iter, KEY_PREDICTIONS_DATA);
    Tuple *pred_count = dict_find(iter, KEY_PREDICTIONS_COUNT);
    if (pred_data && pred_count) {
        int count = pred_count->value->int32;
        uint8_t *raw = pred_data->value->data;
        int actual = count < MAX_PREDICTIONS ? count : MAX_PREDICTIONS;
        int16_t values[MAX_PREDICTIONS];
        for (int i = 0; i < actual; i++) {
            values[i] = (int16_t)((int)raw[i * 2] | ((int)raw[i * 2 + 1] << 8));
        }
        graph_set_predictions(values, actual);
    }

    // Complications from phone
    complications_apply_message(iter, &s_state);

    // Command status feedback
    t = dict_find(iter, KEY_CMD_STATUS);
    if (t) {
        // Could display a brief notification
        APP_LOG(APP_LOG_LEVEL_INFO, "Cmd status: %s", t->value->cstring);
    }

    // Update display
    update_active_face();

    // Check alerts
    alerts_check(&s_state);
}

static void inbox_dropped(AppMessageResult reason, void *context) {
    (void)context;
    APP_LOG(APP_LOG_LEVEL_ERROR, "Message dropped: %d", reason);
}

static void outbox_sent(DictionaryIterator *iter, void *context) {
    (void)iter; (void)context;
}

static void outbox_failed(DictionaryIterator *iter, AppMessageResult reason, void *context) {
    (void)iter; (void)context;
    APP_LOG(APP_LOG_LEVEL_ERROR, "Outbox failed: %d", reason);
}

// ---------- Timer & Tick ----------
static void tick_handler(struct tm *tick_time, TimeUnits units_changed) {
    (void)units_changed; (void)tick_time;

    // Update time display
    update_active_face();

    // Update local complications
    complications_update_battery();
    complications_update_health();

    // Request data every minute
    DictionaryIterator *iter;
    if (app_message_outbox_begin(&iter) == APP_MSG_OK) {
        dict_write_uint8(iter, 0, 0);
        app_message_outbox_send();
    }
}

// ---------- Accelerometer Tap (stand-in for future touch) ----------
static void accel_tap_handler(AccelAxisType axis, int32_t direction) {
    tap_framework_handle_tap(axis, direction);
}

// ---------- Battery Handler ----------
static void battery_handler(BatteryChargeState charge) {
    (void)charge;
    complications_update_battery();
    update_active_face();
}

// ---------- Button Handlers ----------
static void select_click(ClickRecognizerRef recognizer, void *context) {
    (void)recognizer; (void)context;
    // Snooze active alerts
    if (alerts_is_active(&s_state)) {
        alerts_snooze(&s_state);
        vibes_short_pulse();
    }
}

static void up_click(ClickRecognizerRef recognizer, void *context) {
    (void)recognizer; (void)context;
    // Cycle to previous face
    TrioConfig *cfg = config_get();
    cfg->face_type = (cfg->face_type == 0) ? FACE_COUNT - 1 : cfg->face_type - 1;
    config_save();
    reload_face();
}

static void down_click(ClickRecognizerRef recognizer, void *context) {
    (void)recognizer; (void)context;
    // Cycle to next face
    TrioConfig *cfg = config_get();
    cfg->face_type = (cfg->face_type + 1) % FACE_COUNT;
    config_save();
    reload_face();
}

static void click_config(void *context) {
    (void)context;
    window_single_click_subscribe(BUTTON_ID_SELECT, select_click);
    window_single_click_subscribe(BUTTON_ID_UP, up_click);
    window_single_click_subscribe(BUTTON_ID_DOWN, down_click);
}

// ---------- Window Handlers ----------
static void window_load(Window *window) {
    graph_init();
    load_active_face(window);
}

static void window_unload(Window *window) {
    (void)window;
    unload_active_face();
    graph_deinit();
}

// ---------- App Lifecycle ----------
static void init(void) {
    memset(&s_state, 0, sizeof(AppState));

    config_init();
    s_state.config = *config_get();
    alerts_init();
    complications_init();
    tap_framework_init();

    s_main_window = window_create();
    window_set_click_config_provider(s_main_window, click_config);
    window_set_window_handlers(s_main_window, (WindowHandlers){
        .load = window_load,
        .unload = window_unload,
    });
    window_stack_push(s_main_window, true);

    app_message_register_inbox_received(inbox_received);
    app_message_register_inbox_dropped(inbox_dropped);
    app_message_register_outbox_sent(outbox_sent);
    app_message_register_outbox_failed(outbox_failed);
    app_message_open(4096, 512);

    tick_timer_service_subscribe(MINUTE_UNIT, tick_handler);
    battery_state_service_subscribe(battery_handler);
    accel_tap_service_subscribe(accel_tap_handler);
}

static void deinit(void) {
    accel_tap_service_unsubscribe();
    battery_state_service_unsubscribe();
    tick_timer_service_unsubscribe();
    window_destroy(s_main_window);
}

int main(void) {
    init();
    app_event_loop();
    deinit();
}
