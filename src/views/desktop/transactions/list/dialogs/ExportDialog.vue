<template>
    <v-dialog width="900" persistent v-model="showState">
        <v-card class="pa-sm-1 pa-md-2">
            <template #title>
                <div class="d-flex flex-wrap align-center justify-center">
                    <h4 class="text-h4">{{ tt('Export Transactions') }}</h4>
                </div>
            </template>

            <v-card-text>
                <!-- Time Range Selection -->
                <div class="mb-4">
                    <div class="text-subtitle-2 mb-2">{{ tt('Time Range') }}</div>
                    <div class="d-flex flex-wrap gap-2 mb-3">
                        <v-btn size="small" variant="tonal" :color="selectedPreset === preset.value ? 'primary' : 'default'"
                               v-for="preset in timePresets" :key="preset.value"
                               @click="selectPreset(preset)">
                            {{ tt(preset.title) }}
                        </v-btn>
                    </div>
                    <v-row v-if="selectedPreset === -1">
                        <v-col cols="12" md="6">
                            <date-time-select
                                :label="tt('Start Time')"
                                :model-value="customStartTime"
                                @update:model-value="customStartTime = $event" />
                        </v-col>
                        <v-col cols="12" md="6">
                            <date-time-select
                                :label="tt('End Time')"
                                :model-value="customEndTime"
                                @update:model-value="customEndTime = $event" />
                        </v-col>
                    </v-row>
                </div>

                <!-- Type Filter -->
                <div class="mb-4">
                    <div class="text-subtitle-2 mb-2">{{ tt('Transaction Type') }}</div>
                    <v-btn-group density="comfortable" mandatory v-model="filterType">
                        <v-btn :value="0" size="small">{{ tt('All') }}</v-btn>
                        <v-btn :value="2" size="small">{{ tt('Income') }}</v-btn>
                        <v-btn :value="3" size="small">{{ tt('Expense') }}</v-btn>
                        <v-btn :value="4" size="small">{{ tt('Transfer') }}</v-btn>
                    </v-btn-group>
                </div>

                <!-- Summary -->
                <div class="text-body-2 mb-2">
                    {{ tt('Date Range') }}: <b>{{ dateRangeText }}</b>
                    &nbsp;|&nbsp;
                    {{ tt('Total') }}: <b>{{ previewItems.length }}</b> {{ tt('transactions') }}
                    <v-progress-circular indeterminate size="16" class="ms-2" v-if="loading" />
                </div>

                <!-- Preview Table -->
                <v-data-table
                    fixed-header
                    density="compact"
                    :headers="previewHeaders"
                    :items="previewItems"
                    :hover="true"
                    :items-per-page="10"
                    :no-data-text="tt('No data')"
                    :loading="loading"
                    hide-default-footer
                    style="max-height: 300px"
                />
            </v-card-text>

            <v-card-text>
                <div class="w-100 d-flex justify-center flex-wrap mt-sm-1 mt-md-2 gap-4">
                    <v-btn color="primary" :disabled="loading || previewItems.length === 0"
                           @click="doExport">
                        {{ tt('Export to Excel') }}
                        <v-progress-circular indeterminate size="18" class="ms-2" v-if="exporting" />
                    </v-btn>
                    <v-btn color="secondary" variant="tonal" :disabled="exporting" @click="cancel">
                        {{ tt('Cancel') }}
                    </v-btn>
                </div>
            </v-card-text>
        </v-card>
    </v-dialog>

    <snack-bar ref="snackbar" />
</template>

<script setup lang="ts">
import SnackBar from '@/components/desktop/SnackBar.vue';
import DateTimeSelect from '@/components/desktop/DateTimeSelect.vue';

import { ref, computed, watch, useTemplateRef } from 'vue';

import { useI18n } from '@/locales/helpers.ts';

import { useSettingsStore } from '@/stores/setting.ts';
import { useUserStore } from '@/stores/user.ts';
import { useAccountsStore } from '@/stores/account.ts';
import { useTransactionCategoriesStore } from '@/stores/transactionCategory.ts';
import { useTransactionTagsStore } from '@/stores/transactionTag.ts';
import { useTransactionsStore } from '@/stores/transaction.ts';

import { TransactionType } from '@/core/transaction.ts';
import { DateRange } from '@/core/datetime.ts';

import type { TransactionInfoResponse } from '@/models/transaction.ts';
import { Transaction } from '@/models/transaction.ts';

import { getDateRangeByDateType, parseDateTimeFromUnixTime } from '@/lib/datetime.ts';
import { startDownloadFile } from '@/lib/ui/common.ts';
import logger from '@/lib/logger.ts';

import ExcelJS from 'exceljs';

type SnackBarType = InstanceType<typeof SnackBar>;

const { tt, formatDateTimeToShortDateTime, formatAmountToLocalizedNumeralsWithCurrency } = useI18n();

const settingsStore = useSettingsStore();
const userStore = useUserStore();
const accountsStore = useAccountsStore();
const transactionCategoriesStore = useTransactionCategoriesStore();
const transactionTagsStore = useTransactionTagsStore();
const transactionsStore = useTransactionsStore();

const snackbar = useTemplateRef<SnackBarType>('snackbar');

interface TimePreset {
    value: number;
    title: string;
}

const timePresets: TimePreset[] = [
    { value: DateRange.Today.type, title: 'Today' },
    { value: DateRange.Yesterday.type, title: 'Yesterday' },
    { value: DateRange.ThisWeek.type, title: 'This week' },
    { value: DateRange.LastWeek.type, title: 'Last week' },
    { value: DateRange.ThisMonth.type, title: 'This month' },
    { value: DateRange.LastMonth.type, title: 'Last month' },
    { value: DateRange.LastThirtyDays.type, title: 'Recent 30 days' },
    { value: DateRange.ThisYear.type, title: 'This year' },
    { value: DateRange.LastYear.type, title: 'Last year' },
    { value: -2, title: 'Recent 3 months' },
    { value: DateRange.RecentTwelveMonths.type, title: 'Recent 12 months' },
    { value: DateRange.All.type, title: 'All Time' },
    { value: -1, title: 'Custom' },
];

// Computed property for RecentThreeMonths (may not exist in DateRange)
// Use RecentTwelveMonths as fallback and manually compute

const showState = ref<boolean>(false);
const selectedPreset = ref<number>(DateRange.ThisMonth.type);
const customStartTime = ref<number>(0);
const customEndTime = ref<number>(0);
const filterType = ref<number>(0);
const loading = ref<boolean>(false);
const exporting = ref<boolean>(false);
const allTransactions = ref<TransactionInfoResponse[]>([]);

const startTime = computed<number>(() => {
    if (selectedPreset.value === -1) {
        return Math.floor(customStartTime.value / 1000);
    }

    // Handle recent 3 months (magic value -2) specially
    if (selectedPreset.value === -2) {
        const now = new Date();
        const start = new Date(now.getFullYear(), now.getMonth() - 2, 1, 0, 0, 0);
        return Math.floor(start.getTime() / 1000);
    }

    const range = getDateRangeByDateType(selectedPreset.value, userStore.currentUserFirstDayOfWeek, userStore.currentUserFiscalYearStart);
    if (range) {
        return range.minTime;
    }
    return 0;
});

const endTime = computed<number>(() => {
    if (selectedPreset.value === -1) {
        return Math.floor(customEndTime.value / 1000);
    }

    // Handle recent 3 months (magic value -2) specially
    if (selectedPreset.value === -2) {
        const now = new Date();
        return Math.floor(new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59).getTime() / 1000);
    }

    const range = getDateRangeByDateType(selectedPreset.value, userStore.currentUserFirstDayOfWeek, userStore.currentUserFiscalYearStart);
    if (range) {
        return range.maxTime;
    }
    return Math.floor(Date.now() / 1000);
});

const dateRangeText = computed<string>(() => {
    if (startTime.value > 0 && endTime.value > 0) {
        return `${formatUnixTimeToDate(startTime.value)} ~ ${formatUnixTimeToDate(endTime.value)}`;
    }
    return tt('All Time');
});

const previewHeaders = computed<object[]>(() => [
    { key: 'time', title: tt('Time'), width: 160 },
    { key: 'type', title: tt('Type'), width: 80 },
    { key: 'category', title: tt('Category'), width: 120 },
    { key: 'account', title: tt('Account'), width: 120 },
    { key: 'amount', title: tt('Amount'), width: 120, align: 'end' },
    { key: 'comment', title: tt('Description'), width: 200 },
]);

const previewItems = computed<Record<string, unknown>[]>(() => {
    if (!allTransactions.value.length) return [];

    return allTransactions.value.map(tx => {
        const transaction = tx as unknown as Transaction;
        return {
            time: formatUnixTimeToDate(transaction.time),
            type: tt(getTypeName(transaction.type)),
            category: getCategoryName(transaction),
            account: getAccountName(transaction),
            amount: formatAmount(transaction),
            comment: transaction.comment || '',
        };
    });
});

function getTypeName(type: TransactionType): string {
    switch (type) {
        case TransactionType.Income: return 'Income';
        case TransactionType.Expense: return 'Expense';
        case TransactionType.Transfer: return 'Transfer';
        case TransactionType.ModifyBalance: return 'Modify Balance';
        default: return 'Unknown';
    }
}

function getCategoryName(tx: Transaction): string {
    if (tx.category) return tx.category.name;
    const catId = tx.expenseCategoryId || tx.incomeCategoryId || tx.transferCategoryId;
    if (!catId) return '';
    const cats = transactionCategoriesStore.allCategories;
    for (const key of Object.keys(cats)) {
        const list = cats[key as unknown as number];
        if (list) {
            for (const cat of list) {
                if (cat.id === catId) return cat.name;
                if (cat.subCategories) {
                    for (const sub of cat.subCategories) {
                        if (sub.id === catId) return `${cat.name} / ${sub.name}`;
                    }
                }
            }
        }
    }
    return '';
}

function getAccountName(tx: Transaction): string {
    if (tx.sourceAccount) return tx.sourceAccount.name;
    const accounts = accountsStore.allAccounts;
    if (accounts) {
        const acct = accounts.find(a => a.id === tx.sourceAccountId);
        if (acct) return acct.name;
    }
    return '';
}

function formatAmount(tx: Transaction): string {
    return formatAmountToLocalizedNumeralsWithCurrency(tx.sourceAmount, tx.sourceAccount?.currency);
}

function formatUnixTimeToDate(unixTime: number): string {
    const dt = parseDateTimeFromUnixTime(unixTime);
    return formatDateTimeToShortDateTime(dt);
}

function selectPreset(preset: TimePreset): void {
    selectedPreset.value = preset.value;
    loadData();
}

function open(): void {
    showState.value = true;
    allTransactions.value = [];
    selectedPreset.value = DateRange.ThisMonth.type;
    filterType.value = 0;
    customStartTime.value = 0;
    customEndTime.value = 0;

    // Preload data
    loadData();
}

function loadData(): void {
    loading.value = true;

    const req = {
        startTime: startTime.value,
        endTime: endTime.value,
        withPictures: false,
    };

    transactionsStore.getAllTransactionsForExport(req).then(data => {
        let filtered = data as unknown as TransactionInfoResponse[];

        // Apply type filter
        if (filterType.value > 0) {
            filtered = filtered.filter((tx: TransactionInfoResponse) => tx.type === filterType.value);
        }

        allTransactions.value = filtered;
        loading.value = false;
    }).catch(error => {
        loading.value = false;
        logger.error('Failed to load transactions for export', error);
        snackbar.value?.showError(error);
    });
}

function doExport(): void {
    if (exporting.value || allTransactions.value.length === 0) return;

    exporting.value = true;

    try {
        const workbook = new ExcelJS.Workbook();
        workbook.creator = userStore.currentUserNickname || 'NestKeep';
        workbook.created = new Date();

        const sheet = workbook.addWorksheet(tt('Transactions'));

        // Define columns
        const columns = [
            { header: tt('Time'), key: 'time', width: 20 },
            { header: tt('Type'), key: 'type', width: 12 },
            { header: tt('Category'), key: 'category', width: 20 },
            { header: tt('Account'), key: 'account', width: 20 },
            { header: tt('Currency'), key: 'currency', width: 10 },
            { header: tt('Amount'), key: 'amount', width: 15 },
            { header: tt('Related Account'), key: 'relatedAccount', width: 20 },
            { header: tt('Related Currency'), key: 'relatedCurrency', width: 12 },
            { header: tt('Related Amount'), key: 'relatedAmount', width: 15 },
            { header: tt('Tags'), key: 'tags', width: 20 },
            { header: tt('Description'), key: 'comment', width: 30 },
            { header: tt('Geo Location'), key: 'geoLocation', width: 25 },
        ];

        sheet.columns = columns;

        // Style header row
        const headerRow = sheet.getRow(1);
        headerRow.height = 24;
        headerRow.eachCell((cell) => {
            cell.fill = {
                type: 'pattern',
                pattern: 'solid',
                fgColor: { argb: 'FFC67E48' },
            };
            cell.font = {
                color: { argb: 'FFFFFFFF' },
                bold: true,
                size: 11,
            };
            cell.alignment = {
                vertical: 'middle',
                horizontal: 'center',
            };
            cell.border = {
                top: { style: 'thin' },
                left: { style: 'thin' },
                bottom: { style: 'thin' },
                right: { style: 'thin' },
            };
        });

        // Add data rows
        const transactions = allTransactions.value as unknown as Transaction[];
        for (const tx of transactions) {
            const tags = (tx.tags || []).map(t => t.name).join(', ');
            const geo = tx.geoLocation
                ? `${tx.geoLocation.latitude.toFixed(6)}, ${tx.geoLocation.longitude.toFixed(6)}`
                : '';

            sheet.addRow({
                time: formatUnixTimeToDate(tx.time),
                type: tt(getTypeName(tx.type)),
                category: getCategoryName(tx),
                account: getAccountName(tx),
                currency: tx.sourceAccount?.currency || '',
                amount: (tx.sourceAmount || 0) / 100,
                relatedAccount: tx.destinationAccount?.name || '',
                relatedCurrency: tx.destinationAccount?.currency || '',
                relatedAmount: (tx.destinationAmount || 0) / 100,
                tags: tags,
                comment: tx.comment || '',
                geoLocation: geo,
            });
        }

        // Style data rows
        const dataStartRow = 2;
        const dataEndRow = dataStartRow + transactions.length - 1;

        for (let i = dataStartRow; i <= dataEndRow; i++) {
            const row = sheet.getRow(i);
            row.height = 20;

            row.eachCell((cell, colNumber) => {
                // Alternating row colors
                const isEven = (i - dataStartRow) % 2 === 0;
                cell.fill = {
                    type: 'pattern',
                    pattern: 'solid',
                    fgColor: { argb: isEven ? 'FFFAF8F4' : 'FFFFFFFF' },
                };
                cell.font = { size: 10 };
                cell.border = {
                    top: { style: 'thin', color: { argb: 'FFE0E0E0' } },
                    left: { style: 'thin', color: { argb: 'FFE0E0E0' } },
                    bottom: { style: 'thin', color: { argb: 'FFE0E0E0' } },
                    right: { style: 'thin', color: { argb: 'FFE0E0E0' } },
                };

                // Number format for amount columns
                if (colNumber === 6 || colNumber === 9) {
                    cell.numFmt = '#,##0.00';
                    cell.alignment = { horizontal: 'right' };
                } else if (colNumber === 1) {
                    // Time column
                    cell.alignment = { horizontal: 'center' };
                } else if (colNumber === 2) {
                    cell.alignment = { horizontal: 'center' };
                }
            });
        }

        // Freeze header row
        sheet.views = [
            { state: 'frozen', ySplit: 1 }
        ];

        // Auto-filter
        sheet.autoFilter = {
            from: 'A1',
            to: { row: dataEndRow, column: columns.length },
        };

        // Generate and download
        workbook.xlsx.writeBuffer().then(buffer => {
            const blob = new Blob([buffer], {
                type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
            });

            const nickname = userStore.currentUserNickname;
            const filename = nickname
                ? `${nickname}_transactions.xlsx`
                : 'nestkeep_transactions.xlsx';

            startDownloadFile(filename, blob);
            exporting.value = false;
            snackbar.value?.showMessage(tt('Export completed'));
        }).catch(error => {
            exporting.value = false;
            logger.error('Failed to generate Excel file', error);
            snackbar.value?.showError(error);
        });
    } catch (error) {
        exporting.value = false;
        logger.error('Failed to create Excel workbook', error);
        snackbar.value?.showError(error);
    }
}

function cancel(): void {
    showState.value = false;
}

watch(filterType, () => {
    loadData();
});

defineExpose({
    open
});
</script>
