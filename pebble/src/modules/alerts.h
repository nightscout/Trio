#pragma once
#include "../trio_types.h"

void alerts_init(void);
void alerts_check(AppState *state);
void alerts_snooze(AppState *state);
bool alerts_is_active(AppState *state);
