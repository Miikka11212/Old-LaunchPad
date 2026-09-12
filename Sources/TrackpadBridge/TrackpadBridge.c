#include "TrackpadBridge.h"
#include <dlfcn.h>
#include <stdbool.h>
#include <stddef.h>
#include <math.h>
#include <pthread.h>

// MultitouchSupport ABI documented by OpenMultitouchSupport (MIT).
// See ThirdParty/OpenMultitouchSupport-LICENSE.txt. The private framework is
// optional: resolve every symbol before using it, and fail without a listener.
typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint position, velocity; } MTVector;
typedef struct {
    int frame;
    double timestamp;
    int identifier, state, fingerId, handId;
    MTVector normalizedPosition;
    float total, pressure, angle, majorAxis, minorAxis;
    MTVector absolutePosition;
    int field14, field15;
    float density;
} MTTouch;
_Static_assert(sizeof(MTTouch) == 96, "Unexpected multitouch contact ABI");
typedef void (*MTCallback)(void *, MTTouch *, int, double, int);
static void *framework, *device;
static bool (*available)(void);
static void *(*createDevice)(void);
static int (*startDevice)(void *, int);
static int (*stopDevice)(void *);
static void (*releaseDevice)(void *);
static void (*registerCallback)(void *, MTCallback);
static void (*unregisterCallback)(void *, MTCallback);
static OLPContactCallback consumer;
static void *consumerContext;
static pthread_mutex_t consumerLock = PTHREAD_MUTEX_INITIALIZER;

static void receiveContacts(void *source, MTTouch *touches, int count, double timestamp, int frame) {
    (void)source; (void)frame;
    if (count < 0 || count > 16 || (count > 0 && !touches)) return;
    OLPContact contacts[16];
    int active = 0;
    for (int i = 0; i < count; i++) {
        if (touches[i].state != 3 && touches[i].state != 4) continue;
        MTPoint p = touches[i].normalizedPosition.position;
        if (!isfinite(p.x) || !isfinite(p.y) || p.x < 0 || p.x > 1 || p.y < 0 || p.y > 1) return;
        contacts[active++] = (OLPContact){touches[i].identifier, p.x, p.y};
    }
    pthread_mutex_lock(&consumerLock);
    if (consumer) consumer(contacts, active, timestamp, consumerContext);
    pthread_mutex_unlock(&consumerLock);
}

int32_t OLPStartTrackpad(OLPContactCallback callback, void *context) {
    if (device) return 0;
    if (!framework) framework = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY | RTLD_LOCAL);
    if (!framework) return -1;
    available = dlsym(framework, "MTDeviceIsAvailable");
    createDevice = dlsym(framework, "MTDeviceCreateDefault");
    startDevice = dlsym(framework, "MTDeviceStart");
    stopDevice = dlsym(framework, "MTDeviceStop");
    releaseDevice = dlsym(framework, "MTDeviceRelease");
    registerCallback = dlsym(framework, "MTRegisterContactFrameCallback");
    unregisterCallback = dlsym(framework, "MTUnregisterContactFrameCallback");
    if (!available || !createDevice || !startDevice || !stopDevice || !releaseDevice || !registerCallback || !unregisterCallback) return -2;
    if (!available() || !(device = createDevice())) return -3;
    pthread_mutex_lock(&consumerLock);
    consumer = callback;
    consumerContext = context;
    pthread_mutex_unlock(&consumerLock);
    registerCallback(device, receiveContacts);
    int status = startDevice(device, 0);
    if (status != 0) OLPStopTrackpad();
    return status;
}

void OLPStopTrackpad(void) {
    pthread_mutex_lock(&consumerLock);
    consumer = NULL;
    consumerContext = NULL;
    pthread_mutex_unlock(&consumerLock);
    if (!device) return;
    unregisterCallback(device, receiveContacts);
    stopDevice(device);
    releaseDevice(device);
    device = NULL;
}
