<template>
    <f7-page class="home-page theme-jade" ptr @ptr:refresh="reload" @page:afterin="onPageAfterIn" :style="pageBackgroundStyle">
        <f7-navbar>
            <f7-nav-title :title="tt('global.app.title')"></f7-nav-title>
        </f7-navbar>

        <f7-card class="home-summary-card" :class="{ 'skeleton-text': loading }" :style="homeSummaryCardStyle" @taphold="onHomeBgInputClick">
            <f7-link class="home-card-gallery-btn" @click="onHomeBgInputClick">
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
                <div class="home-ruler">
                    <div class="home-ruler-ticks">
                        <span class="tick" v-for="i in 10" :key="'t' + i"></span>
                        <span class="tick tick--now"></span>
                    </div>
                    <span class="home-ruler-note">{{ tt('This Month') }}</span>
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
        return {
            'background-image': `url(${imageUrl})`,
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
/* 页面级浅色皮肤 token（仅作用于首页，不影响其他页面与全局变量） */
.home-page {
    --hp-bg: #F7F8FA;
    --hp-card: #FFFFFF;
    --hp-primary: #2563EB;
    --hp-expense: #E5484D;
    --hp-expense-bg: #FDEDED;
    --hp-income: #00B42A;
    --hp-secondary: #86909C;
    --hp-divider: #F2F3F5;
    --hp-shadow: 0 2px 16px rgba(0, 0, 0, 0.05);
    background: var(--hp-bg);
}

.dark .home-page {
    --hp-bg: #111113;
    --hp-card: #1C1C1E;
    --hp-primary: #3B82F6;
    --hp-expense: #F87171;
    --hp-expense-bg: rgba(244, 63, 94, 0.15);
    --hp-income: #34D399;
    --hp-secondary: #9AA0A6;
    --hp-divider: rgba(255, 255, 255, 0.08);
    --hp-shadow: 0 2px 16px rgba(0, 0, 0, 0.35);
}

/* ===== 风格二：暖橙轻奢 ===== */
.home-page.theme-warm {
    --hp-bg: #F6F1E9;
    --hp-card: #FFFFFF;
    --hp-primary: #C67E48;
    --hp-expense: #D95F2B;
    --hp-expense-bg: #FBEADF;
    --hp-income: #00A36C;
    --hp-secondary: #8A7A6A;
    --hp-divider: #EFE7DA;
    --hp-shadow: 0 2px 16px rgba(198, 126, 72, 0.10);
}

.dark .home-page.theme-warm {
    --hp-bg: #17130F;
    --hp-card: #201B15;
    --hp-primary: #D99B63;
    --hp-expense: #E57A4A;
    --hp-expense-bg: rgba(217, 95, 43, 0.16);
    --hp-income: #3DBE8C;
    --hp-secondary: #A29482;
    --hp-divider: rgba(255, 255, 255, 0.09);
}

/* ===== 风格三：暗夜高级（强制深色） ===== */
.home-page.theme-dark {
    --hp-bg: #0E1116;
    --hp-card: #1A1F26;
    --hp-primary: #38BDF8;
    --hp-expense: #FB7185;
    --hp-expense-bg: rgba(244, 63, 94, 0.14);
    --hp-income: #34D399;
    --hp-secondary: #94A3B8;
    --hp-divider: rgba(255, 255, 255, 0.08);
    --hp-shadow: 0 2px 16px rgba(0, 0, 0, 0.45);
}

.home-page.theme-dark .home-summary-card {
    color: #F1F5F9;
}

.home-page.theme-dark .tabbar.main-tabbar {
    background: #1a1a1e;
    border-top-color: #2a2a35;
}

.home-page.theme-dark .tabbar.main-tabbar .link.home-add-button {
    box-shadow: 0 8px 20px rgba(56, 189, 248, 0.4);
}

/* ===== 风格四：清新薄荷绿 ===== */
.home-page.theme-green {
    --hp-bg: #F0F9F3;
    --hp-card: #FFFFFF;
    --hp-primary: #16A34A;
    --hp-expense: #E5484D;
    --hp-expense-bg: #FDEDED;
    --hp-income: #00B42A;
    --hp-secondary: #7A8B80;
    --hp-divider: #E8F2EC;
    --hp-shadow: 0 2px 16px rgba(22, 163, 74, 0.10);
}

.dark .home-page.theme-green {
    --hp-bg: #0D1510;
    --hp-card: #16201A;
    --hp-primary: #22C55E;
    --hp-expense: #F87171;
    --hp-expense-bg: rgba(244, 63, 94, 0.15);
    --hp-income: #34D399;
    --hp-secondary: #8BA395;
    --hp-divider: rgba(255, 255, 255, 0.09);
}

/* ===== 风格五：玉石（参考墨刀「巢记·详情」设计稿） ===== */
.home-page.theme-jade {
    --paper: #F4F6F3;
    --card: #FFFFFF;
    --ink: #14201C;
    --ink-2: #57635D;
    --ink-3: #8D9892;
    --rule: #E6EAE4;
    --rule-2: #EFF2EE;
    --jade: #1F5F52;
    --jade-soft: #E9F0ED;
    --crimson: #B7362C;
    --amount-red: #D04444;
    --income-green: #34B56A;
    --expense-teal: #1FA08C;
    --font-ui: "PingFang SC", "HarmonyOS Sans SC", "Microsoft YaHei UI", "Microsoft YaHei", "Source Han Sans SC", "Noto Sans SC", sans-serif;
    --font-num: "Bahnschrift", "Bahnschrift SemiCondensed", "DIN Alternate", "Roboto Condensed", "PingFang SC", "Microsoft YaHei", sans-serif;
    background: radial-gradient(120% 90% at 50% 0%, #F0F1EE 0%, var(--paper) 60%, #DEDFDB 100%);
}

.home-page.theme-jade .home-summary-card {
    background: var(--card);
    border-radius: 20px;
    color: var(--ink);
    box-shadow: 0 1px 0 rgba(20, 32, 28, .05), 0 14px 30px -22px rgba(20, 32, 28, .45);
}

/* 数字字体 */
.home-page.theme-jade .home-summary-amount,
.home-page.theme-jade .home-summary-income-value,
.home-page.theme-jade .overview-transaction-amount .text-income small,
.home-page.theme-jade .overview-transaction-amount .text-expense small,
.home-page.theme-jade .overview-transaction-footer {
    font-family: var(--font-num);
    font-variant-numeric: tabular-nums;
}

/* 月份 + 绯红点支出标签 */
.home-page.theme-jade .home-summary-label {
    font-family: var(--font-ui);
    font-size: 19px;
    font-weight: 600;
    letter-spacing: .06em;
    color: var(--ink);
}

.home-page.theme-jade .expense-badge {
    background: transparent;
    color: var(--amount-red);
    font-family: var(--font-ui);
    font-size: 14px;
    font-weight: 500;
    letter-spacing: .04em;
    padding: 0 0 0 14px;
    position: relative;
}

.home-page.theme-jade .expense-badge::before {
    content: "";
    position: absolute;
    left: 0;
    top: 50%;
    transform: translateY(-50%);
    width: 5px;
    height: 5px;
    border-radius: 50%;
    background: var(--crimson);
}

/* 大金额 */
.home-page.theme-jade .home-summary-amount {
    font-size: 46px;
    font-weight: 500;
    letter-spacing: .005em;
    line-height: 1.06;
    color: var(--amount-red);
    margin-top: 6px;
}

.home-page.theme-jade .home-summary-amount .ebk-hide-icon {
    font-size: 18px;
}

/* 当月收入 */
.home-page.theme-jade .home-summary-income-row {
    border-top-color: var(--rule-2);
}

.home-page.theme-jade .home-summary-income-label {
    font-family: var(--font-ui);
    font-size: 13px;
    color: var(--ink-2);
}

.home-page.theme-jade .home-summary-income-value {
    font-size: 15px;
    font-weight: 500;
    color: var(--income-green);
}

/* 刻度尺（玉石色） */
.home-page.theme-jade .home-ruler {
    border-top-color: var(--rule-2);
}

.home-page.theme-jade .home-ruler .tick {
    background: var(--ink-3);
}

.home-page.theme-jade .home-ruler .tick--now {
    background: var(--crimson);
}

.home-page.theme-jade .home-ruler-note {
    font-family: var(--font-ui);
    color: var(--ink-3);
}

/* 区间列表白卡 */
.home-page.theme-jade .overview-transaction-list {
    background: var(--card);
    border-radius: 18px;
    box-shadow: 0 1px 0 rgba(20, 32, 28, .05), 0 14px 30px -22px rgba(20, 32, 28, .45);
}

.home-page.theme-jade .overview-transaction-list .item-title > div {
    font-family: var(--font-ui);
    font-size: 15.5px;
    font-weight: 600;
    letter-spacing: .04em;
    color: var(--ink);
}

.home-page.theme-jade .overview-transaction-footer {
    font-size: 12px;
    color: var(--ink-3);
    letter-spacing: .02em;
}

.home-page.theme-jade .overview-transaction-list .text-income {
    color: var(--amount-red);
    font-size: 14px;
    font-weight: 500;
}

.home-page.theme-jade .overview-transaction-list .text-expense {
    color: var(--expense-teal);
    font-size: 14px;
    font-weight: 500;
}

.home-page.theme-jade .overview-transaction-list .item-inner:after {
    background: var(--rule-2) !important;
}

/* 纯色 Tab + 方形加号 */
.home-page.theme-jade .tabbar.main-tabbar {
    background: #ffffff !important;
    backdrop-filter: none !important;
    -webkit-backdrop-filter: none !important;
    border-top: 1px solid var(--rule);
}

.home-page.theme-jade .tabbar.main-tabbar .link {
    color: var(--ink-3);
}

.home-page.theme-jade .tabbar.main-tabbar .link.active {
    color: var(--ink);
}

.home-page.theme-jade .tabbar.main-tabbar .link.home-add-button {
    width: 46px;
    height: 46px;
    margin-top: -12px;
    border-radius: 12px;
    background: #fff;
    color: var(--ink);
    box-shadow: inset 0 0 0 2px var(--ink);
}

.home-page.theme-jade .home-add-icon {
    font-size: 24px;
    color: var(--ink);
}

.home-page.theme-jade .home-summary-card .ebk-hide-icon {
    color: var(--ink-3);
}

.home-page.theme-jade .home-card-gallery-btn {
    color: var(--ink-3);
    background: rgba(20, 32, 28, .05);
}

/* 月度汇总卡片 */
.home-summary-card {
    background: var(--hp-card);
    border-radius: 20px;
    color: #1a1a1a;
    overflow: hidden;
    margin: 12px 16px !important;
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
    padding: 3px 12px;
    border-radius: 20px;
    letter-spacing: 0.02em;
}

.expense-badge {
    background: var(--hp-expense-bg);
    color: var(--hp-expense);
}

.home-summary-amount {
    font-size: 2.1em;
    font-weight: 700;
    letter-spacing: -0.02em;
    margin-bottom: 8px;
}

.expense-amount {
    color: var(--hp-expense);
}

.home-summary-metrics {
    display: flex;
    align-items: stretch;
    margin-top: 10px;
    padding-top: 10px;
    border-top: 1px solid var(--hp-divider);
}

.home-summary-metric {
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: 0 14px 0 2px;
}

.home-summary-metric-label {
    font-size: 0.8em;
    color: var(--hp-secondary);
}

.home-summary-metric-value {
    font-size: 1.05em;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
}

.home-summary-metric-divider {
    width: 1px;
    margin: 2px 14px 2px 0;
    background: var(--hp-divider);
}

.home-summary-card .ebk-hide-icon {
    color: var(--hp-secondary);
    font-size: 18px;
}

/* 时间列表卡片 */
.overview-transaction-list {
    background: var(--hp-card);
    border-radius: 16px;
    box-shadow: var(--hp-shadow);
    overflow: hidden;
}

.overview-transaction-list .item-content,
.overview-transaction-list .item-inner {
    background: transparent !important;
}

.overview-transaction-list .item-inner:after {
    background: var(--hp-divider) !important;
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
}

.overview-transaction-list .text-income {
    color: var(--hp-income);
}

.overview-transaction-list .text-expense {
    color: var(--hp-expense);
}

/* 底部 Tab 导航 - 纯色不透明 */
.tabbar.main-tabbar {
    overflow: visible;
    background: #ffffff !important;
    backdrop-filter: none !important;
    -webkit-backdrop-filter: none !important;
    border-top: 1px solid #e5e7eb;
}

.dark .tabbar.main-tabbar {
    background: #1a1a1e !important;
    border-top-color: #2a2a35;
}

.tabbar.main-tabbar .link {
    color: #9ca3af;
}

.tabbar.main-tabbar .link.active {
    color: var(--hp-primary);
}

.tabbar.main-tabbar .link i + span.tabbar-label {
    margin-top: var(--ebk-icon-text-margin);
}

/* 中间加号：上浮凸起圆钮 */
.tabbar.main-tabbar .link.home-add-button {
    width: 60px;
    height: 60px;
    margin-top: -30px;
    border-radius: 50%;
    background: var(--hp-primary);
    color: #fff;
    box-shadow: 0 8px 20px rgba(37, 99, 235, 0.35);
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
}

.dark .tabbar.main-tabbar .link.home-add-button {
    background: var(--hp-primary);
    box-shadow: 0 8px 20px rgba(59, 130, 246, 0.4);
}

.home-add-icon {
    font-size: 32px;
    color: #fff;
}

/* 日刻度尺（参考稿元素） */
.home-ruler {
    margin-top: 13px;
    padding-top: 12px;
    border-top: 1px solid var(--hp-divider);
    display: flex;
    align-items: flex-end;
    gap: 12px;
}

.home-ruler-ticks {
    flex: 1;
    min-width: 0;
    display: flex;
    align-items: flex-end;
    justify-content: space-between;
    height: 17px;
}

.home-ruler .tick {
    width: 1px;
    height: 6px;
    border-radius: 1px;
    background: var(--hp-secondary);
    opacity: .4;
}

.home-ruler .tick--now {
    width: 2px;
    height: 17px;
    background: var(--hp-expense);
    opacity: 1;
}

.home-ruler-note {
    flex: none;
    font-family: "PingFang SC", "Microsoft YaHei", sans-serif;
    font-size: 11px;
    color: var(--hp-secondary);
    letter-spacing: .02em;
}

.template-popover-menu .popover-inner {
    max-height: 400px;
    overflow-y: auto;
}

.ai-image-recognition-fab {
    bottom: calc(var(--f7-toolbar-height) + var(--f7-safe-area-bottom) + 16px) !important;
}
</style>
