/*
 * Relays "listen" requests from content scripts to the native extension
 * handler, which writes them to Notchman's shared inbox and returns a
 * notchman:// URL that opens the app.
 */
(function () {
  "use strict";
  var api = globalThis.browser || globalThis.chrome;

  function enqueue(payload, action) {
    return api.runtime.sendNativeMessage("com.notchman.app", {
      action: "enqueue",
      listenAction: action || "read",
      payload: payload,
    });
  }

  api.runtime.onMessage.addListener(function (message, sender, sendResponse) {
    if (!message || message.type !== "notchman.listen") return false;
    enqueue(message.payload, message.action)
      .then(function (response) { sendResponse(response || { ok: false, error: "No response" }); })
      .catch(function (error) { sendResponse({ ok: false, error: String(error) }); });
    return true; // keep the channel open for the async response
  });

  globalThis.NotchmanBackground = { enqueue: enqueue };
})();
