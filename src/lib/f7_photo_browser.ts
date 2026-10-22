/**
 * 记账页「看大图」所需的 Framework7 模块（photo-browser + swiper），按需加载。
 *
 * 这两个模块原先在 mobile-main.ts 里随 app 一起注册，导致 vendor-mobile
 * 首屏固定背上 swiper 的 183KB（约 40KB gzip）——而它们只服务于记账页
 * 点击配图后的图片浏览器。
 *
 * 这里在记账页的 chunk 里注册：
 * - Framework7.use() 只把模块挂到 prototype，已创建的 app 实例不会自动获得
 *   create 方法，因此还要手动 useModule 一次（框架没有对外的动态注册 API）。
 * - app.params 里也缺这两个模块的默认参数，补上后再构造 PhotoBrowser，
 *   否则 photo-browser-class 读 app.params.photoBrowser.* 会取到 undefined。
 */
import Framework7 from 'framework7/lite';
import Framework7PhotoBrowser from 'framework7/components/photo-browser';
import Framework7Swiper from 'framework7/components/swiper';
import F7PhotoBrowserComponent from 'framework7-vue/components/photo-browser.js';
import { f7 } from 'framework7-vue/shared/f7.js';

type ModuleDefaults = { params?: Record<string, unknown> };
type AppInstance = {
    params?: Record<string, unknown>;
    useModule?: (name: string, params?: unknown) => void;
};

let photoBrowserReady = false;

// 整个注册过程包一层 try/catch：最坏情况是图片浏览器不可用（点图看大图无反应），
// 绝不能让异常冒出去把记账页这个 chunk 带崩。
try {
    Framework7.use([Framework7Swiper, Framework7PhotoBrowser]);

    const app = f7 as unknown as AppInstance;

    if (app && typeof app.useModule === 'function') {
        const swiperDefaults = (Framework7Swiper as unknown as ModuleDefaults).params?.swiper;
        const photoBrowserDefaults = (Framework7PhotoBrowser as unknown as ModuleDefaults).params?.photoBrowser;

        app.params = app.params || {};

        if (!app.params.swiper) {
            app.params.swiper = swiperDefaults;
        }

        if (!app.params.photoBrowser) {
            app.params.photoBrowser = photoBrowserDefaults;
        }

        app.useModule('swiper', app.params.swiper);
        app.useModule('photoBrowser', app.params.photoBrowser);

        photoBrowserReady = !!app.params.photoBrowser;
    }
} catch (e) {
    console.error('[f7_photo_browser] failed to register photo-browser modules', e);
}

/**
 * 注册是否成功。调用方用 v-if 挂载 `<F7PhotoBrowser>`：该组件 mounted 时会调用
 * f7.photoBrowser.create()，模块没注册上就会抛错并带崩整个记账页。
 */
export const isPhotoBrowserReady: boolean = photoBrowserReady;

export default F7PhotoBrowserComponent;
