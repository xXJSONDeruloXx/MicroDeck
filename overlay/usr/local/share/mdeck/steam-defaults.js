// Applies MicroDeck's Steam client settings through the UI's own settings protobuf
// (CMsgClientSettings, the message SteamClient.Settings.SetSetting takes as base64).
(() => {
  const want = {
    // The screensaver slideshow costs RAM a game needs, and its popup forces Big Picture opaque over games.
    screensaver_while_ingame: false,
    system_idle_screensaver_ac_sec: 0,
    system_idle_screensaver_battery_sec: 0,
  };
  const cur = settingsStore.clientSettings;
  const todo = Object.keys(want).filter(k => cur[k] !== want[k]);
  if (!todo.length) return "unchanged";
  let req;
  window.webpackChunksteamui.push([[Symbol("mdeck-defaults")], {}, r => { req = r; }]);
  let Msg = null, Writer = null;
  for (const id of Object.keys(req.m)) {
    let mod;
    try { mod = req(id); } catch (e) { continue; }
    if (!mod || typeof mod !== "object") continue;
    if (!Writer && mod.BinaryWriter) Writer = mod.BinaryWriter;
    for (const v of Object.values(mod)) {
      try {
        if (!Msg && v && v.fromObject && v.serializeBinaryToWriter && (String(v.toObject).includes("screensaver_while_ingame") || String(v).includes("screensaver_while_ingame"))) Msg = v;
      } catch (e) {}
    }
    if (Msg && Writer) break;
  }
  if (!Msg || !Writer) return "settings message not found";
  for (const k of todo) {
    const w = new Writer();
    Msg.serializeBinaryToWriter(Msg.fromObject({ [k]: want[k] }), w);
    SteamClient.Settings.SetSetting(w.getResultBase64String());
  }
  return "set " + todo.join(",");
})()
