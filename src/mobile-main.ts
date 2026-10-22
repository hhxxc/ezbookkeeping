import { createApp, defineAsyncComponent } from 'vue';
import { createPinia } from 'pinia';
import { createI18n } from 'vue-i18n';

import Framework7 from 'framework7/lite';
import Framework7Dialog from 'framework7/components/dialog';
import Framework7Popup from 'framework7/components/popup';
import Framework7LoginScreen from 'framework7/components/login-screen';
import Framework7Popover from 'framework7/components/popover';
import Framework7Actions from 'framework7/components/actions';
import Framework7Sheet from 'framework7/components/sheet';
import Framework7Notification from 'framework7/components/notification';
import Framework7Toast from 'framework7/components/toast';
import Framework7Preloader from 'framework7/components/preloader';
import Framework7Progressbar from 'framework7/components/progressbar';
import Framework7Sortable from 'framework7/components/sortable';
import Framework7Swipeout from 'framework7/components/swipeout';
import Framework7Accordion from 'framework7/components/accordion';
import Framework7Card from 'framework7/components/card';
import Framework7Chip from 'framework7/components/chip';
import Framework7Form from 'framework7/components/form';
import Framework7Input from 'framework7/components/input';
import Framework7Checkbox from 'framework7/components/checkbox';
import Framework7Radio from 'framework7/components/radio';
import Framework7Toggle from 'framework7/components/toggle';
import Framework7Range from 'framework7/components/range';
import Framework7Grid from 'framework7/components/grid';
import Framework7Picker from 'framework7/components/picker';
import Framework7Fab from 'framework7/components/fab';
import Framework7InfiniteScroll from 'framework7/components/infinite-scroll';
import Framework7PullToRefresh from 'framework7/components/pull-to-refresh';
import Framework7Searchbar from 'framework7/components/searchbar';
import Framework7Tooltip from 'framework7/components/tooltip';
import Framework7Skeleton from 'framework7/components/skeleton';
import Framework7Treeview from 'framework7/components/treeview';
import Framework7Typography from 'framework7/components/typography';
import Framework7VirtualList from 'framework7/components/virtual-list';
import Framework7Vue from 'framework7-vue';
// f7-vue 按需注册：原 framework7-vue/bundle 全量注册 90 个组件（其主入口静态聚合全部组件且
// 无 sideEffects 声明无法 tree-shake），改为逐组件文件导入，只注册手机端模板实际用到的 48 个
import f7AccordionContent from 'framework7-vue/components/accordion-content.js';
import f7AccordionItem from 'framework7-vue/components/accordion-item.js';
import f7AccordionToggle from 'framework7-vue/components/accordion-toggle.js';
import f7Actions from 'framework7-vue/components/actions.js';
import f7ActionsButton from 'framework7-vue/components/actions-button.js';
import f7ActionsGroup from 'framework7-vue/components/actions-group.js';
import f7ActionsLabel from 'framework7-vue/components/actions-label.js';
import f7App from 'framework7-vue/components/app.js';
import f7Badge from 'framework7-vue/components/badge.js';
import f7Block from 'framework7-vue/components/block.js';
import f7BlockFooter from 'framework7-vue/components/block-footer.js';
import f7BlockTitle from 'framework7-vue/components/block-title.js';
import f7Button from 'framework7-vue/components/button.js';
import f7Card from 'framework7-vue/components/card.js';
import f7CardContent from 'framework7-vue/components/card-content.js';
import f7CardHeader from 'framework7-vue/components/card-header.js';
import f7Chip from 'framework7-vue/components/chip.js';
import f7Fab from 'framework7-vue/components/fab.js';
import f7Icon from 'framework7-vue/components/icon.js';
import f7Input from 'framework7-vue/components/input.js';
import f7Link from 'framework7-vue/components/link.js';
import f7List from 'framework7-vue/components/list.js';
import f7ListButton from 'framework7-vue/components/list-button.js';
import f7ListInput from 'framework7-vue/components/list-input.js';
import f7ListItem from 'framework7-vue/components/list-item.js';
import f7NavLeft from 'framework7-vue/components/nav-left.js';
import f7NavRight from 'framework7-vue/components/nav-right.js';
import f7NavTitle from 'framework7-vue/components/nav-title.js';
import f7Navbar from 'framework7-vue/components/navbar.js';
import f7Page from 'framework7-vue/components/page.js';
import f7PageContent from 'framework7-vue/components/page-content.js';
import f7Popover from 'framework7-vue/components/popover.js';
import f7Popup from 'framework7-vue/components/popup.js';
import f7Preloader from 'framework7-vue/components/preloader.js';
import f7Progressbar from 'framework7-vue/components/progressbar.js';
import f7Range from 'framework7-vue/components/range.js';
import f7Searchbar from 'framework7-vue/components/searchbar.js';
import f7Segmented from 'framework7-vue/components/segmented.js';
import f7Sheet from 'framework7-vue/components/sheet.js';
import f7Subnavbar from 'framework7-vue/components/subnavbar.js';
import f7SwipeoutActions from 'framework7-vue/components/swipeout-actions.js';
import f7SwipeoutButton from 'framework7-vue/components/swipeout-button.js';
import f7Toggle from 'framework7-vue/components/toggle.js';
import f7Toolbar from 'framework7-vue/components/toolbar.js';
import f7Treeview from 'framework7-vue/components/treeview.js';
import f7TreeviewItem from 'framework7-vue/components/treeview-item.js';
import f7View from 'framework7-vue/components/view.js';

import 'framework7-icons';
import 'line-awesome/dist/line-awesome/css/line-awesome.css';

// VueDatePicker 及其样式都随异步组件加载（见 DateTimePicker.vue / MonthPicker.vue）。
// 注意：不要在这里静态 import vue-datepicker 的 CSS——那会让整个包（含 date-fns /
// vueuse / floating-ui，约 63KB gzip）变成首屏静态依赖，凭空多下载 60KB+。
import { getI18nOptions, preloadInitialLanguageContent } from '@/locales/helpers.ts';

// 以下四个组件在首屏链路（登录页/解锁页/应用锁页/账单列表）使用，保留静态注册；
// 其余全局组件全部改为 defineAsyncComponent 按需分块加载，不进入首包。
import PinCodeInput from '@/components/common/PinCodeInput.vue';

import ItemIcon from '@/components/mobile/ItemIcon.vue';
import LanguageSelectButton from '@/components/mobile/LanguageSelectButton.vue';
import PinCodeInputSheet from '@/components/mobile/PinCodeInputSheet.vue';

import { loadRemoteServerSettings } from '@/lib/server_settings.ts';
import { isAppShellSafeAreaSelfManaged } from '@/lib/ui/mobile.ts';
import { useUserStore } from '@/stores/user.ts';

import TextareaAutoSize from '@/directives/mobile/textareaAutoSize.ts';

import '@/styles/mobile/global.scss';
import '@/styles/mobile/font-size-default.scss';
import '@/styles/mobile/font-size-small.scss';
import '@/styles/mobile/font-size-large.scss';
import '@/styles/mobile/font-size-x-large.scss';
import '@/styles/mobile/font-size-xx-large.scss';
import '@/styles/mobile/font-size-xxx-large.scss';
import '@/styles/mobile/font-size-xxxx-large.scss';
import '@/styles/mobile/amount-color.scss';

import App from '@/MobileApp.vue';

// 新版原生壳（contentInset: never）下页面铺满整屏，安全区由页面自己接管
if (isAppShellSafeAreaSelfManaged()) {
    document.documentElement.classList.add('app-shell');
}

Framework7.use([
    Framework7Dialog,
    Framework7Popup,
    Framework7LoginScreen,
    Framework7Popover,
    Framework7Actions,
    Framework7Sheet,
    Framework7Notification,
    Framework7Toast,
    Framework7Preloader,
    Framework7Progressbar,
    Framework7Sortable,
    Framework7Swipeout,
    Framework7Accordion,
    Framework7Card,
    Framework7Chip,
    Framework7Form,
    Framework7Input,
    Framework7Checkbox,
    Framework7Radio,
    Framework7Toggle,
    Framework7Range,
    Framework7Grid,
    Framework7Picker,
    Framework7Fab,
    Framework7InfiniteScroll,
    Framework7PullToRefresh,
    Framework7Searchbar,
    Framework7Tooltip,
    Framework7Skeleton,
    Framework7Treeview,
    Framework7Typography,
    Framework7VirtualList,
    Framework7Vue
]);

const app = createApp(App);
const pinia = createPinia();
const userStore = useUserStore(pinia);
// 按需注册 f7 组件（对齐原 bundle 的 registerComponents，只注册实际用到的）
app.component('f7-accordion-content', f7AccordionContent);
app.component('f7-accordion-item', f7AccordionItem);
app.component('f7-accordion-toggle', f7AccordionToggle);
app.component('f7-actions', f7Actions);
app.component('f7-actions-button', f7ActionsButton);
app.component('f7-actions-group', f7ActionsGroup);
app.component('f7-actions-label', f7ActionsLabel);
app.component('f7-app', f7App);
app.component('f7-badge', f7Badge);
app.component('f7-block', f7Block);
app.component('f7-block-footer', f7BlockFooter);
app.component('f7-block-title', f7BlockTitle);
app.component('f7-button', f7Button);
app.component('f7-card', f7Card);
app.component('f7-card-content', f7CardContent);
app.component('f7-card-header', f7CardHeader);
app.component('f7-chip', f7Chip);
app.component('f7-fab', f7Fab);
app.component('f7-icon', f7Icon);
app.component('f7-input', f7Input);
app.component('f7-link', f7Link);
app.component('f7-list', f7List);
app.component('f7-list-button', f7ListButton);
app.component('f7-list-input', f7ListInput);
app.component('f7-list-item', f7ListItem);
app.component('f7-nav-left', f7NavLeft);
app.component('f7-nav-right', f7NavRight);
app.component('f7-nav-title', f7NavTitle);
app.component('f7-navbar', f7Navbar);
app.component('f7-page', f7Page);
app.component('f7-page-content', f7PageContent);
app.component('f7-popover', f7Popover);
app.component('f7-popup', f7Popup);
app.component('f7-preloader', f7Preloader);
app.component('f7-progressbar', f7Progressbar);
app.component('f7-range', f7Range);
app.component('f7-searchbar', f7Searchbar);
app.component('f7-segmented', f7Segmented);
app.component('f7-sheet', f7Sheet);
app.component('f7-subnavbar', f7Subnavbar);
app.component('f7-swipeout-actions', f7SwipeoutActions);
app.component('f7-swipeout-button', f7SwipeoutButton);
app.component('f7-toggle', f7Toggle);
app.component('f7-toolbar', f7Toolbar);
app.component('f7-treeview', f7Treeview);
app.component('f7-treeview-item', f7TreeviewItem);
app.component('f7-view', f7View);
app.use(pinia);

// 非首屏组件统一异步注册：首次使用时才加载对应 chunk
const asyncComp = (loader: Parameters<typeof defineAsyncComponent>[0]) => defineAsyncComponent(loader);

app.component('VueDatePicker', asyncComp(() => import('@vuepic/vue-datepicker').then(m => m.VueDatePicker)));

app.component('PinCodeInput', PinCodeInput);

app.component('MapView', asyncComp(() => import('@/components/common/MapView.vue')));
app.component('DateTimePicker', asyncComp(() => import('@/components/common/DateTimePicker.vue')));
app.component('MonthPicker', asyncComp(() => import('@/components/common/MonthPicker.vue')));
app.component('TransactionCalendar', asyncComp(() => import('@/components/common/TransactionCalendar.vue')));

app.component('ItemIcon', ItemIcon);
app.component('LanguageSelectButton', LanguageSelectButton);
app.component('PieChart', asyncComp(() => import('@/components/mobile/PieChart.vue')));
app.component('TrendsBarChart', asyncComp(() => import('@/components/mobile/TrendsBarChart.vue')));
app.component('PinCodeInputSheet', PinCodeInputSheet);
app.component('PasswordInputSheet', asyncComp(() => import('@/components/mobile/PasswordInputSheet.vue')));
app.component('PasscodeInputSheet', asyncComp(() => import('@/components/mobile/PasscodeInputSheet.vue')));
app.component('DateTimeSelectionSheet', asyncComp(() => import('@/components/mobile/DateTimeSelectionSheet.vue')));
app.component('DateSelectionSheet', asyncComp(() => import('@/components/mobile/DateSelectionSheet.vue')));
app.component('FiscalYearStartSelectionSheet', asyncComp(() => import('@/components/mobile/FiscalYearStartSelectionSheet.vue')));
app.component('DateRangeSelectionSheet', asyncComp(() => import('@/components/mobile/DateRangeSelectionSheet.vue')));
app.component('MonthSelectionSheet', asyncComp(() => import('@/components/mobile/MonthSelectionSheet.vue')));
app.component('MonthRangeSelectionSheet', asyncComp(() => import('@/components/mobile/MonthRangeSelectionSheet.vue')));
app.component('ListNumberInput', asyncComp(() => import('@/components/mobile/ListNumberInput.vue')));
app.component('ListItemSelectionSheet', asyncComp(() => import('@/components/mobile/ListItemSelectionSheet.vue')));
app.component('ListItemSelectionPopup', asyncComp(() => import('@/components/mobile/ListItemSelectionPopup.vue')));
app.component('TwoColumnListItemSelectionSheet', asyncComp(() => import('@/components/mobile/TwoColumnListItemSelectionSheet.vue')));
app.component('TreeViewSelectionSheet', asyncComp(() => import('@/components/mobile/TreeViewSelectionSheet.vue')));
app.component('IconSelectionSheet', asyncComp(() => import('@/components/mobile/IconSelectionSheet.vue')));
app.component('ColorSelectionSheet', asyncComp(() => import('@/components/mobile/ColorSelectionSheet.vue')));
app.component('InformationSheet', asyncComp(() => import('@/components/mobile/InformationSheet.vue')));
app.component('NumberPadSheet', asyncComp(() => import('@/components/mobile/NumberPadSheet.vue')));
app.component('MapSheet', asyncComp(() => import('@/components/mobile/MapSheet.vue')));
app.component('TransactionTagSelectionSheet', asyncComp(() => import('@/components/mobile/TransactionTagSelectionSheet.vue')));
app.component('ScheduleFrequencySheet', asyncComp(() => import('@/components/mobile/ScheduleFrequencySheet.vue')));
app.component('AccountBalanceTrendsBarChart', asyncComp(() => import('@/components/mobile/AccountBalanceTrendsBarChart.vue')));
app.component('DailyIncomeExpenseBarChart', asyncComp(() => import('@/components/mobile/DailyIncomeExpenseBarChart.vue')));
app.component('AIImageRecognitionSheet', asyncComp(() => import('@/components/mobile/AIImageRecognitionSheet.vue')));

app.directive('TextareaAutoSize', TextareaAutoSize);

// load the content of the user's language before creating the i18n instance, so that the
// first visible frame is already in the correct language instead of the default one
Promise.all([
    preloadInitialLanguageContent(userStore.currentUserLanguage).catch(() => undefined),
    loadRemoteServerSettings()
]).then(([initialLanguage]) => {
    const i18n = createI18n(getI18nOptions(initialLanguage));
    app.use(i18n);

    app.mount('#app');
});
