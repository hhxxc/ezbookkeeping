import { ref, computed } from 'vue';
import { defineStore } from 'pinia';

import type { RecognizedReceiptImageResponse } from '@/models/large_language_model.ts';

export const useBatchRecognitionStore = defineStore('batchRecognition', () => {
    const imageQueue = ref<Blob[]>([]);
    const recognizedResults = ref<RecognizedReceiptImageResponse[]>([]);
    const currentIndex = ref<number>(0);
    const isProcessing = ref<boolean>(false);

    const totalCount = computed<number>(() => imageQueue.value.length);
    const hasNext = computed<boolean>(() => currentIndex.value < imageQueue.value.length);
    const progress = computed<string>(() => `${currentIndex.value + 1} / ${totalCount.value}`);

    function setImages(images: Blob[]): void {
        imageQueue.value = images;
        recognizedResults.value = [];
        currentIndex.value = 0;
    }

    function addResult(result: RecognizedReceiptImageResponse): void {
        recognizedResults.value.push(result);
        currentIndex.value++;
    }

    function getNextImage(): Blob | null {
        if (currentIndex.value < imageQueue.value.length) {
            return imageQueue.value[currentIndex.value];
        }
        return null;
    }

    function reset(): void {
        imageQueue.value = [];
        recognizedResults.value = [];
        currentIndex.value = 0;
        isProcessing.value = false;
    }

    return {
        imageQueue,
        recognizedResults,
        currentIndex,
        isProcessing,
        totalCount,
        hasNext,
        progress,
        setImages,
        addResult,
        getNextImage,
        reset
    };
});
