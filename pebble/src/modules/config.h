#pragma once
#include "../trio_types.h"

void config_init(void);
void config_save(void);
void config_load(void);
void config_apply_message(DictionaryIterator *iter);
TrioConfig *config_get(void);
