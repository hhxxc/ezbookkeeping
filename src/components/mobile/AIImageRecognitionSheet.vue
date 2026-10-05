<template>
    <f7-sheet swipe-to-close swipe-handler=".swipe-handler" style="height:auto"
              :opened="show" @sheet:open="onSheetOpen" @sheet:closed="onSheetClosed">
        <f7-toolbar class="toolbar-with-swipe-handler">
            <div class="swipe-handler"></div>
            <div class="left">
                <f7-link icon-f7="xmark" :class="{ 'disabled': loading || recognizing }"
                         @click="cancel"></f7-link>
            </div>
            <div class="right">
                <f7-button v-if="recognizedResults.length > 0" round fill
                           :class="{ 'disabled': loading || recognizing || selectedResults.length === 0 }"
                           @click="confirmSelection">{{ tt('Add Selected') }} ({{ selectedResults.length }})</f7-button>
                <f7-button v-else round fill icon-f7="checkmark_alt"
                           :class="{ 'disabled': loading || recognizing || !imageFile }"
                           @click="confirm"></f7-button>
            </div>
        </f7-toolbar>
        <f7-page-content class="no-margin-vertical no-padding-vertical">
            <div class="image-picker-area">
                <div class="image-preview" v-if="imageSrc">
                    <img :src="imageSrc" />
                    <div class="image-preview-overlay">
                        <f7-icon f7="camera_fill" size="24"></f7-icon>
                        <span>{{ tt('Tap to change image') }}</span>
                    </div>
                </div>
                <div class="image-placeholder" v-else-if="!loading">
                    <div class="placeholder-icon">
                        <f7-icon f7="camera_fill" size="40" color="gray"></f7-icon>
                    </div>
                    <span class="placeholder-title">{{ tt('Tap to select image') }}</span>
                    <small class="placeholder-hint">{{ tt('Select a receipt or transaction screenshot to recognize') }}</small>
                </div>
                <div class="image-placeholder" v-else-if="loading">
                    <f7-preloader size="32"></f7-preloader>
                    <span class="placeholder-title margin-top-half">{{ tt('Loading image...') }}</span>
                </div>
                <input ref="imageInput" type="file" class="file-input-overlay" :accept="SUPPORTED_IMAGE_MIME_TYPES" :disabled="loading || recognizing" @change="openImage($event)" />
            </div>

            <!-- Recognized transactions list -->
            <div v-if="recognizedResults.length > 0" class="recognized-list">
                <div class="recognized-list-header">
                    <span>{{ tt('Recognized Transactions') }} ({{ recognizedResults.length }})</span>
                    <f7-link v-if="recognizedResults.length > 1" @click="toggleSelectAll">
                        {{ allSelected ? tt('Deselect All') : tt('Select All') }}
                    </f7-link>
                </div>
                <div class="recognized-item" v-for="(item, index) in recognizedResults" :key="index"
                     @click="toggleSelect(index)">
                    <div class="recognized-item-icon" :class="getTypeClass(item.type)">
                        <f7-icon :f7="getTypeIcon(item.type)" size="20"></f7-icon>
                    </div>
                    <div class="recognized-item-info">
                        <div class="recognized-item-amount" :class="getAmountClass(item.type)">
                            {{ getAmountDisplay(item) }}
                        </div>
                        <div class="recognized-item-meta">
                            <span v-if="item.comment" class="recognized-item-comment">{{ item.comment }}</span>
                            <span v-if="item.time" class="recognized-item-time">{{ formatTime(item.time) }}</span>
                        </div>
                    </div>
                    <div class="recognized-item-check">
                        <f7-icon f7="checkmark_circle_fill" size="24"
                                 :color="selectionFlags[index] ? 'var(--f7-theme-color)' : 'rgba(0,0,0,0.15)'"></f7-icon>
                    </div>
                </div>
            </div>

            <div class="privacy-notice">
                <small>{{ tt('Uploaded image and personal data will be sent to the large language model, please be aware of potential privacy risks.') }}</small>
            </div>
        </f7-page-content>

    </f7-sheet>
</template>


<script setup lang="ts">
import { ref, computed, useTemplateRef } from 'vue';

import { useI18n } from '@/locales/helpers.ts';
import { useI18nUIComponents, closeAllDialog } from '@/lib/ui/mobile.ts';

import { useTransactionsStore } from '@/stores/transaction.ts';

import { KnownFileType } from '@/core/file.ts';
import { SUPPORTED_IMAGE_MIME_TYPES } from '@/consts/file.ts';

import type { RecognizedReceiptImageResponse, RecognizedReceiptImageResponses } from '@/models/large_language_model.ts';

import { generateRandomUUID } from '@/lib/misc.ts';
import { compressJpgImage } from '@/lib/ui/common.ts';
import { findPotentialDuplicateTransactions, buildDuplicateConfirmMessage } from '@/lib/ai_recognition.ts';
import logger from '@/lib/logger.ts';

// Transaction type constants
const TYPE_INCOME = 2;
const TYPE_TRANSFER = 4;

defineProps<{
    show: boolean;
}>();

const emit = defineEmits<{
    (e: 'update:show', value: boolean): void;
    (e: 'recognition:change', value: RecognizedReceiptImageResponses): void;
}>();

const { tt } = useI18n();
const { showCancelableLoading, showToast, showConfirm } = useI18nUIComponents();

const transactionsStore = useTransactionsStore();

const imageInput = useTemplateRef<HTMLInputElement>('imageInput');

const loading = ref<boolean>(false);
const recognizing = ref<boolean>(false);
const cancelRecognizingUuid = ref<string | undefined>(undefined);
const imageFile = ref<File | null>(null);
const imageSrc = ref<string | undefined>(undefined);

// Multi-result state
const recognizedResults = ref<RecognizedReceiptImageResponses>([]);
const selectedFlags = ref<boolean[]>([]);

const selectionFlags = computed(() => selectedFlags.value);

const allSelected = computed(() => {
    return recognizedResults.value.length > 0 && selectedFlags.value.every(v => v);
});

const selectedResults = computed(() => {
    return recognizedResults.value.filter((_, i) => selectedFlags.value[i]);
});

function loadImage(image: Blob): void {
    loading.value = true;
    imageFile.value = null;
    imageSrc.value = undefined;
    recognizedResults.value = [];
    selectedFlags.value = [];

    compressJpgImage(image, 1280, 1280, 0.8).then(blob => {
        imageFile.value = KnownFileType.JPG.createFileFromBlob(blob, "image");
        imageSrc.value = URL.createObjectURL(blob);
        loading.value = false;
        // Auto-recognize after compression completes
        confirm();
    }).catch(error => {
        imageFile.value = null;
        imageSrc.value = undefined;
        loading.value = false;
        logger.error('failed to compress image', error);
        showToast('Unable to load image');
    });
}

function openImage(event: Event): void {
    if (!event || !event.target) {
        return;
    }

    const el = event.target as HTMLInputElement;

    if (!el.files || !el.files.length || !el.files[0]) {
        return;
    }

    const image = el.files[0] as File;

    el.value = '';

    loadImage(image);
}

function confirm(): void {
    if (recognizing.value || !imageFile.value) {
        return;
    }

    cancelRecognizingUuid.value = generateRandomUUID();
    recognizing.value = true;
    showCancelableLoading('Recognizing', 'AI can make mistakes. Check important info.', 'Cancel Recognition', cancelRecognize);

    transactionsStore.recognizeReceiptImage({
        imageFile: imageFile.value,
        cancelableUuid: cancelRecognizingUuid.value
    }).then(response => {
        recognizing.value = false;
        cancelRecognizingUuid.value = undefined;
        closeAllDialog();

        // response is now an array
        const results = Array.isArray(response) ? response : [response];
        recognizedResults.value = results;
        // Select all by default
        selectedFlags.value = results.map(() => true);
    }).catch(error => {
        if (error.canceled) {
            return;
        }

        recognizing.value = false;
        cancelRecognizingUuid.value = undefined;
        closeAllDialog();

        if (!error.processed) {
            showToast(error.message || error);
        }
    });
}

function confirmSelection(): void {
    const results = selectedResults.value;

    if (results.length === 0) {
        return;
    }

    // Check duplicates for all selected results
    const duplicateChecks = results.map(r => findPotentialDuplicateTransactions(r));

    Promise.all(duplicateChecks).then(allDuplicates => {
        const hasDuplicates = allDuplicates.some(d => d.length > 0);

        if (hasDuplicates) {
            let details = '';
            for (const duplicates of allDuplicates) {
                if (duplicates.length > 0) {
                    details += buildDuplicateConfirmMessage(duplicates) + '\n';
                }
            }
            const confirmMessage = tt('A similar transaction already exists, do you still want to add it?') + '\n\n' + details;

            showConfirm(confirmMessage, () => {
                emit('update:show', false);
                emit('recognition:change', results);
            });
        } else {
            emit('update:show', false);
            emit('recognition:change', results);
        }
    });
}

function toggleSelect(index: number): void {
    const newFlags = [...selectedFlags.value];
    newFlags[index] = !newFlags[index];
    selectedFlags.value = newFlags;
}

function toggleSelectAll(): void {
    if (allSelected.value) {
        selectedFlags.value = selectedFlags.value.map(() => false);
    } else {
        selectedFlags.value = selectedFlags.value.map(() => true);
    }
}

function getTypeIcon(type: number): string {
    if (type === TYPE_INCOME) return 'arrow_down_circle_fill';
    if (type === TYPE_TRANSFER) return 'arrow_left_arrow_right_circle_fill';
    return 'arrow_up_circle_fill'; // expense
}

function getTypeClass(type: number): string {
    if (type === TYPE_INCOME) return 'type-income';
    if (type === TYPE_TRANSFER) return 'type-transfer';
    return 'type-expense';
}

function getAmountClass(type: number): string {
    if (type === TYPE_INCOME) return 'text-income';
    if (type === TYPE_TRANSFER) return 'text-transfer';
    return 'text-expense';
}

function getAmountDisplay(item: RecognizedReceiptImageResponse): string {
    const amount = item.sourceAmount ?? item.destinationAmount;
    if (!amount) return '-';
    const displayAmount = (amount / 100).toFixed(2);
    if (item.type === TYPE_INCOME) return '+' + displayAmount;
    if (item.type === TYPE_TRANSFER) return displayAmount;
    return '-' + displayAmount;
}

function formatTime(unixTime: number): string {
    if (!unixTime) return '';
    const date = new Date(unixTime * 1000);
    return date.toLocaleString();
}

function cancelRecognize(): void {
    if (!cancelRecognizingUuid.value) {
        return;
    }

    transactionsStore.cancelRecognizeReceiptImage(cancelRecognizingUuid.value);
    recognizing.value = false;
    cancelRecognizingUuid.value = undefined;
    closeAllDialog();

    showToast('User Canceled');
}

function cancel(): void {
    close();
}

function close(): void {
    emit('update:show', false);
    loading.value = false;
    recognizing.value = false;
    cancelRecognizingUuid.value = undefined;
    imageFile.value = null;
    imageSrc.value = undefined;
    recognizedResults.value = [];
    selectedFlags.value = [];
}

function onSheetOpen(): void {
    if (imageInput.value) {
        imageInput.value.value = '';
    }

    loading.value = false;
    recognizing.value = false;
    cancelRecognizingUuid.value = undefined;
    imageFile.value = null;
    imageSrc.value = undefined;
    recognizedResults.value = [];
    selectedFlags.value = [];
}

function onSheetClosed(): void {
    close();
}

defineExpose({
    loadImage
});
</script>

<style>
.image-picker-area {
    --ebk-ai-image-recognition-height: 280px;
    height: var(--ebk-ai-image-recognition-height);
    margin: 16px;
    border: 2px dashed var(--f7-page-master-border-color);
    border-radius: 12px;
    display: flex;
    justify-content: center;
    align-items: center;
    overflow: hidden;
    cursor: pointer;
    position: relative;

    @media (min-height: 630px) {
        --ebk-ai-image-recognition-height: 460px;
    }
}

.image-placeholder {
    display: flex;
    flex-direction: column;
    align-items: center;
    text-align: center;
    padding: 16px;
    gap: 8px;

    .placeholder-icon {
        width: 64px;
        height: 64px;
        border-radius: 50%;
        background-color: var(--f7-list-group-title-bg-color);
        display: flex;
        justify-content: center;
        align-items: center;
        margin-bottom: 4px;
    }

    .placeholder-title {
        font-size: var(--f7-list-item-title-font-size);
        font-weight: 500;
    }

    .placeholder-hint {
        opacity: 0.5;
        max-width: 240px;
    }
}

.image-preview {
    width: 100%;
    height: 100%;
    position: relative;

    > img {
        width: 100%;
        height: 100%;
        object-fit: contain;
    }
}

.image-preview-overlay {
    position: absolute;
    bottom: 0;
    left: 0;
    right: 0;
    background: rgba(0, 0, 0, 0.5);
    color: #fff;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    padding: 8px;
    font-size: var(--f7-list-item-footer-font-size);
    border-radius: 0 0 10px 10px;
}

.file-input-overlay {
    position: absolute;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    opacity: 0;
    cursor: pointer;
}

.privacy-notice {
    text-align: center;
    padding: 0 16px 16px;
    opacity: 0.5;
}

/* Recognized transactions list */
.recognized-list {
    margin: 0 16px 8px;
    border: 1px solid var(--f7-page-master-border-color);
    border-radius: 12px;
    overflow: hidden;
}

.recognized-list-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 10px 14px;
    background: var(--f7-list-group-title-bg-color);
    font-size: 14px;
    font-weight: 600;
    color: var(--f7-text-color);
}

.recognized-item {
    display: flex;
    align-items: center;
    padding: 10px 14px;
    border-top: 1px solid var(--f7-page-master-border-color);
    cursor: pointer;
    transition: background-color 0.15s;

    &:active {
        background-color: var(--f7-list-link-hover-bg-color);
    }
}

.recognized-item-icon {
    width: 36px;
    height: 36px;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
    margin-right: 12px;

    &.type-expense {
        background: rgba(239, 68, 68, 0.1);
        color: #ef4444;
    }

    &.type-income {
        background: rgba(34, 197, 94, 0.1);
        color: #22c55e;
    }

    &.type-transfer {
        background: rgba(59, 130, 246, 0.1);
        color: #3b82f6;
    }
}

.recognized-item-info {
    flex: 1;
    min-width: 0;
}

.recognized-item-amount {
    font-size: 16px;
    font-weight: 600;
    line-height: 1.3;

    &.text-expense {
        color: #ef4444;
    }

    &.text-income {
        color: #22c55e;
    }

    &.text-transfer {
        color: #3b82f6;
    }
}

.recognized-item-meta {
    display: flex;
    gap: 8px;
    align-items: center;
    margin-top: 2px;
    font-size: 13px;
    color: var(--f7-text-color-secondary);
    overflow: hidden;
}

.recognized-item-comment {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    max-width: 180px;
}

.recognized-item-time {
    flex-shrink: 0;
}

.recognized-item-check {
    flex-shrink: 0;
    margin-left: 8px;
}
</style>
