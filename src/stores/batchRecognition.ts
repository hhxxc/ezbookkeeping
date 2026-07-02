import { ref, computed } from 'vue';
import { defineStore } from 'pinia';

import type { RecognizedReceiptImageResponse } from '@/models/large_language_model.ts';

import { generateRandomUUID } from '@/lib/misc.ts';
import { compressJpgImage } from '@/lib/ui/common.ts';
import { KnownFileType } from '@/core/file.ts';
import { useTransactionsStore } from '@/stores/transaction.ts';

interface BatchImageItem {
    file: Blob;
}

interface BatchResultItem {
    imageIndex: number;
    result: RecognizedReceiptImageResponse;
}

export const useBatchRecognitionStore = defineStore('batchRecognition', () => {
    const imageQueue = ref<BatchImageItem[]>([]);
    const results = ref<BatchResultItem[]>([]);
    const currentIndex = ref<number>(0);
    const isProcessing = ref<boolean>(false);
    const totalCount = ref<number>(0);
    const hasNext = computed<boolean>(() => currentIndex.value < imageQueue.value.length);

    function reset(): void {
        imageQueue.value = [];
        results.value = [];
        currentIndex.value = 0;
        isProcessing.value = false;
        totalCount.value = 0;
    }

    function setImages(images: Blob[]): void {
        imageQueue.value = images.map(f => ({ file: f }));
        results.value = [];
        currentIndex.value = 0;
        totalCount.value = images.length;
    }

    async function processNextImage(cancelableUuid?: string): Promise<RecognizedReceiptImageResponse | null> {
        if (currentIndex.value >= imageQueue.value.length) {
            reset();
            return null;
        }

        const idx = currentIndex.value;
        const item = imageQueue.value[idx];

        if (!item) {
            currentIndex.value++;
            return null;
        }

        try {
            const blob = await compressJpgImage(item.file, 1280, 1280, 0.8);

            // Yield to UI thread after compression
            await new Promise(resolve => setTimeout(resolve, 50));

            const imageFile = KnownFileType.JPG.createFileFromBlob(blob, 'image');
            const cancelUuid = cancelableUuid || generateRandomUUID();

            const transactionsStore = useTransactionsStore();
            const result = await transactionsStore.recognizeReceiptImage({
                imageFile: imageFile,
                cancelableUuid: cancelUuid
            });

            results.value.push({ imageIndex: idx, result });
            currentIndex.value++;

            return result;
        } catch (error: any) {
            // On failure, skip this image and continue
            currentIndex.value++;
            throw error;
        }
    }

    function skipCurrentImage(): void {
        if (currentIndex.value < imageQueue.value.length) {
            currentIndex.value++;
        }
    }

    return {
        imageQueue,
        results,
        currentIndex,
        isProcessing,
        totalCount,
        hasNext,
        reset,
        setImages,
        processNextImage,
        skipCurrentImage
    };
});
