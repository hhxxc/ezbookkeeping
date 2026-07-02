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
                <f7-button round fill icon-f7="checkmark_alt"
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
                <div class="image-placeholder" v-else-if="!loading && !isBatchMode">
                    <div class="placeholder-icon">
                        <f7-icon f7="camera_fill" size="40" color="gray"></f7-icon>
                    </div>
                    <span class="placeholder-title">{{ tt('Tap to select image') }}</span>
                    <small class="placeholder-hint">{{ tt('Select a receipt or transaction screenshot to recognize') }}</small>
                </div>
                <div class="image-placeholder" v-else-if="!loading && isBatchMode">
                    <div class="placeholder-icon">
                        <f7-icon f7="photo_on_rectangle" size="40" color="gray"></f7-icon>
                    </div>
                    <span class="placeholder-title">{{ tt('Select multiple images') }}</span>
                    <small class="placeholder-hint">{{ tt('Select multiple receipts, each will be recognized and added one by one') }}</small>
                </div>
                <div class="image-placeholder" v-else-if="loading">
                    <f7-preloader size="32"></f7-preloader>
                    <span class="placeholder-title margin-top-half">{{ tt('Loading image...') }}</span>
                </div>
                <input ref="imageInput" type="file" class="file-input-overlay" :accept="SUPPORTED_IMAGE_MIME_TYPES" :multiple="isBatchMode" :disabled="loading || recognizing" @change="openImage($event)" />
            </div>
            <div class="privacy-notice">
                <small>{{ tt('Uploaded image and personal data will be sent to the large language model, please be aware of potential privacy risks.') }}</small>
            </div>
        </f7-page-content>

    </f7-sheet>
</template>


<script setup lang="ts">
import { ref, useTemplateRef } from 'vue';

import { useI18n } from '@/locales/helpers.ts';
import { useI18nUIComponents, closeAllDialog } from '@/lib/ui/mobile.ts';

import { useTransactionsStore } from '@/stores/transaction.ts';
import { useBatchRecognitionStore } from '@/stores/batchRecognition.ts';

import { KnownFileType } from '@/core/file.ts';
import { SUPPORTED_IMAGE_MIME_TYPES } from '@/consts/file.ts';

import type { RecognizedReceiptImageResponse } from '@/models/large_language_model.ts';

import { generateRandomUUID } from '@/lib/misc.ts';
import { compressJpgImage } from '@/lib/ui/common.ts';
import { findPotentialDuplicateTransactions, buildDuplicateConfirmMessage } from '@/lib/ai_recognition.ts';
import logger from '@/lib/logger.ts';

const props = defineProps<{
    show: boolean;
    isBatchMode?: boolean;
}>();

const emit = defineEmits<{
    (e: 'update:show', value: boolean): void;
    (e: 'recognition:change', value: RecognizedReceiptImageResponse): void;
    (e: 'batch:next'): void;
}>();

const { tt } = useI18n();
const { showCancelableLoading, showToast, showConfirm } = useI18nUIComponents();

const transactionsStore = useTransactionsStore();
const batchRecognitionStore = useBatchRecognitionStore();

const imageInput = useTemplateRef<HTMLInputElement>('imageInput');

const loading = ref<boolean>(false);
const recognizing = ref<boolean>(false);
const cancelRecognizingUuid = ref<string | undefined>(undefined);
const imageFile = ref<File | null>(null);
const imageSrc = ref<string | undefined>(undefined);
const batchImages = ref<Blob[]>([]);

function loadImage(image: Blob): void {
    loading.value = true;
    imageFile.value = null;
    imageSrc.value = undefined;

    compressJpgImage(image, 1280, 1280, 0.8).then(blob => {
        imageFile.value = KnownFileType.JPG.createFileFromBlob(blob, "image");
        imageSrc.value = URL.createObjectURL(blob);
        loading.value = false;
        // Auto-recognize for batch mode
        if (props.isBatchMode) {
            confirm();
        }
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

    const isBatch = props.isBatchMode === true;

    if (isBatch) {
        // Batch mode: store all images in queue
        const images: Blob[] = [];
        for (let i = 0; i < el.files.length; i++) {
            images.push(el.files[i] as File);
        }
        el.value = '';
        batchRecognitionStore.setImages(images);
        // Auto-recognize the first one
        loadImage(images[0]);
        batchRecognitionStore.isProcessing.value = true;
        // Emit batch:next so parent knows we're in batch mode
        emit('batch:next');
    } else {
        const image = el.files[0] as File;
        el.value = '';
        loadImage(image);
    }
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

        // Advance batch queue index so continuation processes the next image
        if (props.isBatchMode) {
            try {
                batchRecognitionStore.skipCurrentImage();
            } catch (e) {
                logger.error('failed to advance batch index', e);
            }
        }

        findPotentialDuplicateTransactions(response).then(duplicates => {
            if (duplicates.length > 0) {
                const details = buildDuplicateConfirmMessage(duplicates);
                const confirmMessage = tt('A similar transaction already exists, do you still want to add it?') + '\n\n' + details;

                showConfirm(confirmMessage, () => {
                    emit('update:show', false);
                    emit('recognition:change', response);
                });
            } else {
                emit('update:show', false);
                emit('recognition:change', response);
            }
        }).catch(e => {
            logger.error('failed to check duplicate transactions', e);
            emit('update:show', false);
            emit('recognition:change', response);
        });
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
</style>
