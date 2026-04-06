#pragma once
#include <pebble.h>

// ============================================================
// Trio Pebble - Shared Types & Constants
// ============================================================

#define APP_VERSION "2.0.0"
#define MAX_GRAPH_POINTS 48
#define MAX_PREDICTIONS 24

// ---------- AppMessage Keys ----------
// Must match package.json messageKeys
typedef enum {
    KEY_GLUCOSE = 0,
    KEY_TREND,
    KEY_DELTA,
    KEY_IOB,
    KEY_COB,
    KEY_LAST_LOOP,
    KEY_GLUCOSE_STALE,
    KEY_CMD_TYPE,
    KEY_CMD_AMOUNT,
    KEY_CMD_STATUS,
    KEY_GRAPH_DATA,
    KEY_GRAPH_COUNT,
    KEY_LOOP_STATUS,
    KEY_UNITS,
    KEY_PUMP_STATUS,
    KEY_RESERVOIR,
    // v2 keys
    KEY_CONFIG_FACE_TYPE,
    KEY_CONFIG_DATA_SOURCE,
    KEY_CONFIG_HIGH_THRESHOLD,
    KEY_CONFIG_LOW_THRESHOLD,
    KEY_CONFIG_ALERT_HIGH_ENABLED,
    KEY_CONFIG_ALERT_LOW_ENABLED,
    KEY_CONFIG_ALERT_URGENT_LOW,
    KEY_CONFIG_ALERT_SNOOZE_MIN,
    KEY_CONFIG_COLOR_SCHEME,
    KEY_BATTERY_PHONE,
    KEY_WEATHER_TEMP,
    KEY_WEATHER_ICON,
    KEY_STEPS,
    KEY_HEART_RATE,
    KEY_PREDICTIONS_DATA,
    KEY_PREDICTIONS_COUNT,
    KEY_PUMP_BATTERY,
    KEY_SENSOR_AGE,
    KEY_CONFIG_CHANGED,
    KEY_TAP_ACTION,
    KEY_COUNT
} AppMessageKey;

// ---------- Data Source ----------
typedef enum {
    DATA_SOURCE_TRIO = 0,
    DATA_SOURCE_DEXCOM_SHARE,
    DATA_SOURCE_NIGHTSCOUT
} DataSource;

// ---------- Face Type ----------
typedef enum {
    FACE_CLASSIC = 0,
    FACE_GRAPH_FOCUS,
    FACE_COMPACT,
    FACE_DASHBOARD,
    FACE_MINIMAL,
    FACE_COUNT
} FaceType;

// ---------- Color Scheme ----------
typedef enum {
    COLOR_SCHEME_DARK = 0,
    COLOR_SCHEME_LIGHT,
    COLOR_SCHEME_HIGH_CONTRAST,
    COLOR_SCHEME_COUNT
} ColorScheme;

// ---------- Trend Direction ----------
typedef enum {
    TREND_NONE = 0,
    TREND_DOUBLE_UP,
    TREND_SINGLE_UP,
    TREND_FORTY_FIVE_UP,
    TREND_FLAT,
    TREND_FORTY_FIVE_DOWN,
    TREND_SINGLE_DOWN,
    TREND_DOUBLE_DOWN,
    TREND_NOT_COMPUTABLE
} TrendDirection;

// ---------- Tap Action (future touch framework) ----------
typedef enum {
    TAP_ACTION_NONE = 0,
    TAP_ACTION_OPEN_CARBS,
    TAP_ACTION_OPEN_BOLUS,
    TAP_ACTION_OPEN_TEMP_BASAL,
    TAP_ACTION_REFRESH,
    TAP_ACTION_TOGGLE_FACE
} TapAction;

// ---------- Configuration ----------
typedef struct {
    FaceType face_type;
    DataSource data_source;
    ColorScheme color_scheme;
    int16_t high_threshold;     // mg/dL
    int16_t low_threshold;      // mg/dL
    int16_t urgent_low;         // mg/dL
    bool alert_high_enabled;
    bool alert_low_enabled;
    uint8_t alert_snooze_min;
    bool show_complications;
    bool is_mmol;               // derived from KEY_UNITS
} TrioConfig;

// ---------- CGM State ----------
typedef struct {
    int16_t glucose;
    TrendDirection trend;
    char trend_str[8];
    char delta_str[16];
    bool is_stale;
    char units[8];
    time_t last_reading_time;
} CGMState;

// ---------- Loop State ----------
typedef struct {
    char iob[16];
    char cob[16];
    char last_loop_time[16];
    char loop_status[32];
    char pump_status[16];
    int8_t reservoir;           // percentage or units
    int8_t pump_battery;        // percentage
    char sensor_age[16];
} LoopState;

// ---------- Complications ----------
typedef struct {
    int8_t phone_battery;       // 0-100
    int16_t weather_temp;       // degrees
    char weather_icon[8];       // icon code
    int32_t steps;
    int16_t heart_rate;
    uint8_t watch_battery;      // 0-100
    bool watch_charging;
} Complications;

// ---------- Graph Data ----------
typedef struct {
    int16_t values[MAX_GRAPH_POINTS];
    int count;
    int16_t predictions[MAX_PREDICTIONS];
    int prediction_count;
} GraphData;

// ---------- Alert State ----------
typedef struct {
    bool high_active;
    bool low_active;
    bool urgent_low_active;
    time_t last_alert_time;
    time_t snooze_until;
} AlertState;

// ---------- Full App State ----------
typedef struct {
    TrioConfig config;
    CGMState cgm;
    LoopState loop;
    Complications comp;
    GraphData graph;
    AlertState alerts;
} AppState;

// ---------- Face Render Interface ----------
typedef void (*FaceLoadFunc)(Window *window, Layer *root, GRect bounds);
typedef void (*FaceUnloadFunc)(void);
typedef void (*FaceUpdateFunc)(AppState *state);

typedef struct {
    const char *name;
    FaceLoadFunc load;
    FaceUnloadFunc unload;
    FaceUpdateFunc update;
} FaceDefinition;

// ---------- Globals ----------
AppState *app_state_get(void);
TrioConfig *config_get(void);
