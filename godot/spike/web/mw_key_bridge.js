/* MineWorld Web key bridge — runs on the page main thread (not the Godot worker).
 * Godot multi-threaded builds cannot reliably attach document listeners from GDScript.
 */
(function () {
  if (window._mwKeyBridge) return;
  window._mwKeyBridge = true;
  window._mw_keys = Object.create(null);
  window._mw_pulse_take = "";
  window._mw_pulse_release = "";

  function setKey(e, down) {
    window._mw_keys[e.code] = down;
    if (down && !e.repeat) {
      if (e.code === "KeyT") window._mw_pulse_take = "1";
      if (e.code === "KeyR") window._mw_pulse_release = "1";
    }
    var block = [
      "KeyW", "KeyA", "KeyS", "KeyD", "KeyQ", "KeyE", "KeyT", "KeyR",
      "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Space",
    ];
    if (block.indexOf(e.code) >= 0) e.preventDefault();
  }

  document.addEventListener("keydown", function (e) { setKey(e, true); }, true);
  document.addEventListener("keyup", function (e) { setKey(e, false); }, true);
  window.addEventListener("blur", function () {
    window._mw_keys = Object.create(null);
  });
  console.log("[MW] key bridge installed on document");
})();
