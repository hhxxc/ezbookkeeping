<template>
    <vue-date-picker ref="datetimepicker"
                     inline auto-apply
                     six-weeks="center"
                     :class="`datetime-picker ${showAlternateDates && alternateCalendarType ? 'datetime-picker-with-alternate-date' : ''} ${datetimePickerClass}`"
                     :config="{ noSwipe: !!noSwipeAndScroll, monthChangeOnScroll: !noSwipeAndScroll }"
                     :time-config="{ enableTimePicker: enableTimePicker, enableSeconds: true, is24: is24Hour }"
                     :input-attrs="{ clearable: !!clearable }"
                     :dark="isDarkMode"
                     :vertical="vertical"
                     :disable-year-select="disableYearSelect"
                     :year-range="yearRange"
                     :day-names="dayNames"
                     :week-start="firstDayOfWeek"
                     :year-first="isYearFirst"
                     :min-date="minDate"
                     :max-date="maxDate"
                     :disabled-dates="disabledDates"
                     :range="isDateRange ? { partialRange: false } : undefined"
                     :preset-dates="presetRanges"
                     @touchstart.capture="onCalendarTouchStart"
                     @touchend.capture="onCalendarTouchEnd"
                     v-model="dateTime">
        <template #year="{ value }">
            {{ getDisplayYear(value) }}
        </template>
        <template #year-overlay-value="{ value }">
            {{ getDisplayYear(value) }}
        </template>
        <template #month="{ value }">
            {{ getDisplayMonth(value) }}
        </template>
        <template #month-overlay-value="{ value }">
            {{ getDisplayMonth(value) }}
        </template>
        <template #day="{ date }">
            <div class="datetime-picker-display-dates">
                <span>{{ getDisplayDay(date) }}</span>
                <span class="datetime-picker-alternate-date" v-if="showAlternateDates && alternateCalendarType && getAlternateDate(date)">{{ getAlternateDate(date) }}</span>
            </div>
        </template>
        <template #am-pm-button="{ toggle, value }">
            <button class="dp__pm_am_button" tabindex="0" @click="toggle">{{ tt(`datetime.${value}.content`) }}</button>
        </template>
    </vue-date-picker>
</template>
<script setup lang="ts">
import { computed, onBeforeUnmount, useTemplateRef } from 'vue';
import { type MenuView, VueDatePicker } from '@vuepic/vue-datepicker';

import { useI18n } from '@/locales/helpers.ts';

import { useUserStore } from '@/stores/user.ts';

import type { CalendarType } from '@/core/calendar.ts';
import { NumeralSystem } from '@/core/numeral.ts';
import type { PresetDateRange, WeekDayValue } from '@/core/datetime.ts';
import { isDefined, isArray, arrangeArrayWithNewStartIndex } from '@/lib/common.ts';
import { getAllowedYearRange, getYearMonthDayDateTime } from '@/lib/datetime.ts';

type VueDatePickerType = InstanceType<typeof VueDatePicker>;
type SupportedModelValue = Date | Date[] | null;

const props = defineProps<{
    modelValue: SupportedModelValue;
    datetimePickerClass?: string;
    isDarkMode: boolean;
    numeralSystem?: number;
    enableTimePicker: boolean;
    disableYearSelect?: boolean;
    vertical?: boolean;
    noSwipeAndScroll?: boolean;
    clearable?: boolean;
    minDate?: Date;
    maxDate?: Date;
    disabledDates?: (date: Date) => boolean;
    showAlternateDates?: boolean;
    presetRanges?: PresetDateRange[];
}>();

const emit = defineEmits<{
    (e: 'update:modelValue', value: SupportedModelValue): void;
}>();

const {
    tt,
    getAllMinWeekdayNames,
    getCurrentCalendarDisplayType,
    getCurrentNumeralSystemType,
    isLongDateMonthAfterYear,
    isLongTime24HourFormat,
    getCalendarDisplayShortYearFromDateTime,
    getCalendarDisplayShortMonthFromDateTime,
    getCalendarDisplayDayOfMonthFromDateTime,
    getCalendarAlternateDate
} = useI18n();

const userStore = useUserStore();

const datetimepicker = useTemplateRef<VueDatePickerType>('datetimepicker');

const yearRange = getAllowedYearRange();

const dayNames = computed<string[]>(() => arrangeArrayWithNewStartIndex(getAllMinWeekdayNames(), firstDayOfWeek.value));
const firstDayOfWeek = computed<WeekDayValue>(() => userStore.currentUserFirstDayOfWeek);
const isYearFirst = computed<boolean>(() => isLongDateMonthAfterYear());
const is24Hour = computed<boolean>(() => isLongTime24HourFormat());
const alternateCalendarType = computed<CalendarType | undefined>(() => getCurrentCalendarDisplayType().secondaryCalendarType);

const actualNumeralSystem = computed<NumeralSystem>(() => {
    if (isDefined(props.numeralSystem)) {
        return NumeralSystem.valueOf(props.numeralSystem) ?? NumeralSystem.Default;
    } else {
        return getCurrentNumeralSystemType();
    }
});

const dateTime = computed<SupportedModelValue>({
    get: () => props.modelValue,
    set: (value: SupportedModelValue) => emit('update:modelValue', value)
});

const isDateRange = computed<boolean>(() => isArray(props.modelValue));

function getAlternateDate(date: Date): string | undefined {
    if (!props.showAlternateDates) {
        return undefined;
    }

    return getCalendarAlternateDate({
        year: date.getFullYear(),
        month: date.getMonth() + 1,
        day: date.getDate()
    })?.displayDate;
};

function switchView(viewType: MenuView): void {
    datetimepicker.value?.switchView(viewType);
}

const calendarTapMaxMoveDistance = 10;

let calendarTouchStartPoint: { x: number, y: number } | undefined = undefined;
let calendarTouchGeneration = 0;
let calendarDuplicateClickGuard: ((event: MouseEvent) => void) | undefined = undefined;
let calendarDuplicateClickGuardTimer: number | undefined = undefined;

/**
 * Whether the given value is a plain date (not a date range)
 */
function isSingleDate(value: SupportedModelValue): value is Date {
    return value instanceof Date;
}

/**
 * Returns the date represented by a calendar day cell
 *
 * Every day cell rendered by @vuepic/vue-datepicker has an id in the form of "dp-<yyyy>-<MM>-<dd>".
 */
function getDateOfCalendarCell(cell: Element): Date | undefined {
    const matched = /^dp-(\d{4})-(\d{2})-(\d{2})$/.exec(cell.getAttribute('id') || '');

    if (!matched) {
        return undefined;
    }

    const current = isSingleDate(props.modelValue) ? props.modelValue : new Date();
    const next = new Date(current.getTime());

    next.setFullYear(parseInt(matched[1]!), parseInt(matched[2]!) - 1, parseInt(matched[3]!));

    return next;
}

function selectDateOfCalendarCell(cell: Element): void {
    const next = getDateOfCalendarCell(cell);

    if (!next) {
        return;
    }

    if (props.disabledDates && props.disabledDates(next)) {
        return;
    }

    if (props.minDate && next.getTime() < props.minDate.getTime()) {
        return;
    }

    if (props.maxDate && next.getTime() > props.maxDate.getTime()) {
        return;
    }

    emit('update:modelValue', next);
}

function onCalendarTouchStart(event: TouchEvent): void {
    const touch = event.changedTouches && event.changedTouches[0];
    calendarTouchStartPoint = touch ? { x: touch.clientX, y: touch.clientY } : undefined;
    calendarTouchGeneration++;
}

function getCalendarCellId(date: Date): string {
    const month = `${date.getMonth() + 1}`.padStart(2, '0');
    const day = `${date.getDate()}`.padStart(2, '0');

    return `dp-${date.getFullYear()}-${month}-${day}`;
}

/**
 * Moves the focus (the blue focus ring) onto the cell of the newly selected date.
 *
 * Selecting a date which is not in the current month re-renders the calendar, and the library reuses the same grid
 * cells for the new dates. The focus has to be moved *after* that re-render, otherwise the cell which gets the
 * focus shows another day a moment later. The focus move is retried a few times because the re-render (and the
 * month transition of the calendar) is asynchronous, and it is aborted as soon as the user touches the calendar
 * again.
 */
function moveFocusToCalendarCell(container: Element | null, date: Date, generation: number, attempt = 0): void {
    if (!container) {
        return;
    }

    const delays = [0, 60, 140, 240];
    const cellId = getCalendarCellId(date);

    window.setTimeout(() => {
        if (generation !== calendarTouchGeneration) {
            return;
        }

        const cell = container.querySelector(`[id="${cellId}"]`) as HTMLElement | null;

        if (cell && document.activeElement !== cell) {
            cell.focus({ preventScroll: true });
        }

        if (attempt < delays.length - 1) {
            moveFocusToCalendarCell(container, date, generation, attempt + 1);
            return;
        }

        if (!cell) {
            const activeElement = document.activeElement as HTMLElement | null;

            if (activeElement && typeof activeElement.blur === 'function' && container.contains(activeElement)) {
                activeElement.blur();
            }
        }
    }, attempt === 0 ? 0 : delays[attempt]! - delays[attempt - 1]!);
}

/**
 * Suppresses the click which the browser dispatches right after our own click was dispatched in onCalendarTouchEnd.
 *
 * That trailing click would hit the same grid *position*, which may already show another date after the calendar
 * re-rendered (e.g. after selecting a date of the previous month), and would therefore select the wrong date.
 */
function armDuplicateClickGuard(): void {
    disarmDuplicateClickGuard();

    const guard = (event: MouseEvent) => {
        disarmDuplicateClickGuard();
        event.stopImmediatePropagation();
        event.stopPropagation();
        event.preventDefault();
    };

    calendarDuplicateClickGuard = guard;
    document.addEventListener('click', guard, true);
    calendarDuplicateClickGuardTimer = window.setTimeout(disarmDuplicateClickGuard, 600);
}

function disarmDuplicateClickGuard(): void {
    if (calendarDuplicateClickGuardTimer !== undefined) {
        window.clearTimeout(calendarDuplicateClickGuardTimer);
        calendarDuplicateClickGuardTimer = undefined;
    }

    if (calendarDuplicateClickGuard) {
        document.removeEventListener('click', calendarDuplicateClickGuard, true);
        calendarDuplicateClickGuard = undefined;
    }
}

/**
 * Fallback for touch devices (mainly iOS inside the native app shell)
 *
 * Framework7 swallows a click when the click target is not exactly the element which received the touchstart
 * (see "handleClick" in framework7/modules/touch/touch.js: it calls stopImmediatePropagation + preventDefault in
 * that case), and the browser may not deliver the click at all. The result is a day that only gets the focus ring
 * but is never selected. Therefore, on touchend, this dispatches another click *on the original touch target*
 * (which satisfies the Framework7 check) and also selects the date directly, so that either path updates the value.
 */
function onCalendarTouchEnd(event: TouchEvent): void {
    const target = event.target as Element | null;
    const touch = event.changedTouches && event.changedTouches[0];

    if (!target || !target.closest) {
        return;
    }

    // a scroll or a swipe (changing the month) must not be treated as a tap
    if (calendarTouchStartPoint && touch
        && (Math.abs(touch.clientX - calendarTouchStartPoint.x) > calendarTapMaxMoveDistance
            || Math.abs(touch.clientY - calendarTouchStartPoint.y) > calendarTapMaxMoveDistance)) {
        return;
    }

    const cell = target.closest('.dp__calendar_item');

    // only day cells are handled here: re-dispatching a click on the month navigation arrows or on the year/month
    // headers would run their handler twice (they are not idempotent). The year/month overlay entries use the same
    // "select one value" semantic as a day cell, so they are safe to re-dispatch.
    const isOverlayEntry = !!target.closest('.dp__overlay_cell');

    if (!cell && !isOverlayEntry) {
        return;
    }

    if (cell) {
        const inner = cell.querySelector('.dp__cell_inner');

        if (inner && inner.classList.contains('dp__cell_disabled')) {
            return;
        }
    }

    disarmDuplicateClickGuard();

    target.dispatchEvent(new MouseEvent('click', {
        bubbles: true,
        cancelable: true,
        view: window,
        detail: 1
    }));

    if (cell) {
        const date = getDateOfCalendarCell(cell);
        const container = cell.closest('.dp__main');
        const generation = calendarTouchGeneration;

        selectDateOfCalendarCell(cell);

        if (date) {
            moveFocusToCalendarCell(container, date, generation);
        }

        armDuplicateClickGuard();
    }
}

function getDisplayYear(year: number): string {
    return getCalendarDisplayShortYearFromDateTime(getYearMonthDayDateTime(year, 1, 1), actualNumeralSystem.value);
}

function getDisplayMonth(month: number): string {
    if (isArray(dateTime.value)) {
        return getCalendarDisplayShortMonthFromDateTime(getYearMonthDayDateTime(dateTime.value[0]!.getFullYear(), month + 1, 1), actualNumeralSystem.value);
    } else if (dateTime.value) {
        return getCalendarDisplayShortMonthFromDateTime(getYearMonthDayDateTime(dateTime.value.getFullYear(), month + 1, 1), actualNumeralSystem.value);
    } else {
        return getCalendarDisplayShortMonthFromDateTime(getYearMonthDayDateTime(new Date().getFullYear(), month + 1, 1), actualNumeralSystem.value);
    }
}

function getDisplayDay(date: Date): string {
    return getCalendarDisplayDayOfMonthFromDateTime(getYearMonthDayDateTime(date.getFullYear(), date.getMonth() + 1, date.getDate()), actualNumeralSystem.value);
}

defineExpose({
    switchView
});

onBeforeUnmount(() => {
    disarmDuplicateClickGuard();
});
</script>

<style>
.datetime-picker-display-dates {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
}

.datetime-picker-alternate-date {
    margin-top: -2px;
    opacity: 0.5;
    font-size: 0.8rem;
}

.dp__cell_disabled .datetime-picker-alternate-date,
.dp__cell_offset .datetime-picker-alternate-date {
    opacity: 0.8;
}

.dp__main.datetime-picker .dp__calendar .dp__calendar_row > .dp__calendar_item .datetime-picker-display-dates > span.datetime-picker-alternate-date {
    display: block;
    width: 100%;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
}

.dp__main.datetime-picker.datetime-picker-with-alternate-date .dp__calendar .dp__calendar_row {
    --dp-cell-size: 45px;
}
</style>
