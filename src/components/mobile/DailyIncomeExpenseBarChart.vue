<template>
    <div class="daily-income-expense-chart-container">
        <div class="daily-income-expense-chart-empty" v-if="!loading && !hasData">
            {{ tt('No transaction data') }}
        </div>

        <svg class="daily-income-expense-chart" viewBox="0 0 340 216" v-else>
            <g class="daily-income-expense-chart-grid" v-if="yAxisStep > 0">
                <line :x1="chartLeft" :y1="getYAxisValue(yAxisStep * tickIdx)" :x2="340 - chartRight" :y2="getYAxisValue(yAxisStep * tickIdx)"
                      :class="{ 'daily-income-expense-chart-grid-line': true, 'daily-income-expense-chart-grid-baseline': tickIdx === 0 }"
                      :key="tickIdx"
                      v-for="tickIdx in yAxisTicks"></line>
            </g>

            <text class="daily-income-expense-chart-y-label"
                  :x="chartLeft - 6" :y="getYAxisValue(yAxisStep * tickIdx) + 3"
                  :key="`y-${tickIdx}`"
                  v-for="tickIdx in yAxisTicks">{{ formatAxisValue(yAxisStep * tickIdx) }}</text>

            <g v-if="chartType === 'bar'">
                <template :key="`bar-${idx}`" v-for="(item, idx) in items">
                    <rect class="daily-income-expense-chart-bar"
                          :x="getExpenseBarX(idx)" :y="getBarY(item.expenseAmount)" :width="getBarWidth()" :height="getBarHeight(item.expenseAmount)"
                          :fill="expenseColor"
                          v-if="showExpense"></rect>
                    <rect class="daily-income-expense-chart-bar"
                          :x="getIncomeBarX(idx)" :y="getBarY(item.incomeAmount)" :width="getBarWidth()" :height="getBarHeight(item.incomeAmount)"
                          :fill="incomeColor"
                          v-if="showIncome"></rect>
                </template>
            </g>

            <g v-else>
                <template v-if="showExpense">
                    <polyline class="daily-income-expense-chart-line"
                              :points="expenseLinePoints"
                              :stroke="expenseColor"
                              v-if="expenseLinePoints"></polyline>
                    <circle class="daily-income-expense-chart-line-dot"
                            :cx="getSlotCenterX(idx)" :cy="getBarY(item.expenseAmount)" r="2.5"
                            :fill="expenseColor"
                            :key="`expense-dot-${idx}`"
                            v-for="(item, idx) in items"></circle>
                </template>
                <template v-if="showIncome">
                    <polyline class="daily-income-expense-chart-line"
                              :points="incomeLinePoints"
                              :stroke="incomeColor"
                              v-if="incomeLinePoints"></polyline>
                    <circle class="daily-income-expense-chart-line-dot"
                            :cx="getSlotCenterX(idx)" :cy="getBarY(item.incomeAmount)" r="2.5"
                            :fill="incomeColor"
                            :key="`income-dot-${idx}`"
                            v-for="(item, idx) in items"></circle>
                </template>
            </g>

            <text class="daily-income-expense-chart-x-label"
                  :x="getSlotCenterX(labelIdx)" :y="216 - 6"
                  :key="`x-${labelIdx}`"
                  v-for="labelIdx in xAxisLabelIndexes">{{ items[labelIdx]?.label }}</text>

            <rect class="daily-income-expense-chart-click-area"
                  :x="getSlotX(idx)" y="0" :width="getSlotWidth()" :height="216"
                  :key="`click-${idx}`"
                  v-for="(item, idx) in items"
                  @click="clickItem(item)"></rect>
        </svg>
    </div>
</template>

<script setup lang="ts">
import { computed } from 'vue';

import { useI18n } from '@/locales/helpers.ts';

interface DailyIncomeExpenseChartDataItem {
    readonly label: string;
    readonly minTime: number;
    readonly maxTime: number;
    readonly expenseAmount: number;
    readonly incomeAmount: number;
}

interface MobileDailyIncomeExpenseBarChartProps {
    items: DailyIncomeExpenseChartDataItem[];
    mode?: 'expense' | 'income' | 'all';
    chartType?: 'bar' | 'line';
    loading?: boolean;
    expenseColor?: string;
    incomeColor?: string;
}

const props = withDefaults(defineProps<MobileDailyIncomeExpenseBarChartProps>(), {
    mode: 'expense',
    chartType: 'bar',
    loading: false,
    expenseColor: '#d43f3f',
    incomeColor: '#009688'
});

const emit = defineEmits<{
    (e: 'click', value: { minTime: number, maxTime: number }): void;
}>();

const { tt, formatAmountToLocalizedNumerals } = useI18n();

const chartLeft = 54;
const chartRight = 8;
const chartTop = 8;
const chartBottom = 26;
const chartBaseline = 216 - chartBottom;

const showExpense = computed<boolean>(() => props.mode === 'expense' || props.mode === 'all');
const showIncome = computed<boolean>(() => props.mode === 'income' || props.mode === 'all');

const maxValue = computed<number>(() => {
    let maxValue = 0;

    for (const item of props.items) {
        if (showExpense.value && item.expenseAmount > maxValue) {
            maxValue = item.expenseAmount;
        }

        if (showIncome.value && item.incomeAmount > maxValue) {
            maxValue = item.incomeAmount;
        }
    }

    return maxValue;
});

const yAxisStep = computed<number>(() => {
    if (maxValue.value <= 0) {
        return 0;
    }

    const rawStep = maxValue.value / 4;
    const exponent = Math.floor(Math.log10(rawStep));
    const base = Math.pow(10, exponent);
    const fraction = rawStep / base;
    let niceFraction: number;

    if (fraction <= 1) {
        niceFraction = 1;
    } else if (fraction <= 2) {
        niceFraction = 2;
    } else if (fraction <= 2.5) {
        niceFraction = 2.5;
    } else if (fraction <= 5) {
        niceFraction = 5;
    } else {
        niceFraction = 10;
    }

    return niceFraction * base;
});

const hasData = computed<boolean>(() => {
    for (const item of props.items) {
        if (item.expenseAmount > 0 || item.incomeAmount > 0) {
            return true;
        }
    }

    return false;
});

const yAxisTicks = [0, 1, 2, 3, 4];

const xAxisLabelIndexes = computed<number[]>(() => {
    const count = props.items.length;

    if (!count) {
        return [];
    }

    const labelIndexes: number[] = [];
    const step = Math.max(1, Math.ceil(count / 9));

    for (let i = 0; i < count; i += step) {
        labelIndexes.push(i);
    }

    if (labelIndexes[labelIndexes.length - 1] !== count - 1) {
        if (count - 1 - labelIndexes[labelIndexes.length - 1]! < step / 2) {
            labelIndexes[labelIndexes.length - 1] = count - 1;
        } else {
            labelIndexes.push(count - 1);
        }
    }

    return labelIndexes;
});

function getSlotWidth(): number {
    return (340 - chartLeft - chartRight) / Math.max(props.items.length, 1);
}

function getSlotX(idx: number): number {
    return chartLeft + idx * getSlotWidth();
}

function getSlotCenterX(idx: number): number {
    return getSlotX(idx) + getSlotWidth() / 2;
}

function getBarWidth(): number {
    const slotWidth = getSlotWidth();

    if (props.mode === 'all') {
        return Math.min(9, slotWidth * 0.28);
    }

    return Math.min(13, slotWidth * 0.55);
}

function getExpenseBarX(idx: number): number {
    const center = getSlotCenterX(idx);

    if (props.mode === 'all') {
        return center - getBarWidth() - 1;
    }

    return center - getBarWidth() / 2;
}

function getIncomeBarX(idx: number): number {
    const center = getSlotCenterX(idx);

    if (props.mode === 'all') {
        return center + 1;
    }

    return center - getBarWidth() / 2;
}

function getYAxisValue(value: number): number {
    const yTopValue = yAxisStep.value * 4;

    if (yTopValue <= 0) {
        return chartBaseline;
    }

    return chartBaseline - (chartBaseline - chartTop) * value / yTopValue;
}

function getBarHeight(value: number): number {
    const yTopValue = yAxisStep.value * 4;

    if (yTopValue <= 0 || value <= 0) {
        return 0;
    }

    const height = (chartBaseline - chartTop) * value / yTopValue;

    return height < 3 ? 3 : height;
}

function getBarY(value: number): number {
    return chartBaseline - getBarHeight(value);
}

function buildLinePoints(valueField: 'expenseAmount' | 'incomeAmount'): string {
    if (!props.items.length) {
        return '';
    }

    return props.items.map((item, idx) => `${getSlotCenterX(idx)},${getBarY(item[valueField])}`).join(' ');
}

const expenseLinePoints = computed<string>(() => buildLinePoints('expenseAmount'));
const incomeLinePoints = computed<string>(() => buildLinePoints('incomeAmount'));

function formatAxisValue(value: number): string {
    return formatAmountToLocalizedNumerals(value);
}

function clickItem(item: DailyIncomeExpenseChartDataItem): void {
    emit('click', {
        minTime: item.minTime,
        maxTime: item.maxTime
    });
}
</script>

<style scoped>
.daily-income-expense-chart-container {
    width: 100%;
}

.daily-income-expense-chart {
    display: block;
    width: 100%;
}

.daily-income-expense-chart-empty {
    padding: 42px 16px;
    text-align: center;
    color: var(--f7-text-color);
    opacity: 0.65;
}

.daily-income-expense-chart-grid-line {
    stroke: var(--ebk-divider-color);
    stroke-width: 1;
    stroke-dasharray: 4 4;
}

.daily-income-expense-chart-grid-baseline {
    stroke-dasharray: none;
    opacity: 0.9;
}

.daily-income-expense-chart-y-label,
.daily-income-expense-chart-x-label {
    font-size: 11px;
    fill: var(--f7-text-color);
    opacity: 0.45;
    text-anchor: middle;
}

.daily-income-expense-chart-y-label {
    text-anchor: end;
}

.daily-income-expense-chart-bar {
    opacity: 0.85;
}

.daily-income-expense-chart-line {
    fill: none;
    stroke-width: 2;
    stroke-linejoin: round;
    stroke-linecap: round;
    opacity: 0.85;
}

.daily-income-expense-chart-click-area {
    fill: transparent;
}
</style>
