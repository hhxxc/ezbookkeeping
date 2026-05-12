<template>
    <f7-page>
        <f7-navbar :title="tt('Settings')" :back-link="tt('Back')"></f7-navbar>

        <f7-block-title class="margin-top">{{ currentNickName }}</f7-block-title>
        <f7-list strong inset dividers>
            <f7-list-item :title="tt('User Profile')" link="/user/profile"></f7-list-item>
            <f7-list-item :title="tt('Transaction Categories')" link="/category/all"></f7-list-item>
            <f7-list-item :title="tt('Transaction Tags')" link="/tag/list"></f7-list-item>
            <f7-list-item :title="tt('Transaction Templates')" link="/template/list"></f7-list-item>
            <f7-list-item :title="tt('Scheduled Transactions')" link="/schedule/list" v-if="isUserScheduledTransactionEnabled()"></f7-list-item>
            <f7-list-item :title="tt('Data Management')" link="/user/data/management"></f7-list-item>
            <f7-list-item :title="tt('Two-Factor Authentication')" link="/user/2fa"></f7-list-item>
            <f7-list-item :title="tt('Device & Sessions')" link="/user/sessions"></f7-list-item>
            <f7-list-button :class="{ 'disabled': logouting }" @click="logout">{{ tt('Log Out') }}</f7-list-button>
        </f7-list>

        <f7-block-title>{{ tt('Application') }}</f7-block-title>
        <f7-list strong inset dividers class="settings-list">
            <f7-list-item
                link="#"
                :title="tt('Theme')"
                :after="findNameByValue(allThemes, currentTheme)"
                @click="showThemePopup = true"
            >
                <list-item-selection-popup value-type="item"
                                           key-field="value" value-field="value"
                                           title-field="name"
                                           :title="tt('Theme')"
                                           :enable-filter="true"
                                           :filter-placeholder="tt('Theme')"
                                           :filter-no-items-text="tt('No results')"
                                           :items="allThemes"
                                           v-model:show="showThemePopup"
                                           v-model="currentTheme">
                </list-item-selection-popup>
            </f7-list-item>

            <f7-list-item :title="tt('Text Size')" link="/settings/textsize"></f7-list-item>

            <f7-list-item
                class="item-truncate-after-text"
                link="#"
                @click="showTimezonePopup = true"
            >
                <template #after-title>
                    <div class="item-actual-title">
                        <span>{{ tt('Timezone') }}</span>
                    </div>
                </template>
                <template #after>
                    {{ currentTimezoneName }}
                </template>
                <list-item-selection-popup value-type="item"
                                           key-field="name" value-field="name"
                                           title-field="displayNameWithUtcOffset"
                                           :title="tt('Timezone')"
                                           :enable-filter="true"
                                           :filter-placeholder="tt('Timezone')"
                                           :filter-no-items-text="tt('No results')"
                                           :items="allTimezones"
                                           v-model:show="showTimezonePopup"
                                           v-model="timeZone">
                </list-item-selection-popup>
            </f7-list-item>

            <f7-list-item :title="tt('Application Lock')" :after="isEnableApplicationLock ? tt('Enabled') : tt('Disabled')" link="/app_lock"></f7-list-item>

            <f7-list-item :title="tt('Exchange Rates Data')" :after="exchangeRatesLastUpdateDate" link="/exchange_rates"></f7-list-item>

            <f7-list-item>
                <template #after-title>
                    {{ tt('Auto-update Exchange Rates Data') }}
                </template>
                <template #after>
                    <f7-toggle :checked="isAutoUpdateExchangeRatesData" @toggle:change="isAutoUpdateExchangeRatesData = $event"></f7-toggle>
                </template>
            </f7-list-item>

            <f7-list-item>
                <template #after-title>
                    {{ tt('Show Account Balance') }}
                </template>
                <template #after>
                    <f7-toggle :checked="showAccountBalance" @toggle:change="showAccountBalance = $event"></f7-toggle>
                </template>
            </f7-list-item>

            <f7-list-item :title="tt('Page Settings')" link="/settings/page"></f7-list-item>
            <f7-list-item :title="tt('Statistics Settings')" link="/statistic/settings"></f7-list-item>
            <f7-list-item :title="tt('Settings Sync')" link="/settings/sync"></f7-list-item>

            <f7-list-item>
                <template #after-title>
                    {{ tt('Enable Swipe Back') }}
                </template>
                <template #after>
                    <f7-toggle :checked="isEnableSwipeBack" @toggle:change="isEnableSwipeBack = $event"></f7-toggle>
                </template>
            </f7-list-item>

            <f7-list-item>
                <template #after-title>
                    {{ tt('Enable Animation') }}
                </template>
                <template #after>
                    <f7-toggle :checked="isEnableAnimate" @toggle:change="isEnableAnimate = $event"></f7-toggle>
                </template>
            </f7-list-item>

            <f7-list-item :title="tt('Browser Cache Management')" link="/settings/browser_caches"></f7-list-item>
            <f7-list-item link="#" no-chevron :title="tt('Switch to Desktop Version')" @click="switchToDesktopVersion"></f7-list-item>

            <f7-list-item :title="tt('About')" link="/about" :after="version"></f7-list-item>

            <f7-list-item
                link="#"
                class="list-item-no-item-after"
                :title="tt('Home Background Image')"
                :after="homeGalleryBackgroundName || tt('Default')"
                @click="showBackgroundGallery = true"
            ></f7-list-item>

            <f7-list-item>
                <template #after-title>
                    <span>{{ tt('Custom Background') }}</span>
                </template>
                <template #after>
                    <div class="display-flex align-items-center">
                        <img v-if="homeBackgroundImage" :src="homeBackgroundImage" style="width: 40px; height: 20px; object-fit: cover; margin-right: 8px; border-radius: 4px;" />
                        <f7-link @click="onHomeBackgroundImageClick">{{ homeBackgroundImage ? tt('Change') : tt('Upload') }}</f7-link>
                        <f7-link v-if="homeBackgroundImage" @click="onRemoveHomeBackgroundImage" class="margin-inline-start-half">{{ tt('Remove') }}</f7-link>
                    </div>
                </template>
            </f7-list-item>
        </f7-list>

        <input ref="homeBgInput" type="file" style="display: none" :accept="SUPPORTED_IMAGE_EXTENSIONS" @change="uploadHomeBackgroundImage($event)" />

        <background-selection-sheet
            v-model:show="showBackgroundGallery"
            v-model="homeGalleryBackgroundId"
        />
    </f7-page>
</template>

<script setup lang="ts">
import { ref, computed, useTemplateRef, watch } from 'vue';
import type { Router } from 'framework7/types';

import { useI18n } from '@/locales/helpers.ts';
import { useI18nUIComponents, showLoading, hideLoading } from '@/lib/ui/mobile.ts';
import { useAppSettingPageBase } from '@/views/base/settings/AppSettingsPageBase.ts';

import { useRootStore } from '@/stores/index.ts';
import { useSettingsStore } from '@/stores/setting.ts';
import { useUserStore } from '@/stores/user.ts';
import { useExchangeRatesStore } from '@/stores/exchangeRates.ts';

import { findNameByValue } from '@/lib/common.ts';
import { parseDateTimeFromUnixTime } from '@/lib/datetime.ts';
import { getClientDisplayVersion, getDesktopVersionPath } from '@/lib/version.ts';
import { isUserScheduledTransactionEnabled } from '@/lib/server_settings.ts';
import { setExpenseAndIncomeAmountColor } from '@/lib/ui/common.ts';
import { SUPPORTED_IMAGE_EXTENSIONS } from '@/consts/file.ts';
import { GALLERY_BACKGROUNDS } from '@/consts/gallery.ts';
import BackgroundSelectionSheet from '@/components/mobile/BackgroundSelectionSheet.vue';

const props = defineProps<{
    f7router: Router.Router;
}>();

const { tt, formatDateTimeToLongDate, initLocale } = useI18n();
const { showToast, showConfirm } = useI18nUIComponents();
const { allThemes, allTimezones, timeZone, isAutoUpdateExchangeRatesData, showAccountBalance } = useAppSettingPageBase();

const rootStore = useRootStore();
const settingsStore = useSettingsStore();
const userStore = useUserStore();
const exchangeRatesStore = useExchangeRatesStore();

const version = `${getClientDisplayVersion()}`;

const logouting = ref<boolean>(false);
const showThemePopup = ref<boolean>(false);
const showTimezonePopup = ref<boolean>(false);

const homeBackgroundImage = ref<string>(settingsStore.appSettings.homeSummaryBackgroundImage);
const homeGalleryBackgroundId = ref<string>(settingsStore.appSettings.homeGalleryBackgroundId || '');
const showBackgroundGallery = ref<boolean>(false);
const homeBgInput = useTemplateRef<HTMLInputElement>('homeBgInput');

const homeGalleryBackgroundName = computed<string>(() => {
    if (!homeGalleryBackgroundId.value) return '';
    const bg = GALLERY_BACKGROUNDS.find(b => b.id === homeGalleryBackgroundId.value);
    return bg ? bg.name : '';
});

watch(homeGalleryBackgroundId, (newId) => {
    if (newId) {
        settingsStore.setHomeSummaryBackgroundImage('');
        homeBackgroundImage.value = '';
    }
    settingsStore.setHomeGalleryBackgroundId(newId);
});

const currentNickName = computed<string>(() => userStore.currentUserNickname || tt('User'));

const currentTheme = computed<string>({
    get: () => settingsStore.appSettings.theme,
    set: value => {
        if (value !== settingsStore.appSettings.theme) {
            settingsStore.setTheme(value);
            location.reload();
        }
    }
});

const currentTimezoneName = computed<string>(() => {
    for (const item of allTimezones.value) {
        if (item.name === timeZone.value) {
            return item.displayNameWithUtcOffset;
        }
    }

    return '';
});

const isEnableSwipeBack = computed<boolean>({
    get: () => settingsStore.appSettings.swipeBack,
    set: value => {
        if (value !== settingsStore.appSettings.swipeBack) {
            settingsStore.setEnableSwipeBack(value);
            location.reload();
        }
    }
});

const isEnableAnimate = computed<boolean>({
    get: () => settingsStore.appSettings.animate,
    set: value => {
        if (value !== settingsStore.appSettings.animate) {
            settingsStore.setEnableAnimate(value);
            location.reload();
        }
    }
});

const isEnableApplicationLock = computed<boolean>(() => settingsStore.appSettings.applicationLock);

const exchangeRatesLastUpdateDate = computed<string>(() => {
    if (!exchangeRatesStore.exchangeRatesLastUpdateTime) {
        return '';
    }

    const exchangeRatesLastUpdateTime = parseDateTimeFromUnixTime(exchangeRatesStore.exchangeRatesLastUpdateTime);
    return formatDateTimeToLongDate(exchangeRatesLastUpdateTime);
});

function switchToDesktopVersion(): void {
    showConfirm('Are you sure you want to switch to desktop version?', () => {
        window.location.replace(getDesktopVersionPath());
    });
}

function onHomeBackgroundImageClick(): void {
    homeBgInput.value?.click();
}

function uploadHomeBackgroundImage(event: Event): void {
    const target = event.target as HTMLInputElement;
    const file = target.files?.[0];

    if (!file) {
        return;
    }

    const reader = new FileReader();

    reader.onload = (e) => {
        const img = new Image();

        img.onload = () => {
            const canvas = document.createElement('canvas');
            const ctx = canvas.getContext('2d');

            if (!ctx) {
                return;
            }

            const targetRatio = 2;
            const maxOutputWidth = 800;

            let sourceX = 0;
            let sourceY = 0;
            let sourceWidth = img.width;
            let sourceHeight = img.height;
            const currentRatio = sourceWidth / sourceHeight;

            if (currentRatio > targetRatio) {
                sourceWidth = sourceHeight * targetRatio;
                sourceX = (img.width - sourceWidth) / 2;
            } else if (currentRatio < targetRatio) {
                sourceHeight = sourceWidth / targetRatio;
                sourceY = (img.height - sourceHeight) / 2;
            }

            const outputWidth = Math.min(img.width, maxOutputWidth);
            const outputHeight = outputWidth / targetRatio;

            canvas.width = outputWidth;
            canvas.height = outputHeight;
            ctx.drawImage(img, sourceX, sourceY, sourceWidth, sourceHeight, 0, 0, outputWidth, outputHeight);

            const dataUrl = canvas.toDataURL('image/jpeg', 0.85);
            settingsStore.setHomeSummaryBackgroundImage(dataUrl);
            homeBackgroundImage.value = dataUrl;
        };

        img.src = e.target?.result as string;
    };

    reader.readAsDataURL(file);
    target.value = '';
}

function onRemoveHomeBackgroundImage(): void {
    showConfirm('Remove home background image?', () => {
        settingsStore.setHomeSummaryBackgroundImage('');
        homeBackgroundImage.value = '';
    });
}

function logout(): void {
    showConfirm('Are you sure you want to log out?', () => {
        logouting.value = true;
        showLoading(() => logouting.value);

        rootStore.logout().then(() => {
            logouting.value = false;
            hideLoading();

            settingsStore.clearAppSettings();

            const localeDefaultSettings = initLocale(userStore.currentUserLanguage, settingsStore.appSettings.timeZone);
            settingsStore.updateLocalizedDefaultSettings(localeDefaultSettings);

            setExpenseAndIncomeAmountColor(userStore.currentUserExpenseAmountColor, userStore.currentUserIncomeAmountColor);

            props.f7router.navigate('/');
        }).catch(error => {
            logouting.value = false;
            hideLoading();

            if (!error.processed) {
                showToast(error.message || error);
            }
        });
    });
}
</script>
