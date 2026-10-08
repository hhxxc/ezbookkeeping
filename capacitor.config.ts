import { CapacitorConfig } from '@capacitor/cli';

/**
 * 巢记 iOS / Android 壳配置
 *
 * 架构说明
 * --------
 * 默认：把业务前端（dist/）直接打包进 App，WebView 加载本地网页，离线即可打开
 * 「巢记」App（数据请求仍走你的 NAS 后端）。这就是「把网页打包成 IPA（本地化网页封装）」。
 *
 *   - 前端有更新 → 需要重新构建并出 IPA（网页在包内，必须重打包）；
 *   - 只有「壳本身」变了（图标、原生配置、权限……）才需要重新出 IPA。
 *
 * 可选远程兜底：构建时注入 NESTKEEP_SHELL_SERVER_URL 时，改用 Capacitor 官方 server.url
 * 远程加载（Web 应用跑在 NAS 容器上，IPA 只作薄壳）。不注入则默认本地打包。
 *
 * `errorPath` 指向打包进 App 的离线诊断页（shell-diag.html，由 ios-shell/index.html 生成）：
 * 本地网页加载失败时由它显示诊断信息、允许修改 NAS 后端地址。
 *
 * `allowNavigation` 把壳可能要跳转的域名声明给原生 WebView，避免 iOS 把跳转丢给 Safari。
 *
 * 构建时由 .github/workflows/build-ios-ipa.yml 或 scripts/build-ios-ipa.sh 注入：
 *   NESTKEEP_SHELL_SERVER_URL   可选远程加载地址（不注入 = 本地打包模式）
 *   NESTKEEP_SHELL_VERSION      IPA 自身的版本号（用于 App 内的更新检查）
 *   （本地打包模式还会向 dist/index.html 注入 window.EZBOOKKEEPING_SERVER_SETTINGS.apiBaseUrl）
 */

function envList(name: string, fallback: string[]): string[] {
    const value = process.env[name];

    if (!value) {
        return fallback;
    }

    const list = value.split(',').map(item => item.trim()).filter(item => !!item);

    return list.length ? list : fallback;
}

function normalizeServerBaseUrl(value: string): string {
    let url = (value || '').trim().replace(/\/+$/, '');

    if (!url) {
        return '';
    }

    if (!/\/mobile$/i.test(url)) {
        url += '/mobile';
    }

    return url;
}

function buildServerUrl(): string {
    const baseUrl = normalizeServerBaseUrl(process.env.NESTKEEP_SHELL_SERVER_URL || '');

    if (!baseUrl) {
        return '';
    }

    const shellVersion = (process.env.NESTKEEP_SHELL_VERSION || '').trim();
    const query = ['appshell=1'];

    if (shellVersion) {
        query.push(`shellv=${encodeURIComponent(shellVersion)}`);
    }

    return `${baseUrl}?${query.join('&')}`;
}

const serverUrl: string = buildServerUrl();

const config: CapacitorConfig = {
    appId: 'com.nestkeep.app',
    appName: '巢记',
    webDir: 'dist',
    server: {
        androidScheme: 'https',
        iosScheme: 'capacitor',
        // 本地网页加载失败时显示打包在 App 里的诊断页（shell-diag.html，由 ios-shell/index.html 生成）
        errorPath: 'shell-diag.html',
        allowNavigation: envList('NESTKEEP_SHELL_ALLOW_NAVIGATION', [
            'example-server.invalid',
            '*.example.com.invalid',
            'REDACTED'
        ]),
        // 未注入服务器地址时不启用远程加载（默认本地打包：WebView 加载包内的 dist）
        ...(serverUrl ? { url: serverUrl } : {})
    },
    ios: {
        contentInset: 'never',
        backgroundColor: '#f6f6f8ff'
    },
    android: {
        contentInset: 'never',
        backgroundColor: '#f6f6f8ff'
    }
};

export default config;
