<template>
    <f7-sheet swipe-to-close swipe-handler=".swipe-handler" style="height:auto"
              :opened="show" @sheet:open="onSheetOpen" @sheet:closed="onSheetClosed">
        <f7-toolbar class="toolbar-with-swipe-handler">
            <div class="swipe-handler"></div>
            <div class="left">
                <f7-link icon-f7="xmark" :class="{ 'disabled': recording || parsing }"
                         @click="cancel"></f7-link>
            </div>
            <div class="right">
                <f7-button v-if="recognizedResults.length > 0" round fill
                           :class="{ 'disabled': parsing }"
                           @click="confirmSelection">{{ tt('Add Selected') }} ({{ recognizedResults.length }})</f7-button>
            </div>
        </f7-toolbar>
        <f7-page-content class="no-margin-vertical no-padding-vertical">
            <div class="voice-record-area">
                <div class="voice-hint" v-if="recognizedResults.length === 0">
                    <span class="voice-hint-title">{{ recording ? tt('Release to recognize') : tt('Hold to speak') }}</span>
                    <small class="voice-hint-sub">{{ recording ? elapsedSecondsDisplay : tt('Describe the transaction, e.g. "Lunch 25 yuan"') }}</small>
                </div>

                <!-- Recognized transactions list -->
                <div v-if="recognizedResults.length > 0" class="recognized-list">
                    <div class="recognized-list-header">
                        <span>{{ tt('Recognized Transactions') }} ({{ recognizedResults.length }})</span>
                    </div>
                    <div class="recognized-item" v-for="(item, index) in recognizedResults" :key="index">
                        <div class="recognized-item-info">
                            <div class="recognized-item-amount" :class="getAmountClass(item.type)">
                                {{ getAmountDisplay(item) }}
                            </div>
                            <div class="recognized-item-meta">
                                <span v-if="item.comment" class="recognized-item-comment">{{ item.comment }}</span>
                                <span v-if="item.time" class="recognized-item-time">{{ formatTime(item.time) }}</span>
                            </div>
                        </div>
                    </div>
                    <f7-button class="voice-retry-button" small fill color="gray" @click="resetToRecord">
                        {{ tt('Record Again') }}
                    </f7-button>
                </div>

                <!-- Hold-to-talk button -->
                <div class="voice-record-button-wrapper" v-if="recognizedResults.length === 0">
                    <button class="voice-record-button"
                            :class="{ 'recording': recording, 'disabled': parsing }"
                            :disabled="parsing"
                            @touchstart.prevent="onRecordStart"
                            @touchend.prevent="onRecordEnd"
                            @touchcancel.prevent="onRecordEnd"
                            @mousedown="onRecordStart"
                            @mouseup="onRecordEnd"
                            @mouseleave="recording && onRecordEnd()">
                        <f7-icon :f7="recording ? 'waveform' : 'mic_fill'" size="34"></f7-icon>
                    </button>
                </div>

                <div class="privacy-notice">
                    <small>{{ tt('Uploaded audio and personal data will be sent to the speech recognition and large language model services, please be aware of potential privacy risks.') }}</small>
                </div>
            </div>
        </f7-page-content>
    </f7-sheet>
</template>

<script setup lang="ts">
import { ref, computed, onUnmounted } from 'vue';

import { useI18n } from '@/locales/helpers.ts';
import { useI18nUIComponents, showLoading, hideLoading } from '@/lib/ui/mobile.ts';

import { getRecorderSupport, AudioRecorder } from '@/lib/audio_recorder.ts';
import { findPotentialDuplicateTransactions, buildDuplicateConfirmMessage } from '@/lib/ai_recognition.ts';

import services from '@/lib/services.ts';
import logger from '@/lib/logger.ts';

import type { RecognizedReceiptImageResponse, RecognizedReceiptImageResponses } from '@/models/large_language_model.ts';

// Transaction type constants (same as AIImageRecognitionSheet)
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
const { showToast, showConfirm } = useI18nUIComponents();

const recorderSupport = getRecorderSupport();
const recorder = ref<AudioRecorder | null>(null);

const recording = ref<boolean>(false);
const parsing = ref<boolean>(false);
const elapsedMilliseconds = ref<number>(0);
const elapsedTimer = ref<number>(0);
const recognizedResults = ref<RecognizedReceiptImageResponses>([]);

const elapsedSecondsDisplay = computed<string>(() => {
    const totalSeconds = Math.floor(elapsedMilliseconds.value / 1000);
    const seconds = totalSeconds % 60;
    const minutes = Math.floor(totalSeconds / 60);
    return `${minutes}:${String(seconds).padStart(2, '0')} / 0:30`;
});

function onSheetOpen(): void {
    resetToRecord();
}

function onSheetClosed(): void {
    stopRecordingWithoutUpload();
}

function onRecordStart(): void {
    if (recording.value || parsing.value || !recorderSupport.mediaRecorder || !recorderSupport.mimeType) {
        if (!recorderSupport.mediaRecorder) {
            showToast(tt('Voice recording is not supported on this device'));
        }

        return;
    }

    const audioRecorder = new AudioRecorder(recorderSupport.mimeType);

    audioRecorder.start().then(() => {
        recorder.value = audioRecorder;
        recording.value = true;
        elapsedMilliseconds.value = 0;

        if (elapsedTimer.value) {
            clearInterval(elapsedTimer.value);
        }

        elapsedTimer.value = window.setInterval(() => {
            if (recorder.value) {
                elapsedMilliseconds.value = recorder.value.getElapsedMilliseconds();
            }
        }, 200);
    }).catch(error => {
        logger.error('failed to start recording', error);
        showToast(tt('Unable to access microphone'));
    });
}

function onRecordEnd(): void {
    if (!recording.value || !recorder.value) {
        return;
    }

    recording.value = false;

    if (elapsedTimer.value) {
        clearInterval(elapsedTimer.value);
        elapsedTimer.value = 0;
    }

    if (recorder.value.getElapsedMilliseconds() < 500) {
        // Too short, treat as invalid recording
        recorder.value.cancel();
        recorder.value = null;
        return;
    }

    recorder.value.stop().then(blob => {
        uploadAudio(blob);
    }).catch(error => {
        recorder.value = null;
        logger.error('failed to stop recording', error);
        showToast(tt('Unable to record audio'));
    });
}

function uploadAudio(blob: Blob): void {
    if (!recorderSupport.mimeType) {
        return;
    }

    parsing.value = true;
    showLoading();

    const extension = recorderSupport.mimeType === 'audio/mp4' ? 'm4a' : 'webm';
    const audioFile = new File([blob], `voice.${extension}`, { type: recorderSupport.mimeType });

    services.parseTransactionAudio({ audioFile }).then(response => {
        parsing.value = false;
        hideLoading();

        const data = response.data;

        if (!data || !data.success || !data.result) {
            showToast(tt('Unable to recognize audio'));
            return;
        }

        const results = Array.isArray(data.result) ? data.result : [data.result];

        if (!results || results.length === 0) {
            showToast(tt('Unable to recognize audio'));
            return;
        }

        recognizedResults.value = results;
    }).catch(error => {
        parsing.value = false;
        hideLoading();

        if (!error.processed) {
            showToast(error.message || tt('Unable to recognize audio'));
        }

        resetToRecord();
    }).finally(() => {
        recorder.value = null;
    });
}

function confirmSelection(): void {
    const results = recognizedResults.value;

    if (!results || results.length === 0) {
        return;
    }

    // Check duplicates for all results, same as image recognition sheet
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

function resetToRecord(): void {
    recognizedResults.value = [];
    parsing.value = false;
    recording.value = false;
    elapsedMilliseconds.value = 0;
}

function stopRecordingWithoutUpload(): void {
    if (recorder.value) {
        recorder.value.cancel();
        recorder.value = null;
    }

    recording.value = false;
    parsing.value = false;

    if (elapsedTimer.value) {
        clearInterval(elapsedTimer.value);
        elapsedTimer.value = 0;
    }
}

function cancel(): void {
    stopRecordingWithoutUpload();
    emit('update:show', false);
}

function getAmountClass(type?: number): string {
    if (type === TYPE_INCOME) {
        return 'text-income';
    } else if (type === TYPE_TRANSFER) {
        return 'text-transfer';
    }

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

function formatTime(unixTime?: number): string {
    if (!unixTime) return '';
    const date = new Date(unixTime * 1000);
    return date.toLocaleString();
}

onUnmounted(() => {
    stopRecordingWithoutUpload();
});
</script>

<style>
.voice-record-area {
    padding: 16px;
    text-align: center;
}

.voice-hint-title {
    display: block;
    font-size: 17px;
    font-weight: 600;
}

.voice-hint-sub {
    display: block;
    margin-top: 4px;
    color: var(--ebk-secondary-text-color);
}

.voice-record-button-wrapper {
    margin: 24px 0 8px;
    display: flex;
    justify-content: center;
}

.voice-record-button {
    width: 84px;
    height: 84px;
    border-radius: 50%;
    border: none;
    background: rgba(var(--ebk-primary-color-rgb, 38, 166, 154), 0.14);
    color: rgb(var(--ebk-primary-color));
    display: flex;
    align-items: center;
    justify-content: center;
    transition: transform 0.15s ease, background 0.15s ease;
    -webkit-tap-highlight-color: transparent;
}

.voice-record-button.recording {
    background: #d0443f;
    color: #fff;
    transform: scale(1.08);
    animation: voice-record-pulse 1.2s ease-in-out infinite;
}

.voice-record-button.disabled {
    opacity: 0.5;
}

@keyframes voice-record-pulse {
    0%, 100% { box-shadow: 0 0 0 0 rgba(208, 68, 63, 0.35); }
    50% { box-shadow: 0 0 0 14px rgba(208, 68, 63, 0); }
}

.voice-record-area .recognized-list {
    text-align: start;
}

.voice-record-area .recognized-list-header {
    font-size: 15px;
    font-weight: 600;
    margin: 8px 0;
}

.voice-record-area .recognized-item {
    display: flex;
    align-items: center;
    padding: 8px 0;
    border-bottom: 1px solid var(--ebk-divider-color, rgba(0,0,0,0.06));
}

.voice-record-area .recognized-item-info {
    flex: 1;
    min-width: 0;
}

.voice-record-area .recognized-item-amount {
    font-size: 16px;
    font-weight: 600;
}

.voice-record-area .recognized-item-meta {
    display: flex;
    gap: 8px;
    margin-top: 2px;
    font-size: 12px;
    color: var(--ebk-secondary-text-color);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
}

.voice-retry-button {
    margin-top: 8px;
}

.voice-record-area .privacy-notice {
    margin-top: 16px;
    color: var(--ebk-secondary-text-color);
}
</style>
