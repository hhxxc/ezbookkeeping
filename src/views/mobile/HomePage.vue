<template>
    <f7-page class="home-page" ptr @ptr:refresh="reload" @page:afterin="onPageAfterIn" :style="pageBackgroundStyle">
        <f7-card class="home-summary-card" :class="{ 'skeleton-text': loading, 'has-bg': !!homeSummaryBackgroundImage }" :style="homeSummaryCardStyle" @taphold="onHomeBgInputClick">
            <f7-link class="home-card-gallery-btn" @click="onHomeBgInputClick">
                <f7-icon f7="photo_on_rectangle" style="font-size: 16px; color: rgba(0,0,0,0.35);"></f7-icon>
            </f7-link>
            <f7-card-header class="display-block" style="padding: 16px 16px 14px;">
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
                <div class="home-summary-metrics">
                    <div class="home-summary-metric">
                        <span class="home-summary-metric-label">{{ tt('Monthly income') }}</span>
                        <span class="home-summary-metric-value text-income">
                            <span v-if="loading">0.00</span>
                            <span v-else-if="!loading">{{ transactionOverview && transactionOverview.thisMonth ? getDisplayIncomeAmount(transactionOverview.thisMonth) : '-' }}</span>
                        </span>
                    </div>
                    <div class="home-summary-metric-divider"></div>
                    <div class="home-summary-metric">
                        <span class="home-summary-metric-label">月结余</span>
                        <span class="home-summary-metric-value" :class="monthlyBalanceClass">
                            <span v-if="loading">0.00</span>
                            <span v-else-if="!loading">{{ monthlyBalanceDisplay }}</span>
                        </span>
                    </div>
                </div>
            </f7-card-header>
        </f7-card>

        <f7-list strong inset dividers class="margin-top overview-transaction-list" :class="{ 'skeleton-text': loading }">
            <f7-list-item :link="`/transaction/list?${overviewStore.getTransactionListPageParams({ dateType: DateRange.Today.type })}`" chevron-center>
                <template #media>
                    <f7-icon f7="calendar_today"></f7-icon>
                </template>
                <template #title>
                    <div>
                        <span v-if="loading">Today</span>
                        <span v-else-if="!loading">{{ tt('Today') }}</span>
                    </div>
                </template>
                <template #footer>
                    <div class="overview-transaction-footer">
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
                    <div>
                        <span v-if="loading">Yesterday</span>
                        <span v-else-if="!loading">{{ tt('Yesterday') }}</span>
                    </div>
                </template>
                <template #footer>
                    <div class="overview-transaction-footer">
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
                    <div>
                        <span v-if="loading">This Week</span>
                        <span v-else-if="!loading">{{ tt('This Week') }}</span>
                    </div>
                </template>
                <template #footer>
                    <div class="overview-transaction-footer">
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
                    <div>
                        <span v-if="loading">This Month</span>
                        <span v-else-if="!loading">{{ tt('This Month') }}</span>
                    </div>
                </template>
                <template #footer>
                    <div class="overview-transaction-footer">
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

            <f7-list-item :link="`/transaction/list?${overviewStore.getTransactionListPageParams({ dateType: DateRange.LastMonth.type })}`" chevron-center>
                <template #media>
                    <f7-icon f7="calendar"></f7-icon>
                </template>
                <template #title>
                    <div>
                        <span v-if="loading">Last Month</span>
                        <span v-else-if="!loading">{{ tt('Last Month') }}</span>
                    </div>
                </template>
                <template #footer>
                    <div class="overview-transaction-footer">
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
                    <div>
                        <span v-if="loading">This Year</span>
                        <span v-else-if="!loading">{{ tt('This Year') }}</span>
                    </div>
                </template>
                <template #footer>
                    <div class="overview-transaction-footer">
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
            <f7-link id="homepage-add-button" class="link dragenabled home-add-button"
                     href="/transaction/add" @taphold="openTransactionTemplatePopover">
                <f7-icon f7="plus" class="home-add-icon"></f7-icon>
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

        <input ref="homeBgInput" type="file" style="display: none" accept="image/*" @change="uploadHomeBackgroundImage($event)" />

        <a-i-image-recognition-sheet ref="aiImageRecognitionSheet"
                                     v-model:show="showAIReceiptImageRecognitionSheet"
                                     @recognition:change="onReceiptRecognitionChanged"/>

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

import { ref, computed, useTemplateRef } from 'vue';
import type { Router } from 'framework7/types';

import { useI18n } from '@/locales/helpers.ts';
import { useI18nUIComponents, showLoading, hideLoading } from '@/lib/ui/mobile.ts';
import { useHomePageBase } from '@/views/base/HomePageBase.ts';

import { useAccountsStore } from '@/stores/account.ts';
import { useTransactionCategoriesStore } from '@/stores/transactionCategory.ts';
import { useTransactionTemplatesStore } from '@/stores/transactionTemplate.ts';
import { useOverviewStore } from '@/stores/overview.ts';

import { DateRange } from '@/core/datetime.ts';
import { TemplateType } from '@/core/template.ts';
import { TransactionTemplate } from '@/models/transaction_template.ts';
import type { RecognizedReceiptImageResponses } from '@/models/large_language_model.ts';

import { isUserLogined, isUserUnlocked } from '@/lib/userstate.ts';
import { getShareCacheImageBlob } from '@/lib/cache.ts';
import { isTransactionFromAIImageRecognitionEnabled } from '@/lib/server_settings.ts';
import { useSettingsStore } from '@/stores/setting.ts';
import services from '@/lib/services.ts';
import { compressJpgImage } from '@/lib/ui/common.ts';
import { KnownFileType } from '@/core/file.ts';

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
    getDisplayAmount,
    getDisplayIncomeAmount,
    getDisplayExpenseAmount
} = useHomePageBase();

const monthlyBalanceDisplay = computed<string>(() => {
    const item = transactionOverview.value?.thisMonth;
    if (!item) {
        return '-';
    }

    return getDisplayAmount(item.incomeAmount - item.expenseAmount, item.incompleteIncomeAmount || item.incompleteExpenseAmount);
});

const monthlyBalanceClass = computed<string>(() => {
    const item = transactionOverview.value?.thisMonth;
    if (!item) {
        return 'text-expense';
    }

    return item.incomeAmount - item.expenseAmount >= 0 ? 'text-income' : 'text-expense';
});

const settingsStore = useSettingsStore();
const homeSummaryBackgroundImage = ref<string>(settingsStore.appSettings.homeSummaryBackgroundImage);
const homeBgInput = useTemplateRef<HTMLInputElement>('homeBgInput');

const homeSummaryCardStyle = computed(() => {
    if (homeSummaryBackgroundImage.value) {
        const imageUrl = services.getHomeBackgroundImageUrl(homeSummaryBackgroundImage.value);
        // 图片上叠一层暗色渐变（scrim），保证卡片文字在任意图片上都可读
        return {
            'background-image': `linear-gradient(rgba(0, 0, 0, 0.26), rgba(0, 0, 0, 0.46)), url(${imageUrl})`,
            'background-size': 'cover',
            'background-position': 'center',
            'background-repeat': 'no-repeat'
        } as Record<string, string>;
    }
    return {} as Record<string, string>;
});

const pageBackgroundImage = ref<string>(settingsStore.appSettings.pageBackgroundImage);

const pageBackgroundStyle = computed(() => {
    if (pageBackgroundImage.value) {
        const imageUrl = services.getHomeBackgroundImageUrl(pageBackgroundImage.value);
        return {
            'background-image': `url(${imageUrl})`,
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

const pendingRecognitionQueue = ref<RecognizedReceiptImageResponses>([]);

function onReceiptRecognitionChanged(results: RecognizedReceiptImageResponses): void {
    if (!results || results.length === 0) {
        return;
    }

    // Put all results in queue, navigate to first one
    pendingRecognitionQueue.value = [...results];
    navigateToNextRecognition();
}

function navigateToNextRecognition(): void {
    if (pendingRecognitionQueue.value.length === 0) {
        return;
    }

    const result = pendingRecognitionQueue.value.shift()!;
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

function onHomeBgInputClick(): void {
    homeBgInput.value?.click();
}

function uploadHomeBackgroundImage(event: Event): void {
    const target = event.target as HTMLInputElement;
    const file = target.files?.[0];

    if (!file) {
        return;
    }

    showLoading();

    compressJpgImage(file, 1200, 900, 0.85).then(compressedBlob => {
        const compressedFile = KnownFileType.JPG.createFileFromBlob(compressedBlob, 'bg');
        return services.uploadHomeBackground({ pictureFile: compressedFile });
    }).then(response => {
        hideLoading();
        const data = response.data;

        if (!data || !data.success || !data.result) {
            showToast(tt('Failed to upload image'));
            return;
        }

        const imageUrl = data.result.url;
        settingsStore.setHomeSummaryBackgroundImage(imageUrl);
        homeSummaryBackgroundImage.value = imageUrl;
    }).catch(error => {
        hideLoading();
        console.error('[HomePage] upload home background failed:', error);
        showToast(error?.message || tt('Failed to upload image'));
    });

    target.value = '';
}

function onPageAfterIn(): void {
    homeSummaryBackgroundImage.value = settingsStore.appSettings.homeSummaryBackgroundImage;
    pageBackgroundImage.value = settingsStore.appSettings.pageBackgroundImage;

    // Continue recognition queue if there are pending results
    if (pendingRecognitionQueue.value.length > 0) {
        navigateToNextRecognition();
        return;
    }

    if (!loading.value) {
        reload();
    }
}

init();
</script>

<style>
/* 首页 · 清爽现代理财风皮肤（仅作用于首页，不影响其他页面与全局变量） */
.home-page {
    --hp-card: #FFFFFF;
    --hp-ink: #1F2937;
    --hp-primary: rgb(var(--ebk-primary-color));
    --hp-expense: #D0443F;
    --hp-expense-bg: #FCEBEA;
    --hp-income: #1E9E6F;
    --hp-secondary: var(--ebk-secondary-text-color);
    --hp-divider: var(--ebk-divider-color);
    --hp-shadow: var(--ebk-card-shadow);
}

.dark .home-page {
    --hp-card: #252530;
    --hp-ink: #E8EAED;
    --hp-primary: #4db6ac;
    --hp-expense: #F87171;
    --hp-expense-bg: rgba(248, 113, 113, 0.15);
    --hp-income: #34D399;
    --hp-shadow: var(--ebk-card-shadow-dark);
}

/* 汇总卡片 */
.home-summary-card {
    background: var(--hp-card);
    border-radius: var(--ebk-card-border-radius);
    color: var(--hp-ink);
    overflow: hidden;
    /* 首页没有导航栏，卡片从状态栏下方留出一段呼吸空间开始 */
    margin: calc(var(--f7-safe-area-top, 0px) + 24px) 16px 16px !important;
    border: none;
    outline: none;
    box-shadow: var(--hp-shadow);
}

.dark .home-summary-card {
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
    top: 12px;
    right: 12px;
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

/* 月份 + 支出徽标 */
.home-summary-row {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-bottom: 6px;
}

.home-summary-label {
    font-size: 17px;
    font-weight: 600;
    line-height: 1.4;
}

.home-summary-badge {
    font-size: 12px;
    font-weight: 600;
    padding: 2px 10px;
    border-radius: 8px;
    letter-spacing: 0.02em;
}

.expense-badge {
    background: var(--hp-expense-bg);
    color: var(--hp-expense);
}

/* 大金额 */
.home-summary-amount {
    font-size: 2em;
    font-weight: 600;
    letter-spacing: -0.01em;
    margin-bottom: 4px;
}

.expense-amount {
    color: var(--hp-ink);
}

.home-summary-card .ebk-hide-icon {
    color: var(--hp-secondary);
    font-size: 18px;
}

/* 收入 / 结余 */
.home-summary-metrics {
    display: flex;
    align-items: stretch;
    margin-top: 12px;
    padding-top: 12px;
    border-top: 1px solid var(--hp-divider);
}

.home-summary-metric {
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: 0 16px 0 2px;
}

.home-summary-metric-label {
    font-size: 12px;
    color: var(--hp-secondary);
}

.home-summary-metric-value {
    font-size: 14px;
    font-weight: 600;
    line-height: 1.5;
    font-variant-numeric: tabular-nums;
}

.home-summary-metric-divider {
    width: 1px;
    margin: 2px 16px 2px 0;
    background: var(--hp-divider);
}

/* 设置了背景图时：文字统一走白色系并加投影，分割线提亮，保证在任意图片上可读 */
.home-summary-card.has-bg .home-summary-label,
.home-summary-card.has-bg .home-summary-amount {
    color: #fff;
    text-shadow: 0 1px 4px rgba(0, 0, 0, 0.35);
}

.home-summary-card.has-bg .home-summary-metric-label {
    color: rgba(255, 255, 255, 0.9);
    text-shadow: 0 1px 3px rgba(0, 0, 0, 0.45);
}

.home-summary-card.has-bg .home-summary-metrics {
    border-top-color: rgba(255, 255, 255, 0.28);
}

.home-summary-card.has-bg .home-summary-metric-divider {
    background: rgba(255, 255, 255, 0.28);
}

.home-summary-card.has-bg .ebk-hide-icon {
    color: rgba(255, 255, 255, 0.9);
}

.home-summary-card.has-bg .home-card-gallery-btn {
    background: rgba(0, 0, 0, 0.3);
}

.home-summary-card.has-bg .home-card-gallery-btn i.f7-icons {
    color: rgba(255, 255, 255, 0.85) !important;
}

/* 区间列表卡片 */
.overview-transaction-list {
    background: var(--hp-card);
    border-radius: var(--ebk-card-border-radius);
    box-shadow: var(--hp-shadow);
    overflow: hidden;
    margin-bottom: 68px;
}

.overview-transaction-list .item-content,
.overview-transaction-list .item-inner {
    background: transparent !important;
}

.overview-transaction-list .item-inner:after {
    background: var(--hp-divider) !important;
}

.overview-transaction-list .item-media i.f7-icons {
    font-size: 21px;
}

.overview-transaction-list .item-title {
    font-size: 16px;
}

.overview-transaction-list .item-title > div {
    overflow: hidden;
    text-overflow: ellipsis;
}

.overview-transaction-list .item-after {
    max-width: 100%;
}

.overview-transaction-list .overview-transaction-footer {
    padding-top: 4px;
    font-size: 12px;
    color: var(--hp-secondary);
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
    line-height: 1.35;
}

.overview-transaction-list .overview-transaction-amount small {
    font-size: 13px;
}

.overview-transaction-list .text-income {
    color: var(--hp-income);
}

.overview-transaction-list .text-expense {
    color: var(--hp-expense);
}

/* 底部 Tab 导航 - 无底色无阴影，与页面背景融为一体 */
.home-page .tabbar.main-tabbar {
    /* 收紧图标行高度，让按钮整体更贴近屏幕底部 */
    --f7-tabbar-icons-height: 52px;
    overflow: visible;
    background: transparent !important;
    backdrop-filter: none !important;
    -webkit-backdrop-filter: none !important;
    border-top: none;
    box-shadow: none !important;
}

/* F7 iOS 主题会在底栏上方画 16px 渐变+毛玻璃（::before/::after），全部压掉 */
.home-page .tabbar.main-tabbar::before,
.home-page .tabbar.main-tabbar::after {
    display: none !important;
    content: none !important;
}

/* 壳模式（页面接管安全区）下按钮行往下探一点，减少底部留白 */
html.app-shell .tabbar.main-tabbar .toolbar-inner {
    bottom: calc(var(--f7-safe-area-bottom) - 8px);
}

.dark .home-page .tabbar.main-tabbar {
    background: transparent !important;
    border-top: none;
}

.tabbar.main-tabbar .link {
    color: var(--ebk-secondary-text-color);
}

.tabbar.main-tabbar .link.active {
    color: var(--hp-primary);
}

.tabbar.main-tabbar .link i + span.tabbar-label {
    margin-top: var(--ebk-icon-text-margin);
}

/* 中间加号：主色圆钮 */
.tabbar.main-tabbar .link.home-add-button {
    width: 56px;
    height: 56px;
    margin-top: -28px;
    border-radius: 50%;
    background: var(--hp-primary);
    color: #fff;
    box-shadow: 0 4px 12px rgba(38, 166, 154, 0.35);
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
}

.dark .tabbar.main-tabbar .link.home-add-button {
    background: var(--hp-primary);
    box-shadow: 0 4px 12px rgba(38, 166, 154, 0.4);
}

.home-add-icon {
    font-size: 28px;
    color: #fff;
}

.template-popover-menu .popover-inner {
    max-height: 400px;
    overflow-y: auto;
}

.ai-image-recognition-fab {
    --f7-fab-size: 48px;
    bottom: calc(var(--f7-toolbar-height) + var(--f7-safe-area-bottom) + 16px) !important;
}

.ai-image-recognition-fab > a i {
    font-size: 24px;
}
</style>
