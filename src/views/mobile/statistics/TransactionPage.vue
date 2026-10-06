<template>
    <f7-page class="statistics-page" ptr with-subnavbar @ptr:refresh="reload" @page:afterin="onPageAfterIn">
        <f7-navbar>
            <f7-nav-left :class="{ 'disabled': loading }" :back-link="tt('Back')"></f7-nav-left>
            <f7-nav-title>
                <div class="period-mode-segmented" :class="{ 'disabled': loading || reloading }">
                    <span :class="{ 'active': !isYearLikePeriod }" @click="setPeriodMode(false)">{{ tt('Month') }}</span>
                    <span :class="{ 'active': isYearLikePeriod }" @click="setPeriodMode(true)">{{ tt('Year') }}</span>
                </div>
            </f7-nav-title>
            <f7-nav-right :class="{ 'disabled': loading }">
                <f7-link icon-f7="line_horizontal_3_decrease" @click="showMoreActionSheet = true"></f7-link>
            </f7-nav-right>

            <f7-subnavbar :inner="false" class="statistics-period-subnavbar">
                <div class="statistics-period-row" :class="{ 'disabled': loading || reloading }">
                    <f7-link class="statistics-period-shift-button" :class="{ 'disabled': reloading || !canShiftDateRange }" @click="shiftDateRange(-1)">
                        <f7-icon f7="chevron_left"></f7-icon>
                    </f7-link>
                    <f7-link class="statistics-period-label" popover-open=".date-popover-menu" :class="{ 'disabled': reloading || !canChangeDateRange }">
                        <f7-icon f7="calendar"></f7-icon>
                        <span>{{ periodDisplayName }}</span>
                    </f7-link>
                    <f7-link class="statistics-period-shift-button" :class="{ 'disabled': reloading || !canShiftDateRange }" @click="shiftDateRange(1)">
                        <f7-icon f7="chevron_right"></f7-icon>
                    </f7-link>
                </div>
            </f7-subnavbar>
        </f7-navbar>

        <f7-popover class="date-popover-menu" @popover:open="scrollPopoverToSelectedItem">
            <f7-list dividers>
                <f7-list-item link="#" no-chevron popover-close
                              :title="dateRange.displayName"
                              :class="{ 'list-item-selected': queryDateType === dateRange.type }"
                              :key="dateRange.type"
                              v-for="dateRange in allDateRanges"
                              @click="setDateFilter(dateRange.type)">
                    <template #after>
                        <f7-icon class="list-item-checked-icon" f7="checkmark_alt" v-if="queryDateType === dateRange.type"></f7-icon>
                    </template>
                    <template #footer>
                        <div v-if="dateRange.isUserCustomRange && canShowCustomDateRange(dateRange.type)">
                            <span>{{ queryStartTime }}</span>
                            <span>&nbsp;-&nbsp;</span>
                            <br/>
                            <span>{{ queryEndTime }}</span>
                        </div>
                    </template>
                </f7-list-item>
            </f7-list>
        </f7-popover>

        <f7-card>
            <div class="statistics-card-title">{{ tt('Income and Expense Overview') }}</div>
            <div class="statistics-overview-grid">
                <div class="statistics-overview-item">
                    <div class="statistics-overview-label">{{ tt('Expense') }}</div>
                    <div class="statistics-overview-value" :class="{ 'skeleton-text': loading }">
                        <span v-if="!loading">{{ getDisplayAmount(overviewExpenseAmount) }}</span>
                        <span v-else>***.**</span>
                    </div>
                </div>
                <div class="statistics-overview-item">
                    <div class="statistics-overview-label">{{ tt('Income') }}</div>
                    <div class="statistics-overview-value" :class="{ 'skeleton-text': loading }">
                        <span v-if="!loading">{{ getDisplayAmount(overviewIncomeAmount) }}</span>
                        <span v-else>***.**</span>
                    </div>
                </div>
                <div class="statistics-overview-item">
                    <div class="statistics-overview-label">{{ tt('Balance') }}</div>
                    <div class="statistics-overview-value" :class="{ 'skeleton-text': loading }">
                        <span v-if="!loading">{{ getDisplayAmount(overviewBalanceAmount) }}</span>
                        <span v-else>***.**</span>
                    </div>
                </div>
                <div class="statistics-overview-item">
                    <div class="statistics-overview-label">{{ tt('Daily Average Expense') }}</div>
                    <div class="statistics-overview-value" :class="{ 'skeleton-text': loading }">
                        <span v-if="!loading">{{ getDisplayAmount(dailyAverageExpenseAmount) }}</span>
                        <span v-else>***.**</span>
                    </div>
                </div>
            </div>
        </f7-card>

        <f7-card>
            <div class="statistics-card-title-row">
                <div class="statistics-card-title">{{ tt('Daily Income and Expense Statistics') }}</div>
                <f7-link class="statistics-chart-type-toggle" :class="{ 'disabled': loading || reloading }" @click="toggleDailyChartType">
                    <f7-icon :f7="dailyChartType === 'bar' ? 'chart_bar_fill' : 'chart_bar'"></f7-icon>
                </f7-link>
            </div>
            <div class="statistics-daily-chart-container">
                <daily-income-expense-bar-chart
                    :items="dailyChartItems"
                    :mode="dailyChartMode"
                    :chart-type="dailyChartType"
                    :loading="loading || reloading"
                    :expense-color="expenseDisplayColor"
                    :income-color="incomeDisplayColor"
                    @click="onClickDailyChartItem"
                ></daily-income-expense-bar-chart>
            </div>
            <div class="statistics-chart-mode-segmented" :class="{ 'disabled': loading || reloading }">
                <span :class="{ 'active': dailyChartMode === 'expense' }" @click="dailyChartMode = 'expense'">{{ tt('Expense') }}</span>
                <span :class="{ 'active': dailyChartMode === 'income' }" @click="dailyChartMode = 'income'">{{ tt('Income') }}</span>
                <span :class="{ 'active': dailyChartMode === 'all' }" @click="dailyChartMode = 'all'">{{ tt('All') }}</span>
            </div>
        </f7-card>

        <f7-card>
            <div class="statistics-card-title-row">
                <div class="statistics-card-title">{{ tt('Categorical Analysis') }}</div>
                <div class="statistics-category-header-controls">
                    <div class="statistics-category-dimension-segmented" :class="{ 'disabled': loading || reloading }">
                        <span :class="{ 'active': categoryDimension === 'expense' }" @click="setCategoryDimension('expense')">{{ tt('Expense') }}</span>
                        <span :class="{ 'active': categoryDimension === 'income' }" @click="setCategoryDimension('income')">{{ tt('Income') }}</span>
                    </div>
                    <f7-link href="#" popover-open=".sorting-type-popover-menu" :class="{ 'disabled': loading }">
                        <f7-icon f7="arrow_up_arrow_down"></f7-icon>
                    </f7-link>
                </div>
            </div>
            <div class="statistics-pie-chart-container">
                <pie-chart
                    :items="[{value: 60, color: '7c7c7f'}, {value: 20, color: 'a5a5aa'}, {value: 20, color: 'c5c5c9'}]"
                    :skeleton="true"
                    :show-center-text="true"
                    class="statistics-pie-chart"
                    name-field="name"
                    value-field="value"
                    color-field="color"
                    v-if="loading"
                ></pie-chart>
                <pie-chart
                    :items="categoricalAnalysisData.items"
                    :show-percent="true"
                    :show-value="true"
                    :show-center-text="true"
                    :enable-click-item="true"
                    :amount-value="true"
                    :default-currency="defaultCurrency"
                    class="statistics-pie-chart"
                    name-field="name"
                    value-field="totalAmount"
                    percent-field="percent"
                    hidden-field="hidden"
                    v-else-if="!loading"
                    @click="onClickPieChartItem"
                >
                    <text class="statistics-pie-chart-total-amount-title" v-if="categoricalAnalysisData.items && categoricalAnalysisData.items.length">
                        {{ categoryTotalAmountName }}
                    </text>
                    <text class="statistics-pie-chart-total-amount-value" v-if="categoricalAnalysisData.items && categoricalAnalysisData.items.length">
                        {{ getDisplayAmount(categoricalAnalysisData.totalAmount, defaultCurrency, 16) }}
                    </text>
                    <text class="statistics-pie-chart-total-no-data" cy="50%" v-if="!categoricalAnalysisData.items || !categoricalAnalysisData.items.length">
                        {{ tt('No data') }}
                    </text>
                </pie-chart>
            </div>
            <div class="statistics-category-ranking-list" v-if="!loading && categoricalAnalysisData.items && categoricalAnalysisData.items.length">
                <div class="statistics-category-ranking-item"
                     :key="idx"
                     v-for="(item, idx) in categoricalAnalysisData.items"
                     v-show="!item.hidden"
                     @click="onClickCategoryItem(item)"
                >
                    <div class="statistics-category-ranking-icon">
                        <ItemIcon icon-type="category" :icon-id="item.icon" :color="item.color" v-if="item.icon"></ItemIcon>
                        <f7-icon f7="pencil_ellipsis_rectangle" v-else></f7-icon>
                    </div>
                    <div class="statistics-category-ranking-main">
                        <div class="statistics-category-ranking-first-row">
                            <span class="statistics-category-ranking-name">{{ item.name }}</span>
                            <small class="statistics-category-ranking-percent" v-if="showPercentInCategoricalChart && item.percent >= 0 && item.totalAmount >= 0">{{ formatPercentToLocalizedNumerals(item.percent, 2, '<0.01') }}</small>
                        </div>
                        <div class="statistics-category-ranking-bar">
                            <div class="statistics-category-ranking-bar-fill" :style="{ 'width': (item.percent >= 0 ? item.percent : 0) + '%', 'background-color': getCategoryItemDisplayColor(item) }"></div>
                        </div>
                    </div>
                    <div class="statistics-category-ranking-amount">{{ getDisplayAmount(item.totalAmount, defaultCurrency) }}</div>
                </div>
            </div>
        </f7-card>

        <f7-card>
            <div class="statistics-daily-report-title">{{ tt('Daily Report') }}</div>
            <div class="statistics-daily-report-table" v-if="dailyReportRows.length">
                <div class="statistics-daily-report-row statistics-daily-report-header">
                    <span>{{ tt('Date') }}</span>
                    <span>{{ tt('Income') }}</span>
                    <span>{{ tt('Expense') }}</span>
                    <span>{{ tt('Balance') }}</span>
                </div>
                <div class="statistics-daily-report-row" :key="row.label" v-for="row in dailyReportRows">
                    <span>{{ row.label }}</span>
                    <span>{{ formatDisplayAmount(row.incomeAmount) }}</span>
                    <span>{{ formatDisplayAmount(row.expenseAmount) }}</span>
                    <span :class="{ 'text-expense': row.balanceAmount < 0 }">{{ formatDisplayAmount(row.balanceAmount) }}</span>
                </div>
                <div class="statistics-daily-report-row statistics-daily-report-average" v-if="elapsedDaysInRange > 0">
                    <span>{{ tt('Average') }}</span>
                    <span>{{ formatDisplayAmount(reportTotalIncomeAmount / elapsedDaysInRange) }}</span>
                    <span>{{ formatDisplayAmount(reportTotalExpenseAmount / elapsedDaysInRange) }}</span>
                    <span :class="{ 'text-expense': reportTotalBalanceAmount < 0 }">{{ formatDisplayAmount(reportTotalBalanceAmount / elapsedDaysInRange) }}</span>
                </div>
            </div>
            <div class="statistics-daily-report-empty" v-else-if="!loading">
                {{ tt('No transaction data') }}
            </div>
            <div class="statistics-daily-report-empty skeleton-text" v-else>
                ********
            </div>
        </f7-card>

        <div class="statistics-view-details-link" v-if="!loading">
            <f7-link @click="viewTransactionDetails">{{ tt('View transaction details') }}</f7-link>
        </div>

        <f7-popover class="sorting-type-popover-menu" @popover:open="scrollPopoverToSelectedItem">
            <f7-list dividers>
                <f7-list-item link="#" no-chevron popover-close
                              :title="sortingType.displayName"
                              :class="{ 'list-item-selected': query.sortingType === sortingType.type }"
                              :key="sortingType.type"
                              v-for="sortingType in allSortingTypes"
                              @click="setSortingType(sortingType.type)">
                    <template #after>
                        <f7-icon class="list-item-checked-icon" f7="checkmark_alt" v-if="query.sortingType === sortingType.type"></f7-icon>
                    </template>
                </f7-list-item>
            </f7-list>
        </f7-popover>

        <date-range-selection-sheet :title="tt('Custom Date Range')"
                                    :min-time="query.categoricalChartStartTime"
                                    :max-time="query.categoricalChartEndTime"
                                    v-model:show="showCustomDateRangeSheet"
                                    @dateRange:change="setCustomDateFilter">
        </date-range-selection-sheet>

        <f7-actions close-by-outside-click close-on-escape :opened="showMoreActionSheet" @actions:closed="showMoreActionSheet = false">
            <f7-actions-group>
                <f7-actions-button :class="{ 'disabled': reloading }" @click="filterAccounts">{{ tt('Filter Accounts') }}</f7-actions-button>
                <f7-actions-button :class="{ 'disabled': reloading }" @click="filterCategories">{{ tt('Filter Transaction Categories') }}</f7-actions-button>
                <f7-actions-button :class="{ 'disabled': reloading }" @click="filterTags">{{ tt('Filter Transaction Tags') }}</f7-actions-button>
            </f7-actions-group>
            <f7-actions-group>
                <f7-actions-label v-if="query.keyword">{{ query.keyword }}</f7-actions-label>
                <f7-actions-button :class="{ 'disabled': reloading }" @click="filterDescription">{{ tt('Filter transaction description') }}</f7-actions-button>
            </f7-actions-group>
            <f7-actions-group>
                <f7-actions-button @click="settings">{{ tt('Settings') }}</f7-actions-button>
            </f7-actions-group>
            <f7-actions-group>
                <f7-actions-button bold close>{{ tt('Cancel') }}</f7-actions-button>
            </f7-actions-group>
        </f7-actions>
    </f7-page>
</template>

<script setup lang="ts">
import { ref, computed } from 'vue';
import type { Router } from 'framework7/types';

import { useI18n } from '@/locales/helpers.ts';
import { useEnvironmentsStore } from '@/stores/environment.ts';

import { useAccountsStore } from '@/stores/account.ts';
import { useTransactionCategoriesStore } from '@/stores/transactionCategory.ts';
import { type TransactionStatisticsFilter, useStatisticsStore } from '@/stores/statistics.ts';
import { useUserStore } from '@/stores/user.ts';

import { type LocalizedDateRange, type WeekDayValue, type YearMonthDay, DateRangeScene, DateRange } from '@/core/datetime.ts';
import type { TypeAndDisplayName } from '@/core/base.ts';
import { PresetAmountColor } from '@/core/color.ts';
import { StatisticsAnalysisType, ChartDataType, ChartSortingType } from '@/core/statistics.ts';

import type { TransactionCategoricalAnalysisDataItem, TransactionDailyAnalysisDataItem } from '@/models/transaction.ts';

import {
    limitText,
    isObjectEmpty
} from '@/lib/common.ts';
import {
    parseDateTimeFromUnixTime,
    getGregorianCalendarYearAndMonthFromUnixTime,
    getYearMonthFirstUnixTime,
    getYearMonthLastUnixTime,
    getYearMonthDayDateTime,
    getGregorianCalendarYearMonthDays,
    getDayDifference,
    getTodayFirstUnixTime,
    getShiftedDateRangeAndDateType,
    getDateTypeByDateRange,
    getDateRangeByDateType
} from '@/lib/datetime.ts';
import { getCategoryDisplayColor, getAccountDisplayColor } from '@/lib/color.ts';
import { scrollToSelectedItem } from '@/lib/ui/common.ts';
import { type Framework7Dom, useI18nUIComponents } from '@/lib/ui/mobile.ts';
import { getFinalAccountIdsByFilteredAccountIds } from '@/lib/account.ts';
import { getFinalCategoryIdsByFilteredCategoryIds } from '@/lib/category.ts';

const props = defineProps<{
    f7router: Router.Router;
}>();

const {
    tt,
    getAllDateRanges,
    getAllStatisticsSortingTypes,
    formatDateTimeToLongDateTime,
    formatDateTimeToGregorianLikeShortYearMonth,
    formatDateTimeToGregorianLikeShortYear,
    formatDateTimeToShortMonthDay,
    formatDateRange,
    formatAmountToLocalizedNumeralsWithCurrency,
    formatAmountToLocalizedNumerals,
    formatNumberToLocalizedNumerals,
    formatPercentToLocalizedNumerals
} = useI18n();

const { showPrompt, showToast, routeBackOnError } = useI18nUIComponents();

const environmentsStore = useEnvironmentsStore();
const accountsStore = useAccountsStore();
const transactionCategoriesStore = useTransactionCategoriesStore();
const statisticsStore = useStatisticsStore();
const userStore = useUserStore();

const loading = ref<boolean>(true);
const loadingError = ref<unknown | null>(null);
const reloading = ref<boolean>(false);
const showCustomDateRangeSheet = ref<boolean>(false);
const showMoreActionSheet = ref<boolean>(false);
const dailyChartMode = ref<'expense' | 'income' | 'all'>('expense');
const dailyChartType = ref<'bar' | 'line'>('bar');
const categoryDimension = ref<'expense' | 'income'>('expense');

const defaultCurrency = computed<string>(() => userStore.currentUserDefaultCurrency);
const firstDayOfWeek = computed<WeekDayValue>(() => userStore.currentUserFirstDayOfWeek);
const fiscalYearStart = computed<number>(() => userStore.currentUserFiscalYearStart);

const query = computed<TransactionStatisticsFilter>(() => statisticsStore.transactionStatisticsFilter);

const allDateRanges = computed<LocalizedDateRange[]>(() => getAllDateRanges(DateRangeScene.Normal, true));
const allSortingTypes = computed<TypeAndDisplayName[]>(() => getAllStatisticsSortingTypes());

const queryDateType = computed<number | null>(() => query.value.categoricalChartDateType);
const queryStartTime = computed<string>(() => formatDateTimeToLongDateTime(parseDateTimeFromUnixTime(query.value.categoricalChartStartTime)));
const queryEndTime = computed<string>(() => formatDateTimeToLongDateTime(parseDateTimeFromUnixTime(query.value.categoricalChartEndTime)));

const canChangeDateRange = computed<boolean>(() => true);
const canShiftDateRange = computed<boolean>(() => query.value.categoricalChartDateType !== DateRange.All.type);

const isYearLikePeriod = computed<boolean>(() => {
    return queryDateType.value === DateRange.ThisYear.type || queryDateType.value === DateRange.LastYear.type;
});

const periodDisplayName = computed<string>(() => {
    const startTime = query.value.categoricalChartStartTime;
    const endTime = query.value.categoricalChartEndTime;

    if (!startTime || !endTime) {
        return tt(DateRange.All.name);
    }

    const startYearMonth = getGregorianCalendarYearAndMonthFromUnixTime(startTime);
    const endYearMonth = getGregorianCalendarYearAndMonthFromUnixTime(endTime);

    if (startYearMonth && startYearMonth === endYearMonth) {
        return formatDateTimeToGregorianLikeShortYearMonth(parseDateTimeFromUnixTime(startTime));
    }

    const startYear = parseDateTimeFromUnixTime(startTime).getGregorianCalendarYear();
    const endYear = parseDateTimeFromUnixTime(endTime).getGregorianCalendarYear();
    const startMonth = parseDateTimeFromUnixTime(startTime).getGregorianCalendarMonth();
    const endMonth = parseDateTimeFromUnixTime(endTime).getGregorianCalendarMonth();

    if (startYear === endYear && startMonth === 1 && endMonth === 12) {
        return formatDateTimeToGregorianLikeShortYear(parseDateTimeFromUnixTime(startTime));
    }

    return formatDateRange(query.value.categoricalChartDateType, startTime, endTime);
});

const overviewIncomeAmount = computed<number>(() => {
    return statisticsStore.categoricalOverviewAnalysisData?.totalIncome || 0;
});

const overviewExpenseAmount = computed<number>(() => {
    return statisticsStore.categoricalOverviewAnalysisData?.totalExpense || 0;
});

const overviewBalanceAmount = computed<number>(() => {
    return overviewIncomeAmount.value - overviewExpenseAmount.value;
});

function getYearMonthDayOfUnixTime(unixTime: number): YearMonthDay {
    const dateTime = parseDateTimeFromUnixTime(unixTime);

    return {
        year: dateTime.getGregorianCalendarYear(),
        month: dateTime.getGregorianCalendarMonth(),
        day: dateTime.getGregorianCalendarDay()
    };
}

function getDaysInRange(startTime: number, endTime: number): number {
    if (!startTime || !endTime) {
        return 0;
    }

    const days = getDayDifference(getYearMonthDayOfUnixTime(startTime), getYearMonthDayOfUnixTime(endTime)) + 1;

    return days > 0 ? days : 0;
}

const elapsedDaysInRange = computed<number>(() => {
    const startTime = query.value.categoricalChartStartTime;
    const endTime = query.value.categoricalChartEndTime;

    if (!startTime || !endTime) {
        return 0;
    }

    const todayFirstUnixTime = getTodayFirstUnixTime();
    const effectiveEndTime = endTime < todayFirstUnixTime ? endTime : todayFirstUnixTime;

    return getDaysInRange(startTime, effectiveEndTime);
});

const dailyAverageExpenseAmount = computed<number>(() => {
    if (elapsedDaysInRange.value <= 0) {
        return 0;
    }

    return Math.round(overviewExpenseAmount.value / elapsedDaysInRange.value);
});

const dailyAnalysisData = computed<TransactionDailyAnalysisDataItem[]>(() => statisticsStore.dailyAnalysisData);

interface DailyReportRow {
    label: string;
    incomeAmount: number;
    expenseAmount: number;
    balanceAmount: number;
}

interface DailyChartDataItem {
    label: string;
    minTime: number;
    maxTime: number;
    expenseAmount: number;
    incomeAmount: number;
}

const useDailySlots = computed<boolean>(() => {
    const startTime = query.value.categoricalChartStartTime;
    const endTime = query.value.categoricalChartEndTime;

    if (!startTime || !endTime) {
        return false;
    }

    const days = getDaysInRange(startTime, endTime);

    return days > 0 && days <= 62;
});

interface ChartSlotRange {
    label: string;
    minTime: number;
    maxTime: number;
}

const chartSlotRanges = computed<ChartSlotRange[]>(() => {
    const startTime = query.value.categoricalChartStartTime;
    const endTime = query.value.categoricalChartEndTime;

    if (!startTime || !endTime) {
        return [];
    }

    const slots: ChartSlotRange[] = [];
    const startDateTime = parseDateTimeFromUnixTime(startTime);
    const endDateTime = parseDateTimeFromUnixTime(endTime);
    const startYear = startDateTime.getGregorianCalendarYear();
    const endYear = endDateTime.getGregorianCalendarYear();
    const startMonth = startDateTime.getGregorianCalendarMonth();
    const endMonth = endDateTime.getGregorianCalendarMonth();

    let cursorYear = startYear;
    let cursorMonth = startMonth;

    while (cursorYear < endYear || (cursorYear === endYear && cursorMonth <= endMonth)) {
        const firstDay = (cursorYear === startYear && cursorMonth === startMonth) ? startDateTime.getGregorianCalendarDay() : 1;
        const lastDay = (cursorYear === endYear && cursorMonth === endMonth) ? endDateTime.getGregorianCalendarDay() : getGregorianCalendarYearMonthDays({ year: cursorYear, month1base: cursorMonth });

        if (useDailySlots.value) {
            for (let day = firstDay; day <= lastDay; day++) {
                const dayUnixTime = getYearMonthDayDateTime(cursorYear, cursorMonth, day).getUnixTime();

                if (dayUnixTime < startTime) {
                    continue;
                }

                if (dayUnixTime > endTime) {
                    break;
                }

                let label = '';

                if (startYear === endYear && startMonth === endMonth) {
                    label = formatNumberToLocalizedNumerals(day, 0);
                } else {
                    label = formatDateTimeToShortMonthDay(parseDateTimeFromUnixTime(dayUnixTime));
                }

                slots.push({
                    label: label,
                    minTime: dayUnixTime,
                    maxTime: dayUnixTime + 86399
                });
            }
        } else {
            const minTime = getYearMonthFirstUnixTime({ year: cursorYear, month1base: cursorMonth });
            const maxTime = getYearMonthLastUnixTime({ year: cursorYear, month1base: cursorMonth });
            let label = '';

            if (startYear === endYear) {
                label = formatNumberToLocalizedNumerals(cursorMonth, 0);
            } else {
                label = formatDateTimeToGregorianLikeShortYearMonth(parseDateTimeFromUnixTime(minTime));
            }

            slots.push({
                label: label,
                minTime: minTime,
                maxTime: maxTime
            });
        }

        cursorMonth++;

        if (cursorMonth > 12) {
            cursorMonth = 1;
            cursorYear++;
        }
    }

    return slots;
});

const dailyChartItems = computed<DailyChartDataItem[]>(() => {
    const items: DailyChartDataItem[] = [];

    for (const slot of chartSlotRanges.value) {
        items.push({
            label: slot.label,
            minTime: slot.minTime,
            maxTime: slot.maxTime,
            expenseAmount: 0,
            incomeAmount: 0
        });
    }

    if (!items.length) {
        return items;
    }

    for (const dailyItem of dailyAnalysisData.value) {
        const dayUnixTime = getYearMonthDayDateTime(dailyItem.year, dailyItem.month, dailyItem.day).getUnixTime();

        for (const item of items) {
            if (dayUnixTime >= item.minTime && dayUnixTime <= item.maxTime) {
                item.expenseAmount += dailyItem.expenseAmount;
                item.incomeAmount += dailyItem.incomeAmount;
                break;
            }
        }
    }

    return items;
});

const dailyReportRows = computed<DailyReportRow[]>(() => {
    const rows: DailyReportRow[] = [];

    for (const slot of chartSlotRanges.value) {
        let incomeAmount = 0;
        let expenseAmount = 0;

        for (const dailyItem of dailyAnalysisData.value) {
            const dayUnixTime = getYearMonthDayDateTime(dailyItem.year, dailyItem.month, dailyItem.day).getUnixTime();

            if (dayUnixTime >= slot.minTime && dayUnixTime <= slot.maxTime) {
                incomeAmount += dailyItem.incomeAmount;
                expenseAmount += dailyItem.expenseAmount;
            }
        }

        if (incomeAmount === 0 && expenseAmount === 0) {
            continue;
        }

        rows.push({
            label: slot.label,
            incomeAmount: incomeAmount,
            expenseAmount: expenseAmount,
            balanceAmount: incomeAmount - expenseAmount
        });
    }

    return rows;
});

const reportTotalIncomeAmount = computed<number>(() => {
    let total = 0;

    for (const row of dailyReportRows.value) {
        total += row.incomeAmount;
    }

    return total;
});

const reportTotalExpenseAmount = computed<number>(() => {
    let total = 0;

    for (const row of dailyReportRows.value) {
        total += row.expenseAmount;
    }

    return total;
});

const reportTotalBalanceAmount = computed<number>(() => {
    return reportTotalIncomeAmount.value - reportTotalExpenseAmount.value;
});

const categoricalAnalysisData = computed<{ totalAmount: number, items: TransactionCategoricalAnalysisDataItem[] }>(() => statisticsStore.categoricalAnalysisData);

const categoryTotalAmountName = computed<string>(() => {
    if (categoryDimension.value === 'income') {
        return tt('Total Income');
    }

    return tt('Total Expense');
});

const showPercentInCategoricalChart = computed<boolean>(() => true);

const expenseDisplayColor = computed<string>(() => {
    const preset = PresetAmountColor.valueOf(userStore.currentUserExpenseAmountColor);

    if (!preset) {
        return PresetAmountColor.DefaultExpenseColor.lightThemeColor;
    }

    return environmentsStore.framework7DarkMode ? preset.darkThemeColor : preset.lightThemeColor;
});

const incomeDisplayColor = computed<string>(() => {
    const preset = PresetAmountColor.valueOf(userStore.currentUserIncomeAmountColor);

    if (!preset) {
        return PresetAmountColor.DefaultIncomeColor.lightThemeColor;
    }

    return environmentsStore.framework7DarkMode ? preset.darkThemeColor : preset.lightThemeColor;
});

function getDisplayAmount(amount: number, currency?: string, textLimit?: number): string {
    const finalAmount = formatAmountToLocalizedNumeralsWithCurrency(Math.round(amount), currency || defaultCurrency.value);

    if (textLimit) {
        return limitText(finalAmount, textLimit);
    }

    return finalAmount;
}

function formatDisplayAmount(amount: number): string {
    return formatAmountToLocalizedNumerals(Math.round(amount));
}

function getCategoryItemDisplayColor(item: TransactionCategoricalAnalysisDataItem): string {
    if (item.type === 'account') {
        return getAccountDisplayColor(item.color);
    }

    return getCategoryDisplayColor(item.color);
}

function canShowCustomDateRange(dateRangeType: number): boolean {
    return query.value.categoricalChartDateType === dateRangeType && !!query.value.categoricalChartStartTime && !!query.value.categoricalChartEndTime;
}

function setPeriodMode(yearMode: boolean): void {
    if (yearMode === isYearLikePeriod.value) {
        return;
    }

    setDateFilter(yearMode ? DateRange.ThisYear.type : DateRange.ThisMonth.type);
}

function setCategoryDimension(dimension: 'expense' | 'income'): void {
    if (categoryDimension.value === dimension) {
        return;
    }

    categoryDimension.value = dimension;
    statisticsStore.updateTransactionStatisticsFilter({
        chartDataType: dimension === 'income' ? ChartDataType.IncomeByPrimaryCategory.type : ChartDataType.ExpenseByPrimaryCategory.type
    });
}

function toggleDailyChartType(): void {
    dailyChartType.value = dailyChartType.value === 'bar' ? 'line' : 'bar';
}

function setSortingType(type: number): void {
    if (type < ChartSortingType.Amount.type || type > ChartSortingType.Name.type) {
        return;
    }

    statisticsStore.updateTransactionStatisticsFilter({
        sortingType: type
    });
}

function setDateFilter(dateType: number): void {
    if (dateType === DateRange.Custom.type) {
        showCustomDateRangeSheet.value = true;
        return;
    } else if (query.value.categoricalChartDateType === dateType) {
        return;
    }

    const dateRange = getDateRangeByDateType(dateType, firstDayOfWeek.value, fiscalYearStart.value);

    if (!dateRange) {
        return;
    }

    const changed = statisticsStore.updateTransactionStatisticsFilter({
        categoricalChartDateType: dateRange.dateType,
        categoricalChartStartTime: dateRange.minTime,
        categoricalChartEndTime: dateRange.maxTime
    });

    if (changed) {
        reload();
    }
}

function setCustomDateFilter(startTime: number, endTime: number): void {
    if (!startTime || !endTime) {
        return;
    }

    const chartDateType = getDateTypeByDateRange(startTime, endTime, firstDayOfWeek.value, fiscalYearStart.value, DateRangeScene.Normal);

    const changed = statisticsStore.updateTransactionStatisticsFilter({
        categoricalChartDateType: chartDateType,
        categoricalChartStartTime: startTime,
        categoricalChartEndTime: endTime
    });

    showCustomDateRangeSheet.value = false;

    if (changed) {
        reload();
    }
}

function shiftDateRange(scale: number): void {
    if (query.value.categoricalChartDateType === DateRange.All.type) {
        return;
    }

    const newDateRange = getShiftedDateRangeAndDateType(query.value.categoricalChartStartTime, query.value.categoricalChartEndTime, scale, firstDayOfWeek.value, fiscalYearStart.value, DateRangeScene.Normal);

    const changed = statisticsStore.updateTransactionStatisticsFilter({
        categoricalChartDateType: newDateRange.dateType,
        categoricalChartStartTime: newDateRange.minTime,
        categoricalChartEndTime: newDateRange.maxTime
    });

    if (changed) {
        reload();
    }
}

function filterAccounts(): void {
    props.f7router.navigate('/settings/filter/account?type=statisticsCurrent');
}

function filterCategories(): void {
    props.f7router.navigate('/settings/filter/category?type=statisticsCurrent');
}

function filterTags(): void {
    props.f7router.navigate('/settings/filter/tag?type=statisticsCurrent');
}

function filterDescription(): void {
    showPrompt('Filter transaction description', query.value.keyword, value => {
        if (query.value.keyword === value) {
            return;
        }

        const changed = statisticsStore.updateTransactionStatisticsFilter({
            keyword: value
        });

        if (changed) {
            reload();
        }
    });
}

function settings(): void {
    props.f7router.navigate('/statistic/settings');
}

function scrollPopoverToSelectedItem(event: { $el: Framework7Dom }): void {
    scrollToSelectedItem(event.$el[0], '.popover-inner', '.popover-inner', 'li.list-item-selected');
}

function getCategoryItemLinkUrl(itemId: string): string {
    return '/transaction/list?' + statisticsStore.getTransactionListPageParams(StatisticsAnalysisType.CategoricalAnalysis, itemId);
}

function getDailyChartItemLinkUrl(minTime: number, maxTime: number): string {
    const querys: string[] = [];

    if (dailyChartMode.value === 'income') {
        querys.push('type=2');
    } else if (dailyChartMode.value === 'expense') {
        querys.push('type=3');
    }

    if (!isObjectEmpty(query.value.filterAccountIds)) {
        querys.push('accountIds=' + getFinalAccountIdsByFilteredAccountIds(accountsStore.allAccountsMap, query.value.filterAccountIds));
    }

    if (!isObjectEmpty(query.value.filterCategoryIds)) {
        querys.push('categoryIds=' + getFinalCategoryIdsByFilteredCategoryIds(transactionCategoriesStore.allTransactionCategoriesMap, query.value.filterCategoryIds));
    }

    if (query.value.tagFilter) {
        querys.push('tagFilter=' + query.value.tagFilter);
    }

    if (query.value.keyword) {
        querys.push('keyword=' + encodeURIComponent(query.value.keyword));
    }

    const dateType = getDateTypeByDateRange(minTime, maxTime, firstDayOfWeek.value, fiscalYearStart.value, DateRangeScene.Normal);
    querys.push('dateType=' + dateType);

    if (dateType === DateRange.Custom.type) {
        querys.push('minTime=' + minTime);
        querys.push('maxTime=' + maxTime);
    }

    return '/transaction/list?' + querys.join('&');
}

function viewTransactionDetails(): void {
    const querys: string[] = [];

    if (!isObjectEmpty(query.value.filterAccountIds)) {
        querys.push('accountIds=' + getFinalAccountIdsByFilteredAccountIds(accountsStore.allAccountsMap, query.value.filterAccountIds));
    }

    if (!isObjectEmpty(query.value.filterCategoryIds)) {
        querys.push('categoryIds=' + getFinalCategoryIdsByFilteredCategoryIds(transactionCategoriesStore.allTransactionCategoriesMap, query.value.filterCategoryIds));
    }

    if (query.value.tagFilter) {
        querys.push('tagFilter=' + query.value.tagFilter);
    }

    if (query.value.keyword) {
        querys.push('keyword=' + encodeURIComponent(query.value.keyword));
    }

    querys.push('dateType=' + query.value.categoricalChartDateType);

    if (query.value.categoricalChartDateType === DateRange.Custom.type) {
        querys.push('minTime=' + query.value.categoricalChartStartTime);
        querys.push('maxTime=' + query.value.categoricalChartEndTime);
    }

    props.f7router.navigate('/transaction/list?' + querys.join('&'));
}

function onClickPieChartItem(item: Record<string, unknown>): void {
    props.f7router.navigate(getCategoryItemLinkUrl(item['id'] as string));
}

function onClickCategoryItem(item: TransactionCategoricalAnalysisDataItem): void {
    props.f7router.navigate(getCategoryItemLinkUrl(item.id));
}

function onClickDailyChartItem(value: { minTime: number, maxTime: number }): void {
    props.f7router.navigate(getDailyChartItemLinkUrl(value.minTime, value.maxTime));
}

function loadStatisticsData({ force }: { force: boolean }): Promise<unknown> {
    const promises: Promise<unknown>[] = [];

    if (query.value.categoricalChartDateType === DateRange.All.type) {
        statisticsStore.resetDailyAnalysisData();
    } else {
        promises.push(statisticsStore.loadDailyAnalysis({
            force: force,
            startTime: query.value.categoricalChartStartTime,
            endTime: query.value.categoricalChartEndTime
        }));
    }

    promises.push(statisticsStore.loadCategoricalAnalysis({
        force: force
    }));

    return Promise.all(promises);
}

function init(): void {
    statisticsStore.initTransactionStatisticsFilter(StatisticsAnalysisType.CategoricalAnalysis);
    statisticsStore.updateTransactionStatisticsFilter({
        chartDataType: categoryDimension.value === 'income' ? ChartDataType.IncomeByPrimaryCategory.type : ChartDataType.ExpenseByPrimaryCategory.type
    });

    Promise.all([
        accountsStore.loadAllAccounts({ force: false }),
        transactionCategoriesStore.loadAllCategories({ force: false })
    ]).then(() => {
        return loadStatisticsData({ force: false });
    }).then(() => {
        loading.value = false;
    }).catch(error => {
        if (error.processed) {
            loading.value = false;
        } else {
            loadingError.value = error;
            showToast(error.message || error);
        }
    });
}

function reload(done?: () => void): void {
    const force = !!done;

    reloading.value = true;

    loadStatisticsData({ force: force }).then(() => {
        reloading.value = false;
        done?.();

        if (force) {
            showToast('Data has been updated');
        }
    }).catch(error => {
        reloading.value = false;
        done?.();

        if (!error.processed) {
            showToast(error.message || error);
        }
    });
}

function onPageAfterIn(): void {
    if (statisticsStore.transactionStatisticsStateInvalid && !loading.value) {
        reload();
    }

    routeBackOnError(props.f7router, loadingError);
}

init();
</script>

<style>
.statistics-period-subnavbar .subnavbar-inner {
    justify-content: center;
}

.statistics-period-row {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 100%;
    padding: 4px 12px;
}

.statistics-period-row .statistics-period-shift-button {
    color: var(--f7-text-color);
    opacity: 0.7;
    --f7-icon-font-size: 21px;
}

.statistics-period-row .statistics-period-label {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    margin: 0 16px;
    font-size: 18px;
    font-weight: 600;
    color: var(--f7-text-color);
}

.statistics-period-row .statistics-period-label .f7-icons {
    font-size: 18px;
    opacity: 0.8;
}

.period-mode-segmented {
    display: inline-flex;
    align-items: center;
    padding: 2px;
    border-radius: 15px;
    background: rgba(128, 128, 128, 0.14);
}

.period-mode-segmented span {
    padding: 3px 18px;
    border-radius: 13px;
    font-size: 15px;
    font-weight: 500;
    line-height: 20px;
    color: var(--f7-text-color);
    opacity: 0.72;
    cursor: pointer;
}

.period-mode-segmented span.active {
    background: var(--f7-card-bg-color);
    opacity: 1;
    font-weight: 600;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.12);
}

.statistics-page .card {
    border-radius: var(--ebk-card-border-radius);
    box-shadow: var(--ebk-card-shadow);
}

.dark .statistics-page .card {
    box-shadow: var(--ebk-card-shadow-dark);
}

.statistics-card-title {
    font-size: 17px;
    font-weight: 600;
    color: var(--f7-text-color);
    padding: 16px 16px 0;
}

.statistics-card-title-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 16px 16px 0;
}

.statistics-card-title-row .statistics-card-title {
    padding: 0;
}

.statistics-card-title-row .statistics-chart-type-toggle {
    color: var(--f7-text-color);
    opacity: 0.55;
    --f7-icon-font-size: 21px;
}

.statistics-overview-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 18px 12px;
    padding: 16px;
}

.statistics-overview-item {
    text-align: center;
}

.statistics-overview-label {
    font-size: 14px;
    color: var(--ebk-secondary-text-color);
    margin-bottom: 4px;
}

.statistics-overview-value {
    font-size: 21px;
    font-weight: 700;
    font-variant-numeric: tabular-nums;
    color: var(--f7-text-color);
}

.statistics-daily-chart-container {
    margin-top: 4px;
}

.statistics-chart-mode-segmented {
    display: flex;
    align-items: center;
    justify-content: center;
    width: fit-content;
    margin: 4px auto 14px;
    padding: 2px;
    border-radius: 15px;
    background: rgba(128, 128, 128, 0.14);
}

.statistics-chart-mode-segmented span {
    padding: 3px 18px;
    border-radius: 13px;
    font-size: 14px;
    line-height: 18px;
    color: var(--f7-text-color);
    opacity: 0.72;
    cursor: pointer;
}

.statistics-chart-mode-segmented span.active {
    background: var(--f7-card-bg-color);
    opacity: 1;
    font-weight: 600;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.12);
}

.dark .period-mode-segmented span.active,
.dark .statistics-chart-mode-segmented span.active {
    background: rgba(255, 255, 255, 0.14);
    box-shadow: none;
}

.statistics-category-header-controls {
    display: flex;
    align-items: center;
    gap: 10px;
}

.statistics-category-dimension-segmented {
    display: inline-flex;
    align-items: center;
    padding: 2px;
    border-radius: 12px;
    background: rgba(128, 128, 128, 0.14);
}

.statistics-category-dimension-segmented span {
    padding: 2px 10px;
    border-radius: 10px;
    font-size: 13px;
    line-height: 16px;
    color: var(--f7-text-color);
    opacity: 0.72;
    cursor: pointer;
}

.statistics-category-dimension-segmented span.active {
    background: var(--f7-card-bg-color);
    opacity: 1;
    font-weight: 600;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.12);
}

.dark .statistics-category-dimension-segmented span.active {
    background: rgba(255, 255, 255, 0.14);
    box-shadow: none;
}

.statistics-category-header-controls > .f7-link {
    color: var(--f7-text-color);
    opacity: 0.55;
    --f7-icon-font-size: 18px;
}

.statistics-pie-chart-container {
    margin-top: 4px;
}

.statistics-pie-chart .pie-chart-text-group {
    text-anchor: middle;
}

.statistics-pie-chart-total-amount-title {
    fill: var(--ebk-secondary-text-color, #78909c);
    font-size: 12px;
    -moz-transform: translateY(-0.15em);
    -ms-transform: translateY(-0.15em);
    -webkit-transform: translateY(-0.15em);
    transform: translateY(-0.15em);
}

.statistics-pie-chart-total-amount-value {
    fill: #1f2937;
    font-size: 19px;
    font-weight: 600;
    -moz-transform: translateY(1.22em);
    -ms-transform: translateY(1.22em);
    -webkit-transform: translateY(1.22em);
    transform: translateY(1.22em);
}

.dark .statistics-pie-chart-total-amount-value {
    fill: #eceff3;
}

.statistics-pie-chart-total-no-data {
    fill: var(--ebk-secondary-text-color, #78909c);
    font-size: 12px;
    -moz-transform: translateY(0.35em);
    -ms-transform: translateY(0.35em);
    -webkit-transform: translateY(0.35em);
    transform: translateY(0.35em);
}

.statistics-category-ranking-list {
    padding: 8px 16px 16px;
}

.statistics-category-ranking-item {
    display: flex;
    align-items: center;
    padding: 8px 0;
    cursor: pointer;
}

.statistics-category-ranking-icon {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 34px;
    margin-inline-end: 10px;
    --f7-icon-font-size: 23px;
}

.statistics-category-ranking-main {
    flex: 1;
    min-width: 0;
    margin-inline-end: 10px;
}

.statistics-category-ranking-first-row {
    display: flex;
    align-items: baseline;
    gap: 6px;
    margin-bottom: 5px;
}

.statistics-category-ranking-name {
    font-size: 15px;
    color: var(--f7-text-color);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}

.statistics-category-ranking-percent {
    font-size: 13px;
    color: var(--ebk-secondary-text-color);
    flex-shrink: 0;
}

.statistics-category-ranking-bar {
    height: 3px;
    border-radius: 2px;
    background: rgba(128, 128, 128, 0.15);
    overflow: hidden;
}

.statistics-category-ranking-bar-fill {
    height: 100%;
    border-radius: 2px;
}

.statistics-category-ranking-amount {
    font-size: 15px;
    font-weight: 500;
    font-variant-numeric: tabular-nums;
    color: var(--f7-text-color);
    white-space: nowrap;
}

.statistics-daily-report-title {
    font-size: 17px;
    font-weight: 600;
    color: var(--f7-text-color);
    text-align: center;
    padding: 16px 16px 4px;
}

.statistics-daily-report-table {
    padding: 4px 16px 16px;
}

.statistics-daily-report-row {
    display: grid;
    grid-template-columns: 1.1fr 1fr 1fr 1.2fr;
    align-items: center;
    padding: 9px 0;
    font-size: 14px;
    font-variant-numeric: tabular-nums;
    color: var(--f7-text-color);
}

.statistics-daily-report-row > span:nth-child(2),
.statistics-daily-report-row > span:nth-child(3) {
    text-align: end;
}

.statistics-daily-report-row > span:nth-child(4) {
    text-align: end;
}

.statistics-daily-report-header {
    color: var(--ebk-secondary-text-color);
    font-size: 13px;
}

.statistics-daily-report-average {
    color: var(--ebk-secondary-text-color);
}

.statistics-daily-report-empty {
    padding: 8px 16px 20px;
    text-align: center;
    color: var(--f7-text-color);
    opacity: 0.65;
}

.statistics-view-details-link {
    display: flex;
    justify-content: center;
    padding: 4px 0 24px;
}

.statistics-view-details-link .f7-link {
    color: rgb(var(--ebk-primary-color));
    font-size: 15px;
}
</style>
