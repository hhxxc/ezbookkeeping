import { ref, computed } from 'vue';

import { useI18n } from '@/locales/helpers.ts';

import { useSystemsStore } from '@/stores/system.ts';
import { useExchangeRatesStore } from '@/stores/exchangeRates.ts';

import type { VersionInfo, ClientUpdateInfo } from '@/core/version.ts';

import type { LatestExchangeRateResponse } from '@/models/exchange_rate.ts';

import { parseDateTimeFromUnixTime } from '@/lib/datetime.ts';
import { getMapProvider } from '@/lib/server_settings.ts';
import { getMapWebsite } from '@/lib/map/index.ts';
import { getContributors } from '@/lib/contributors.ts';
import { getLicense, getThirdPartyLicenses } from '@/lib/licenses.ts';
import { formatDisplayVersion, getClientDisplayVersion, getClientBuildTime, getClientVersionInfo } from '@/lib/version.ts';
import { clearAllBrowserCaches } from '@/lib/cache.ts';

const GITHUB_RELEASES_API_URL = 'https://api.github.com/repos/hhxxc/ezbookkeeping/releases/latest';

interface GitHubRelease {
    readonly tag_name: string;
    readonly html_url: string;
    readonly body?: string;
}

export function useAboutPageBase() {
    const { tt, formatDateTimeToLongDateTime } = useI18n();

    const systemsStore = useSystemsStore();
    const exchangeRatesStore = useExchangeRatesStore();

    const clientVersion = `${getClientDisplayVersion()}`;

    const serverVersion = ref<VersionInfo | null>(null);
    const clientVersionMatchServerVersion = ref<boolean>(true);

    const serverDisplayVersion = computed<string>(() => {
        if (!serverVersion.value) {
            return '';
        }

        return formatDisplayVersion(serverVersion.value);
    });

    const clientBuildTime = computed<string>(() => {
        const time = getClientBuildTime();

        if (!time) {
            return time;
        }

        const buildDateTime = parseDateTimeFromUnixTime(parseInt(time));
        return formatDateTimeToLongDateTime(buildDateTime);
    });

    const exchangeRatesData = computed<LatestExchangeRateResponse | undefined>(() => exchangeRatesStore.latestExchangeRates.data);
    const isUserCustomExchangeRates = computed<boolean>(() => exchangeRatesStore.isUserCustomExchangeRates);

    const mapProviderName = computed<string>(() => {
        const provider = getMapProvider();
        return provider ? tt(`mapprovider.${provider}`) : '';
    });
    const mapProviderWebsite = computed<string>(() => getMapWebsite());

    const contributors = computed<ContributorInfo>(() => getContributors());
    const licenseLines = computed<string[]>(() => getLicense().replace(/\r/g, '').split('\n'));
    const thirdPartyLicenses = computed<LicenseInfo[]>(() => getThirdPartyLicenses());

    const clientUpdateInfo = ref<ClientUpdateInfo | null>(null);
    const hasUpdate = computed<boolean>(() => {
        if (!clientUpdateInfo.value || !clientUpdateInfo.value.latestVersion) {
            return false;
        }

        return getClientVersionInfo().version !== clientUpdateInfo.value.latestVersion;
    });

    function refreshBrowserCache(): void {
        clearAllBrowserCaches().then(() => {
            location.reload();
        });
    }

    function init(): void {
        systemsStore.checkIfClientVersionMatchServerVersion().then(({ match, version }) => {
            serverVersion.value = version;
            clientVersionMatchServerVersion.value = match;
        });

        fetch(GITHUB_RELEASES_API_URL, {
            headers: { 'Accept': 'application/json' }
        }).then(response => {
            if (!response.ok) {
                return;
            }

            return response.json() as Promise<GitHubRelease>;
        }).then(release => {
            if (!release) {
                return;
            }

            const latestVersion = release.tag_name.replace(/^v/, '');

            clientUpdateInfo.value = {
                latestVersion: latestVersion,
            };
        }).catch(() => {
            // ignore errors - update check is best-effort
        });
    }

    return {
        // constants
        clientVersion,
        // states
        clientVersionMatchServerVersion,
        // computed states
        serverDisplayVersion,
        clientBuildTime,
        exchangeRatesData,
        isUserCustomExchangeRates,
        mapProviderName,
        mapProviderWebsite,
        contributors,
        licenseLines,
        thirdPartyLicenses,
        clientUpdateInfo,
        hasUpdate,
        // functions
        refreshBrowserCache,
        init
    };
}
