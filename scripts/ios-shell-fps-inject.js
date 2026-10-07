/**
 * CI 里把「120Hz 解锁 + FPS 诊断 HUD」注入 Capacitor 生成的 AppDelegate.swift。
 *
 * ios/App 是每次构建时 `npx cap add ios` 生成的（不入库），原生定制统一走本注入机制：
 * 在 didFinishLaunchingWithOptions 里挂 ShellFpsInjection.start()（尽早尝试关闭 WebKit
 * 的 PreferPageRenderingUpdatesNear60FPSEnabled 60fps 上限），类文件本体追加在文件尾部。
 * 幂等：已注入则跳过。
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

const insideClass = fs.readFileSync('scripts/ios-shell-fps-appdelegate.swift', 'utf8');
const tailClasses = fs.readFileSync('scripts/ios-shell-fps-hud.swift', 'utf8');

source = source.slice(0, closing.index) + insideClass + '\n}\n\n' + tailClasses + '\n';

fs.writeFileSync(path, source);
console.log('Injected 120Hz unlock + FPS HUD into AppDelegate.swift');
