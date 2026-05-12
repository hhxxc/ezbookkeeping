import { APP_NAME_EN } from '@/consts/brand';

const SW_CACHE_PREFIX = APP_NAME_EN.toLowerCase() + '-';

export const SW_PRECACHE_CACHE_NAME_PREFIX: string = 'workbox-precache-v2-';
export const SW_RUNTIME_CACHE_NAME_PREFIX: string = 'workbox-runtime-';
export const SW_ASSETS_CACHE_NAME: string = SW_CACHE_PREFIX + 'assets-cache';
export const SW_CODE_CACHE_NAME: string = SW_CACHE_PREFIX + 'code-cache';
export const SW_MAP_CACHE_NAME: string = SW_CACHE_PREFIX + 'map-cache';
export const SW_SHARE_CACHE_NAME: string = SW_CACHE_PREFIX + 'share-cache';

export const SW_MESSAGE_TYPE_UPDATE_MAP_CACHE_CONFIG: string = 'UPDATE_MAP_CACHE_CONFIG';
export const SW_MESSAGE_TYPE_UPDATE_MAP_CACHE_CONFIG_RESPONSE: string = 'UPDATE_MAP_CACHE_CONFIG_RESPONSE';

export const MAP_CACHE_MAX_ENTRIES: number = 1000;
