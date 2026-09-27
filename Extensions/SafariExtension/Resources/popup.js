/*
 * Toolbar popup: "Listen to this page". Extracts the current page (selection,
 * site messages, or article text) and hands it to Notchman.
 */
(function () {
  "use strict";
  var api = globalThis.browser || globalThis.chrome;
  var button = document.getElementById("listen");
  var status = document.getElementById("status");

  function show(message) { status.textContent = message; }

  async function listen() {
    button.disabled = true;
    show("Reading page…");
    try {
      var tabs = await api.tabs.query({ active: true, currentWindow: true });
      var tab = tabs[0];
      await api.scripting.executeScript({ target: { tabId: tab.id }, files: ["extractors.js"] });
      var results = await api.scripting.executeScript({
        target: { tabId: tab.id },
        func: function () {
          var X = globalThis.NotchmanExtractors;
          return X ? X.extractPage(document, location, { selection: String(getSelection() || ""), window: window }) : null;
        },
      });
      var payload = results && results[0] && results[0].result;
      if (!payload) throw new Error("Nothing readable on this page.");

      var response = await api.runtime.sendNativeMessage("app.notchman", {
        action: "enqueue",
        listenAction: "read",
        payload: payload,
      });
      if (!response || !response.ok) throw new Error((response && response.error) || "Notchman didn't respond.");

      show("Opening Notchman…");
      await api.scripting.executeScript({
        target: { tabId: tab.id },
        func: function (url) { window.location.href = url; },
        args: [response.url],
      });
      window.close();
    } catch (error) {
      show(error && error.message ? error.message : String(error));
      button.disabled = false;
    }
  }

  button.addEventListener("click", listen);
})();
