import { type NavigationGuardReturn, createRouter, createWebHashHistory } from 'vue-router';

import { TemplateType } from '@/core/template.ts';
import { isUserLogined, isUserUnlocked } from '@/lib/userstate.ts';

// 布局与登录流程页静态导入；登录后的各功能页全部懒加载（vue-router 原生支持
// component 返回动态 import），views 不打进入口包
import MainLayout from '@/views/desktop/MainLayout.vue';
import LoginPage from '@/views/desktop/LoginPage.vue';
import SignUpPage from '@/views/desktop/SignupPage.vue';
import VerifyEmailPage from '@/views/desktop/VerifyEmailPage.vue';
import ForgetPasswordPage from '@/views/desktop/ForgetPasswordPage.vue';
import ResetPasswordPage from '@/views/desktop/ResetPasswordPage.vue';
import OAuth2CallbackPage from '@/views/desktop/OAuth2CallbackPage.vue';
import UnlockPage from '@/views/desktop/UnlockPage.vue';

import HomePage from '@/views/desktop/HomePage.vue';

function checkLogin(): NavigationGuardReturn {
    if (!isUserLogined()) {
        return {
            path: '/login',
            replace: true
        };
    }

    if (!isUserUnlocked()) {
        return {
            path: '/unlock',
            replace: true
        };
    }

    return true;
}

function checkLocked(): NavigationGuardReturn {
    if (!isUserLogined()) {
        return {
            path: '/login',
            replace: true
        };
    }

    if (isUserUnlocked()) {
        return {
            path: '/',
            replace: true
        };
    }

    return true;
}

function checkNotLogin(): NavigationGuardReturn {
    if (isUserLogined() && !isUserUnlocked()) {
        return {
            path: '/unlock',
            replace: true
        };
    }

    if (isUserLogined()) {
        return {
            path: '/',
            replace: true
        };
    }

    return true;
}

const router = createRouter({
    history: createWebHashHistory(),
    routes: [
        {
            path: '/',
            component: MainLayout,
            beforeEnter: checkLogin,
            children: [
                {
                    path: '',
                    component: HomePage,
                    beforeEnter: checkLogin
                },
                {
                    path: '/transaction/list',
                    component: () => import('@/views/desktop/transactions/ListPage.vue'),
                    beforeEnter: checkLogin,
                    props: route => ({
                        initPageType: route.query['pageType'],
                        initDateType: route.query['dateType'],
                        initMaxTime: route.query['maxTime'],
                        initMinTime: route.query['minTime'],
                        initType: route.query['type'],
                        initCategoryIds: route.query['categoryIds'],
                        initAccountIds: route.query['accountIds'],
                        initTagFilter: route.query['tagFilter'],
                        initAmountFilter: route.query['amountFilter'],
                        initKeyword: route.query['keyword']
                    })
                },
                {
                    path: '/statistics/transaction',
                    component: () => import('@/views/desktop/statistics/TransactionPage.vue'),
                    beforeEnter: checkLogin,
                    props: route => ({
                        initAnalysisType: route.query['analysisType'],
                        initChartDataType: route.query['chartDataType'],
                        initChartType: route.query['chartType'],
                        initChartDateType: route.query['chartDateType'],
                        initStartTime: route.query['startTime'],
                        initEndTime: route.query['endTime'],
                        initFilterAccountIds: route.query['filterAccountIds'],
                        initFilterCategoryIds: route.query['filterCategoryIds'],
                        initTagFilter: route.query['tagFilter'],
                        initKeyword: route.query['keyword'],
                        initSortingType: route.query['sortingType'],
                        initTrendDateAggregationType: route.query['trendDateAggregationType'],
                        initAssetTrendsDateAggregationType: route.query['assetTrendsDateAggregationType']
                    })
                },
                {
                    path: '/insights/explorer',
                    component: () => import('@/views/desktop/insights/ExplorerPage.vue'),
                    beforeEnter: checkLogin,
                    props: route => ({
                        initId: route.query['id'],
                        initActiveTab: route.query['activeTab'],
                        initDateRangeType: route.query['dateRangeType'],
                        initStartTime: route.query['startTime'],
                        initEndTime: route.query['endTime']
                    })
                },
                {
                    path: '/account/list',
                    component: () => import('@/views/desktop/accounts/ListPage.vue'),
                    beforeEnter: checkLogin
                },
                {
                    path: '/category/list',
                    component: () => import('@/views/desktop/categories/ListPage.vue'),
                    beforeEnter: checkLogin
                },
                {
                    path: '/tag/list',
                    component: () => import('@/views/desktop/tags/ListPage.vue'),
                    beforeEnter: checkLogin
                },
                {
                    path: '/template/list',
                    component: () => import('@/views/desktop/templates/ListPage.vue'),
                    beforeEnter: checkLogin,
                    props: {
                        initType: TemplateType.Normal.type
                    }
                },
                {
                    path: '/schedule/list',
                    component: () => import('@/views/desktop/templates/ListPage.vue'),
                    beforeEnter: checkLogin,
                    props: {
                        initType: TemplateType.Schedule.type
                    }
                },
                {
                    path: '/exchange_rates',
                    component: () => import('@/views/desktop/exchangerates/ListPage.vue'),
                    beforeEnter: checkLogin
                },
                {
                    path: '/user/settings',
                    component: () => import('@/views/desktop/user/UserSettingsPage.vue'),
                    beforeEnter: checkLogin,
                    props: route => ({
                        initTab: route.query['tab']
                    })
                },
                {
                    path: '/app/settings',
                    component: () => import('@/views/desktop/app/AppSettingsPage.vue'),
                    beforeEnter: checkLogin,
                    props: route => ({
                        initTab: route.query['tab']
                    })
                },
                {
                    path: '/about',
                    component: () => import('@/views/desktop/AboutPage.vue'),
                    beforeEnter: checkLogin
                }
            ]
        },
        {
            path: '/login',
            component: LoginPage,
            beforeEnter: checkNotLogin
        },
        {
            path: '/signup',
            component: SignUpPage,
            beforeEnter: checkNotLogin
        },
        {
            path: '/verify_email',
            component: VerifyEmailPage,
            props: route => ({
                email: route.query['email'],
                token: route.query['token'],
                hasValidEmailVerifyToken: route.query['emailSent'] === 'true'
            })
        },
        {
            path: '/forgetpassword',
            component: ForgetPasswordPage,
            beforeEnter: checkNotLogin
        },
        {
            path: '/resetpassword',
            component: ResetPasswordPage,
            props: route => ({
                token: route.query['token']
            })
        },
        {
            path: '/oauth2_callback',
            component: OAuth2CallbackPage,
            props: route => ({
                token: route.query['token'],
                provider: route.query['provider'],
                platform: route.query['platform'],
                userName: route.query['userName'],
                errorCode: route.query['errorCode'],
                errorMessage: route.query['errorMessage']
            })
        },
        {
            path: '/unlock',
            component: UnlockPage,
            beforeEnter: checkLocked
        }
    ],
})

export default router;
