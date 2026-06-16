<template>
    <f7-sheet swipe-to-close swipe-handler=".swipe-handler"
              style="height: 70vh;"
              :opened="show" @sheet:open="onSheetOpen" @sheet:closed="$emit('update:show', false)">
        <div class="swipe-handler"></div>
        <div class="sheet-scroll-area">
            <div class="display-flex padding justify-content-space-between align-items-center">
                <div class="ebk-sheet-title"><b>{{ tt('Background Image') }}</b></div>
                <f7-link @click="$emit('update:show', false)">{{ tt('Done') }}</f7-link>
            </div>
            <div class="padding-horizontal padding-bottom">
                <div class="gallery-grid">
                    <div
                        v-for="bg in backgrounds"
                        :key="bg.id"
                        class="gallery-item"
                        :class="{ 'gallery-item-selected': currentValue === bg.id }"
                        :style="{ background: bg.css }"
                        @click="select(bg.id)"
                    >
                        <span class="gallery-item-name">{{ bg.name }}</span>
                        <f7-icon v-if="currentValue === bg.id" class="gallery-check" f7="checkmark_alt_circle_fill"></f7-icon>
                    </div>
                    <div
                        class="gallery-item gallery-item-none"
                        :class="{ 'gallery-item-selected': !currentValue }"
                        @click="select('')"
                    >
                        <f7-icon f7="xmark_circle" style="font-size: 24px; opacity: 0.5;"></f7-icon>
                        <span class="gallery-item-name">{{ tt('None') }}</span>
                        <f7-icon v-if="!currentValue" class="gallery-check" f7="checkmark_alt_circle_fill"></f7-icon>
                    </div>
                </div>
            </div>
        </div>
    </f7-sheet>
</template>

<script setup lang="ts">
import { ref } from 'vue';

import { useI18n } from '@/locales/helpers.ts';
import { GALLERY_BACKGROUNDS } from '@/consts/gallery.ts';

const props = defineProps<{
    show: boolean;
    modelValue: string;
}>();

const emit = defineEmits<{
    'update:show': [value: boolean];
    'update:modelValue': [value: string];
}>();

const { tt } = useI18n();

const backgrounds = GALLERY_BACKGROUNDS;

const currentValue = ref<string>(props.modelValue);

function onSheetOpen(): void {
    currentValue.value = props.modelValue;
}

function select(id: string): void {
    currentValue.value = id;
    emit('update:modelValue', id);
    emit('update:show', false);
}
</script>

<style scoped>
.sheet-scroll-area {
    height: calc(70vh - 50px);
    overflow-y: auto;
    overflow-x: hidden;
    -webkit-overflow-scrolling: touch;
}

.gallery-grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 10px;
}

.gallery-item {
    position: relative;
    aspect-ratio: 2 / 1;
    border-radius: 12px;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: transform 0.15s ease;
    box-shadow: 0 1px 4px rgba(0, 0, 0, 0.08);
    overflow: hidden;
}

.gallery-item:active {
    transform: scale(0.95);
}

.gallery-item-selected {
    box-shadow: 0 0 0 3px var(--f7-theme-color);
    transform: scale(1.02);
}

.gallery-item-name {
    font-size: 12px;
    color: #fff;
    font-weight: 600;
    pointer-events: none;
}

.gallery-item-none {
    background: var(--f7-list-bg-color);
    border: 2px dashed #ccc;
}

.dark .gallery-item-none {
    border-color: #555;
}

.gallery-item-none .gallery-item-name {
    color: var(--f7-text-color);
    text-shadow: none;
}

.gallery-check {
    position: absolute;
    top: 4px;
    right: 4px;
    color: var(--f7-theme-color);
    font-size: 20px;
    background: #fff;
    border-radius: 50%;
}

.dark .gallery-check {
    background: #333;
}
</style>
