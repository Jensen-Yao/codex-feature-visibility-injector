(() => {
  const INSTALL_KEY = "__codexFeatureVisibilityInjectorInstalled";
  const API_KEY = "__codexFeatureVisibilityInjector";
  const ADAPTER_MARKER = "__codexFeatureVisibilityInjector";
  const SCRIPT_VERSION = 3;
  const MAX_INSTALL_ATTEMPTS = 120;
  const RETRY_MS = 500;
  const REFRESH_MS = 5000;

  const FORCED_GATES = new Map([
    ["3075919032", { label: "Automations", ruleID: "codex-local-automations-nav" }],
    ["1714131075", { label: "Browser sidebar", ruleID: "codex-local-browser-sidebar" }],
    ["1506311413", { label: "Computer use", ruleID: "codex-local-computer-use" }],
    ["410262010", { label: "Browser use", ruleID: "codex-local-browser-use" }],
    ["410065390", { label: "External browser use", ruleID: "codex-local-external-browser-use" }],
    ["4114442250", { label: "Remote connections", ruleID: "codex-local-remote-connections" }],
    ["1042620455", { label: "Remote control connections", ruleID: "codex-local-remote-control" }],
    ["2798711298", { label: "Codex mobile onboarding", ruleID: "codex-local-codex-mobile" }],
    ["72045066", { label: "Browser password settings", ruleID: "codex-local-browser-passwords" }],
    ["1025107964", { label: "Browser password settings fallback", ruleID: "codex-local-browser-passwords-fallback" }],
  ]);

  function getClient() {
    const statsig = globalThis.__STATSIG__;
    if (!statsig) return null;
    return statsig.firstInstance || statsig.instance?.() || null;
  }

  function gateName(gate) {
    if (typeof gate === "string") return gate;
    return gate?.name ?? gate?.ruleID ?? null;
  }

  function isOurAdapter(adapter) {
    return adapter && adapter[ADAPTER_MARKER] === true;
  }

  function makeGateOverride(gate, meta) {
    return {
      ...(typeof gate === "object" && gate != null ? gate : { name: gateName(gate) }),
      details: {
        ...((typeof gate === "object" && gate?.details) || {}),
        reason: "LocalOverride:CodexFeatureVisibilityInjector",
      },
      ruleID: meta.ruleID,
      value: true,
    };
  }

  function installOverride(client) {
    if (!client || isOurAdapter(client.overrideAdapter)) return Boolean(client);

    const previous = client.overrideAdapter || null;
    client.overrideAdapter = {
      [ADAPTER_MARKER]: true,
      __previousAdapter: previous,
      loadFromStorage: previous?.loadFromStorage?.bind(previous),
      getGateOverride(gate, user, options) {
        const name = gateName(gate);
        const meta = name == null ? null : FORCED_GATES.get(name);
        if (meta) return makeGateOverride(gate, meta);
        return previous?.getGateOverride?.(gate, user, options) ?? null;
      },
      getDynamicConfigOverride: previous?.getDynamicConfigOverride?.bind(previous),
      getExperimentOverride: previous?.getExperimentOverride?.bind(previous),
      getLayerOverride: previous?.getLayerOverride?.bind(previous),
      getParamStoreOverride: previous?.getParamStoreOverride?.bind(previous),
    };

    client._memoCache = {};
    try {
      localStorage.setItem("codex.featureVisibilityInjector.lastInstall", new Date().toISOString());
      localStorage.setItem("codex.featureVisibilityInjector.gates", JSON.stringify([...FORCED_GATES.keys()]));
    } catch {}
    try {
      client.$emt?.({ name: "values_updated", status: "Ready" });
    } catch {}
    return true;
  }

  function refresh() {
    const client = getClient();
    if (!installOverride(client)) return false;

    try {
      client._memoCache = {};
      client.$emt?.({ name: "values_updated", status: "Ready" });
    } catch {}
    return true;
  }

  if (window[INSTALL_KEY]) {
    const existingApi = window[API_KEY];
    const currentGates = Array.isArray(existingApi?.gates) ? existingApi.gates : [];
    const desiredGates = [...FORCED_GATES.keys()];
    const isCurrent =
      existingApi?.version === SCRIPT_VERSION &&
      desiredGates.length === currentGates.length &&
      desiredGates.every((gate) => currentGates.includes(gate));

    if (isCurrent) {
      existingApi?.refresh?.();
      return;
    }

    existingApi?.destroy?.();
    const client = getClient();
    if (isOurAdapter(client?.overrideAdapter)) {
      client.overrideAdapter = client.overrideAdapter.__previousAdapter || null;
    }
  }

  window[INSTALL_KEY] = true;
  let attempts = 0;
  let retryTimer = null;
  let refreshTimer = null;

  const api = {
    version: SCRIPT_VERSION,
    gates: [...FORCED_GATES.keys()],
    refresh,
    destroy() {
      if (retryTimer != null) clearTimeout(retryTimer);
      if (refreshTimer != null) clearInterval(refreshTimer);
      delete window[INSTALL_KEY];
      delete window[API_KEY];
    },
  };
  window[API_KEY] = api;

  function retryInstall() {
    attempts += 1;
    if (refresh()) {
      refreshTimer = setInterval(refresh, REFRESH_MS);
      return;
    }
    if (attempts < MAX_INSTALL_ATTEMPTS) {
      retryTimer = setTimeout(retryInstall, RETRY_MS);
    }
  }

  retryInstall();
})();
