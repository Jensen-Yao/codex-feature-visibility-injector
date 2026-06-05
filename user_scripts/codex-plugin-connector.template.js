(() => {
  const INSTALL_KEY = "__codexPluginConnectorInstalled";
  const API_KEY = "__codexPluginConnector";
  const ROOT_ID = "codex-plugin-connector";
  const STYLE_ID = "codex-plugin-connector-style";
  const SCRIPT_VERSION = 2;

  const CODEXPP_ROOT = "__CODEXPP_ROOT__";
  const PLUGIN_REPAIR_ROOT = `${CODEXPP_ROOT}\\plugin-repair`;
  const CMD_PATH = `${PLUGIN_REPAIR_ROOT}\\connect-plugins.cmd`;
  const CONNECT_COMMAND =
    `powershell -NoProfile -ExecutionPolicy Bypass -File "${PLUGIN_REPAIR_ROOT}\\connect-openai-bundled-plugins.ps1"`;
  const DIAGNOSE_COMMAND =
    `powershell -NoProfile -ExecutionPolicy Bypass -File "${PLUGIN_REPAIR_ROOT}\\diagnose-computer-use-state.ps1"`;

  const text = {
    mainButton: "\u63d2\u4ef6\u8fde\u63a5",
    mainTitle:
      "\u8bca\u65ad\u5e76\u8fde\u63a5 Computer Use / Chrome",
    panelTitle:
      "\u8fde\u63a5 Codex \u672c\u673a\u63d2\u4ef6",
    panelText:
      "\u5148\u68c0\u67e5\u63d2\u4ef6\u662f\u5426\u771f\u7684\u5df2\u5b89\u88c5\uff0c\u5df2\u5b89\u88c5\u65f6\u4fee\u590d Chrome Native Host \u548c\u6269\u5c55\u8fde\u63a5\u3002",
    copyConnect: "\u590d\u5236\u8fde\u63a5\u547d\u4ee4",
    copyDiagnose: "\u590d\u5236\u8bca\u65ad\u547d\u4ee4",
    openScript: "\u6253\u5f00\u811a\u672c",
    reload: "\u5237\u65b0\u7a97\u53e3",
    hide: "\u6536\u8d77",
    copiedConnect:
      "\u5df2\u590d\u5236\u8fde\u63a5\u547d\u4ee4\u3002",
    copiedDiagnose:
      "\u5df2\u590d\u5236\u8bca\u65ad\u547d\u4ee4\u3002",
    copyFailed:
      "\u590d\u5236\u5931\u8d25\uff0c\u8bf7\u624b\u52a8\u9009\u4e2d\u547d\u4ee4\u3002",
    opened:
      "\u5df2\u5c1d\u8bd5\u6253\u5f00\u672c\u5730 CMD \u811a\u672c\uff1b\u5982\u88ab\u62e6\u622a\uff0c\u8bf7\u8fd0\u884c\u5df2\u590d\u5236\u7684\u547d\u4ee4\u3002",
    openFailed:
      "\u6253\u5f00\u811a\u672c\u5931\u8d25\uff1a",
  };

  function installStyle() {
    if (document.getElementById(STYLE_ID)) return;

    const style = document.createElement("style");
    style.id = STYLE_ID;
    style.textContent = `
      #${ROOT_ID} {
        position: fixed;
        right: 18px;
        bottom: 72px;
        z-index: 2147483647;
        display: flex;
        flex-direction: column;
        align-items: flex-end;
        gap: 8px;
        font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      }
      #${ROOT_ID} .cpc-button {
        border: 1px solid rgba(120, 120, 120, 0.32);
        border-radius: 8px;
        background: rgba(28, 28, 28, 0.94);
        color: #fff;
        padding: 8px 11px;
        font-size: 12px;
        line-height: 1;
        box-shadow: 0 6px 18px rgba(0, 0, 0, 0.22);
        cursor: pointer;
      }
      #${ROOT_ID} .cpc-panel {
        width: min(460px, calc(100vw - 28px));
        border: 1px solid rgba(120, 120, 120, 0.28);
        border-radius: 8px;
        background: rgba(24, 24, 24, 0.97);
        color: #f5f5f5;
        padding: 10px;
        box-shadow: 0 12px 32px rgba(0, 0, 0, 0.32);
      }
      #${ROOT_ID} .cpc-panel[hidden] {
        display: none;
      }
      #${ROOT_ID} .cpc-title {
        font-size: 13px;
        font-weight: 600;
        margin-bottom: 8px;
      }
      #${ROOT_ID} .cpc-text {
        font-size: 12px;
        line-height: 1.45;
        margin-bottom: 8px;
        color: rgba(255, 255, 255, 0.8);
      }
      #${ROOT_ID} .cpc-code {
        width: 100%;
        box-sizing: border-box;
        border: 1px solid rgba(255, 255, 255, 0.16);
        border-radius: 6px;
        background: rgba(0, 0, 0, 0.35);
        color: #fff;
        padding: 8px;
        font-size: 11px;
        line-height: 1.35;
        resize: vertical;
        min-height: 66px;
      }
      #${ROOT_ID} .cpc-actions {
        display: flex;
        gap: 8px;
        margin-top: 8px;
        flex-wrap: wrap;
      }
      #${ROOT_ID} .cpc-action {
        border: 1px solid rgba(255, 255, 255, 0.18);
        border-radius: 6px;
        background: rgba(255, 255, 255, 0.08);
        color: #fff;
        padding: 7px 9px;
        font-size: 12px;
        cursor: pointer;
      }
      #${ROOT_ID} .cpc-status {
        min-height: 16px;
        margin-top: 8px;
        font-size: 11px;
        color: rgba(255, 255, 255, 0.72);
      }
    `;
    document.documentElement.appendChild(style);
  }

  async function copyText(value) {
    try {
      await navigator.clipboard.writeText(value);
      return true;
    } catch {
      const textArea = document.createElement("textarea");
      textArea.value = value;
      textArea.style.position = "fixed";
      textArea.style.left = "-9999px";
      document.body.appendChild(textArea);
      textArea.focus();
      textArea.select();
      const copied = document.execCommand("copy");
      textArea.remove();
      return copied;
    }
  }

  function tryOpenCmd(status) {
    const fileUrl = `file:///${CMD_PATH.replace(/\\/g, "/")}`;
    try {
      window.open(fileUrl, "_blank", "noopener,noreferrer");
      status.textContent = text.opened;
    } catch (error) {
      status.textContent = `${text.openFailed} ${error?.message || error}`;
    }
  }

  function ensureRoot() {
    let root = document.getElementById(ROOT_ID);
    if (root) return root;

    root = document.createElement("div");
    root.id = ROOT_ID;

    const button = document.createElement("button");
    button.className = "cpc-button";
    button.type = "button";
    button.textContent = text.mainButton;
    button.title = text.mainTitle;

    const panel = document.createElement("div");
    panel.className = "cpc-panel";
    panel.hidden = true;

    const title = document.createElement("div");
    title.className = "cpc-title";
    title.textContent = text.panelTitle;

    const description = document.createElement("div");
    description.className = "cpc-text";
    description.textContent = text.panelText;

    const code = document.createElement("textarea");
    code.className = "cpc-code";
    code.readOnly = true;
    code.value = CONNECT_COMMAND;

    const actions = document.createElement("div");
    actions.className = "cpc-actions";

    const copyConnectButton = document.createElement("button");
    copyConnectButton.className = "cpc-action";
    copyConnectButton.type = "button";
    copyConnectButton.textContent = text.copyConnect;

    const copyDiagnoseButton = document.createElement("button");
    copyDiagnoseButton.className = "cpc-action";
    copyDiagnoseButton.type = "button";
    copyDiagnoseButton.textContent = text.copyDiagnose;

    const openButton = document.createElement("button");
    openButton.className = "cpc-action";
    openButton.type = "button";
    openButton.textContent = text.openScript;

    const reloadButton = document.createElement("button");
    reloadButton.className = "cpc-action";
    reloadButton.type = "button";
    reloadButton.textContent = text.reload;

    const hideButton = document.createElement("button");
    hideButton.className = "cpc-action";
    hideButton.type = "button";
    hideButton.textContent = text.hide;

    const status = document.createElement("div");
    status.className = "cpc-status";

    async function copyCommand(command, successText) {
      code.value = command;
      const copied = await copyText(command);
      status.textContent = copied ? successText : text.copyFailed;
    }

    button.addEventListener("click", async () => {
      panel.hidden = !panel.hidden;
      if (!panel.hidden) {
        await copyCommand(CONNECT_COMMAND, text.copiedConnect);
      }
    });

    copyConnectButton.addEventListener("click", () =>
      copyCommand(CONNECT_COMMAND, text.copiedConnect),
    );
    copyDiagnoseButton.addEventListener("click", () =>
      copyCommand(DIAGNOSE_COMMAND, text.copiedDiagnose),
    );
    openButton.addEventListener("click", () => tryOpenCmd(status));
    reloadButton.addEventListener("click", () => window.location.reload());
    hideButton.addEventListener("click", () => {
      panel.hidden = true;
    });

    actions.append(
      copyConnectButton,
      copyDiagnoseButton,
      openButton,
      reloadButton,
      hideButton,
    );
    panel.append(title, description, code, actions, status);
    root.append(panel, button);
    document.documentElement.appendChild(root);
    return root;
  }

  function install() {
    installStyle();
    ensureRoot();
  }

  if (window[INSTALL_KEY]) {
    window[API_KEY]?.destroy?.();
  }

  window[INSTALL_KEY] = true;
  window[API_KEY] = {
    version: SCRIPT_VERSION,
    refresh: install,
    destroy() {
      document.getElementById(ROOT_ID)?.remove();
      document.getElementById(STYLE_ID)?.remove();
      delete window[INSTALL_KEY];
      delete window[API_KEY];
    },
  };

  install();
})();
