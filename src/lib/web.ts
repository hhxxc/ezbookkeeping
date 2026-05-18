export function getBasePath(): string {
    const apiBaseUrl = window.EZBOOKKEEPING_SERVER_SETTINGS?.apiBaseUrl;

    if (apiBaseUrl) {
        return (apiBaseUrl as string).replace(/\/+$, '');
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
