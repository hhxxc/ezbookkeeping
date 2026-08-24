<template>
    <f7-page ptr @ptr:refresh="reload" @page:afterin="onPageAfterIn">
        <f7-navbar>
            <f7-nav-title :title="tt('global.app.title')"></f7-nav-title>
        </f7-navbar>

        <f7-card class="home-summary-card" :class="{ 'skeleton-text': loading }" :style="homeSummaryCardStyle" @taphold="showBackgroundGallery = true">
            <f7-link class="home-card-gallery-btn" @click="showBackgroundGallery = true">
                <f7-icon f7="photo_on_rectangle" style="font-size: 16px; color: rgba(0,0,0,0.35);"></f7-icon>
            </f7-link>
            <f7-card-header class="display-block" style="padding: 20px 20px 16px;">
                <div class="home-summary-row">
                    <span class="home-summary-label">
                        <span v-if="loading">{{ displayDateRange?.thisMonth?.displayTime }}</span>
                        <span v-else-if="!loading">{{ displayDateRange?.thisMonth?.displayTime }}</span>
                    </span>
                    <span class="home-summary-badge expense-badge">{{ tt('Expense') }}</span>
                </div>
                <div class="home-summary-amount expense-amount">
                    <span v-if="loading">0.00</span>
                    <span v-else-if="!loading">{{ transactionOverview && transactionOverview.thisMonth ? getDisplayExpenseAmount(transactionOverview.thisMonth) : '-' }}</span>
                    <f7-link class="display-inline-flex margin-inline-start-half" @click="showAmountInHomePage = !showAmountInHomePage">
                        <f7-icon class="ebk-hide-icon" :f7="showAmountInHomePage ? 'eye_slash_fill' : 'eye_fill'"></f7-icon>
                    </f7-link>
                </div>
                <div class="home-summary-income-row">
                    <span class="home-summary-income-label">{{ tt('Monthly income') }}</span>
                    <span class="home-summary-income-value">
                        <span v-if="loading">0.00</span>
                        <span v-else-if="!loading">{{ transactionOverview && transactionOverview.thisMonth ? getDisplayIncomeAmount(transactionOverview.thisMonth) : '-' }}</span>
                    </span>
                </div>
            </f7-card-header>
        </f7-card>

        <f7-list strong inset dividers class="margin-top overview-transaction-list" :class="{ 'skeleton-text': loading }">
            <f7-list-item :link="`/transaction/list?${overviewStore.getTransactionListPageParams({ dateType: DateRange.Today.type })}`" chevron-center>
                <template #media>
                    <f7-icon f7="calendar_today"></f7-icon>
                </template>
                <template #title>
                    <div class="padding-top-half">
                        <span v-if="loading">Today</span>
                        <span v-else-if="!loading">{{ tt('Today') }}</span>
                    </div>
                </template>
                <template #footer>
                    <div class="overview-transaction-footer padding-bottom-half">
                        <span v-if="loading">MM/DD/YYYY</span>
                        <span v-else-if="!loading">{{ displayDateRange?.today?.displayTime }}</span>
                    </div>
                </template>
                <template #after>
                    <div class="overview-transaction-amount">
                        <div class="text-income text-align-right">
                            <small v-if="loading">0.00 USD</small>
                            <small v-else-if="!loading && transactionOverview.today && transactionOverview.today.valid">{{ getDisplayIncomeAmount(transactionOverview.today) }}</small>
                        </div>
                        <div class="text-expense text-align-right">
                            <small v-if="loading">0.00 USD</small>
                            <small v-else-if="!loading && transactionOverview.today && transactionOverview.today.valid">{{ getDisplayExpenseAmount(transactionOverview.today) }}</small>
                        </div>
                    </div>
                </template>
            </f7-list-item>

            <f7-list-item :link="`/transaction/list?${overviewStore.getTransactionListPageParams({ dateType: DateRange.Yesterday.type })}`" chevron-center>
                <template #media>
                    <f7-icon f7="calendar"></f7-icon>
                </template>
                <template #title>
                    <div class="padding-top-half">
                        <span v-if="loading">Yesterday</span>
                        <span v-else-if="!loading">{{ tt('Yesterday') }}</span>
                    </div>
                </template>
                <template #footer>
                    <div class="overview-transaction-footer padding-bottom-half">
                        <span v-if="loading">MM/DD/YYYY</span>
                        <span v-else-if="!loading">{{ displayDateRange?.yesterday?.displayTime }}</span>
                    </div>
                </template>
                <template #after>
                    <div class="overview-transaction-amount">
                        <div class="text-income text-align-right">
                            <small v-if="loading">0.00 USD</small>
                            <small v-else-if="!loading && transactionOverview.yesterday && transactionOverview.yesterday.valid">{{ getDisplayIncomeAmount(transactionOverview.yesterday) }}</small>
                        </div>
                        <div class="text-expense text-align-right">
                            <small v-if="loading">0.00 USD</small>
                            <small v-else-if="!loading && transactionOverview.yesterday && transactionOverview.yesterday.valid">{{ getDisplayExpenseAmount(transactionOverview.yesterday) }}</small>
                        </div>
                    </div>
                </template>
            </f7-list-item>

            <f7-list-item :link="`/transaction/list?${overviewStore.getTransactionListPageParams({ dateType: DateRange.ThisWeek.type })}`" chevron-center>
                <template #media>
                    <f7-icon f7="calendar"></f7-icon>
                </template>
                <template #title>
                    <div class="padding-top-half">
                        <span v-if="loading">This Week</span>
                        <span v-else-if="!loading">{{ tt('This Week') }}</span>
                    </div>
                </template>
                <template #footer>
                    <div class="overview-transaction-footer padding-bottom-half">
                        <span v-if="loading">MM/DD</span>
                        <span v-else-if="!loading">{{ displayDateRange?.thisWeek?.startTime }}</span>
                        <span>-</span>
                        <span v-if="loading">MM/DD</span>
                        <span v-else-if="!loading">{{ displayDateRange?.thisWeek?.endTime }}</span>
                    </div>
                </template>
                <template #after>
                    <div class="overview-transaction-amount">
                        <div class="text-income text-align-right">
                            <small v-if="loading">0.00 USD</small>
                            <small v-else-if="!loading && transactionOverview.thisWeek && transactionOverview.thisWeek.valid">{{ getDisplayIncomeAmount(transactionOverview.thisWeek) }}</small>
                        </div>
                        <div class="text-expense text-align-right">
                            <small v-if="loading">0.00 USD</small>
                            <small v-else-if="!loading && transactionOverview.thisWeek && transactionOverview.thisWeek.valid">{{ getDisplayExpenseAmount(transactionOverview.thisWeek) }}</small>
                        </div>
                    </div>
                </template>
            </f7-list-item>

            <f7-list-item :link="`/transaction/list?${overviewStore.getTransactionListPageParams({ dateType: DateRange.ThisMonth.type })}`" chevron-center>
                <template #media>
                    <f7-icon f7="calendar"></f7-icon>
                </template>
                <template #title>
                    <div class="padding-top-half">
                        <span v-if="loading">This Month</span>
                        <span v-else-if="!loading">{{ tt('This Month') }}</span>
                    </div>
                </template>
                <template #footer>
                    <div class="overview-transaction-footer padding-bottom-half">
                        <span v-if="loading">MM/DD</span>
                        <span v-else-if="!loading">{{ displayDateRange?.thisMonth?.startTime }}</span>
                        <span>-</span>
                        <span v-if="loading">MM/DD</span>
                        <span v-else-if="!loading">{{ displayDateRange?.thisMonth?.endTime }}</span>
                    </div>
                </template>
                <template #after>
                    <div class="overview-transaction-amount">
                        <div class="text-income text-align-right">
                            <small v-if="loading">0.00 USD</small>
                            <small v-else-if="!loading && transactionOverview.thisMonth && transactionOverview.thisMonth.valid">{{ getDisplayIncomeAmount(transactionOverview.thisMonth) }}</small>
                        </div>
                        <div class="text-expense text-align-right">
                            <small v-if="loading">0.00 USD</small>
                            <small v-else-if="!loading && transactionOverview.thisMonth && transactionOverview.thisMonth.valid">{{ getDisplayExpenseAmount(transactionOverview.thisMonth) }}</small>
                        </div>
                    </div>
                </template>
            </f7-list-item>

            <f7-list-item :link="`/transaction/list?${overviewStore.getTransactionListPageParams({ dateType: DateRange.LastMonth.type, minTime: (displayDateRange?.lastMonth?.startTime || 0).toString(), maxTime: (displayDateRange?.lastMonth?.endTime || 0).toString() })}`" chevron-center>
                <template #media>
                    <f7-icon f7="calendar"></f7-icon>
                </template>
                <template #title>
                    <div class="padding-top-half">
                        <span v-if="loading">Last Month</span>
                        <span v-else-if="!loading">{{ tt('Last Month') }}</span>
                    </div>
                </template>
                <template #footer>
                    <div class="overview-transaction-footer padding-bottom-half">
                        <span v-if="loading">MM/DD</span>
                        <span v-else-if="!loading">{{ displayDateRange?.lastMonth?.startTime }}</span>
                        <span>-</span>
                        <span v-if="loading">MM/DD</span>
                        <span v-else-if="!loading">{{ displayDateRange?.lastMonth?.endTime }}</span>
                    </div>
                </template>
                <template #after>
                    <div class="overview-transaction-amount">
                        <div class="text-income text-align-right">
                            <small v-if="loading">0.00 USD</small>
                            <small v-else-if="!loading && transactionOverview.lastMonth && transactionOverview.lastMonth.valid">{{ getDisplayIncomeAmount(transactionOverview.lastMonth) }}</small>
                        </div>
                        <div class="text-expense text-align-right">
                            <small v-if="loading">0.00 USD</small>
                            <small v-else-if="!loading && transactionOverview.lastMonth && transactionOverview.lastMonth.valid">{{ getDisplayExpenseAmount(transactionOverview.lastMonth) }}</small>
                        </div>
                    </div>
                </template>
            </f7-list-item>

            <f7-list-item :link="`/transaction/list?${overviewStore.getTransactionListPageParams({ dateType: DateRange.ThisYear.type })}`" chevron-center>
                <template #media>
                    <f7-icon f7="square_stack_3d_up"></f7-icon>
                </template>
                <template #title>
                    <div class="padding-top-half">
                        <span v-if="loading">This Year</span>
                        <span v-else-if="!loading">{{ tt('This Year') }}</span>
                    </div>
                </template>
                <template #footer>
                    <div class="overview-transaction-footer padding-bottom-half">
                        <span v-if="loading">YYYY</span>
                        <span v-else-if="!loading">{{ displayDateRange?.thisYear?.displayTime }}</span>
                    </div>
                </template>
                <template #after>
                    <div class="overview-transaction-amount">
                        <div class="text-income text-align-right">
                            <small v-if="loading">0.00 USD</small>
                            <small v-else-if="!loading && transactionOverview.thisYear && transactionOverview.thisYear.valid">{{ getDisplayIncomeAmount(transactionOverview.thisYear) }}</small>
                        </div>
                        <div class="text-expense text-align-right">
                            <small v-if="loading">0.00 USD</small>
                            <small v-else-if="!loading && transactionOverview.thisYear && transactionOverview.thisYear.valid">{{ getDisplayExpenseAmount(transactionOverview.thisYear) }}</small>
                        </div>
                    </div>
                </template>
            </f7-list-item>
        </f7-list>

        <f7-toolbar tabbar icons bottom class="main-tabbar">
            <f7-link class="link" href="/transaction/list">
                <f7-icon f7="square_list"></f7-icon>
                <span class="tabbar-label">{{ tt('Details') }}</span>
            </f7-link>
            <f7-link class="link" href="/account/list">
                <f7-icon f7="creditcard"></f7-icon>
                <span class="tabbar-label">{{ tt('Accounts') }}</span>
            </f7-link>
            <f7-link id="homepage-add-button" class="link dragenabled"
                     href="/transaction/add" @taphold="openTransactionTemplatePopover">
                <f7-icon f7="plus_square" class="ebk-tarbar-big-icon"></f7-icon>
            </f7-link>
            <f7-link class="link" href="/statistic/transaction">
                <f7-icon f7="chart_pie"></f7-icon>
                <span class="tabbar-label">{{ tt('Statistics') }}</span>
            </f7-link>
            <f7-link class="link" href="/settings">
                <f7-icon f7="gear_alt"></f7-icon>
                <span class="tabbar-label">{{ tt('Settings') }}</span>
            </f7-link>
        </f7-toolbar>

        <f7-popover class="template-popover-menu" target-el="#homepage-add-button"
                    v-model:opened="showTransactionTemplatePopover">
            <f7-list dividers v-if="allTransactionTemplates">
                <f7-list-item key="AIImageRecognition" :title="tt('AI Image Recognition')"
                              @click="showAIReceiptImageRecognitionSheet = true; showTransactionTemplatePopover = false"
                              v-if="isTransactionFromAIImageRecognitionEnabled()">
                    <template #media>
                        <f7-icon f7="wand_stars"></f7-icon>
                    </template>
                </f7-list-item>
                <f7-list-item :key="template.id" :title="template.name"
                              :link="'/transaction/add?templateId=' + template.id"
                              v-for="template in allTransactionTemplates">
                    <template #media>
                        <f7-icon f7="doc_plaintext"></f7-icon>
                    </template>
                </f7-list-item>
            </f7-list>
        </f7-popover>

        <a-i-image-recognition-sheet ref="aiImageRecognitionSheet"
                                     v-model:show="showAIReceiptImageRecognitionSheet"
                                     @recognition:change="onReceiptRecognitionChanged"/>

        <background-selection-sheet
            v-model:show="showBackgroundGallery"
            v-model="homeGalleryBackgroundId"
        />

        <template #fixed>
            <f7-fab v-if="isTransactionFromAIImageRecognitionEnabled()"
                    position="right-bottom"
                    class="ai-image-recognition-fab"
                    @click="showAIReceiptImageRecognitionSheet = true">
                <f7-icon f7="camera"></f7-icon>
            </f7-fab>
        </template>
    </f7-page>
</template>

<script setup lang="ts">
import AIImageRecognitionSheet from '@/components/mobile/AIImageRecognitionSheet.vue';
import BackgroundSelectionSheet from '@/components/mobile/BackgroundSelectionSheet.vue';

import { ref, computed, useTemplateRef, watch } from 'vue';
import type { Router } from 'framework7/types';

import { useI18n } from '@/locales/helpers.ts';
import { useI18nUIComponents } from '@/lib/ui/mobile.ts';
import { useHomePageBase } from '@/views/base/HomePageBase.ts';

import { useAccountsStore } from '@/stores/account.ts';
import { useTransactionCategoriesStore } from '@/stores/transactionCategory.ts';
import { useTransactionTemplatesStore } from '@/stores/transactionTemplate.ts';
import { useOverviewStore } from '@/stores/overview.ts';

import { DateRange } from '@/core/datetime.ts';
import { TemplateType } from '@/core/template.ts';
import { TransactionTemplate } from '@/models/transaction_template.ts';
import type { RecognizedReceiptImageResponse } from '@/models/large_language_model.ts';

import { isUserLogined, isUserUnlocked } from '@/lib/userstate.ts';
import { getShareCacheImageBlob } from '@/lib/cache.ts';
import { isTransactionFromAIImageRecognitionEnabled } from '@/lib/server_settings.ts';
import { useSettingsStore } from '@/stores/setting.ts';
import { GALLERY_BACKGROUNDS } from '@/consts/gallery.ts';

type AIImageRecognitionSheetType = InstanceType<typeof AIImageRecognitionSheet>;

const props = defineProps<{
    f7router: Router.Router;
}>();

const { tt } = useI18n();
const { showToast } = useI18nUIComponents();

const {
    showAmountInHomePage,
    displayDateRange,
    transactionOverview,
    getDisplayIncomeAmount,
    getDisplayExpenseAmount
} = useHomePageBase();

const settingsStore = useSettingsStore();
const homeSummaryBackgroundImage = ref<string>(settingsStore.appSettings.homeSummaryBackgroundImage);
const homeGalleryBackgroundId = ref<string>(settingsStore.appSettings.homeGalleryBackgroundId || '');
const showBackgroundGallery = ref<boolean>(false);

watch(homeGalleryBackgroundId, (newId) => {
    if (newId) {
        settingsStore.setHomeSummaryBackgroundImage('');
        homeSummaryBackgroundImage.value = '';
    }
    settingsStore.setHomeGalleryBackgroundId(newId);
});

const homeSummaryCardStyle = computed(() => {
    if (homeGalleryBackgroundId.value) {
        const bg = GALLERY_BACKGROUNDS.find(b => b.id === homeGalleryBackgroundId.value);
        if (bg) {
            return {
                'background-image': bg.css,
                'background-size': 'cover',
                'background-position': 'center',
                'background-repeat': 'no-repeat'
            } as Record<string, string>;
        }
    }
    if (homeSummaryBackgroundImage.value) {
        return {
            'background-image': `url(${homeSummaryBackgroundImage.value})`,
            'background-size': 'cover',
            'background-position': 'center',
            'background-repeat': 'no-repeat'
        } as Record<string, string>;
    }
    return {} as Record<string, string>;
});

const accountsStore = useAccountsStore();
const transactionCategoriesStore = useTransactionCategoriesStore();
const transactionTemplatesStore = useTransactionTemplatesStore();
const overviewStore = useOverviewStore();

const aiImageRecognitionSheet = useTemplateRef<AIImageRecognitionSheetType>('aiImageRecognitionSheet');

const loading = ref<boolean>(true);
const showTransactionTemplatePopover = ref<boolean>(false);
const showAIReceiptImageRecognitionSheet = ref<boolean>(false);

const allTransactionTemplates = computed<TransactionTemplate[]>(() => {
    const allTemplates = transactionTemplatesStore.allVisibleTemplates;
    return allTemplates[TemplateType.Normal.type] || [];
});

function openTransactionTemplatePopover(): void {
    if (isTransactionFromAIImageRecognitionEnabled() || (allTransactionTemplates.value && allTransactionTemplates.value.length)) {
        showTransactionTemplatePopover.value = true;
    }
}

function init(): void {
    if (isUserLogined() && isUserUnlocked()) {
        loading.value = true;

        // Load overview first for fast initial paint, then warm caches in background
        overviewStore.loadTransactionOverview({ force: false, loadLast11Months: true }).then(() => {
            loading.value = false;
        }).catch(error => {
            loading.value = false;

            if (!error.processed) {
                showToast(error.message || error);
            }
        });

        // Pre-warm caches non-blocking, not needed for home page display
        Promise.all([
            getShareCacheImageBlob(),
            accountsStore.loadAllAccounts({ force: false }),
            transactionCategoriesStore.loadAllCategories({ force: false }),
            transactionTemplatesStore.loadAllTemplates({ templateType: TemplateType.Normal.type, force: false })
        ]).then(responses => {
            if (responses[0] && responses[0] instanceof Blob) {
                aiImageRecognitionSheet.value?.loadImage(responses[0]);
                showAIReceiptImageRecognitionSheet.value = true;
            }
        }).catch(() => {
            // background cache pre-warm failures are non-critical
        });
    }
}

function reload(done?: () => void): void {
    const force = !!done;

    overviewStore.loadTransactionOverview({
        force: force,
        loadLast11Months: true
    }).then(() => {
        done?.();

        if (force) {
            showToast('Data has been updated');
        }
    }).catch(error => {
        done?.();

        if (!error.processed) {
            showToast(error.message || error);
        }
    });
}

function onReceiptRecognitionChanged(result: RecognizedReceiptImageResponse): void {
    const params: string[] = [];

    if (result.type) {
        params.push(`type=${result.type}`);
    }

    if (result.time) {
        params.push(`time=${result.time}`);
    }

    if (result.categoryId) {
        params.push(`categoryId=${result.categoryId}`);
    }

    if (result.sourceAccountId) {
        params.push(`accountId=${result.sourceAccountId}`);
    }

    if (result.destinationAccountId) {
        params.push(`destinationAccountId=${result.destinationAccountId}`);
    }

    if (result.sourceAmount) {
        params.push(`amount=${result.sourceAmount}`);
    }

    if (result.destinationAmount) {
        params.push(`destinationAmount=${result.destinationAmount}`);
    }

    if (result.tagIds) {
        params.push(`tagIds=${result.tagIds.join(',')}`);
    }

    if (result.comment) {
        params.push(`comment=${encodeURIComponent(result.comment)}`);
    }

    params.push(`noTransactionDraft=true`);

    props.f7router.navigate(`/transaction/add?${params.join('&')}`);
}

function onPageAfterIn(): void {
    homeSummaryBackgroundImage.value = settingsStore.appSettings.homeSummaryBackgroundImage;
    homeGalleryBackgroundId.value = settingsStore.appSettings.homeGalleryBackgroundId || '';

    if (!loading.value) {
        reload();
    }
}

init();
</script>

<style>
.home-summary-card {
    background: #fff;
    border-radius: var(--ebk-card-border-radius);
    color: #1a1a1a;
    overflow: hidden;
    margin: 12px 16px !important;
    border: none;
    outline: none;
}

.dark .home-summary-card {
    background: #1c1c1e;
    color: #f0f0f0;
}

.home-summary-card::before,
.home-summary-card::after {
    display: none !important;
    content: none !important;
    background: none !important;
}

.home-summary-card * {
    background-color: transparent !important;
}

.home-card-gallery-btn {
    position: absolute;
    top: 10px;
    right: 10px;
    z-index: 5;
    width: 30px;
    height: 30px;
    border-radius: 8px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: rgba(0, 0, 0, 0.04);
}

.dark .home-card-gallery-btn {
    background: rgba(255, 255, 255, 0.08);
}

.home-card-gallery-btn:active {
    background: rgba(0, 0, 0, 0.08);
}

.dark .home-card-gallery-btn:active {
    background: rgba(255, 255, 255, 0.15);
}

.home-summary-row {
    display: flex;
    align-items: center;
    gap: 10px;
    margin-bottom: 4px;
}

.home-summary-label {
    font-size: 1.05em;
    font-weight: 600;
}

.home-summary-badge {
    font-size: 0.72em;
    font-weight: 600;
    padding: 2px 10px;
    border-radius: 20px;
    letter-spacing: 0.02em;
}

.expense-badge {
    background: #fee2e2;
    color: #dc2626;
}

.dark .expense-badge {
    background: rgba(220, 38, 38, 0.15);
    color: #fca5a5;
}

.home-summary-amount {
    font-size: 2em;
    font-weight: 700;
    letter-spacing: -0.02em;
    margin-bottom: 8px;
}

.expense-amount {
    color: #dc2626;
}

.dark .expense-amount {
    color: #fca5a5;
}

.home-summary-income-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding-top: 8px;
    border-top: 1px solid rgba(0, 0, 0, 0.06);
}

.dark .home-summary-income-row {
    border-top-color: rgba(255, 255, 255, 0.08);
}

.home-summary-income-label {
    font-size: 0.88em;
    color: rgba(0, 0, 0, 0.5);
}

.dark .home-summary-income-label {
    color: rgba(255, 255, 255, 0.5);
}

.home-summary-income-value {
    font-size: 1em;
    font-weight: 600;
    color: #07c160;
}

.dark .home-summary-income-value {
    color: #6ee7b7;
}

.home-summary-card .ebk-hide-icon {
    color: rgba(0, 0, 0, 0.25);
    font-size: 18px;
}

.dark .home-summary-card .ebk-hide-icon {
    color: rgba(255, 255, 255, 0.35);
}

.overview-transaction-list .item-title > div {
    overflow: hidden;
    text-overflow: ellipsis;
}

.overview-transaction-list .item-after {
    max-width: 100%;
}

.overview-transaction-list .overview-transaction-footer {
    padding-top: 6px;
    font-size: var(--ebk-large-footer-font-size);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
}

.overview-transaction-list .overview-transaction-footer > span {
    margin-inline-end: 4px;
}

.overview-transaction-list .overview-transaction-amount {
    max-width: 100%;
}

.overview-transaction-list .overview-transaction-amount > div {
    max-width: 100%;
    overflow: hidden;
    text-overflow: ellipsis;
}

.tabbar.main-tabbar .link i + span.tabbar-label {
    margin-top: var(--ebk-icon-text-margin);
}

.tabbar.main-tabbar .link i.ebk-tarbar-big-icon {
    font-size: var(--ebk-big-icon-button-size);
    width: var(--ebk-big-icon-button-size);
    height: var(--ebk-big-icon-button-size);
    line-height: var(--ebk-big-icon-button-size);
}

.template-popover-menu .popover-inner {
    max-height: 400px;
    overflow-y: auto;
}

.ai-image-recognition-fab {
    bottom: calc(var(--f7-toolbar-height) + var(--f7-safe-area-bottom) + 16px) !important;
}
</style>
