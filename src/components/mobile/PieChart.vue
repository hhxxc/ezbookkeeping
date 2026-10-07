<template>
    <div class="pie-chart-container">
        <svg class="pie-chart" :viewBox="`${-diameter} ${-diameter} ${diameter * 2} ${diameter * 2}`">
            <circle class="pie-chart-track" cx="0" cy="0" fill="none" :r="ringRadius" :stroke-width="ringWidth"></circle>

            <template :key="idx" v-for="(item, idx) in validItems">
                <circle class="pie-chart-item"
                        fill="none"
                        cx="0" cy="0"
                        :r="ringRadius"
                        :stroke="item.color"
                        :stroke-width="ringWidth"
                        stroke-linecap="round"
                        :stroke-dasharray="getItemStrokeDash(item)"
                        :stroke-dashoffset="getItemDashOffset(item, itemCommonDashOffset)"
                        @click="switchSelectedIndex(idx)"
                        v-if="item.actualValue > 0 && item.paintPercent > minPaintPercent && !isWedgeItem(item)">
                </circle>
                <path class="pie-chart-item"
                      :fill="item.color"
                      :d="getWedgePathD(item)"
                      @click="switchSelectedIndex(idx)"
                      v-else-if="item.actualValue > 0 && item.paintPercent > minPaintPercent">
                </path>
            </template>

            <clipPath id="pie-chart-text-clip">
                <rect :x="-textClipBound" :y="-textClipBound" :width="textClipBound * 2" :height="textClipBound * 2"/>
            </clipPath>

            <g class="pie-chart-text-group" clip-path="url(#pie-chart-text-clip)" v-if="showCenterText">
                <slot></slot>
            </g>
        </svg>
        <div class="pie-chart-toolbox-container padding-horizontal" v-if="showSelectedItemInfo">
            <div class="pie-chart-toolbox">
                <f7-link class="pie-chart-toolbox-button" :class="{ 'disabled': !!skeleton || !validItems || validItems.length <= 1 }" @click="switchSelectedItem(1)">
                    <f7-icon class="icon-with-direction" f7="arrow_left"></f7-icon>
                </f7-link>

                <div class="pie-chart-toolbox-info">
                    <p v-if="showPercent && selectedItem && selectedItem.actualValue >= 0">
                        <f7-chip class="chip-placeholder" outline v-if="skeleton">
                            <span class="skeleton-text">Percent</span>
                        </f7-chip>
                        <f7-chip outline
                                 :text="selectedItem.displayPercent"
                                 :style="getColorStyle(selectedItem?.color, '--f7-chip-outline-border-color')"
                                 v-else-if="!skeleton"></f7-chip>
                    </p>
                    <p v-else-if="showPercent && (!validItems || !validItems.length || !selectedItem || selectedItem.actualValue < 0)">
                        <f7-chip outline text="---"></f7-chip>
                    </p>
                    <f7-link class="pie-chart-selected-item-info" :no-link-class="!enableClickItem" v-if="selectedItem" @click="clickItem(selectedItem)">
                        <span class="skeleton-text" v-if="skeleton">Name</span>
                        <span v-else-if="!skeleton && selectedItem.displayName">{{ selectedItem.displayName }}</span>
                        <span class="skeleton-text" v-if="skeleton">Value</span>
                        <span v-else-if="!skeleton && showValue" :style="getColorStyle(selectedItem?.color)">{{ selectedItem.displayValue }}</span>
                        <f7-icon class="item-navigate-icon icon-with-direction" f7="chevron_right" v-if="enableClickItem"></f7-icon>
                    </f7-link>
                    <f7-link :no-link-class="true" v-else-if="!validItems || !validItems.length">
                        {{ tt('No transaction data') }}
                    </f7-link>
                </div>

                <f7-link class="pie-chart-toolbox-button" :class="{ 'disabled': !!skeleton || !validItems || validItems.length <= 1 }" @click="switchSelectedItem(-1)">
                    <f7-icon class="icon-with-direction" f7="arrow_right"></f7-icon>
                </f7-link>
            </div>
        </div>
    </div>
</template>

<script setup lang="ts">
import { computed } from 'vue';

import { useI18n } from '@/locales/helpers.ts';
import { type CommonPieChartDataItem, type CommonPieChartProps, usePieChartBase } from '@/components/base/PieChartBase.ts'

import type { ColorStyleValue } from '@/core/color.ts';

interface MobilePieChartProps extends CommonPieChartProps {
    showCenterText?: boolean;
    showSelectedItemInfo?: boolean;
}

const props = defineProps<MobilePieChartProps>();

const emit = defineEmits<{
    (e: 'click', value: Record<string, unknown>): void;
}>();

const { tt } = useI18n();
const { selectedIndex, validItems } = usePieChartBase(props);

const minPaintPercent = 0.0001; // 0.01%
const diameter: number = 100;
// 细环 + 圆头分段 + 分段间隙的现代环形图：分段间隙 = 2*margin - ringWidth（圆头各占 ringWidth/2）
const ringRadius: number = 78;
const ringWidth: number = 20;
const segmentMargin: number = (ringWidth + 6) / 2;
const segmentGap: number = 6;
// 圆头分段的最小弧位：dash 保底 1.5 + 两端圆头各 ringWidth/2 + 一端间隙
const roundCapMinSlot: number = 1.5 + ringWidth + segmentGap;
// 装不下圆点的分段用带圆角的楔形块渲染：两端各收缩 wedgeSideInset（与圆头相邻的间隙
// = wedgeSideInset + 圆头回缩 segmentMargin - ringWidth/2），圆角半径随弧长自适应收缩
const wedgeSideInset: number = 1.5;
const wedgeCornerRadius: number = 4;
const circumference: number = 2 * Math.PI * ringRadius;
// 中心文字裁切到环形内孔（旧设计裁到中心圆盘 ±38，金额两端会被削出毛边）
const textClipBound: number = ringRadius - ringWidth / 2 - 2;

const totalValidValue = computed<number>(() => {
    let totalValidValue = 0;

    for (const item of validItems.value) {
        if (item.actualValue > 0 && item.paintPercent > minPaintPercent) {
            totalValidValue += item.value;
        }
    }

    return totalValidValue;
});

const itemCommonDashOffset = computed<number>(() => {
    if (totalValidValue.value <= 0) {
        return 0;
    }

    let offset = 0;

    for (let i = 0; i < Math.min(selectedIndex.value + 1, validItems.value.length); i++) {
        const item = validItems.value[i] as CommonPieChartDataItem;

        if (item.actualValue > 0 && item.paintPercent > minPaintPercent) {
            if (i === selectedIndex.value) {
                offset += -circumference * (1 - item.paintPercent) / 2;
            } else {
                offset += -circumference * (1 - item.paintPercent);
            }
        } else {
            if (i === selectedIndex.value) {
                offset += -circumference / 2;
            } else {
                offset += -circumference;
            }
        }
    }

    return offset;
});

function getColorStyle(color: ColorStyleValue, additionalFieldName?: string): Record<string, string> {
    const ret: Record<string, string> = {
        color: color
    };

    if (additionalFieldName) {
        ret[additionalFieldName] = color;
    }

    return ret;
}

function isWedgeItem(item: CommonPieChartDataItem): boolean {
    if (validItems.value.length <= 1) {
        return false;
    }

    return item.paintPercent * circumference < roundCapMinSlot;
}

function getItemStartInset(): number {
    return validItems.value.length > 1 ? segmentMargin : 0;
}

function getItemAllPreviousLength(item: CommonPieChartDataItem): number {
    let allPreviousPercent = 0;

    for (const curItem of validItems.value) {
        if (curItem === item) {
            break;
        }

        allPreviousPercent += curItem.paintPercent > 0 ? curItem.paintPercent : 0;
    }

    return allPreviousPercent * circumference;
}

function getItemStrokeDash(item: CommonPieChartDataItem): string {
    let length = item.paintPercent * circumference;

    if (validItems.value.length > 1) {
        // 两端各收缩 margin，配合圆头端点形成分段间隙
        length = Math.max(length - segmentMargin * 2, 1.5);
    }

    return `${length} ${circumference - length}`;
}

function getItemDashOffset(item: CommonPieChartDataItem, commonOffset: number): number {
    const base = circumference / 4 + commonOffset;
    const allPreviousLength = getItemAllPreviousLength(item);

    if (allPreviousLength <= 0) {
        return base - getItemStartInset();
    }

    return circumference - allPreviousLength + base - getItemStartInset();
}

function getWedgePathD(item: CommonPieChartDataItem): string {
    const slot = item.paintPercent * circumference;
    // 与虚线圆头分段同一坐标系：起点 = 前序弧长 - 基准偏移 - 选中旋转 + 单侧内缩
    const start = getItemAllPreviousLength(item) - circumference / 4 - itemCommonDashOffset.value + wedgeSideInset;
    const sweep = Math.max(slot - wedgeSideInset * 2, 0.8);
    const theta0 = start / ringRadius;
    const theta1 = (start + sweep) / ringRadius;

    const outerRadius = ringRadius + ringWidth / 2;
    const innerRadius = ringRadius - ringWidth / 2;
    const innerArcLength = sweep * innerRadius / ringRadius;
    const cornerRadius = Math.max(Math.min(wedgeCornerRadius, innerArcLength / 2.5, ringWidth / 2 - 1), 0.3);
    const outerDelta = cornerRadius / outerRadius;
    const innerDelta = cornerRadius / innerRadius;

    const point = (theta: number, radius: number): string => `${(radius * Math.cos(theta)).toFixed(4)} ${(radius * Math.sin(theta)).toFixed(4)}`;

    return [
        `M ${point(theta0 + outerDelta, outerRadius)}`,
        `A ${outerRadius} ${outerRadius} 0 0 1 ${point(theta1 - outerDelta, outerRadius)}`,
        `Q ${point(theta1, outerRadius)} ${point(theta1, innerRadius + cornerRadius)}`,
        `Q ${point(theta1, innerRadius)} ${point(theta1 - innerDelta, innerRadius)}`,
        `A ${innerRadius} ${innerRadius} 0 0 0 ${point(theta0 + innerDelta, innerRadius)}`,
        `Q ${point(theta0, innerRadius)} ${point(theta0, innerRadius + cornerRadius)}`,
        `L ${point(theta0, outerRadius - cornerRadius)}`,
        `Q ${point(theta0, outerRadius)} ${point(theta0 + outerDelta, outerRadius)}`,
        'Z'
    ].join(' ');
}

const selectedItem = computed<CommonPieChartDataItem | null>(() => {
    if (!validItems.value || !validItems.value.length) {
        return null;
    }

    let index = selectedIndex.value;

    if (index < 0 || index >= validItems.value.length) {
        index = 0;
    }

    return validItems.value[index] ?? null;
});

function switchSelectedIndex(index: number): void {
    selectedIndex.value = index;
}

function switchSelectedItem(offset: number): void {
    let newSelectedIndex = selectedIndex.value + offset;

    while (newSelectedIndex < 0) {
        newSelectedIndex += validItems.value.length;
    }

    selectedIndex.value = newSelectedIndex % validItems.value.length;
}

function clickItem(item: CommonPieChartDataItem): void {
    if (props.enableClickItem) {
        emit('click', item.sourceItem);
    }
}
</script>

<style scoped>
.pie-chart-container {
    width: 100%;
    height: 100%;
}

.pie-chart {
    margin: 0 24px 0 24px;
}

.pie-chart-toolbox-container {
    margin-top: 16px;
    padding-bottom: 16px;
}

.pie-chart-toolbox {
    display: inline-flex;
    width: 100%;
    justify-content: space-between;
}

.pie-chart-toolbox-info {
    --f7-chip-height: var(--ebk-pie-chart-toolbox-percentage-height);
    --f7-chip-font-size: var(--ebk-pie-chart-toolbox-percentage-font-size);
    font-size: var(--ebk-pie-chart-toolbox-text-font-size);
    align-self: center;
}

.pie-chart-toolbox-info p {
    text-align: center;
    margin: 0 0 4px 0;
}

.pie-chart-toolbox-info a {
    color: var(--f7-text-color);
}

.pie-chart-toolbox-info a > span + span {
    padding-inline-start: 8px;
}

.pie-chart-toolbox-info .item-navigate-icon {
    color: rgba(0, 0, 0, 0.2);
    font-size: 19px;
    font-weight: bold;
    padding-inline-start: 4px;
}

.pie-chart-toolbox-button {
    color: var(--f7-text-color);
}

.pie-chart-selected-item-info {
    display: inline-block;
    text-align: center;
}

.pie-chart-track {
    stroke: #eef1f4;
}

.dark .pie-chart-track {
    stroke: rgba(255, 255, 255, 0.08);
}

.pie-chart-text-group {
    font-size: 0.7em;
    -moz-transform: translateY(-1em);
    -ms-transform: translateY(-1em);
    -webkit-transform: translateY(-1em);
    transform: translateY(-1em);
}
</style>
