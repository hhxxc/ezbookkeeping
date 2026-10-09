import type { Router } from 'framework7/types';

import { isUserLogined, isUserUnlocked } from '@/lib/userstate.ts';

// 首屏关键页 + 高频页（账单列表/编辑）静态导入，其余页面全部懒加载：
// asyncResolve 收到的是已加载组件；lazyResolve 收到动态 import 工厂，
// 首次导航时才拉取对应 chunk（views 不打进入口包，首屏 JS 减 30%~50%）

import HomePage from '@/views/mobile/HomePage.vue';
import LoginPage from '@/views/mobile/LoginPage.vue';
import SignUpPage from '@/views/mobile/SignupPage.vue';
import UnlockPage from '@/views/mobile/UnlockPage.vue';

import TransactionListPage from '@/views/mobile/transactions/ListPage.vue';
import TransactionEditPage from '@/views/mobile/transactions/EditPage.vue';

function asyncResolve(component: unknown): (ctx: Router.RouteCallbackCtx) => void {
    return function({ resolve }: { resolve: ({ component }: { component: unknown }) => void }): void {
        return resolve({
            component: component
        });
    } as unknown as (ctx: Router.RouteCallbackCtx) => void;
}

function lazyResolve(loader: () => Promise<{ default: unknown }>): (ctx: Router.RouteCallbackCtx) => void {
    return function({ resolve }: { resolve: ({ component }: { component: unknown }) => void }): void {
        void loader().then((module) => {
            resolve({
                component: module.default
            });
        });
    } as unknown as (ctx: Router.RouteCallbackCtx) => void;
}

function checkLogin({ router, resolve, reject }: { router: Router.Router, resolve: () => void, reject: () => void }): void {
    if (!isUserLogined()) {
        reject();
        router.navigate('/login', {
            clearPreviousHistory: true,
            browserHistory: false
        });
        return;
    }

    if (!isUserUnlocked()) {
        reject();
        router.navigate('/unlock', {
            clearPreviousHistory: true,
            browserHistory: false
        });
        return;
    }

    resolve();
}

function checkLocked({ router, resolve, reject }: { router: Router.Router, resolve: () => void, reject: () => void }): void {
    if (!isUserLogined()) {
        reject();
        router.navigate('/login', {
            clearPreviousHistory: true,
            browserHistory: false
        });
        return;
    }

    if (isUserUnlocked()) {
        reject();
        router.navigate('/', {
            clearPreviousHistory: true,
            browserHistory: false
        });
        return;
    }

    resolve();
}

function checkNotLogin({ router, resolve, reject }: { router: Router.Router, resolve: () => void, reject: () => void }): void {
    if (isUserLogined() && !isUserUnlocked()) {
        reject();
        router.navigate('/unlock', {
            clearPreviousHistory: true,
            browserHistory: false
        });
        return;
    }

    if (isUserLogined()) {
        reject();
        router.navigate('/', {
            clearPreviousHistory: true,
            browserHistory: false
        });
        return;
    }

    resolve();
}

const routes: Router.RouteParameters[] = [
    {
        path: '/',
        async: asyncResolve(HomePage),
        beforeEnter: [checkLogin],
        options: {
            animate: false,
        }
    },
    {
        path: '/login',
        async: asyncResolve(LoginPage),
        beforeEnter: [checkNotLogin],
        options: {
            animate: false,
        }
    },
    {
        path: '/signup',
        async: asyncResolve(SignUpPage),
        beforeEnter: [checkNotLogin],
        options: {
            animate: false,
        }
    },
    {
        path: '/unlock',
        async: asyncResolve(UnlockPage),
        beforeEnter: [checkLocked],
        options: {
            animate: false,
        }
    },
    {
        path: '/transaction/list',
        async: asyncResolve(TransactionListPage),
        beforeEnter: [checkLogin]
    },
    {
        path: '/transaction/add',
        async: asyncResolve(TransactionEditPage),
        beforeEnter: [checkLogin]
    },
    {
        path: '/transaction/edit',
        async: asyncResolve(TransactionEditPage),
        beforeEnter: [checkLogin]
    },
    {
        path: '/transaction/detail',
        async: asyncResolve(TransactionEditPage),
        beforeEnter: [checkLogin]
    },
    {
        path: '/account/list',
        async: lazyResolve(() => import('@/views/mobile/accounts/ListPage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/account/add',
        async: lazyResolve(() => import('@/views/mobile/accounts/EditPage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/account/edit',
        async: lazyResolve(() => import('@/views/mobile/accounts/EditPage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/account/reconciliation_statements',
        async: lazyResolve(() => import('@/views/mobile/accounts/ReconciliationStatementPage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/account/move_all_transactions',
        async: lazyResolve(() => import('@/views/mobile/accounts/MoveAllTransactionsPage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/statistic/transaction',
        async: lazyResolve(() => import('@/views/mobile/statistics/TransactionPage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/statistic/settings',
        async: lazyResolve(() => import('@/views/mobile/statistics/SettingsPage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/settings/textsize',
        async: lazyResolve(() => import('@/views/mobile/settings/TextSizeSettingsPage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/settings/filter/account',
        async: lazyResolve(() => import('@/views/mobile/settings/AccountFilterSettingsPage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/settings/filter/category',
        async: lazyResolve(() => import('@/views/mobile/settings/CategoryFilterSettingsPage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/settings/filter/tag',
        async: lazyResolve(() => import('@/views/mobile/settings/TransactionTagFilterSettingsPage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/settings/page',
        async: lazyResolve(() => import('@/views/mobile/settings/PageSettingsPage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/settings/account_category_display_order',
        async: lazyResolve(() => import('@/views/mobile/settings/AccountCategoryDisplayOrderSettingsPage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/settings/sync',
        async: lazyResolve(() => import('@/views/mobile/settings/ApplicationCloudSyncSettingsPage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/settings/browser_caches',
        async: lazyResolve(() => import('@/views/mobile/settings/BrowserCacheSettingPage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/settings',
        async: lazyResolve(() => import('@/views/mobile/SettingsPage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/app_lock',
        async: lazyResolve(() => import('@/views/mobile/ApplicationLockPage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/exchange_rates',
        async: lazyResolve(() => import('@/views/mobile/exchangerates/ListPage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/exchange_rates/update',
        async: lazyResolve(() => import('@/views/mobile/exchangerates/UpdatePage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/about',
        async: lazyResolve(() => import('@/views/mobile/AboutPage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/user/profile',
        async: lazyResolve(() => import('@/views/mobile/users/UserProfilePage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/user/data/management',
        async: lazyResolve(() => import('@/views/mobile/users/DataManagementPage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/user/2fa',
        async: lazyResolve(() => import('@/views/mobile/users/TwoFactorAuthPage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/user/sessions',
        async: lazyResolve(() => import('@/views/mobile/users/SessionListPage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/category/all',
        async: lazyResolve(() => import('@/views/mobile/categories/AllPage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/category/list',
        async: lazyResolve(() => import('@/views/mobile/categories/ListPage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/category/add',
        async: lazyResolve(() => import('@/views/mobile/categories/EditPage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/category/edit',
        async: lazyResolve(() => import('@/views/mobile/categories/EditPage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/category/preset',
        async: lazyResolve(() => import('@/views/mobile/categories/PresetPage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/tag/list',
        async: lazyResolve(() => import('@/views/mobile/tags/ListPage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/tag/group/list',
        async: lazyResolve(() => import('@/views/mobile/tags/GroupListPage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/template/list',
        async: lazyResolve(() => import('@/views/mobile/templates/ListPage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/schedule/list',
        async: lazyResolve(() => import('@/views/mobile/templates/ListPage.vue')),
        beforeEnter: [checkLogin]
    },
    {
        path: '/template/add',
        async: asyncResolve(TransactionEditPage),
        beforeEnter: [checkLogin]
    },
    {
        path: '/template/edit',
        async: asyncResolve(TransactionEditPage),
        beforeEnter: [checkLogin]
    },
    {
        path: '(.*)',
        redirect: '/'
    }
];

export default routes;
