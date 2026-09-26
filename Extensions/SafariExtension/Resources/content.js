/*
 * Adds a small "🎧 Listen" button under long messages on supported sites
 * (ChatGPT, Claude, Reddit). Tapping it sends only that message to Notchman.
 */
(function () {
  "use strict";
  var X = globalThis.NotchmanExtractors;
  if (!X || window.__notchmanContentInstalled) return;
  window.__notchmanContentInstalled = true;

  var api = globalThis.browser || globalThis.chrome;
  var host = location.hostname;
  var buttons = new WeakMap();

  function makeButton(block) {
    var button = document.createElement("button");
    button.type = "button";
    button.className = "notchman-listen";
    button.setAttribute("data-notchman-ignore", "");
    button.setAttribute("aria-label", "Listen with Notchman");
    button.innerHTML = '<span class="notchman-listen__icon" aria-hidden="true">🎧</span><span class="notchman-listen__label">Listen</span>';
    button.addEventListener("click", function (event) {
      event.preventDefault();
      event.stopPropagation();
      listen(block.element, button);
    });
    return button;
  }

  function place(button, block) {
    var anchor = block.anchor || block.element;
    var slot = anchor.getAttribute && anchor.getAttribute("slot");
    if (slot) button.setAttribute("slot", slot);
    if (block.site === "reddit") {
      anchor.insertAdjacentElement("afterend", button);
    } else {
      // Appending after existing children is the least disruptive spot inside React-managed trees.
      block.element.appendChild(button);
    }
  }

  function decorate() {
    X.listenableBlocks(document, host).forEach(function (block) {
      var existing = buttons.get(block.element);
      if (existing && existing.isConnected) return;
      var button = makeButton(block);
      buttons.set(block.element, button);
      place(button, block);
    });
  }

  function setState(button, state, label) {
    button.dataset.state = state;
    button.querySelector(".notchman-listen__label").textContent = label;
  }

  function listen(element, button) {
    // Re-extract at tap time so edits and late-loading content are included.
    var blocks = X.listenableBlocks(document, host);
    var block = blocks.filter(function (b) { return b.element === element; })[0];
    if (!block) return;

    setState(button, "sending", "Opening…");
    api.runtime.sendMessage({
      type: "notchman.listen",
      action: "read",
      payload: {
        url: location.href,
        title: block.title || document.title,
        messages: [block.text],
        focusIndex: 0,
        site: block.site,
      },
    }).then(function (response) {
      if (response && response.ok && response.url) {
        setState(button, "done", "Listening");
        window.location.href = response.url;
      } else {
        setState(button, "error", "Try again");
      }
    }).catch(function () {
      setState(button, "error", "Try again");
    }).finally(function () {
      setTimeout(function () { setState(button, "idle", "Listen"); }, 3000);
    });
  }

  var scheduled = null;
  function scheduleDecorate() {
    if (scheduled) clearTimeout(scheduled);
    scheduled = setTimeout(function () {
      scheduled = null;
      decorate();
    }, 700);
  }

  new MutationObserver(scheduleDecorate).observe(document.documentElement, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ["data-is-streaming", "class"],
  });
  decorate();
})();
