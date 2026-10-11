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
import Framework7Swiper from 'framework7/components/swiper';
import Framework7VirtualList from 'framework7/components/virtual-list';
import Framework7PhotoBrowser from 'framework7/components/photo-browser';
// @ts-expect-error there is a function called "registerComponents" in the framework7-vue package, but it is not declared in the type definition file
import Framework7Vue, { registerComponents } from 'framework7-vue/bundle';

import 'framework7-icons';
import 'line-awesome/dist/line-awesome/css/line-awesome.css';

// VueDatePicker 改为异步注册（见下方），样式保留在首屏 CSS 避免闪变
import '@vuepic/vue-datepicker/dist/main.css';

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
    Framework7Swiper,
    Framework7VirtualList,
    Framework7PhotoBrowser,
    Framework7Vue
]);

const app = createApp(App);
const pinia = createPinia();
const userStore = useUserStore(pinia);
registerComponents(app);
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
