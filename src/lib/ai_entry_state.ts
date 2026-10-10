import { reactive, computed } from 'vue';

import {
    wasServerSettingsLoadFailed,
    isServerSettingsLoaded,
    getServerSettingsLoadRetryCount,
    isTransactionFromAIImageRecognitionEnabled,
    isTransactionFromVoiceInputEnabled,
    retryLoadServerSettings
} from '@/lib/server_settings.ts';

export type AIEntryState = 'ok' | 'disabled' | 'load-failed';

// AI 入口状态：ok = 服务端开关开启，正常显示入口；
// load-failed = server_settings.js 重试全失败，显示占位卡片；
// disabled = 服务端未开启 AI 记账，不显示（现状）
export const aiEntryStateStore = reactive({
    state: 'disabled' as AIEntryState
});

// AI 入口状态（响应式 computed）：模板中直接引用，重试成功后自动翻转
export const aiEntryState = computed<AIEntryState>(() => aiEntryStateStore.state);

// 诊断弹层展示的最近一次门控状态快照
export const aiEntryDiagnosticSnapshot = reactive({
    settingsLoaded: false,
    loadFailed: false,
    loadRetryCount: 0,
    textRecognitionEnabled: false,
    voiceInputEnabled: false,
    pageUrl: ''
});

function computeAIEntryState(): AIEntryState {
    if (!isServerSettingsLoaded() && wasServerSettingsLoadFailed()) {
        return 'load-failed';
    }

    if (isTransactionFromAIImageRecognitionEnabled()) {
        return 'ok';
    }

    return 'disabled';
}

// 刷新 AI 入口状态（页面挂载时调用；重试成功后也会触发响应式刷新）
export function refreshAIEntryState(): void {
    aiEntryStateStore.state = computeAIEntryState();
}

// 占位卡片上的 [重试]：重新注入 script 拉取 server_settings.js，成功后状态响应式翻转
export async function retryAIEntry(): Promise<boolean> {
    const success = await retryLoadServerSettings();
    refreshAIEntryState();

    return success;
}

// 打开诊断弹层前刷新快照
export function updateAIEntryDiagnosticSnapshot(): void {
    aiEntryDiagnosticSnapshot.settingsLoaded = isServerSettingsLoaded();
    aiEntryDiagnosticSnapshot.loadFailed = wasServerSettingsLoadFailed();
    aiEntryDiagnosticSnapshot.loadRetryCount = getServerSettingsLoadRetryCount();
    aiEntryDiagnosticSnapshot.textRecognitionEnabled = isTransactionFromAIImageRecognitionEnabled();
    aiEntryDiagnosticSnapshot.voiceInputEnabled = isTransactionFromVoiceInputEnabled();
    aiEntryDiagnosticSnapshot.pageUrl = window.location.href;
}
