import { CapacitorConfig } from '@capacitor/cli';

/**
 * 巢记 iOS / Android 壳配置
 *
 * 架构说明
 * --------
 * IPA 只是一个「启动壳」：它不打包业务前端，而是直接加载服务器上的 Web 应用
 * （NAS 上的 Docker 容器提供，例如 https://ezbookx.x.ddnsto.com/mobile）。
 *
 *   - 前端有更新 → 只要更新 NAS 上的容器，App 下次启动/刷新就能拿到新版本，IPA 不用重新打包；
 *   - 只有「壳本身」变了（图标、原生配置、权限……）才需要重新出 IPA。
 *
 * 实现上用 Capacitor 官方支持的 `server.url`（远程加载模式）——这是最可靠的方式，
 * 不依赖 WebView 对 JS 跳转的放行策略。
 *
 * `errorPath` 指向打包进 App 的 ios-shell/index.html：服务器连不上时由它显示诊断页，
 * 里面可以改服务器地址、重试、查看诊断信息。
 *
 * `allowNavigation` 把壳可能要跳转的域名声明给原生 WebView，避免 iOS 把跳转丢给 Safari。
 *
 * 构建时由 .github/workflows/build-ios-ipa.yml 注入下面两个环境变量：
 *   NESTKEEP_SHELL_SERVER_URL  服务器地址（默认取仓库变量 IOS_API_BASE_URL）
 *   NESTKEEP_SHELL_VERSION     IPA 自身的版本号（用于 App 内的更新检查）
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
        // 服务器连不上时显示打包在 App 里的诊断页（ios-shell/index.html）
        errorPath: 'index.html',
        allowNavigation: envList('NESTKEEP_SHELL_ALLOW_NAVIGATION', [
            'ezbookx.x.ddnsto.com',
            '*.ddnsto.com',
            '192.168.31.198'
        ]),
        // 未注入服务器地址时不启用远程加载（本地开发时就用打包进 App 的前端）
        ...(serverUrl ? { url: serverUrl } : {})
    },
    ios: {
        contentInset: 'always',
        backgroundColor: '#f6f6f8ff'
    },
    android: {
        backgroundColor: '#f6f6f8ff'
    }
};

export default config;
