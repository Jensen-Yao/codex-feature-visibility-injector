# 大家好，这是一个配合codex++用的脚本，希望能帮助到有需要的人

# CodexUnhide

CodexUnhide 是一个配合 Codex++ 使用的用户脚本，用于在 Codex Desktop 启动时自动注入本地 feature gate 覆盖，让部分因为 Statsig/网络初始化失败而隐藏的入口重新显示。

GitHub 仓库地址：

```text
https://github.com/Jensen-Yao/CodexUnhide
```

也可以直接在 GitHub 搜索：

```text
Jensen-Yao/CodexUnhide
```

当前覆盖的入口包括：

- Automations
- Codex mobile
- Computer use
- Browser use / Browser sidebar
- Remote connections
- Browser password settings

> 注意：本脚本只恢复本地 UI 入口和可见性，不会绕过 OpenAI/ChatGPT 服务端权限。某些功能仍可能需要账号开通、网络连通、手机端配对、MFA、浏览器环境或远程连接能力。

## 文件

- `user_scripts/codex-feature-visibility-injector.js`：Codex++ 用户脚本
- `install.ps1`：Windows 安装脚本，会复制脚本到 Codex++ 并更新 `user_scripts.json`

## 一键安装

在 PowerShell 中克隆本仓库，然后运行安装脚本：

```powershell
git clone https://github.com/Jensen-Yao/CodexUnhide.git
cd CodexUnhide
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

如果已经下载或解压了本仓库，也可以直接在仓库目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

安装脚本会写入：

```text
C:\Users\<你的用户名>\AppData\Roaming\Codex++\user_scripts\codex-feature-visibility-injector.js
```

并在下面的配置文件里启用：

```text
C:\Users\<你的用户名>\AppData\Roaming\Codex++\user_scripts.json
```

安装完成后，完全退出并重新打开 Codex Desktop。

## 手动安装

如果不想运行安装脚本，也可以手动复制：

1. 将 `user_scripts/codex-feature-visibility-injector.js` 复制到：

   ```text
   C:\Users\<你的用户名>\AppData\Roaming\Codex++\user_scripts\
   ```

2. 打开或创建：

   ```text
   C:\Users\<你的用户名>\AppData\Roaming\Codex++\user_scripts.json
   ```

3. 确保配置里包含：

   ```json
   {
     "enabled": true,
     "scripts": {
       "user:codex-feature-visibility-injector.js": true
     }
   }
   ```

如果你的 `user_scripts.json` 里已经有其他脚本，请只追加 `scripts` 里的这一项，不要删除原有配置。

## 工作原理

Codex Desktop 使用 Statsig feature gates 控制一些入口是否展示。网络失败或远端 bootstrap 失败时，这些 gate 可能默认返回 `false`，导致 UI 入口隐藏。

本脚本通过 Codex++ 的用户脚本机制，在 Codex 渲染进程启动后安装一个 Statsig `overrideAdapter`，对指定 gate 返回 `true`，并刷新 Statsig memo cache，触发界面重新读取 gate 状态。

脚本会反复尝试注入一段时间，以适配 Codex 启动早期 `__STATSIG__` 尚未初始化的情况。

## 验证

启动 Codex 后，如果侧边栏或设置中能看到 `Automations`、`Codex mobile`、`Computer use` 等入口，说明注入已经生效。

也可以在 DevTools 控制台检查：

```javascript
window.__codexFeatureVisibilityInjector
```

正常情况下应能看到 `version` 和 `gates` 字段。

## 卸载

删除下面的文件：

```text
C:\Users\<你的用户名>\AppData\Roaming\Codex++\user_scripts\codex-feature-visibility-injector.js
```

然后从 `user_scripts.json` 的 `scripts` 中移除：

```json
"user:codex-feature-visibility-injector.js": true
```

重启 Codex Desktop 后生效。

## 兼容性说明

- 仅针对 Codex Desktop + Codex++ 用户脚本环境。
- Codex 更新后 gate 名称或内部 Statsig 接口可能变化，届时需要更新脚本。
- 入口显示不代表功能一定可用，最终能力仍取决于账号和服务端。
