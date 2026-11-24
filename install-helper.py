"""Install the locally built menu-bar helper without administrator access."""
import os
import pathlib
import plistlib
import shutil
import subprocess

base = pathlib.Path(__file__).resolve().parent
home = pathlib.Path.home()
app = home / 'Applications/Ctrl Shortcuts.app'
contents = app / 'Contents'
(contents / 'MacOS').mkdir(parents=True, exist_ok=True)
shutil.copy2(base / 'CtrlShortcuts', contents / 'MacOS/CtrlShortcuts')
info = {
    'CFBundleIdentifier': 'local.xin.ctrlshortcuts',
    'CFBundleName': 'Ctrl Shortcuts',
    'CFBundleDisplayName': 'Ctrl 快捷键助手',
    'CFBundleExecutable': 'CtrlShortcuts',
    'CFBundlePackageType': 'APPL',
    'CFBundleVersion': '5',
    'CFBundleShortVersionString': '1.4',
    'LSUIElement': True,
    'LSMinimumSystemVersion': '14.0',
    'NSHighResolutionCapable': True,
}
(contents / 'Info.plist').write_bytes(plistlib.dumps(info))
subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', '--identifier',
                'local.xin.ctrlshortcuts', str(app)], check=True)

agents = home / 'Library/LaunchAgents'
agents.mkdir(parents=True, exist_ok=True)
agent = agents / 'local.xin.ctrlshortcuts.plist'
agent.write_bytes(plistlib.dumps({
    'Label': 'local.xin.ctrlshortcuts',
    'ProgramArguments': ['/usr/bin/open', '-g', str(app)],
    'RunAtLoad': True,
    'LimitLoadToSessionType': 'Aqua',
}))
subprocess.run(['/usr/bin/plutil', '-lint', str(agent)], check=True)
domain = 'gui/' + str(os.getuid())
service = domain + '/local.xin.ctrlshortcuts'
if subprocess.run(['/bin/launchctl', 'print', service], capture_output=True).returncode:
    subprocess.run(['/bin/launchctl', 'bootstrap', domain, str(agent)], check=True)
else:
    subprocess.run(['/usr/bin/open', '-g', str(app)], check=True)
print('Installed:', app)
print('Login item:', agent)
