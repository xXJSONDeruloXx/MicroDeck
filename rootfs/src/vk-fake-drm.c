// LD_PRELOAD shim for experiments: makes a Vulkan device without VK_EXT_physical_device_drm (llvmpipe)
// report it, so gamescope accepts the CPU renderer. The extension only identifies which DRM nodes a device
// belongs to; it adds no commands. Reports the first render node as the device's.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>

typedef struct { uint32_t sType; const void *pNext; } Base;
typedef struct { uint32_t sType; void *pNext; uint32_t hasPrimary, hasRender; int64_t primaryMajor, primaryMinor, renderMajor, renderMinor; } DrmProps;
typedef struct { char extensionName[256]; uint32_t specVersion; } ExtProps;
typedef struct {
  uint32_t sType; const void *pNext; uint32_t flags; uint32_t queueCreateInfoCount; const void *pQueueCreateInfos;
  uint32_t enabledLayerCount; const char *const *ppEnabledLayerNames; uint32_t enabledExtensionCount;
  const char *const *ppEnabledExtensionNames; const void *pEnabledFeatures;
} DeviceCreateInfo;

#define DRM_EXT "VK_EXT_physical_device_drm"
#define DRM_PROPS_STYPE 1000353000
#define VK_INCOMPLETE 5

static void *real(const char *name) { return dlsym(RTLD_NEXT, name); }

int vkEnumerateDeviceExtensionProperties(void *phys, const char *layer, uint32_t *count, ExtProps *props) {
  int (*fn)(void *, const char *, uint32_t *, ExtProps *) = real("vkEnumerateDeviceExtensionProperties");
  if (layer) return fn(phys, layer, count, props);
  uint32_t n = 0;
  fn(phys, NULL, &n, NULL);
  ExtProps *all = calloc(n + 1, sizeof *all);
  int r = fn(phys, NULL, &n, all);
  if (r) { free(all); return r; }
  int have = 0;
  for (uint32_t i = 0; i < n; i++) have |= !strcmp(all[i].extensionName, DRM_EXT);
  if (!have) { strcpy(all[n].extensionName, DRM_EXT); all[n].specVersion = 1; n++; }
  if (!props) { *count = n; free(all); return 0; }
  uint32_t out = *count < n ? *count : n;
  memcpy(props, all, out * sizeof *all);
  r = out < n ? VK_INCOMPLETE : 0;
  *count = out;
  free(all);
  return r;
}

static void fill_drm(const void *pnext) {
  struct stat st;
  for (const Base *b = pnext; b; b = (const Base *)b->pNext) {
    if (b->sType != DRM_PROPS_STYPE) continue;
    DrmProps *d = (DrmProps *)(uintptr_t)b;
    if (stat("/dev/dri/renderD128", &st) == 0) {
      d->hasRender = 1; d->renderMajor = major(st.st_rdev); d->renderMinor = minor(st.st_rdev);
    }
    if (stat("/dev/dri/card0", &st) == 0 || stat("/dev/dri/card1", &st) == 0) {
      d->hasPrimary = 1; d->primaryMajor = major(st.st_rdev); d->primaryMinor = minor(st.st_rdev);
    }
  }
}

void vkGetPhysicalDeviceProperties2(void *phys, Base *props) {
  void (*fn)(void *, Base *) = real("vkGetPhysicalDeviceProperties2");
  fn(phys, props);
  fill_drm(props->pNext);
}
void vkGetPhysicalDeviceProperties2KHR(void *phys, Base *props) {
  void (*fn)(void *, Base *) = real("vkGetPhysicalDeviceProperties2KHR");
  if (!fn) fn = real("vkGetPhysicalDeviceProperties2");
  fn(phys, props);
  fill_drm(props->pNext);
}

int vkCreateDevice(void *phys, const DeviceCreateInfo *ci, const void *alloc, void *dev) {
  int (*fn)(void *, const DeviceCreateInfo *, const void *, void *) = real("vkCreateDevice");
  DeviceCreateInfo copy = *ci;
  const char **names = calloc(ci->enabledExtensionCount + 1, sizeof *names);
  uint32_t n = 0;
  // Drop what the device lacks: gamescope's presentation backends ask for present_id/present_wait/hdr_metadata
  // outright, and llvmpipe fails the whole vkCreateDevice with VK_ERROR_EXTENSION_NOT_PRESENT.
  int (*enumerate)(void *, const char *, uint32_t *, ExtProps *) = real("vkEnumerateDeviceExtensionProperties");
  uint32_t have_n = 0;
  enumerate(phys, NULL, &have_n, NULL);
  ExtProps *have = calloc(have_n + 1, sizeof *have);
  enumerate(phys, NULL, &have_n, have);
  for (uint32_t i = 0; i < ci->enabledExtensionCount; i++) {
    const char *want = ci->ppEnabledExtensionNames[i];
    int found = 0;
    for (uint32_t j = 0; j < have_n && !found; j++) found = !strcmp(have[j].extensionName, want);
    if (found) names[n++] = want;
    else if (getenv("MDECK_VK_DEBUG")) fprintf(stderr, "vk-fake-drm: dropping %s\n", want);
  }
  free(have);
  copy.enabledExtensionCount = n;
  copy.ppEnabledExtensionNames = names;
  int r = fn(phys, &copy, alloc, dev);
  free(names);
  return r;
}

void *vkGetInstanceProcAddr(void *inst, const char *name) {
  void *(*fn)(void *, const char *) = real("vkGetInstanceProcAddr");
  if (!strcmp(name, "vkEnumerateDeviceExtensionProperties")) return vkEnumerateDeviceExtensionProperties;
  if (!strcmp(name, "vkGetPhysicalDeviceProperties2")) return vkGetPhysicalDeviceProperties2;
  if (!strcmp(name, "vkGetPhysicalDeviceProperties2KHR")) return vkGetPhysicalDeviceProperties2KHR;
  if (!strcmp(name, "vkCreateDevice")) return vkCreateDevice;
  return fn(inst, name);
}
