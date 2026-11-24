# Ctrl 快捷键助手

[English](README.md)

一个 macOS 菜单栏小工具，让你用熟悉的 Ctrl 组合键编辑内容。

| 快捷键 | 功能 |
| --- | --- |
| `Ctrl+A`、`Ctrl+C`、`Ctrl+V`、`Ctrl+X` | 全选、复制、粘贴、剪切 |
| `Ctrl+Z`、`Ctrl+Shift+Z` | 撤销、重做 |
| `Option+=` | Microsoft PowerPoint 在前台时插入公式 |
| `Ctrl+Option+S` | 按需打开 Flameshot 的截图框选界面 |

原有的 Command 快捷键仍然可用。UU 远程和受支持的终端保留原始 Ctrl 编辑按键。

## 从源码安装

需要 macOS 14 或更新版本、Apple 命令行工具（`xcode-select --install`）和 Python 3。

```sh
git clone https://github.com/ZhxinMath/ctrl-shortcuts-macos.git
cd ctrl-shortcuts-macos
xcrun swiftc -target "$(uname -m)-apple-macos14.0" CtrlShortcuts.swift -o CtrlShortcuts
./CtrlShortcuts --self-test
python3 install-helper.py
```

安装脚本会把 **Ctrl Shortcuts.app** 放到 `~/Applications`，启动它并设置登录时打开。请在 **系统设置 → 隐私与安全 → 辅助功能** 中允许该应用。部分 macOS 版本将该页面称为「设备控制和数据访问」。菜单栏的 **Ctrl** 显示「已启用」时即可使用。

使用截图快捷键前，请安装 [Flameshot](https://github.com/flameshot-org/flameshot/releases/latest)，并在系统设置中授予 **Flameshot**「录屏与系统录音」权限。按快捷键时，Ctrl 助手会调用 `flameshot gui`。两次截图之间可以完全退出 Flameshot。

## 暂停或卸载

在 **Ctrl** 菜单里选择「暂停转换」可以暂时停用，选择「退出并恢复原快捷键」会退出并恢复先前的快捷键设置。卸载时，先退出助手，再运行下面的命令，最后把 `~/Applications` 中的 **Ctrl Shortcuts.app** 移到废纸篓。

```sh
launchctl bootout "gui/$(id -u)/local.xin.ctrlshortcuts"
rm ~/Library/LaunchAgents/local.xin.ctrlshortcuts.plist
```
