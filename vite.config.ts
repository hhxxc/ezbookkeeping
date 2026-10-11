import fs from 'fs';
import { resolve } from 'path';

import { type UserConfig, type Plugin, defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue';
import vuetify from 'vite-plugin-vuetify';
import { VitePWA } from 'vite-plugin-pwa';
import Checker from 'vite-plugin-checker';
import git from 'git-rev-sync';

import packageFile from './package.json';
import contributorsFile from './contributors.json';
import thirdPartyLicenseFile from './third-party-dependencies.json';

const SRC_DIR = resolve(__dirname, './src');
const PUBLIC_DIR = resolve(__dirname, './public');
const BUILD_DIR = resolve(__dirname, './dist',);

function injectFramework7CssFile({ htmlFileName, placeHolders }: { htmlFileName: string, placeHolders: { name: string, srcFileName: string, distFileNamePrefix: string }[] }): Plugin[] {
    return [
        {
            name: 'inject-framework7-css-file:serve',
            apply: 'serve',
            enforce: 'post',
            transformIndexHtml(html: string): string {
                for (const placeholder of placeHolders) {
                    html = html.replace(`{{${placeholder.name}}}`, `${placeholder.srcFileName}`);
                }
                return html;
            }
        },
        {
            name: 'inject-framework7-css-file:build',
            apply: 'build',
            enforce: 'post',
            generateBundle(_, bundle): void {
                const placeholderCssFilePathMap: Record<string, string> = {};

                for (const fileName of Object.keys(bundle)) {
                    for (const placeholder of placeHolders) {
                        if (fileName.startsWith(placeholder.distFileNamePrefix)) {
                            placeholderCssFilePathMap[placeholder.name] = fileName;
                            break;
                        }
                    }
                }

                const htmlAsset = bundle[htmlFileName];

                if (!htmlAsset || htmlAsset.type !== 'asset') {
                    return;
                }

                let html = htmlAsset.source as string;

                for (const [placeholder, filePath] of Object.entries(placeholderCssFilePathMap)) {
                    html = html.replace(`{{${placeholder}}}`, `./${filePath}`);
                }

                htmlAsset.source = html;
            }
        }
    ];
}

export default defineConfig(() => {
    const licenseContent = fs.readFileSync('./LICENSE', { encoding: 'utf-8' });
    const buildUnixTime = process.env['buildUnixTime'] || '';

    const options: UserConfig = {
        root: SRC_DIR,
        publicDir: PUBLIC_DIR,
        base: './',
        define: {
            __EZBOOKKEEPING_IS_PRODUCTION__: process.env['NODE_ENV'] === 'production',
            __EZBOOKKEEPING_VERSION__: JSON.stringify(packageFile.version),
            __EZBOOKKEEPING_BUILD_UNIX_TIME__: JSON.stringify(buildUnixTime),
            __EZBOOKKEEPING_BUILD_COMMIT_HASH__: JSON.stringify(git.short()),
            __EZBOOKKEEPING_CONTRIBUTORS__: JSON.stringify(contributorsFile),
            __EZBOOKKEEPING_LICENSE__: JSON.stringify(licenseContent),
            __EZBOOKKEEPING_THIRD_PARTY_LICENSES__: JSON.stringify(thirdPartyLicenseFile)
        },
        plugins: [
            vue({
                template: {
                    compilerOptions: {
                        isCustomElement: tag => tag.includes('swiper-')
                    }
                }
            }),
            vuetify({
                styles: {
                    configFile: 'styles/desktop/configured-variables/_vuetify.scss'
                }
            }),
            injectFramework7CssFile({
                htmlFileName: 'mobile.html',
                placeHolders: [
                    {
                        name: 'framework7-ltr-css-filepath',
                        srcFileName: 'mobile-ltr.scss',
                        distFileNamePrefix: 'css/vendor-framework7-ltr'
                    },
                    {
                        name: 'framework7-rtl-css-filepath',
                        srcFileName: 'mobile-rtl.scss',
                        distFileNamePrefix: 'css/vendor-framework7-rtl'
                    }
                ]
            }),
            Checker({
                vueTsc: false
            }),
            VitePWA({
                strategies: 'injectManifest',
                srcDir: './',
                filename: 'sw.ts',
                injectRegister: false,
                manifestFilename: 'manifest.json',
                manifest: {
                    name: '巢记',
                    short_name: '巢记',
                    description: '巢记 - 轻量级个人记账应用',
                    theme_color: '#2563EB',
                    background_color: '#F6F7F8',
                    start_url: './',
                    scope: './',
                    display: 'standalone',
                    related_applications: [],
                    prefer_related_applications: false,
                    icons: [
                        {
                            src: 'img/nestkeep-logo-192.png',
                            sizes: '192x192',
                            type: 'image/png',
                            purpose: 'any'
                        },
                        {
                            src: 'img/nestkeep-logo-512.png',
                            sizes: '512x512',
                            type: 'image/png',
                            purpose: 'any'
                        }
                    ],
                    share_target: {
                        action: './__share__image__',
                        method: 'POST',
                        enctype: 'multipart/form-data',
                        params: {
                            files: [
                                {
                                    'name': 'image',
                                    'accept': ['image/*']
                                }
                            ]
                        }
                    }
                },
                injectManifest: {
                    globDirectory: 'dist/',
                    globPatterns: ['**/*.{js,css,html,ico,png,jpg,jpeg,gif,tiff,bmp,ttf,woff,woff2,svg,eot}'],
                    globIgnores: [
                        'index.html',
                        'mobile.html',
                        'desktop.html',
                        'robots.txt',
                        'img/desktop/*',
                        'fonts/*.eot',
                        'fonts/*.ttf',
                        'fonts/*.svg',
                        'fonts/*.woff',
                        'css/*.css',
                        'js/*.js',
                        // iOS PWA splash 图（约 3.9MB，42 张）对 iOS 原生壳毫无用处，浏览器 PWA 也只按
                        // media query 用其中一张。首次访问时 SW 会在后台把整批图片拉一遍抢占首屏带宽，
                        // 排除后仅按实际需要请求对应尺寸的那一张。
                        'img/splash_screens/*',
                        // nestkeep-logo.svg 仅用于 iOS 原生壳（Capacitor）构建时读取，以及三个 HTML 的
                        // <link rel="icon" type="image/svg+xml">。它在 public/ 下会被原样拷进 dist/，
                        // 但部署链路里并不下发（线上实际返回 404）→ 若被 Workbox 预缓存清单收录，
                        // SW install 会抛 bad-precaching-response 并整体安装失败（缓存/离线/更新链路全废）。
                        // 这里显式排除；HTML 里的 SVG icon 引用仅为渐进增强，404 不影响页面。
                        'nestkeep-logo.svg'
                    ],
                    maximumFileSizeToCacheInBytes: 5 * 1024 * 1024, // 5 MB
                }
            })
        ],
        build: {
            target: [
                'chrome91',
                'edge91',
                'firefox91',
                'safari15.4'
            ],
            outDir: BUILD_DIR,
            sourcemap: false,
            assetsInlineLimit: 0,
            emptyOutDir: true,
            rollupOptions: {
                input: {
                    index: resolve(SRC_DIR, 'index.html'),
                    desktop: resolve(SRC_DIR, 'desktop.html'),
                    mobile: resolve(SRC_DIR, 'mobile.html'),
                    'vendor-framework7-ltr': resolve(SRC_DIR, 'mobile-ltr.scss'),
                    'vendor-framework7-rtl': resolve(SRC_DIR, 'mobile-rtl.scss')
                },
                output: {
                    assetFileNames: assetInfo => {
                        const fileExt = assetInfo.names[0]?.split('.')[1];

                        if (!fileExt) {
                            throw new Error('Invalid asset file name.');
                        }

                        let assetType = fileExt;

                        if (/png|jpe?g|gif|tiff|bmp|ico/i.test(fileExt)) {
                            assetType = 'img';
                        } else if (/ttf|woff|woff2|svg|eot/i.test(fileExt)) {
                            assetType = 'fonts';
                        }

                        return `${assetType}/[name]-[hash][extname]`;
                    },
                    chunkFileNames: 'js/[name]-[hash].js',
                    entryFileNames: 'js/[name]-[hash].js',
                    manualChunks: id => {
                        if (/[\\/]node_modules[\\/]leaflet[\\/]/i.test(id)) {
                            return 'leaflet';
                        } else if (/[\\/]node_modules[\\/](moment|moment-timezone)[\\/]/i.test(id)) {
                            return 'moment';
                        } else if (/[\\/]node_modules[\\/](@capacitor|@capgo)[\\/]/i.test(id)) {
                            // capacitor 运行时独立成 chunk：插件包里的动态 import('./web') 会用到
                            // vite 的 preload 助手函数，若留在 vendor-common，助手函数会被挪进
                            // common（locales 懒加载也在用），vendor-common 反向 import common
                            // 形成 chunk 循环，顶层 axios 配置触发 TDZ 白屏（2026-10-06 事故）
                            return 'capacitor';
                        } else if (/[\\/]node_modules[\\/](dom7|framework7.*|skeleton-elements|swiper)[\\/]/i.test(id)) {
                            return 'vendor-mobile';
                        } else if (/[\\/]node_modules[\\/](vuetify|vue-router|vue3-perfect-scrollbar|perfect-scrollbar|vuedraggable|sortablejs|@mdi.*|tslib)[\\/]/i.test(id)) {
                            // tslib 跟 vuetify 同块：vuetify/exceljs 都依赖它，放这里避免
                            // vendor-desktop/vendor-echarts/vendor-export 互相 import 成环
                            return 'vendor-desktop';
                        } else if (/[\\/]node_modules[\\/](echarts|zrender|resize-detector|vue-echarts)[\\/]/i.test(id)) {
                            // 图表族独立成块：桌面端图表页已懒加载（router asyncResolve），
                            // 首页/列表页打开时不必拉 echarts
                            return 'vendor-echarts';
                        } else if (/plugin-vuetify:/i.test(id)) {
                            return 'vendor-desktop';
                        } else if (/[\\/]node_modules[\\/](exceljs|jszip)[\\/]/i.test(id)) {
                            // 仅桌面端 ExportDialog 引用（Excel 导出）。独立成块，
                            // 不进导出对话框就永不加载；jszip 是 exceljs 的依赖，一并处理。
                            return 'vendor-export';
                        } else if (/[\\/]node_modules[\\/]chardet[\\/]/i.test(id)) {
                            // 仅桌面端 ImportDialog 经 src/lib/file.ts 的 detectFileEncoding 动态 import
                            // 使用。若归入 vendor-common（兜底规则）会被移动端首屏强制加载，故脱离之，
                            // 由 rollup 拆成按需异步 chunk：移动端永不加载，桌面端仅导入对话框打开时才拉取。
                            return null;
                        } else if (/[\\/]node_modules[\\/]/i.test(id)) {
                            return 'vendor-common';
                        } else if (/[\\/]src[\\/](core|consts|models|stores)[\\/]/i.test(id)) {
                            return 'common';
                        } else if (/[\\/]src[\\/]lib[\\/](map[\\/]|ui[\\/]common|[a-zA-Z0-9-_]+\.(js|ts))/i.test(id)) {
                            return 'common';
                        } else if (/[\\/]src[\\/]components[\\/]common[\\/](MapView|DateTimePicker|MonthPicker|TransactionCalendar)\.vue/i.test(id)) {
                            // 全局注册的按需组件（mobile-main 里 defineAsyncComponent），
                            // 不归入首屏必载的 common，让 rollup 拆成按需 chunk
                            //（桌面入口静态引用它们，rollup 会生成两端共享的独立 chunk）
                            return null;
                        } else if (/[\\/]src[\\/]components[\\/](base|common)[\\/]/i.test(id)) {
                            return 'common';
                        } else if (/[\\/]src[\\/]views[\\/]base[\\/]/i.test(id)) {
                            return 'common';
                        } else if (/[\\/]src[\\/]locales[\\/]helpers\.(js|ts)/i.test(id)) {
                            return 'common';
                        } else {
                            // language JSON files are loaded on demand and each becomes
                            // its own async chunk, so they must not be merged into a
                            // single shared chunk here
                            return null;
                        }
                    }
                },
            },
        },
        resolve: {
            alias: {
                '@': SRC_DIR,
            },
        },
        server: {
            host: '0.0.0.0',
            port: 28081,
            strictPort: true,
            proxy: {
                '/server_settings.js': {
                    target: 'http://127.0.0.1:15080/',
                    changeOrigin: true
                },
                '/mobile/server_settings.js': {
                    target: 'http://127.0.0.1:15080/',
                    changeOrigin: true
                },
                '/desktop/server_settings.js': {
                    target: 'http://127.0.0.1:15080/',
                    changeOrigin: true
                },
                '/oauth2': {
                    target: 'http://127.0.0.1:15080/',
                    changeOrigin: true
                },
                '/api': {
                    target: 'http://127.0.0.1:15080/',
                    changeOrigin: true
                },
                '/mcp': {
                    target: 'http://127.0.0.1:15080/',
                    changeOrigin: true
                },
                '/avatar': {
                    target: 'http://127.0.0.1:15080/',
                    changeOrigin: true
                },
                '/pictures': {
                    target: 'http://127.0.0.1:15080/',
                    changeOrigin: true
                },
                '/qrcode': {
                    target: 'http://127.0.0.1:15080/',
                    changeOrigin: true
                },
                '/proxy': {
                    target: 'http://127.0.0.1:15080/',
                    changeOrigin: true
                },
                '/_AMapService': {
                    target: 'http://127.0.0.1:15080/',
                    changeOrigin: true
                }
            }
        },
    };

    return options;
})
