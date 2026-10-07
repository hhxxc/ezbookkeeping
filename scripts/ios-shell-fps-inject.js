/**
 * CI 里把「120Hz 解锁」注入 Capacitor 生成的 AppDelegate.swift。
 *
 * ios/App 是每次构建时 `npx cap add ios` 生成的（不入库），原生定制统一走本注入机制：
 * 在 didFinishLaunchingWithOptions 里挂 ShellFpsInjection.start()（尽早尝试关闭 WebKit
 * 的 PreferPageRenderingUpdatesNear60FPSEnabled 60fps 上限），解锁类本体追加在文件尾部
 * （scripts/ios-shell-unlock.swift）。幂等：已注入则跳过。
 * 历史说明：曾同时注入 FPS 诊断悬浮窗（v1.6.01.05~.08），2026-10-07 按用户要求移除，
 * 旧实现见 git 历史（scripts/ios-shell-fps-hud.swift / scripts/ios-shell-fps-appdelegate.swift）。
 */
const fs = require('fs');

const path = 'ios/App/App/AppDelegate.swift';
let source = fs.readFileSync(path, 'utf8');

if (source.includes('ShellFpsInjection')) {
    console.log('AppDelegate already patched, skip');
    process.exit(0);
}

if (!source.includes('return true')) {
    throw new Error('didFinishLaunchingWithOptions "return true" anchor not found in AppDelegate.swift');
}

source = source.replace('return true', 'ShellFpsInjection.start()\n        return true');
source = 'import WebKit\nimport ObjectiveC\n' + source;

const closing = source.match(/\}\s*$/);
if (!closing) {
    throw new Error('class closing brace not found in AppDelegate.swift');
}

const unlockClass = fs.readFileSync('scripts/ios-shell-unlock.swift', 'utf8');

source = source.slice(0, closing.index) + '\n}\n\n' + unlockClass + '\n';

fs.writeFileSync(path, source);
console.log('Injected 120Hz unlock into AppDelegate.swift');
