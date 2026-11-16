<template>
    <v-card-text class="statistics-overview-panel" :class="{ 'disabled': loading && !initing }">
        <!-- 收支总览 -->
        <v-row class="overview-cards-row" dense>
            <v-col cols="12" sm="6" lg="3">
                <v-card class="overview-amount-card" variant="tonal" color="error" :elevation="0">
                    <div class="overview-amount-label">{{ tt('Expense') }}</div>
                    <div class="overview-amount-value text-expense" v-if="!initing">{{ getDisplayAmount(overviewExpenseAmount) }}</div>
                    <v-skeleton-loader class="skeleton-no-margin" width="100" type="text" :loading="true" v-else/>
                </v-card>
            </v-col>
            <v-col cols="12" sm="6" lg="3">
                <v-card class="overview-amount-card" variant="tonal" color="success" :elevation="0">
                    <div class="overview-amount-label">{{ tt('Income') }}</div>
                    <div class="overview-amount-value text-income" v-if="!initing">{{ getDisplayAmount(overviewIncomeAmount) }}</div>
                    <v-skeleton-loader class="skeleton-no-margin" width="100" type="text" :loading="true" v-else/>
                </v-card>
            </v-col>
            <v-col cols="12" sm="6" lg="3">
                <v-card class="overview-amount-card" variant="tonal" :elevation="0">
                    <div class="overview-amount-label">{{ tt('Balance') }}</div>
                    <div class="overview-amount-value" v-if="!initing">{{ getDisplayAmount(overviewBalanceAmount) }}</div>
                    <v-skeleton-loader class="skeleton-no-margin" width="100" type="text" :loading="true" v-else/>
                </v-card>
            </v-col>
            <v-col cols="12" sm="6" lg="3">
                <v-card class="overview-amount-card" variant="tonal" :elevation="0">
                    <div class="overview-amount-label">{{ tt('Daily Average Expense') }}</div>
                    <div class="overview-amount-value" v-if="!initing">{{ getDisplayAmount(dailyAverageExpenseAmount) }}</div>
                    <v-skeleton-loader class="skeleton-no-margin" width="100" type="text" :loading="true" v-else/>
                </v-card>
            </v-col>
        </v-row>

        <v-row dense>
            <!-- 每日收支统计 -->
            <v-col cols="12" lg="7">
                <v-card class="overview-block-card" variant="outlined" :elevation="0">
                    <template #title>
                        <div class="d-flex align-center">
                            <span class="overview-block-title">{{ tt('Daily Income and Expense Statistics') }}</span>
                            <v-spacer/>
                            <v-btn-group density="compact" variant="outlined" divided :disabled="loading">
                                <v-btn size="small" :color="dailyChartType === 'bar' ? 'primary' : 'default'"
                                       :variant="dailyChartType === 'bar' ? 'tonal' : 'outlined'"
                                       @click="dailyChartType = 'bar'">
                                    <v-icon :icon="mdiChartBar" size="18"/>
                                </v-btn>
                                <v-btn size="small" :color="dailyChartType === 'line' ? 'primary' : 'default'"
                                       :variant="dailyChartType === 'line' ? 'tonal' : 'outlined'"
                                       @click="dailyChartType = 'line'">
                                    <v-icon :icon="mdiChartLine" size="18"/>
                                </v-btn>
                            </v-btn-group>
                            <v-btn-group class="ms-3" density="compact" variant="outlined" divided :disabled="loading">
                                <v-btn size="small" :color="dailyChartMode === 'expense' ? 'primary' : 'default'"
                                       :variant="dailyChartMode === 'expense' ? 'tonal' : 'outlined'"
                                       @click="dailyChartMode = 'expense'">{{ tt('Expense') }}</v-btn>
                                <v-btn size="small" :color="dailyChartMode === 'income' ? 'primary' : 'default'"
                                       :variant="dailyChartMode === 'income' ? 'tonal' : 'outlined'"
                                       @click="dailyChartMode = 'income'">{{ tt('Income') }}</v-btn>
                                <v-btn size="small" :color="dailyChartMode === 'all' ? 'primary' : 'default'"
                                       :variant="dailyChartMode === 'all' ? 'tonal' : 'outlined'"
                                       @click="dailyChartMode = 'all'">{{ tt('All') }}</v-btn>
                            </v-btn-group>
                        </div>
                    </template>
                    <v-card-text class="pt-0">
                        <daily-income-expense-chart
                            :items="dailyChartItems"
                            :mode="dailyChartMode"
                            :chart-type="dailyChartType"
                            :loading="loading || initing"
                            :expense-color="expenseColor"
                            :income-color="incomeColor"
                            @click="onClickDailyChartItem"
                        />
                    </v-card-text>
                </v-card>
            </v-col>

            <!-- 每日报告 -->
            <v-col cols="12" lg="5">
                <v-card class="overview-block-card" variant="outlined" :elevation="0">
                    <template #title>
                        <span class="overview-block-title">{{ tt('Daily Report') }}</span>
                    </template>
                    <v-card-text class="pt-0">
                        <v-table class="daily-report-table" density="compact" v-if="!initing && dailyReportRows.length">
                            <thead>
                                <tr>
                                    <th class="text-start">{{ tt('Date') }}</th>
                                    <th class="text-end">{{ tt('Income') }}</th>
                                    <th class="text-end">{{ tt('Expense') }}</th>
                                    <th class="text-end">{{ tt('Balance') }}</th>
                                </tr>
                            </thead>
                            <tbody>
                                <tr :key="row.label" v-for="row in dailyReportRows">
                                    <td>{{ row.label }}</td>
                                    <td class="text-end">{{ formatDisplayAmount(row.incomeAmount) }}</td>
                                    <td class="text-end">{{ formatDisplayAmount(row.expenseAmount) }}</td>
                                    <td class="text-end" :class="{ 'text-expense': row.balanceAmount < 0 }">{{ formatDisplayAmount(row.balanceAmount) }}</td>
                                </tr>
                                <tr class="daily-report-average" v-if="elapsedDaysInRange > 0">
                                    <td>{{ tt('Average') }}</td>
                                    <td class="text-end">{{ formatDisplayAmount(reportTotalIncomeAmount / elapsedDaysInRange) }}</td>
                                    <td class="text-end">{{ formatDisplayAmount(reportTotalExpenseAmount / elapsedDaysInRange) }}</td>
                                    <td class="text-end" :class="{ 'text-expense': reportTotalBalanceAmount < 0 }">{{ formatDisplayAmount(reportTotalBalanceAmount / elapsedDaysInRange) }}</td>
                                </tr>
                            </tbody>
                        </v-table>
                        <div class="overview-empty" v-else-if="!initing">{{ tt('No transaction data') }}</div>
                        <v-skeleton-loader class="skeleton-no-margin" type="table-row@4" :loading="true" v-else/>
                    </v-card-text>
                </v-card>
            </v-col>

            <!-- 分类排行 -->
            <v-col cols="12">
                <v-card class="overview-block-card" variant="outlined" :elevation="0">
                    <template #title>
                        <div class="d-flex align-center">
                            <span class="overview-block-title">{{ tt('Categorical Analysis') }}</span>
                            <v-spacer/>
                            <v-btn-group density="compact" variant="outlined" divided :disabled="loading">
                                <v-btn size="small" :color="categoryDimension === 'expense' ? 'primary' : 'default'"
                                       :variant="categoryDimension === 'expense' ? 'tonal' : 'outlined'"
                                       @click="setCategoryDimension('expense')">{{ tt('Expense') }}</v-btn>
                                <v-btn size="small" :color="categoryDimension === 'income' ? 'primary' : 'default'"
                                       :variant="categoryDimension === 'income' ? 'tonal' : 'outlined'"
                                       @click="setCategoryDimension('income')">{{ tt('Income') }}</v-btn>
                            </v-btn-group>
                            <span class="overview-total-amount ms-6">{{ categoryTotalAmountName }}</span>
                            <span class="overview-total-amount-value ms-2"
                                  :class="categoryDimension === 'income' ? 'text-income' : 'text-expense'">
                                {{ getDisplayAmount(categoricalTotalAmount) }}
                            </span>
                        </div>
                    </template>
                    <v-card-text class="pt-0">
                        <div class="category-ranking-list" v-if="!initing && categoryItems.length">
                            <div class="category-ranking-item" :key="item.id" v-for="item in categoryItems" v-show="!item.hidden"
                                 @click="onClickCategoryItem(item)">
                                <div class="category-ranking-icon">
                                    <ItemIcon icon-type="category" :icon-id="item.icon" :color="item.color" v-if="item.icon"
                                              :size="'22px'"/>
                                    <v-icon :icon="mdiShapeOutline" size="22" v-else/>
                                </div>
                                <div class="category-ranking-main">
                                    <div class="category-ranking-title">
                                        <span class="category-ranking-name">{{ item.name }}</span>
                                        <span class="category-ranking-percent" v-if="item.percent >= 0 && item.totalAmount >= 0">
                                            {{ formatPercentToLocalizedNumerals(item.percent, 2, '<0.01') }}
                                        </span>
                                    </div>
                                    <div class="category-ranking-bar">
                                        <div class="category-ranking-bar-fill"
                                             :style="{ 'width': (item.percent >= 0 ? item.percent : 0) + '%', 'background-color': getCategoryItemColor(item) }"></div>
                                    </div>
                                </div>
                                <div class="category-ranking-amount">{{ getDisplayAmount(item.totalAmount) }}</div>
                            </div>
                        </div>
                        <div class="overview-empty" v-else-if="!initing">{{ tt('No transaction data') }}</div>
                        <v-skeleton-loader class="skeleton-no-margin" type="list-item-two-line@5" :loading="true" v-else/>
                    </v-card-text>
                </v-card>
            </v-col>
        </v-row>

        <div class="overview-view-details" v-if="!initing">
            <v-btn variant="text" size="small" color="primary" @click="emit('view:details')">
                {{ tt('View transaction details') }}
            </v-btn>
        </div>
    </v-card-text>
</template>

<script setup lang="ts">
import DailyIncomeExpenseChart from '@/components/common/DailyIncomeExpenseChart.vue';

import { ref, computed } from 'vue';

import { useI18n } from '@/locales/helpers.ts';

import type { TransactionStatisticsFilter } from '@/stores/statistics.ts';

import { type YearMonthDay } from '@/core/datetime.ts';

import type { TransactionCategoricalAnalysisDataItem, TransactionDailyAnalysisDataItem } from '@/models/transaction.ts';

import {
    parseDateTimeFromUnixTime,
    getYearMonthFirstUnixTime,
    getYearMonthLastUnixTime,
    getYearMonthDayDateTime,
    getGregorianCalendarYearMonthDays,
    getDayDifference,
    getTodayFirstUnixTime
} from '@/lib/datetime.ts';
import { getCategoryDisplayColor, getAccountDisplayColor } from '@/lib/color.ts';

import {
    mdiChartBar,
    mdiChartLine,
    mdiShapeOutline
} from '@mdi/js';

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

interface ChartSlotRange {
    label: string;
    minTime: number;
    maxTime: number;
}

const props = defineProps<{
    loading: boolean;
    initing: boolean;
    query: TransactionStatisticsFilter;
    overviewIncomeAmount: number;
    overviewExpenseAmount: number;
    dailyItems: TransactionDailyAnalysisDataItem[];
    categoryItems: TransactionCategoricalAnalysisDataItem[];
    categoricalTotalAmount: number;
    categoryDimension: 'expense' | 'income';
    defaultCurrency: string;
    expenseColor: string;
    incomeColor: string;
}>();

const emit = defineEmits<{
    (e: 'update:categoryDimension', value: 'expense' | 'income'): void;
    (e: 'click:day', value: { minTime: number, maxTime: number, mode: 'expense' | 'income' | 'all' }): void;
    (e: 'click:category', value: string): void;
    (e: 'view:details'): void;
}>();

const {
    tt,
    formatDateTimeToShortMonthDay,
    formatDateTimeToGregorianLikeShortMonth,
    formatDateTimeToGregorianLikeShortYearMonth,
    formatAmountToLocalizedNumeralsWithCurrency,
    formatAmountToLocalizedNumerals,
    formatNumberToLocalizedNumerals,
    formatPercentToLocalizedNumerals
} = useI18n();

const dailyChartMode = ref<'expense' | 'income' | 'all'>('expense');
const dailyChartType = ref<'bar' | 'line'>('bar');

const categoryTotalAmountName = computed<string>(() => {
    return props.categoryDimension === 'income' ? tt('Total Income') : tt('Total Expense');
});

const overviewBalanceAmount = computed<number>(() => {
    return props.overviewIncomeAmount - props.overviewExpenseAmount;
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
    const startTime = props.query.categoricalChartStartTime;
    const endTime = props.query.categoricalChartEndTime;

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

    return Math.round(props.overviewExpenseAmount / elapsedDaysInRange.value);
});

const useDailySlots = computed<boolean>(() => {
    const startTime = props.query.categoricalChartStartTime;
    const endTime = props.query.categoricalChartEndTime;

    if (!startTime || !endTime) {
        return false;
    }

    const days = getDaysInRange(startTime, endTime);

    return days > 0 && days <= 62;
});

const chartSlotRanges = computed<ChartSlotRange[]>(() => {
    const startTime = props.query.categoricalChartStartTime;
    const endTime = props.query.categoricalChartEndTime;

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

    for (const dailyItem of props.dailyItems) {
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
    const startTime = props.query.categoricalChartStartTime;
    const endTime = props.query.categoricalChartEndTime;

    if (!startTime || !endTime) {
        return rows;
    }

    const sameYear = parseDateTimeFromUnixTime(startTime).getGregorianCalendarYear() === parseDateTimeFromUnixTime(endTime).getGregorianCalendarYear();

    for (const slot of chartSlotRanges.value) {
        let incomeAmount = 0;
        let expenseAmount = 0;

        for (const dailyItem of props.dailyItems) {
            const dayUnixTime = getYearMonthDayDateTime(dailyItem.year, dailyItem.month, dailyItem.day).getUnixTime();

            if (dayUnixTime >= slot.minTime && dayUnixTime <= slot.maxTime) {
                incomeAmount += dailyItem.incomeAmount;
                expenseAmount += dailyItem.expenseAmount;
            }
        }

        if (incomeAmount === 0 && expenseAmount === 0) {
            continue;
        }

        let label: string;

        if (useDailySlots.value) {
            label = formatDateTimeToShortMonthDay(parseDateTimeFromUnixTime(slot.minTime));
        } else if (sameYear) {
            label = formatDateTimeToGregorianLikeShortMonth(parseDateTimeFromUnixTime(slot.minTime));
        } else {
            label = formatDateTimeToGregorianLikeShortYearMonth(parseDateTimeFromUnixTime(slot.minTime));
        }

        rows.push({
            label: label,
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

function getDisplayAmount(amount: number, currency?: string): string {
    return formatAmountToLocalizedNumeralsWithCurrency(Math.round(amount), currency || props.defaultCurrency);
}

function formatDisplayAmount(amount: number): string {
    return formatAmountToLocalizedNumerals(Math.round(amount));
}

function getCategoryItemColor(item: TransactionCategoricalAnalysisDataItem): string {
    if (item.type === 'account') {
        return getAccountDisplayColor(item.color);
    }

    return getCategoryDisplayColor(item.color);
}

function setCategoryDimension(dimension: 'expense' | 'income'): void {
    if (props.categoryDimension === dimension) {
        return;
    }

    emit('update:categoryDimension', dimension);
}

function onClickDailyChartItem(value: { minTime: number, maxTime: number }): void {
    emit('click:day', {
        minTime: value.minTime,
        maxTime: value.maxTime,
        mode: dailyChartMode.value
    });
}

function onClickCategoryItem(item: TransactionCategoricalAnalysisDataItem): void {
    emit('click:category', item.id);
}
</script>

<style scoped>
.statistics-overview-panel {
    padding-top: 0;
}

.overview-cards-row > .v-col {
    padding-top: 0;
}

.overview-amount-card {
    padding: 14px 16px;
    height: 100%;
}

.overview-amount-label {
    font-size: 13px;
    opacity: 0.7;
    margin-bottom: 6px;
}

.overview-amount-value {
    font-size: 22px;
    font-weight: 600;
    line-height: 1.2;
    word-break: break-all;
}

.overview-block-card {
    height: 100%;
}

.overview-block-title {
    font-size: 16px;
}

.overview-total-amount {
    font-size: 13px;
    opacity: 0.7;
}

.overview-total-amount-value {
    font-size: 16px;
    font-weight: 600;
}

.overview-empty {
    padding: 40px 16px;
    text-align: center;
    opacity: 0.6;
}

.overview-view-details {
    display: flex;
    justify-content: center;
    padding-top: 8px;
}

.daily-report-table {
    background: transparent;
}

.daily-report-table :deep(th),
.daily-report-table :deep(td) {
    white-space: nowrap;
}

.daily-report-average :deep(td) {
    font-weight: 600;
    border-top: 1px solid rgba(var(--v-border-color), var(--v-border-opacity));
}

.category-ranking-list {
    display: flex;
    flex-direction: column;
    gap: 6px;
}

.category-ranking-item {
    display: flex;
    align-items: center;
    padding: 6px 8px;
    border-radius: 8px;
    cursor: pointer;
    transition: background-color 0.15s ease;
}

.category-ranking-item:hover {
    background-color: rgba(var(--v-border-color), 0.25);
}

.category-ranking-icon {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 30px;
    flex: 0 0 30px;
}

.category-ranking-main {
    flex: 1 1 auto;
    min-width: 0;
    margin-inline: 10px;
}

.category-ranking-title {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 8px;
}

.category-ranking-name {
    font-size: 14px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
}

.category-ranking-percent {
    font-size: 12px;
    opacity: 0.6;
    flex: 0 0 auto;
}

.category-ranking-bar {
    height: 6px;
    margin-top: 4px;
    border-radius: 3px;
    background-color: rgba(var(--v-border-color), 0.35);
    overflow: hidden;
}

.category-ranking-bar-fill {
    height: 100%;
    border-radius: 3px;
    transition: width 0.3s ease;
}

.category-ranking-amount {
    flex: 0 0 auto;
    font-size: 14px;
    font-weight: 500;
    text-align: end;
    min-width: 90px;
}
</style>
