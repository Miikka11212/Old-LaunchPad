#ifndef OLDLAUNCHPAD_TRACKPAD_BRIDGE_H
#define OLDLAUNCHPAD_TRACKPAD_BRIDGE_H
#include <stdint.h>

typedef struct { int32_t identifier; float x; float y; } OLPContact;
typedef void (*OLPContactCallback)(const OLPContact *, int32_t, double, void *);
// Reads the default trackpad without taking exclusive ownership of its input.
int32_t OLPStartTrackpad(OLPContactCallback callback, void *context);
void OLPStopTrackpad(void);
#endif
