// 本地打包（IPA）模式下，后端地址可能在壳的诊断页里被用户改过并存进 localStorage，
// 这里优先用构建时注入的 window.EZBOOKKEEPING_SERVER_SETTINGS，其次回退到 localStorage。
const STORAGE_KEY_API_BASE = 'nestkeep.shell.apiBaseUrl';

function getApiBaseUrlFromSettingsOrStorage(): string {
    const injected = window.EZBOOKKEEPING_SERVER_SETTINGS?.apiBaseUrl;

    if (injected) {
        return (injected as string).replace(/\/+$/, '');
    }

    try {
        const saved = window.localStorage.getItem(STORAGE_KEY_API_BASE);

        if (saved) {
            return saved.replace(/\/+$/, '');
        }
    } catch (e) {
        // ignore
    }

    return '';
}

export function getBasePath(): string {
    const apiBaseUrl = getApiBaseUrlFromSettingsOrStorage();

    if (apiBaseUrl) {
        return apiBaseUrl;
    }

    const path = window.location.pathname;
    const lastSlashIndex = path.lastIndexOf('/');

    if (lastSlashIndex < 0) {
        return path;
    }

    return path.substring(0, lastSlashIndex);
}

export function navigateToHomePage(type: 'desktop' | 'mobile'): void {
    if (__EZBOOKKEEPING_IS_PRODUCTION__) {
        window.location.replace(`${type}#/`);
    } else {
        window.location.replace(`${type}.html#/`);
    }
}
