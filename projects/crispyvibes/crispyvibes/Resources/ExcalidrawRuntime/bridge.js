// F052: mounts the offline Excalidraw canvas and bridges it to Swift.
// Externalized from index.html so the page CSP needs no `script-src
// 'unsafe-inline'`. Loaded after React/ReactDOM/Excalidraw UMD bundles.
(function () {
  "use strict";

  var api = null;             // ExcalidrawImperativeAPI once mounted
  var ready = false;
  var suppressChange = false; // true while we apply a Swift-pushed scene
  var lastSerialized = "";    // last JSON sent to / received from Swift (echo guard)
  var pendingScene = null;    // scene pushed before the API was ready
  var saveTimer = null;
  var setThemeExternal = null;

  function send(name, payload) {
    try { window.webkit.messageHandlers[name].postMessage(payload); } catch (e) { /* not hosted */ }
  }
  function log(msg) { send("whiteboardLog", String(msg)); }

  function scheduleSave(elements, appState, files) {
    if (suppressChange) return;
    if (saveTimer) clearTimeout(saveTimer);
    saveTimer = setTimeout(function () {
      try {
        var json = ExcalidrawLib.serializeAsJSON(elements, appState, files, "local");
        if (json !== lastSerialized) {
          lastSerialized = json;
          send("whiteboardChanged", json);
        }
      } catch (e) { log("serialize error: " + e); }
    }, 600);
  }

  function applyScene(jsonString) {
    var data = null;
    try { data = (jsonString && jsonString.trim()) ? JSON.parse(jsonString) : null; }
    catch (e) { log("parse error: " + e); return; }
    if (!api) { pendingScene = jsonString; return; }
    // Echo guard: record what we're loading so the resulting onChange isn't
    // re-sent to Swift as a user edit.
    lastSerialized = (jsonString && jsonString.trim()) ? jsonString : lastSerialized;
    suppressChange = true;
    try {
      var elements = ExcalidrawLib.restoreElements ? ExcalidrawLib.restoreElements(data ? data.elements || [] : [], null) : (data ? data.elements || [] : []);
      var appState = data && data.appState ? data.appState : {};
      // collaborators must be a Map/empty — strip the persisted form to avoid restore errors.
      if (appState && appState.collaborators) { delete appState.collaborators; }
      api.updateScene({ elements: elements, appState: appState });
      if (data && data.files) { api.addFiles(Object.keys(data.files).map(function (k) { return data.files[k]; })); }
    } catch (e) { log("applyScene error: " + e); }
    // Window must outlast Excalidraw's async onChange after updateScene on heavy
    // scenes, or a spurious save fires immediately after load.
    setTimeout(function () { suppressChange = false; }, 250);
  }

  // ---- Swift → JS bridge ----
  window.crispyvibesSetScene = function (jsonString) { applyScene(jsonString); };
  window.crispyvibesSetTheme = function (t) {
    if (setThemeExternal) setThemeExternal(t === "dark" ? "dark" : "light");
  };

  function App() {
    var themeState = React.useState("light");
    var theme = themeState[0];
    React.useEffect(function () { setThemeExternal = themeState[1]; }, []);

    var onAPI = React.useCallback(function (a) {
      api = a;
      window.__excalidrawAPI = a;
      if (!ready) {
        ready = true;
        send("whiteboardReady", {});
      }
      if (pendingScene !== null) {
        var s = pendingScene; pendingScene = null;
        applyScene(s);
      }
    }, []);

    var onChange = React.useCallback(function (elements, appState, files) {
      scheduleSave(elements, appState, files);
    }, []);

    return React.createElement(ExcalidrawLib.Excalidraw, {
      excalidrawAPI: onAPI,
      onChange: onChange,
      theme: theme,
      autoFocus: true,
      // Host app owns the file lifecycle; hide in-canvas open/save-to-file.
      UIOptions: { canvasActions: { loadScene: false, saveToActiveFile: false } }
    });
  }

  var root = ReactDOM.createRoot(document.getElementById("app"));
  root.render(React.createElement(App));
})();
