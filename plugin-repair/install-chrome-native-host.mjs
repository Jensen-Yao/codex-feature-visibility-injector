import { pathToFileURL } from "node:url";

const [installScriptPath, codexCliPath, nodePath, nodeReplPath] =
  process.argv.slice(2);

if (!installScriptPath || !codexCliPath || !nodePath || !nodeReplPath) {
  console.error(
    "Usage: install-chrome-native-host.mjs <installManifest.mjs> <codex.exe> <node.exe> <node_repl.exe>",
  );
  process.exit(2);
}

try {
  const installer = await import(pathToFileURL(installScriptPath).href);
  await installer.install({
    appServerRuntimePaths: {
      codexCliPath,
      nodePath,
      nodeReplPath,
    },
  });
} catch (error) {
  console.error(error?.stack || String(error));
  process.exit(1);
}
