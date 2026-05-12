import { APP_NAME_EN } from '@/consts/brand';
import { isEnableDebug } from './settings.ts';

function logDebug(msg: string, obj?: unknown): void {
    if (isEnableDebug()) {
        if (obj) {
            console.debug('[' + APP_NAME_EN + ' Debug] ' + msg, obj);
        } else {
            console.debug('[' + APP_NAME_EN + ' Debug] ' + msg);
        }
    }
}

function logInfo(msg: string, obj?: unknown): void {
    if (obj) {
        console.info('[' + APP_NAME_EN + ' Info] ' + msg, obj);
    } else {
        console.info('[' + APP_NAME_EN + ' Info] ' + msg);
    }
}

function logWarn(msg: string, obj?: unknown): void {
    if (obj) {
        console.warn('[' + APP_NAME_EN + ' Warn] ' + msg, obj);
    } else {
        console.warn('[' + APP_NAME_EN + ' Warn] ' + msg);
    }
}

function logError(msg: string, obj?: unknown): void {
    if (obj) {
        console.error('[' + APP_NAME_EN + ' Error] ' + msg, obj);
    } else {
        console.error('[' + APP_NAME_EN + ' Error] ' + msg);
    }
}

export default {
    debug: logDebug,
    info: logInfo,
    warn: logWarn,
    error: logError
};
