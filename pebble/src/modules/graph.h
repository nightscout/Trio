#pragma once
#include "../trio_types.h"

void graph_init(void);
void graph_deinit(void);
void graph_set_data(int16_t *values, int count);
void graph_set_predictions(int16_t *values, int count);
void graph_draw(Layer *layer, GContext *ctx, TrioConfig *config);
