// MicroDeck desktop mode: 1 GB of RAM and a 640x480 screen. Two content processes, small caches, idle tabs are unloaded.
pref("dom.ipc.processCount", 2);
pref("browser.tabs.unloadOnLowMemory", true);
pref("browser.cache.memory.capacity", 32768);
pref("browser.sessionhistory.max_total_viewers", 1);
pref("browser.sessionstore.max_tabs_undo", 1);
pref("browser.shell.checkDefaultBrowser", false);
pref("browser.aboutwelcome.enabled", false);
pref("datareporting.policy.dataSubmissionEnabled", false);
pref("toolkit.telemetry.enabled", false);
// Fission would give every site its own process; one shared web process plus the tab being used is what 1 GB can carry.
pref("fission.webContentIsolationStrategy", 0);
pref("dom.ipc.processCount.webIsolated", 1);
pref("dom.ipc.processPrelaunch.enabled", false);
