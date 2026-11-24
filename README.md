# Ctrl Shortcuts for macOS

[简体中文](README.zh-CN.md)

A small menu bar app that brings familiar Control-key editing shortcuts to macOS.

| Shortcut | Action |
| --- | --- |
| `Ctrl+A`, `Ctrl+C`, `Ctrl+V`, `Ctrl+X` | Select all, copy, paste, and cut |
| `Ctrl+Z`, `Ctrl+Shift+Z` | Undo and redo |
| `Option+=` | Insert an equation when Microsoft PowerPoint is in front |
| `Ctrl+Option+S` | Open the Flameshot region capture interface on demand |

The usual Command shortcuts still work. Editing shortcuts keep their original Control behavior in UU Remote and supported terminals. The menu bar controls are in Simplified Chinese.

## Install from source

Requires macOS 14 or later, Apple's Command Line Tools (`xcode-select --install`), and Python 3.

```sh
git clone https://github.com/ZhxinMath/ctrl-shortcuts-macos.git
cd ctrl-shortcuts-macos
xcrun swiftc -target "$(uname -m)-apple-macos14.0" CtrlShortcuts.swift -o CtrlShortcuts
./CtrlShortcuts --self-test
python3 install-helper.py
```

The installer places **Ctrl Shortcuts.app** in `~/Applications`, starts it, and registers it to open at login. Grant the app Accessibility access in **System Settings → Privacy & Security → Accessibility**. On some macOS versions this section is called **Device Control and Data Access**. The menu bar item **Ctrl** shows **已启用** when the helper is active.

To use the capture shortcut, install [Flameshot](https://github.com/flameshot-org/flameshot/releases/latest) and grant **Flameshot** Screen & System Audio Recording access. The Ctrl helper starts `flameshot gui` when you press the shortcut. Flameshot can be fully quit between captures.

## Pause or uninstall

In the **Ctrl** menu, select **暂停转换** to pause or **退出并恢复原快捷键** to quit and restore the previous shortcut settings. To uninstall, run the commands below after quitting, then move **Ctrl Shortcuts.app** from `~/Applications` to the Trash.

```sh
launchctl bootout "gui/$(id -u)/local.xin.ctrlshortcuts"
rm ~/Library/LaunchAgents/local.xin.ctrlshortcuts.plist
```
