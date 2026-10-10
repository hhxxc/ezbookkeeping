function getServerSetting(key: string): string | number | boolean | Record<string, string> | undefined | null {
    const settings = window.EZBOOKKEEPING_SERVER_SETTINGS || {};
    return settings[key];
}

export async function loadRemoteServerSettings(): Promise<void> {
    const url = getRemoteServerSettingsUrl();

    if (!url) return;

    // 失败重试 2 次（间隔 1s/2s）：iOS 壳冷启动时隧道/NAS 可能还没就绪，
    // 静默失败会让 llmt 等开关整场缺失（AI 入口卡消失）
    return new Promise((resolve) => {
        const tryLoad = (attempt: number) => {
            const script = document.createElement('script');
            script.src = url;
            script.onload = () => {
                document.head.removeChild(script);
                resolve();
            };
            script.onerror = () => {
                document.head.removeChild(script);
                if (attempt < 2) {
                    setTimeout(() => tryLoad(attempt + 1), 1000 * (attempt + 1));
                } else {
                    resolve();
                }
            };
            document.head.appendChild(script);
        };
        tryLoad(0);
    });
}

/// 远程设置的地址：老版本依赖 window.EZBOOKKEEPING_SERVER_SETTINGS.apiBaseUrl，
/// 但后端从未在该脚本里下发过这个字段（只有 API Token 响应才有），
/// 导致本函数永远静默跳过、llmt 永远缺失（AI 识图入口一直不出现的根因）。
/// 实际页面与 API 同源，直接按当前路径推导即可。
function getRemoteServerSettingsUrl(): string | null {
    const apiBaseUrl = window.EZBOOKKEEPING_SERVER_SETTINGS?.apiBaseUrl;

    if (apiBaseUrl) {
        return (apiBaseUrl as string).replace(/\/+$/, '') + '/mobile/server_settings.js';
    }

    const path = window.location.pathname.replace(/\/+$/, '');

    if (path.endsWith('/mobile') || path.endsWith('/desktop')) {
        return path + '/server_settings.js';
    }

    if (path === '' || path === '/') {
        return '/server_settings.js';
    }

    // 未知路径（如直接打开 /index.html）：按相对路径兜底
    const lastSlashIndex = path.lastIndexOf('/');

    if (lastSlashIndex < 0) {
        return '/server_settings.js';
    }

    return path.substring(0, lastSlashIndex) + '/server_settings.js';
}

export function isInternalAuthEnabled(): boolean {
    return getServerSetting('a') !== 0;
}

export function isOAuth2Enabled(): boolean {
    return getServerSetting('o') === 1;
}

export function isUserRegistrationEnabled(): boolean {
    return getServerSetting('r') === 1;
}

export function isUserForgetPasswordEnabled(): boolean {
    return getServerSetting('f') === 1;
}

export function isAPITokenEnabled(): boolean {
    return getServerSetting('t') === 1;
}

export function isUserVerifyEmailEnabled(): boolean {
    return getServerSetting('v') === 1;
}

export function isTransactionPicturesEnabled(): boolean {
    return getServerSetting('p') === 1;
}

export function isUserScheduledTransactionEnabled(): boolean {
    return getServerSetting('s') === 1;
}

export function isDataExportingEnabled(): boolean {
    return getServerSetting('e') === 1;
}

export function isDataImportingEnabled(): boolean {
    return getServerSetting('i') === 1;
}

export function getOAuth2Provider(): string {
    return getServerSetting('op') as string;
}

export function getOIDCCustomDisplayNames(): Record<string, string>{
    return getServerSetting('ocn') as Record<string, string>;
}

export function isMCPServerEnabled(): boolean {
    return getServerSetting('mcp') === 1;
}

export function isTransactionFromAIImageRecognitionEnabled(): boolean {
    return getServerSetting('llmt') === 1;
}

export function getLoginPageTips(): Record<string, string>{
    return getServerSetting('lpt') as Record<string, string>;
}

export function getMapProvider(): string {
    return getServerSetting('m') as string;
}

export function isMapDataFetchProxyEnabled(): boolean {
    return getServerSetting('mp') === 1;
}

export function getCustomMapTileLayerUrl(): string {
    return getServerSetting('cmsu') as string;
}

export function getCustomMapAnnotationLayerUrl(): string {
    return getServerSetting('cmau') as string;
}

export function isCustomMapAnnotationLayerDataFetchProxyEnabled(): boolean {
    return getServerSetting('cmap') === 1;
}

export function getCustomMapMinZoomLevel(): number {
    const zoomLevelSettings = (getServerSetting('cmzl') as string || '').split('-');
    return (zoomLevelSettings && zoomLevelSettings[0]) ? parseInt(zoomLevelSettings[0]) : 1;
}

export function getCustomMapMaxZoomLevel(): number {
    const zoomLevelSettings = (getServerSetting('cmzl') as string || '').split('-');
    return (zoomLevelSettings && zoomLevelSettings[1]) ? parseInt(zoomLevelSettings[1]) : 18;
}

export function getCustomMapDefaultZoomLevel(): number {
    const zoomLevelSettings = (getServerSetting('cmzl') as string || '').split('-');
    return (zoomLevelSettings && zoomLevelSettings[2]) ? parseInt(zoomLevelSettings[2]) : 14;
}

export function getTomTomMapAPIKey(): string {
    return getServerSetting('tmak') as string;
}

export function getTianDiTuMapAPIKey(): string {
    return getServerSetting('tdak') as string;
}

export function getGoogleMapAPIKey(): string {
    return getServerSetting('gmak') as string;
}

export function getBaiduMapAK(): string {
    return getServerSetting('bmak') as string;
}

export function getAmapApplicationKey(): string {
    return getServerSetting('amak') as string;
}

export function getAmapSecurityVerificationMethod(): string {
    return getServerSetting('amsv') as string;
}

export function getAmapApiExternalProxyUrl(): string {
    return getServerSetting('amep') as string;
}

export function getAmapApplicationSecret(): string {
    return getServerSetting('amas') as string;
}

export function getExchangeRatesRequestTimeout(): number {
    return getServerSetting('errt') as number;
}
