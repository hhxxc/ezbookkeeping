/**
 * 跨 store 数据失效广播。
 *
 * 交易发生增删改后，统计（statistics）与数据探查（explorer）的缓存都要标记为失效。
 * 如果 transaction store 直接 import 这两个 store，移动端首屏就会被迫下载它们
 * （两者源码各约 100KB，且只在统计页 / 桌面 Insights 页才用到）。
 *
 * 这里用一个极轻的模块级订阅表做单向通知：写入方 emit，消费方在自己初始化时 subscribe。
 * 语义与原先的直接调用完全一致（同步派发），只是解开了编译期依赖。
 */
export type DataInvalidationEvent = 'transaction-data-changed' | 'user-data-reset';

const listeners: Record<DataInvalidationEvent, Set<() => void>> = {
    'transaction-data-changed': new Set<() => void>(),
    'user-data-reset': new Set<() => void>()
};

export function onDataInvalidated(event: DataInvalidationEvent, listener: () => void): void {
    listeners[event].add(listener);
}

export function emitDataInvalidated(event: DataInvalidationEvent): void {
    listeners[event].forEach(listener => listener());
}
