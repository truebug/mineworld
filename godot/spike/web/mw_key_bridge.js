/* MineWorld Web — optional debug mirror of keys on window._mw_keys.
 * Actual input is handled in Godot via JavaScriptBridge document listeners
 * (single-thread Web export). This file stays for DevTools inspection.
 */
(function () {
  if (window._mwKeyBridge) return;
  window._mwKeyBridge = true;
  window._mw_keys = Object.create(null);

  function setKey(e, down) {
    window._mw_keys[e.code] = down;
  }

  document.addEventListener("keydown", function (e) { setKey(e, true); }, true);
  document.addEventListener("keyup", function (e) { setKey(e, false); }, true);
  window.addEventListener("blur", function () {
    window._mw_keys = Object.create(null);
  });
  console.log("[MW] key bridge installed on document");
})();
