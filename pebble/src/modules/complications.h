#pragma once
#include "../trio_types.h"

void complications_init(void);
void complications_update_battery(void);
void complications_update_health(void);
void complications_apply_message(DictionaryIterator *iter, AppState *state);

void complications_draw_bar(GContext *ctx, GRect area, AppState *state, TrioConfig *config);
