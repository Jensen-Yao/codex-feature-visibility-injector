# CodexUnhide

给 Codex++ 用的小工具。

## 功能

- 显示被隐藏的 Codex 入口
- 修复 `browser / computer-use / chrome@openai-bundled`
- 区分“没安装”和“已安装但没连接”
- 修复 Chrome Native Host / 扩展连接

## 安装

```powershell
git clone https://github.com/Jensen-Yao/CodexUnhide.git
cd CodexUnhide
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

安装后重启 Codex / Codex++。

## 修复插件

```powershell
powershell -ExecutionPolicy Bypass -File "$env:APPDATA\Codex++\plugin-repair\connect-openai-bundled-plugins.ps1"
```

## 只诊断

```powershell
powershell -ExecutionPolicy Bypass -File "$env:APPDATA\Codex++\plugin-repair\diagnose-computer-use-state.ps1"
```

## 说明

这不是绕过服务端权限，只修本机入口、插件安装缓存、配置和 Chrome 连接层。
