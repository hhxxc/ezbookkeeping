<template>
    <f7-page :class="{ 'quick-edit-layout': useQuickEditLayout }" @page:afterin="onPageAfterIn" @page:beforeout="onPageBeforeOut">
        <f7-navbar v-if="!useQuickEditLayout">
            <f7-nav-left :class="{ 'disabled': loading }" :back-link="tt('Back')"></f7-nav-left>
            <f7-nav-title :title="tt(title)"></f7-nav-title>
            <f7-nav-right :class="{ 'navbar-compact-icons': true, 'disabled': loading }" v-if="mode !== TransactionEditPageMode.View || transaction.type !== TransactionType.ModifyBalance">
                <f7-link icon-f7="doc_on_doc" @click="duplicate(false, false)" v-if="transaction.type !== TransactionType.ModifyBalance"></f7-link>
                <f7-link icon-f7="ellipsis" @click="showMoreActionSheet = true"></f7-link>
                <f7-link icon-f7="checkmark_alt" :class="{ 'disabled': inputIsEmpty || submitting }" @click="save(AfterSaveAction.GoBack)" v-if="mode !== TransactionEditPageMode.View"></f7-link>
            </f7-nav-right>
        </f7-navbar>

        <template v-if="useQuickEditLayout">
            <div class="quick-edit-header">
                <div class="quick-edit-header-side">
                    <f7-link class="quick-edit-header-icon" icon-f7="multiply" :class="{ 'disabled': loading }" @click="goBack"></f7-link>
                </div>
                <f7-segmented strong round class="quick-edit-type-segmented">
                    <f7-button round :text="tt('Expense')" :active="transaction.type === TransactionType.Expense"
                               @click="switchTransactionType(TransactionType.Expense)"></f7-button>
                    <f7-button round :text="tt('Income')" :active="transaction.type === TransactionType.Income"
                               @click="switchTransactionType(TransactionType.Income)"></f7-button>
                    <f7-button round :text="tt('Transfer')" :active="transaction.type === TransactionType.Transfer"
                               @click="switchTransactionType(TransactionType.Transfer)"></f7-button>
                </f7-segmented>
                <div class="quick-edit-header-side quick-edit-header-side-right">
                    <f7-link class="quick-edit-header-icon" icon-f7="ellipsis" :class="{ 'disabled': loading }" @click="showMoreActionSheet = true"></f7-link>
                </div>
            </div>

            <div class="quick-edit-body" :class="{ 'disabled': loading || submitting }">
                <div class="quick-edit-category-area">
                    <div class="quick-edit-category-grid">
                        <div class="quick-edit-category-item" :key="category.id"
                             v-for="category in visibleCurrentTypeCategories"
                             @click="selectPrimaryCategory(category)">
                            <div class="quick-edit-category-icon" :class="{ 'active': category.id === selectedPrimaryCategoryId }"
                                 :style="getCategoryCircleStyle(category)">
                                <item-icon icon-type="category" :icon-id="category.icon" size="22px"
                                           :color="category.id === selectedPrimaryCategoryId ? 'FFFFFF' : undefined"></item-icon>
                            </div>
                            <div class="quick-edit-category-name" :class="{ 'active': category.id === selectedPrimaryCategoryId }">{{ category.name }}</div>
                        </div>
                    </div>
                    <div class="quick-edit-subcategory-bar" v-if="visibleSubCategoriesOfSelected.length">
                        <f7-chip class="quick-edit-subcategory-chip" :key="subCategory.id"
                                 :class="{ 'active': subCategory.id === transaction.categoryId }"
                                 v-for="subCategory in visibleSubCategoriesOfSelected"
                                 @click="selectSubCategory(subCategory)">{{ subCategory.name }}</f7-chip>
                    </div>
                    <div class="quick-edit-pictures" v-if="transaction.pictures && transaction.pictures.length > 0">
                        <swiper-container
                            :pagination="false"
                            :space-between="10"
                            :slides-per-view="'auto'"
                            class="transaction-pictures"
                        >
                            <swiper-slide class="transaction-picture-container" :key="picIdx"
                                          v-for="(pictureInfo, picIdx) in transaction.pictures"
                                          @click="viewOrRemovePicture(pictureInfo)">
                                <div class="transaction-picture">
                                    <div class="display-flex justify-content-center align-items-center transaction-picture-control-backdrop">
                                        <f7-icon class="picture-control-icon picture-remove-icon" f7="trash" v-if="pictureInfo.pictureId !== removingPictureId"></f7-icon>
                                        <f7-preloader color="white" :size="28" v-if="pictureInfo.pictureId === removingPictureId" />
                                    </div>
                                    <img alt="picture" :src="getTransactionPictureUrl(pictureInfo, true)"/>
                                </div>
                            </swiper-slide>
                        </swiper-container>
                    </div>
                </div>

                <div class="quick-edit-chips-bar">
                    <f7-chip class="quick-edit-chip" @click="showSourceAccountSheet = true" v-if="transaction.type !== TransactionType.Transfer">
                        <template #media><f7-icon f7="creditcard"></f7-icon></template>
                        <template #text>{{ sourceAccountName || tt('Account') }}</template>
                    </f7-chip>
                    <f7-chip class="quick-edit-chip" @click="showSourceAccountSheet = true" v-if="transaction.type === TransactionType.Transfer">
                        <template #media><f7-icon f7="minus"></f7-icon></template>
                        <template #text>{{ sourceAccountName || tt('Source Account') }}</template>
                    </f7-chip>
                    <f7-chip class="quick-edit-chip" @click="showDestinationAccountSheet = true" v-if="transaction.type === TransactionType.Transfer">
                        <template #media><f7-icon f7="plus"></f7-icon></template>
                        <template #text>{{ destinationAccountName || tt('Destination Account') }}</template>
                    </f7-chip>
                    <f7-chip class="quick-edit-chip" @click="showDateTimeDialog('date')">
                        <template #media><f7-icon f7="calendar"></f7-icon></template>
                        <template #text>{{ transactionTimeChipText }}</template>
                    </f7-chip>
                    <f7-chip class="quick-edit-chip" @click="showTransactionTagSheet = true">
                        <template #media><f7-icon f7="number"></f7-icon></template>
                        <template #text>{{ tagsChipText }}</template>
                    </f7-chip>
                    <f7-chip class="quick-edit-chip" @click="showOpenPictureDialog"
                             v-if="isTransactionPicturesEnabled() && canAddTransactionPicture">
                        <template #media><f7-icon f7="photo"></f7-icon></template>
                        <template #text>{{ picturesChipText }}</template>
                    </f7-chip>
                </div>

                <div class="quick-edit-input-bar" @click="activeAmountField = 'source'">
                    <input type="text" class="quick-edit-note-input"
                           :placeholder="tt('Tap to enter note')"
                           v-model="transaction.comment" />
                    <div class="quick-edit-amount" :class="[sourceAmountClass, { 'inactive': transaction.type === TransactionType.Transfer && activeAmountField !== 'source' }]">
                        <span class="quick-edit-amount-text">{{ sourceAmountDisplay }}</span>
                    </div>
                </div>
                <div class="quick-edit-input-bar quick-edit-input-bar-second"
                     v-if="transaction.type === TransactionType.Transfer"
                     @click="activeAmountField = 'destination'">
                    <span class="quick-edit-input-bar-label">{{ tt('Transfer In Amount') }}</span>
                    <div class="quick-edit-amount text-color-primary"
                         :class="{ 'inactive': activeAmountField !== 'destination' }">
                        <span class="quick-edit-amount-text">{{ destinationAmountDisplay }}</span>
                    </div>
                </div>

                <div class="quick-edit-keypad">
                    <f7-button class="quick-edit-key" @click="inputDigit(1)"><span class="quick-edit-key-text">{{ keypadDigits[1] }}</span></f7-button>
                    <f7-button class="quick-edit-key" @click="inputDigit(2)"><span class="quick-edit-key-text">{{ keypadDigits[2] }}</span></f7-button>
                    <f7-button class="quick-edit-key" @click="inputDigit(3)"><span class="quick-edit-key-text">{{ keypadDigits[3] }}</span></f7-button>
                    <f7-button class="quick-edit-key" @click="backspaceAmount" @taphold="clearAmountInput">
                        <span class="quick-edit-key-text"><f7-icon class="icon-with-direction" f7="delete_left"></f7-icon></span>
                    </f7-button>
                    <f7-button class="quick-edit-key" @click="inputDigit(4)"><span class="quick-edit-key-text">{{ keypadDigits[4] }}</span></f7-button>
                    <f7-button class="quick-edit-key" @click="inputDigit(5)"><span class="quick-edit-key-text">{{ keypadDigits[5] }}</span></f7-button>
                    <f7-button class="quick-edit-key" @click="inputDigit(6)"><span class="quick-edit-key-text">{{ keypadDigits[6] }}</span></f7-button>
                    <f7-button class="quick-edit-key" :class="{ 'quick-edit-key-active-side': transaction.type === TransactionType.Transfer && activeAmountField === 'source' }" @click="onMinusKey">
                        <span class="quick-edit-key-text">&minus;</span>
                    </f7-button>
                    <f7-button class="quick-edit-key" @click="inputDigit(7)"><span class="quick-edit-key-text">{{ keypadDigits[7] }}</span></f7-button>
                    <f7-button class="quick-edit-key" @click="inputDigit(8)"><span class="quick-edit-key-text">{{ keypadDigits[8] }}</span></f7-button>
                    <f7-button class="quick-edit-key" @click="inputDigit(9)"><span class="quick-edit-key-text">{{ keypadDigits[9] }}</span></f7-button>
                    <f7-button class="quick-edit-key" :class="{ 'quick-edit-key-active-side': transaction.type === TransactionType.Transfer && activeAmountField === 'destination' }" @click="onPlusKey">
                        <span class="quick-edit-key-text">&plus;</span>
                    </f7-button>
                    <f7-button class="quick-edit-key quick-edit-key-action" @click="save(AfterSaveAction.StayWithNewTransaction)" v-if="mode === TransactionEditPageMode.Add">
                        <span class="quick-edit-key-text">{{ tt('Record Again') }}</span>
                    </f7-button>
                    <f7-button class="quick-edit-key" @click="inputDigit(0)"><span class="quick-edit-key-text">{{ keypadDigits[0] }}</span></f7-button>
                    <f7-button class="quick-edit-key" @click="inputDecimalSeparator" v-if="amountFractionDigits > 0">
                        <span class="quick-edit-key-text">{{ decimalSeparator }}</span>
                    </f7-button>
                    <f7-button class="quick-edit-key" disabled v-else></f7-button>
                    <f7-button class="quick-edit-key quick-edit-key-save"
                               :class="{ 'quick-edit-key-span-2': mode !== TransactionEditPageMode.Add, 'disabled': inputIsEmpty || submitting }"
                               @click="save(AfterSaveAction.GoBack)">
                        <span class="quick-edit-key-text">{{ tt('Save') }}</span>
                    </f7-button>
                </div>
            </div>
        </template>

        <f7-block :class="{ 'no-margin-top margin-bottom': true, 'disabled': loading }" v-if="!useQuickEditLayout">
            <f7-segmented strong round :class="{ 'readonly': pageTypeAndMode?.type === TransactionEditPageType.Transaction && mode !== TransactionEditPageMode.Add }">
                <f7-button round :text="tt('Expense')" :active="transaction.type === TransactionType.Expense"
                           :disabled="pageTypeAndMode?.type === TransactionEditPageType.Transaction && mode !== TransactionEditPageMode.Add && transaction.type !== TransactionType.Expense"
                           v-if="transaction.type !== TransactionType.ModifyBalance"
                           @click="transaction.type = TransactionType.Expense"></f7-button>
                <f7-button round :text="tt('Income')" :active="transaction.type === TransactionType.Income"
                           :disabled="pageTypeAndMode?.type === TransactionEditPageType.Transaction && mode !== TransactionEditPageMode.Add && transaction.type !== TransactionType.Income"
                           v-if="transaction.type !== TransactionType.ModifyBalance"
                           @click="transaction.type = TransactionType.Income"></f7-button>
                <f7-button round :text="tt('Transfer')" :active="transaction.type === TransactionType.Transfer"
                           :disabled="pageTypeAndMode?.type === TransactionEditPageType.Transaction && mode !== TransactionEditPageMode.Add && transaction.type !== TransactionType.Transfer"
                           v-if="transaction.type !== TransactionType.ModifyBalance"
                           @click="transaction.type = TransactionType.Transfer"></f7-button>
                <f7-button round :text="tt('Modify Balance')" :active="transaction.type === TransactionType.ModifyBalance"
                           v-if="pageTypeAndMode?.type === TransactionEditPageType.Transaction && transaction.type === TransactionType.ModifyBalance"></f7-button>
            </f7-segmented>
        </f7-block>

        <f7-list strong inset dividers class="margin-vertical skeleton-text" v-if="loading && !useQuickEditLayout">
            <f7-list-input label="Template Name" placeholder="Template Name" v-if="pageTypeAndMode?.type === TransactionEditPageType.Template"></f7-list-input>
            <f7-list-item
                class="transaction-edit-amount ebk-large-amount"
                header="Expense Amount" title="0.00">
            </f7-list-item>
            <f7-list-item class="list-item-with-header-and-title list-item-title-hide-overflow" header="Category" title="Category Names" v-if="transaction.type !== TransactionType.ModifyBalance"></f7-list-item>
            <f7-list-item class="list-item-with-header-and-title" header="Account" title="Account Name"></f7-list-item>
            <f7-list-item class="list-item-with-header-and-title" header="Transaction Time" title="YYYY/MM/DD HH:mm:ss" v-if="pageTypeAndMode?.type === TransactionEditPageType.Transaction"></f7-list-item>
            <f7-list-item class="list-item-with-header-and-title" header="Scheduled Transaction Frequency" title="Every XXXXX" v-if="pageTypeAndMode?.type === TransactionEditPageType.Template && transaction instanceof TransactionTemplate && transaction.templateType === TemplateType.Schedule.type"></f7-list-item>
            <f7-list-item class="list-item-with-header-and-title list-item-title-hide-overflow list-item-no-item-after" header="Transaction Timezone" title="(UTC XX:XX) System Default" link="#" :no-chevron="mode === TransactionEditPageMode.View" v-if="pageTypeAndMode?.type === TransactionEditPageType.Transaction || (pageTypeAndMode?.type === TransactionEditPageType.Template && transaction instanceof TransactionTemplate && transaction.templateType === TemplateType.Schedule.type)"></f7-list-item>
            <f7-list-item class="list-item-with-header-and-title list-item-title-hide-overflow" header="Geographic Location" title="No Location" v-if="pageTypeAndMode?.type === TransactionEditPageType.Transaction"></f7-list-item>
            <f7-list-item header="Tags">
                <template #footer>
                    <f7-block class="margin-top-half no-padding no-margin">
                        <f7-chip class="transaction-edit-tag" text="None"></f7-chip>
                    </f7-block>
                </template>
            </f7-list-item>
            <f7-list-input type="textarea" label="Description" placeholder="Your transaction description (optional)"></f7-list-input>
        </f7-list>

        <f7-list form strong inset dividers class="margin-vertical" v-else-if="!loading && !useQuickEditLayout">
            <f7-list-input
                type="text"
                clear-button
                :label="tt('Template Name')"
                :placeholder="tt('Template Name')"
                v-model:value="transaction.name"
                v-if="pageTypeAndMode?.type === TransactionEditPageType.Template && transaction instanceof TransactionTemplate"
            ></f7-list-input>

            <f7-list-item
                class="transaction-edit-amount"
                :class="sourceAmountClass"
            >
                <template #header>{{ sourceAmountTitle }}</template>
                <template #title>
                    <input type="text"
                           class="amount-native-input-large"
                           :placeholder="tt('Enter amount')"
                           :value="isSourceAmountFocused ? sourceAmountInputValue : getDisplayAmount(transaction.sourceAmount, transaction.hideAmount, sourceAccountCurrency)"
                           inputmode="decimal"
                           @focus="onSourceAmountFocus"
                           @blur="onSourceAmountBlur"
                           @input="updateSourceAmount(($event.target as HTMLInputElement).value)"
                           v-if="transaction.type !== TransactionType.ModifyBalance" />
                </template>
            </f7-list-item>

            <f7-list-input
                type="textarea"
                class="transaction-edit-comment"
                style="height: auto"
                :class="{ 'readonly': mode === TransactionEditPageMode.View }"
                :label="tt('Description')"
                :placeholder="mode !== TransactionEditPageMode.View ? tt('Your transaction description (optional)') : ''"
                v-textarea-auto-size
                v-model:value="transaction.comment"
            ></f7-list-input>

            <f7-list-item
                class="transaction-edit-amount text-color-primary"
                :class="destinationAmountClass"
            >
                <template #header>{{ transferInAmountTitle }}</template>
                <template #title>
                    <input type="text"
                           class="amount-native-input-large"
                           :placeholder="tt('Enter amount')"
                           :value="isDestinationAmountFocused ? destinationAmountInputValue : getDisplayAmount(transaction.destinationAmount, transaction.hideAmount, destinationAccountCurrency)"
                           inputmode="decimal"
                           @focus="onDestinationAmountFocus"
                           @blur="onDestinationAmountBlur"
                           @input="updateDestinationAmount(($event.target as HTMLInputElement).value)"
                           v-if="transaction.type === TransactionType.Transfer" />
                </template>
            </f7-list-item>

            <f7-list-item
                class="list-item-with-header-and-title list-item-title-hide-overflow"
                key="expenseCategorySelection"
                link="#" no-chevron
                :class="{ 'disabled': !hasVisibleExpenseCategories, 'readonly': mode === TransactionEditPageMode.View }"
                :header="tt('Category')"
                @click="showCategorySheet = true"
                v-if="transaction.type === TransactionType.Expense"
            >
                <template #title>
                    <div class="list-item-custom-title" v-if="hasVisibleExpenseCategories">
                        <span>{{ getTransactionPrimaryCategoryName(transaction.expenseCategoryId, allCategories[CategoryType.Expense]) }}</span>
                        <f7-icon class="category-separate-icon icon-with-direction" f7="chevron_right"></f7-icon>
                        <span>{{ getTransactionSecondaryCategoryName(transaction.expenseCategoryId, allCategories[CategoryType.Expense]) }}</span>
                    </div>
                    <div class="list-item-custom-title" v-else-if="!hasVisibleExpenseCategories">
                        <span>{{ tt('None') }}</span>
                    </div>
                </template>
            </f7-list-item>

            <f7-list-item
                class="list-item-with-header-and-title list-item-title-hide-overflow"
                key="incomeCategorySelection"
                link="#" no-chevron
                :class="{ 'disabled': !hasVisibleIncomeCategories, 'readonly': mode === TransactionEditPageMode.View }"
                :header="tt('Category')"
                @click="showCategorySheet = true"
                v-if="transaction.type === TransactionType.Income"
            >
                <template #title>
                    <div class="list-item-custom-title" v-if="hasVisibleIncomeCategories">
                        <span>{{ getTransactionPrimaryCategoryName(transaction.incomeCategoryId, allCategories[CategoryType.Income]) }}</span>
                        <f7-icon class="category-separate-icon icon-with-direction" f7="chevron_right"></f7-icon>
                        <span>{{ getTransactionSecondaryCategoryName(transaction.incomeCategoryId, allCategories[CategoryType.Income]) }}</span>
                    </div>
                    <div class="list-item-custom-title" v-else-if="!hasVisibleIncomeCategories">
                        <span>{{ tt('None') }}</span>
                    </div>
                </template>
            </f7-list-item>

            <f7-list-item
                class="list-item-with-header-and-title list-item-title-hide-overflow"
                key="transferCategorySelection"
                link="#" no-chevron
                :class="{ 'disabled': !hasVisibleTransferCategories, 'readonly': mode === TransactionEditPageMode.View }"
                :header="tt('Category')"
                @click="showCategorySheet = true"
                v-if="transaction.type === TransactionType.Transfer"
            >
                <template #title>
                    <div class="list-item-custom-title" v-if="hasVisibleTransferCategories">
                        <span>{{ getTransactionPrimaryCategoryName(transaction.transferCategoryId, allCategories[CategoryType.Transfer]) }}</span>
                        <f7-icon class="category-separate-icon icon-with-direction" f7="chevron_right"></f7-icon>
                        <span>{{ getTransactionSecondaryCategoryName(transaction.transferCategoryId, allCategories[CategoryType.Transfer]) }}</span>
                    </div>
                    <div class="list-item-custom-title" v-else-if="!hasVisibleTransferCategories">
                        <span>{{ tt('None') }}</span>
                    </div>
                </template>
            </f7-list-item>

            <f7-list-item
                class="list-item-with-header-and-title"
                link="#" no-chevron
                :class="{ 'disabled': !allVisibleAccounts.length || (mode === TransactionEditPageMode.Edit && transaction.type === TransactionType.ModifyBalance), 'readonly': mode === TransactionEditPageMode.View }"
                :header="tt(sourceAccountTitle)"
                :title="sourceAccountName"
                @click="showSourceAccountSheet = true"
            >
            </f7-list-item>

            <f7-list-item
                class="list-item-with-header-and-title"
                link="#" no-chevron
                :class="{ 'disabled': !allVisibleAccounts.length, 'readonly': mode === TransactionEditPageMode.View }"
                :header="tt('Destination Account')"
                :title="destinationAccountName"
                v-if="transaction.type === TransactionType.Transfer"
                @click="showDestinationAccountSheet = true"
            >
            </f7-list-item>

            <f7-list-item
                class="transaction-edit-datetime list-item-with-header-and-title"
                link="#" no-chevron
                :class="{ 'disabled': mode === TransactionEditPageMode.Edit && transaction.type === TransactionType.ModifyBalance, 'readonly': mode === TransactionEditPageMode.View && transaction.utcOffset === currentTimezoneOffsetMinutes }"
                v-if="pageTypeAndMode?.type === TransactionEditPageType.Transaction"
            >
                <template #header>
                    <div class="transaction-edit-datetime-header" @click="showDateTimeDialog('date')">{{ tt('Transaction Time') }}</div>
                </template>
                <template #title>
                    <div class="transaction-edit-datetime-title" @click="showDateTimeDialog('date')">
                        <div>{{ transactionDisplayDate }}</div>&nbsp;<div class="transaction-edit-datetime-time" @click.stop="showDateTimeDialog('time')">{{ transactionDisplayTime }}</div>
                    </div>
                </template>
            </f7-list-item>

            <f7-list-item
                class="list-item-with-header-and-title"
                link="#" no-chevron
                :class="{ 'readonly': mode === TransactionEditPageMode.View }"
                :header="tt('Scheduled Transaction Frequency')"
                :title="transactionDisplayScheduledFrequency"
                @click="showTransactionScheduledFrequencySheet = true"
                v-if="pageTypeAndMode?.type === TransactionEditPageType.Template && transaction instanceof TransactionTemplate && transaction.templateType === TemplateType.Schedule.type"
            >
                <schedule-frequency-sheet v-model:show="showTransactionScheduledFrequencySheet"
                                          v-model:type="transaction.scheduledFrequencyType"
                                          v-model="transaction.scheduledFrequency">
                </schedule-frequency-sheet>
            </f7-list-item>

            <f7-list-item
                class="transaction-edit-datetime list-item-with-header-and-title"
                link="#" no-chevron
                :class="{ 'readonly': mode === TransactionEditPageMode.View }"
                :header="tt('Start Date')"
                :title="transactionDisplayScheduledStartDate"
                @click="showScheduledStartDateSheet = true"
                v-if="pageTypeAndMode?.type === TransactionEditPageType.Template && transaction instanceof TransactionTemplate && transaction.templateType === TemplateType.Schedule.type"
            >
                <date-selection-sheet v-model:show="showScheduledStartDateSheet"
                                      v-model="transaction.scheduledStartDate">
                </date-selection-sheet>
            </f7-list-item>

            <f7-list-item
                class="transaction-edit-datetime list-item-with-header-and-title"
                link="#" no-chevron
                :class="{ 'readonly': mode === TransactionEditPageMode.View }"
                :header="tt('End Date')"
                :title="transactionDisplayScheduledEndDate"
                @click="showScheduledEndDateSheet = true"
                v-if="pageTypeAndMode?.type === TransactionEditPageType.Template && transaction instanceof TransactionTemplate && transaction.templateType === TemplateType.Schedule.type"
            >
                <date-selection-sheet v-model:show="showScheduledEndDateSheet"
                                      v-model="transaction.scheduledEndDate">
                </date-selection-sheet>
            </f7-list-item>

            <f7-list-item
                :no-chevron="mode === TransactionEditPageMode.View"
                link="#"
                class="list-item-with-header-and-title list-item-title-hide-overflow list-item-no-item-after"
                :class="{ 'disabled': mode === TransactionEditPageMode.Edit && transaction.type === TransactionType.ModifyBalance, 'readonly': mode === TransactionEditPageMode.View }"
                :header="tt('Transaction Timezone')"
                v-if="pageTypeAndMode?.type === TransactionEditPageType.Transaction || (pageTypeAndMode?.type === TransactionEditPageType.Template && transaction instanceof TransactionTemplate && transaction.templateType === TemplateType.Schedule.type)"
                @click="showTimezonePopup = true"
            >
                <template #title>
                    <f7-block class="list-item-custom-title no-padding no-margin">
                        <span>{{ `(${transactionDisplayTimezone})` }}</span>
                        <span class="transaction-edit-timezone-name" v-if="transaction.timeZone || transaction.timeZone === ''">{{ transactionDisplayTimezoneName }}</span>
                        <span class="transaction-edit-timezone-name" v-else-if="!transaction.timeZone && transaction.timeZone !== ''">{{ transactionTimezoneTimeDifference }}</span>
                    </f7-block>
                </template>
            </f7-list-item>

            <f7-list-item
                link="#" no-chevron
                class="list-item-with-header-and-title list-item-title-hide-overflow"
                :class="{ 'readonly': mode === TransactionEditPageMode.View && !transaction.geoLocation }"
                :header="tt('Geographic Location')"
                @click="showGeoLocationActionSheet = true"
                v-if="pageTypeAndMode?.type === TransactionEditPageType.Transaction"
            >
                <template #title>
                    <f7-block class="list-item-custom-title no-padding no-margin">
                        <span v-if="transaction.geoLocation">{{ `(${formatCoordinate(transaction.geoLocation, coordinateDisplayType)})` }}</span>
                        <span v-else-if="!transaction.geoLocation">{{ geoLocationStatusInfo }}</span>
                    </f7-block>
                </template>
            </f7-list-item>

            <f7-list-item
                link="#" no-chevron
                :class="{ 'readonly': mode === TransactionEditPageMode.View }"
                :header="tt('Tags')"
                @click="showTransactionTagSheet = true"
            >
                <template #footer>
                    <f7-block class="margin-top-half no-padding no-margin" v-if="transaction.tagIds && transaction.tagIds.length">
                        <f7-chip media-text-color="var(--f7-chip-text-color)" class="transaction-edit-tag"
                                 :text="allTagsMap[tagId]?.name ?? ''"
                                 :key="tagId"
                                 v-for="tagId in transaction.tagIds">
                            <template #media>
                                <f7-icon f7="number"></f7-icon>
                            </template>
                        </f7-chip>
                    </f7-block>
                    <f7-block class="margin-top-half no-padding no-margin" v-else-if="!transaction.tagIds || !transaction.tagIds.length">
                        <f7-chip class="transaction-edit-tag" :text="tt('None')">
                        </f7-chip>
                    </f7-block>
                </template>
            </f7-list-item>

            <f7-list-item
                link="#" no-chevron
                :header="tt('Pictures')"
                v-if="showTransactionPictures || (transaction.pictures && transaction.pictures.length > 0)"
            >
                <template #footer>
                    <f7-block class="margin-top-half no-padding no-margin" :class="{ 'readonly': submitting || uploadingPicture || removingPictureId }">
                        <swiper-container
                            :pagination="false"
                            :space-between="10"
                            :slides-per-view="'auto'"
                            class="transaction-pictures"
                        >
                            <swiper-slide class="transaction-picture-container" :key="picIdx"
                                          v-for="(pictureInfo, picIdx) in transaction.pictures"
                                          @click="viewOrRemovePicture(pictureInfo)">
                                <div class="transaction-picture">
                                    <div class="display-flex justify-content-center align-items-center transaction-picture-control-backdrop"
                                         v-if="mode === TransactionEditPageMode.Add || mode === TransactionEditPageMode.Edit">
                                        <f7-icon class="picture-control-icon picture-remove-icon" f7="trash" v-if="pictureInfo.pictureId !== removingPictureId"></f7-icon>
                                        <f7-preloader color="white" :size="28" v-if="pictureInfo.pictureId === removingPictureId" />
                                    </div>
                                    <img alt="picture" :src="getTransactionPictureUrl(pictureInfo, true)"/>
                                </div>
                            </swiper-slide>
                            <swiper-slide @click="showOpenPictureDialog" v-if="canAddTransactionPicture">
                                <div class="display-flex justify-content-center align-items-center transaction-picture transaction-picture-add">
                                    <f7-icon class="picture-control-icon" f7="plus" v-if="!uploadingPicture"></f7-icon>
                                    <f7-preloader :size="28" v-if="uploadingPicture" />
                                </div>
                            </swiper-slide>
                        </swiper-container>
                    </f7-block>
                </template>
            </f7-list-item>

        </f7-list>

        <tree-view-selection-sheet primary-key-field="id" primary-title-field="name"
                                   primary-icon-field="icon" primary-icon-type="category" primary-color-field="color"
                                   primary-hidden-field="hidden" primary-sub-items-field="subCategories"
                                   secondary-key-field="id" secondary-value-field="id" secondary-title-field="name"
                                   secondary-icon-field="icon" secondary-icon-type="category" secondary-color-field="color"
                                   secondary-hidden-field="hidden"
                                   :enable-filter="true" :filter-placeholder="tt('Find category')" :filter-no-items-text="tt('No available category')"
                                   :items="allCategories[CategoryType.Expense]"
                                   v-model:show="showCategorySheet"
                                   v-model="transaction.expenseCategoryId"
                                   v-if="transaction.type === TransactionType.Expense">
        </tree-view-selection-sheet>
        <tree-view-selection-sheet primary-key-field="id" primary-title-field="name"
                                   primary-icon-field="icon" primary-icon-type="category" primary-color-field="color"
                                   primary-hidden-field="hidden" primary-sub-items-field="subCategories"
                                   secondary-key-field="id" secondary-value-field="id" secondary-title-field="name"
                                   secondary-icon-field="icon" secondary-icon-type="category" secondary-color-field="color"
                                   secondary-hidden-field="hidden"
                                   :enable-filter="true" :filter-placeholder="tt('Find category')" :filter-no-items-text="tt('No available category')"
                                   :items="allCategories[CategoryType.Income]"
                                   v-model:show="showCategorySheet"
                                   v-model="transaction.incomeCategoryId"
                                   v-if="transaction.type === TransactionType.Income">
        </tree-view-selection-sheet>
        <tree-view-selection-sheet primary-key-field="id" primary-title-field="name"
                                   primary-icon-field="icon" primary-icon-type="category" primary-color-field="color"
                                   primary-hidden-field="hidden" primary-sub-items-field="subCategories"
                                   secondary-key-field="id" secondary-value-field="id" secondary-title-field="name"
                                   secondary-icon-field="icon" secondary-icon-type="category" secondary-color-field="color"
                                   secondary-hidden-field="hidden"
                                   :enable-filter="true" :filter-placeholder="tt('Find category')" :filter-no-items-text="tt('No available category')"
                                   :items="allCategories[CategoryType.Transfer]"
                                   v-model:show="showCategorySheet"
                                   v-model="transaction.transferCategoryId"
                                   v-if="transaction.type === TransactionType.Transfer">
        </tree-view-selection-sheet>

        <two-column-list-item-selection-sheet primary-key-field="id" primary-value-field="category"
                                              primary-title-field="name" primary-footer-field="displayBalance"
                                              primary-icon-field="icon" primary-icon-type="account"
                                              primary-sub-items-field="accounts"
                                              :primary-title-i18n="true"
                                              secondary-key-field="id" secondary-value-field="id"
                                              secondary-title-field="name" secondary-footer-field="displayBalance"
                                              secondary-icon-field="icon" secondary-icon-type="account" secondary-color-field="color"
                                              :enable-filter="true" :filter-placeholder="tt('Find account')" :filter-no-items-text="tt('No available account')"
                                              :items="allVisibleCategorizedAccounts"
                                              v-model:show="showSourceAccountSheet"
                                              v-model="transaction.sourceAccountId">
        </two-column-list-item-selection-sheet>
        <two-column-list-item-selection-sheet primary-key-field="id" primary-value-field="category"
                                              primary-title-field="name" primary-footer-field="displayBalance"
                                              primary-icon-field="icon" primary-icon-type="account"
                                              primary-sub-items-field="accounts"
                                              :primary-title-i18n="true"
                                              secondary-key-field="id" secondary-value-field="id"
                                              secondary-title-field="name" secondary-footer-field="displayBalance"
                                              secondary-icon-field="icon" secondary-icon-type="account" secondary-color-field="color"
                                              :enable-filter="true" :filter-placeholder="tt('Find account')" :filter-no-items-text="tt('No available account')"
                                              :items="allVisibleCategorizedAccounts"
                                              v-model:show="showDestinationAccountSheet"
                                              v-model="transaction.destinationAccountId">
        </two-column-list-item-selection-sheet>

        <date-time-selection-sheet :init-mode="transactionDateTimeSheetMode"
                                   :timezone-utc-offset="transaction.utcOffset"
                                   :model-value="transaction.time"
                                   v-model:show="showTransactionDateTimeSheet"
                                   @update:model-value="updateTransactionTime">
        </date-time-selection-sheet>

        <list-item-selection-popup value-type="item"
                                   key-field="name" value-field="name"
                                   title-field="displayNameWithUtcOffset"
                                   :title="tt('Transaction Timezone')"
                                   :enable-filter="true"
                                   :filter-placeholder="tt('Timezone')"
                                   :filter-no-items-text="tt('No results')"
                                   :items="allTimezones"
                                   :model-value="transaction.timeZone"
                                   v-model:show="showTimezonePopup"
                                   @update:model-value="updateTransactionTimezone">
        </list-item-selection-popup>

        <map-sheet :readonly="mode === TransactionEditPageMode.View"
                   v-model="transaction.geoLocation"
                   v-model:set-geo-location-by-click-map="setGeoLocationByClickMap"
                   v-model:show="showGeoLocationMapSheet">
        </map-sheet>

        <transaction-tag-selection-sheet :allow-add-new-tag="true" :enable-filter="true"
                                         v-model:show="showTransactionTagSheet"
                                         v-model="transaction.tagIds">
        </transaction-tag-selection-sheet>

        <f7-actions close-by-outside-click close-on-escape :opened="showGeoLocationActionSheet" @actions:closed="showGeoLocationActionSheet = false">
            <f7-actions-group>
                <f7-actions-button v-if="mode !== TransactionEditPageMode.View" @click="updateGeoLocation(true)">{{ tt('Update Geographic Location') }}</f7-actions-button>
                <f7-actions-button v-if="mode !== TransactionEditPageMode.View" @click="clearGeoLocation">{{ tt('Clear Geographic Location') }}</f7-actions-button>
            </f7-actions-group>
            <f7-actions-group v-if="!!getMapProvider()">
                <f7-actions-button :class="{ 'disabled': !transaction.geoLocation }" @click="setGeoLocationByClickMap = false; showGeoLocationMapSheet = true">{{ tt('Show on the map') }}</f7-actions-button>
            </f7-actions-group>
            <f7-actions-group>
                <f7-actions-button bold close>{{ tt('Cancel') }}</f7-actions-button>
            </f7-actions-group>
        </f7-actions>

        <f7-actions close-by-outside-click close-on-escape :opened="showMoreActionSheet" @actions:closed="showMoreActionSheet = false">
            <f7-actions-group v-if="mode !== TransactionEditPageMode.View && transaction.type === TransactionType.Transfer">
                <f7-actions-button @click="swapTransactionData(true, false)">{{ tt('Swap Account') }}</f7-actions-button>
                <f7-actions-button @click="swapTransactionData(false, true)">{{ tt('Swap Amount') }}</f7-actions-button>
                <f7-actions-button @click="swapTransactionData(true, true)">{{ tt('Swap Account and Amount') }}</f7-actions-button>
            </f7-actions-group>
            <f7-actions-group v-if="mode !== TransactionEditPageMode.View">
                <f7-actions-button v-if="isSupportClipboard && !isiOS()" @click="pasteAmount('sourceAmount')">{{ tt('Paste Amount') }}</f7-actions-button>
                <f7-actions-button v-if="isSupportClipboard && !isiOS() && transaction.type === TransactionType.Transfer" @click="pasteAmount('destinationAmount')">{{ tt('Paste Destination Amount') }}</f7-actions-button>
                <f7-actions-button v-if="transaction.hideAmount" @click="transaction.hideAmount = false">{{ tt('Show Amount') }}</f7-actions-button>
                <f7-actions-button v-if="!transaction.hideAmount" @click="transaction.hideAmount = true">{{ tt('Hide Amount') }}</f7-actions-button>
            </f7-actions-group>
            <f7-actions-group v-if="pageTypeAndMode?.type === TransactionEditPageType.Transaction && (mode === TransactionEditPageMode.Add || mode === TransactionEditPageMode.Edit) && isTransactionPicturesEnabled() && !showTransactionPictures && !useQuickEditLayout">
                <f7-actions-button @click="showTransactionPictures = true">{{ tt('Add Picture') }}</f7-actions-button>
            </f7-actions-group>
            <f7-actions-group v-if="useQuickEditLayout">
                <f7-actions-button @click="showGeoLocationActionSheet = true">{{ tt('Geographic Location') }}</f7-actions-button>
                <f7-actions-button @click="showTimezonePopup = true">{{ tt('Transaction Timezone') }}</f7-actions-button>
                <f7-actions-button v-if="mode === TransactionEditPageMode.Edit && transaction.type !== TransactionType.ModifyBalance" @click="duplicate(false, false)">{{ tt('Duplicate') }}</f7-actions-button>
            </f7-actions-group>
            <f7-actions-group v-if="pageTypeAndMode?.type === TransactionEditPageType.Transaction && mode === TransactionEditPageMode.View && transaction.type !== TransactionType.ModifyBalance">
                <f7-actions-button @click="duplicate(false, false)">{{ tt('Duplicate') }}</f7-actions-button>
                <f7-actions-button @click="duplicate(true, false)">{{ tt('Duplicate (With Time)') }}</f7-actions-button>
                <f7-actions-button @click="duplicate(false, true)" v-if="transaction.geoLocation">{{ tt('Duplicate (With Geographic Location)') }}</f7-actions-button>
                <f7-actions-button @click="duplicate(true, true)" v-if="transaction.geoLocation">{{ tt('Duplicate (With Time and Geographic Location)') }}</f7-actions-button>
            </f7-actions-group>
            <f7-actions-group>
                <f7-actions-button bold close>{{ tt('Cancel') }}</f7-actions-button>
            </f7-actions-group>
        </f7-actions>

        <template #fixed>
            <f7-fab id="quick-save-button" :class="{ 'disabled': inputIsEmpty || submitting }" :position="quickSaveButtonFloatingPosition"
                    :text="tt(quickSaveButtonTitle)"
                    @click="quickSave"
                    v-if="(quickSaveButtonStyleType === TransactionQuickSaveButtonStyle.BottomLeftFloating.type || quickSaveButtonStyleType === TransactionQuickSaveButtonStyle.BottomCenterFloating.type || quickSaveButtonStyleType === TransactionQuickSaveButtonStyle.BottomRightFloating.type) && mode !== TransactionEditPageMode.View && !useQuickEditLayout">
            </f7-fab>
            <f7-fab id="copy-button" position="center-bottom" color="primary"
                    @click="duplicate(false, false)"
                    v-if="mode === TransactionEditPageMode.View && transaction.type !== TransactionType.ModifyBalance">
                <f7-icon f7="doc_on_doc"></f7-icon>
            </f7-fab>
        </template>

        <f7-toolbar id="quick-save-button" tabbar bottom v-if="quickSaveButtonStyleType === TransactionQuickSaveButtonStyle.BottomFixed.type && mode !== TransactionEditPageMode.View && !useQuickEditLayout">
            <f7-link :class="{ 'disabled': inputIsEmpty || submitting }" @click="quickSave">
                <span class="tabbar-primary-link">{{ tt(quickSaveButtonTitle) }}</span>
            </f7-link>
        </f7-toolbar>

        <f7-popover class="quick-save-popover" target-el="#quick-save-button"
                    v-model:opened="showQuickSavePopover">
            <f7-list>
                <f7-list-item link="#" no-chevron popover-close
                              :title="tt(TransactionQuickAddButtonActionType.SaveAndGoBack.name)"
                              @click="save(AfterSaveAction.GoBack)"></f7-list-item>
                <f7-list-item link="#" no-chevron popover-close
                              :title="tt(TransactionQuickAddButtonActionType.SaveAndAddNewTransaction.name)"
                              @click="save(AfterSaveAction.StayWithNewTransaction)"></f7-list-item>
                <f7-list-item link="#" no-chevron popover-close
                              :title="tt(TransactionQuickAddButtonActionType.SaveAndKeepCurrentData.name)"
                              @click="save(AfterSaveAction.StayWithCurrentTransaction)"></f7-list-item>
            </f7-list>
        </f7-popover>

        <f7-photo-browser ref="pictureBrowser" type="popup" navbar-of-text="/"
                          :navbar-show-count="true" :exposition="false"
                          :photos="transactionPictures" :thumbs="transactionThumbs" />
        <input ref="pictureInput" type="file" style="display: none" :accept="`${SUPPORTED_IMAGE_EXTENSIONS};capture=camera`" @change="uploadPicture($event)" />
    </f7-page>
</template>

<script setup lang="ts">
import { ref, computed, watch, useTemplateRef } from 'vue';
import type { PhotoBrowser, Router } from 'framework7/types';

import { useI18n } from '@/locales/helpers.ts';
import { useI18nUIComponents, isiOS, showLoading, hideLoading } from '@/lib/ui/mobile.ts';
import {
    TransactionEditPageMode,
    TransactionEditPageType,
    GeoLocationStatus,
    AfterSaveAction,
    useTransactionEditPageBase
} from '@/views/base/transactions/TransactionEditPageBase.ts';

import { useSettingsStore } from '@/stores/setting.ts';
import { useUserStore } from '@/stores/user.ts';
import { useAccountsStore } from '@/stores/account.ts';
import { useTransactionCategoriesStore } from '@/stores/transactionCategory.ts';
import { useTransactionTagsStore } from '@/stores/transactionTag.ts';
import { useTransactionsStore } from '@/stores/transaction.ts';
import { useTransactionTemplatesStore } from '@/stores/transactionTemplate.ts';

import { CategoryType } from '@/core/category.ts';
import {
    TransactionType,
    TransactionEditScopeType,
    TransactionQuickSaveButtonStyle,
    TransactionQuickAddButtonActionType
} from '@/core/transaction.ts';
import { ScheduledTemplateFrequencyType, TemplateType } from '@/core/template.ts';

import { TRANSACTION_MAX_AMOUNT, TRANSACTION_MIN_AMOUNT } from '@/consts/transaction.ts';
import { KnownErrorCode } from '@/consts/api.ts';
import { SUPPORTED_IMAGE_EXTENSIONS } from '@/consts/file.ts';

import { TransactionTemplate } from '@/models/transaction_template.ts';
import type { TransactionPictureInfoBasicResponse } from '@/models/transaction_picture_info.ts';
import type { TransactionCategory } from '@/models/transaction_category.ts';
import { Transaction } from '@/models/transaction.ts';

import {
    getTimezoneOffset,
    getTimezoneOffsetMinutes,
    parseDateTimeFromUnixTimeWithTimezoneOffset,
    getCurrentUnixTime
} from '@/lib/datetime.ts';
import { formatCoordinate } from '@/lib/coordinate.ts';
import { generateRandomUUID } from '@/lib/misc.ts';
import { isNumber } from '@/lib/common.ts';
import { compressTransactionPicture } from '@/lib/ui/common.ts';
import {
    getTransactionPrimaryCategoryName,
    getTransactionSecondaryCategoryName,
    transactionTypeToCategoryType,
    allVisiblePrimaryTransactionCategoriesByType
} from '@/lib/category.ts';
import { type SetTransactionOptions } from '@/lib/transaction.ts';
import { getMapProvider, isTransactionPicturesEnabled } from '@/lib/server_settings.ts';
import { ALL_CURRENCIES } from '@/consts/currency.ts';
import { DEFAULT_CATEGORY_COLOR } from '@/consts/color.ts';
import logger from '@/lib/logger.ts';

const props = defineProps<{
    f7route: Router.Route;
    f7router: Router.Router;
}>();

const query = props.f7route.query;
const pageTypeAndMode = getPageTypeNameMode();

const {
    tt,
    getMultiMonthAndDayLongNames,
    getMultiMonthdayShortNames,
    getMultiWeekdayLongNames,
    formatDateTimeToLongDate,
    formatDateTimeToLongTime,
    formatDateTimeToShortDate,
    formatGregorianTextualYearMonthDayToLongDate,
    parseAmountFromLocalizedNumerals,
    parseAmountFromWesternArabicNumerals,
    formatAmountToWesternArabicNumeralsWithoutDigitGrouping,
    getAllLocalizedDigits,
    getCurrentDecimalSeparator
} = useI18n();
const { showAlert, showConfirm, showToast, routeBackOnError } = useI18nUIComponents();

const {
    mode,
    isSupportGeoLocation,
    editId,
    addByTemplateId,
    duplicateFromId,
    clientSessionId,
    loading,
    submitting,
    submitted,
    uploadingPicture,
    geoLocationStatus,
    setGeoLocationByClickMap,
    transaction,
    numeralSystem,
    currentTimezoneOffsetMinutes,
    defaultCurrency,
    firstDayOfWeek,
    coordinateDisplayType,
    allTimezones,
    allVisibleAccounts,
    allVisibleCategorizedAccounts,
    allCategories,
    allCategoriesMap,
    allTagsMap,
    firstVisibleAccountId,
    hasVisibleExpenseCategories,
    hasVisibleIncomeCategories,
    hasVisibleTransferCategories,
    canAddTransactionPicture,
    title,
    quickSaveButtonTitle,
    sourceAmountTitle,
    sourceAccountTitle,
    transferInAmountTitle,
    sourceAccountName,
    destinationAccountName,
    sourceAccountCurrency,
    destinationAccountCurrency,
    transactionDisplayTimezone,
    transactionTimezoneTimeDifference,
    geoLocationStatusInfo,
    inputEmptyProblemMessage,
    inputIsEmpty,
    setTransactionModel,
    updateTransactionModelByAfterSaveAction,
    updateTransactionTime,
    updateTransactionTimezone,
    swapTransactionData,
    getDisplayAmount,
    getTransactionPictureUrl
} = useTransactionEditPageBase(pageTypeAndMode?.type || TransactionEditPageType.Transaction, pageTypeAndMode?.mode, query['type'] ? parseInt(query['type']) : undefined);

const settingsStore = useSettingsStore();
const userStore = useUserStore();
const accountsStore = useAccountsStore();
const transactionCategoriesStore = useTransactionCategoriesStore();
const transactionTagsStore = useTransactionTagsStore();
const transactionsStore = useTransactionsStore();
const transactionTemplatesStore = useTransactionTemplatesStore();

const pictureBrowser = useTemplateRef<PhotoBrowser.PhotoBrowser>('pictureBrowser');
const pictureInput = useTemplateRef<HTMLInputElement>('pictureInput');

const isSupportClipboard = !!navigator.clipboard;

const loadingError = ref<unknown | null>(null);
const removingPictureId = ref<string | null>(null);
const transactionDateTimeSheetMode = ref<string>('time');
const showTimeInDefaultTimezone = ref<boolean>(false);
const showQuickSavePopover = ref<boolean>(false);
const showTimezonePopup = ref<boolean>(false);
const showGeoLocationActionSheet = ref<boolean>(false);
const showMoreActionSheet = ref<boolean>(false);
const showCategorySheet = ref<boolean>(false);
const showSourceAccountSheet = ref<boolean>(false);
const showDestinationAccountSheet = ref<boolean>(false);
const showTransactionDateTimeSheet = ref<boolean>(false);
const showTransactionScheduledFrequencySheet = ref<boolean>(false);
const showScheduledStartDateSheet = ref<boolean>(false);
const showScheduledEndDateSheet = ref<boolean>(false);
const showGeoLocationMapSheet = ref<boolean>(false);
const showTransactionTagSheet = ref<boolean>(false);
const showTransactionPictures = ref<boolean>(pageTypeAndMode?.type === TransactionEditPageType.Transaction
    && (pageTypeAndMode?.mode === TransactionEditPageMode.Add || pageTypeAndMode?.mode === TransactionEditPageMode.Edit)
    && settingsStore.appSettings.alwaysShowTransactionPicturesInMobileTransactionEditPage);

// Amount input editing state
const sourceAmountInputValue = ref<string>('');
const destinationAmountInputValue = ref<string>('');
const isSourceAmountFocused = ref<boolean>(false);
const isDestinationAmountFocused = ref<boolean>(false);
const shouldClearAmountOnFocus = ref<boolean>(false);

// Quick edit layout state
const activeAmountField = ref<'source' | 'destination'>('source');
const sourceAmountKeypadValue = ref<string>('');
const destinationAmountKeypadValue = ref<string>('');

const quickSaveButtonStyleType = computed<number>(() => settingsStore.appSettings.quickSaveButtonStyleInMobileTransactionListPage);
const quickSaveButtonFloatingPosition = computed<string>(() => {
    switch (settingsStore.appSettings.quickSaveButtonStyleInMobileTransactionListPage) {
        case TransactionQuickSaveButtonStyle.BottomLeftFloating.type:
            return 'left-bottom';
        case TransactionQuickSaveButtonStyle.BottomCenterFloating.type:
            return 'center-bottom';
        case TransactionQuickSaveButtonStyle.BottomRightFloating.type:
            return 'right-bottom';
        default:
            return 'right-bottom';
    }
});

const sourceAmountClass = computed<Record<string, boolean>>(() => {
    const classes: Record<string, boolean> = {
        'readonly': mode.value === TransactionEditPageMode.View,
        'text-expense': transaction.value.type === TransactionType.Expense,
        'text-income': transaction.value.type === TransactionType.Income,
        'text-color-primary': transaction.value.type === TransactionType.Transfer
    };

    classes[getFontClassByAmount(transaction.value.sourceAmount)] = true;

    return classes;
});

const useQuickEditLayout = computed<boolean>(() => {
    if (pageTypeAndMode?.type !== TransactionEditPageType.Transaction) {
        return false;
    }

    if (mode.value !== TransactionEditPageMode.Add && mode.value !== TransactionEditPageMode.Edit) {
        return false;
    }

    return transaction.value.type !== TransactionType.ModifyBalance;
});

const visibleCurrentTypeCategories = computed<TransactionCategory[]>(() => {
    const categoryType = transactionTypeToCategoryType(transaction.value.type);

    if (categoryType === null) {
        return [];
    }

    return allVisiblePrimaryTransactionCategoriesByType(allCategories.value, categoryType);
});

const selectedPrimaryCategoryId = computed<string>(() => {
    const categoryId = transaction.value.categoryId;

    if (!categoryId) {
        return '';
    }

    const category = allCategoriesMap.value[categoryId];

    if (!category) {
        return '';
    }

    return category.parentId && category.parentId !== '0' ? category.parentId : category.id;
});

const selectedPrimaryCategory = computed<TransactionCategory | null>(() => {
    return visibleCurrentTypeCategories.value.find(category => category.id === selectedPrimaryCategoryId.value) ?? null;
});

const visibleSubCategoriesOfSelected = computed<TransactionCategory[]>(() => {
    return (selectedPrimaryCategory.value?.subCategories ?? []).filter(subCategory => !subCategory.hidden);
});

const keypadDigits = computed<string[]>(() => getAllLocalizedDigits());
const decimalSeparator = computed<string>(() => getCurrentDecimalSeparator());

const amountFractionDigits = computed<number>(() => {
    const currency = activeAmountField.value === 'destination' ? destinationAccountCurrency.value : sourceAccountCurrency.value;
    const currencyInfo = currency ? ALL_CURRENCIES[currency] : undefined;

    if (!currencyInfo || !isNumber(currencyInfo.fraction)) {
        return 2;
    }

    return currencyInfo.fraction;
});

const transactionTimeChipText = computed<string>(() => {
    const dateTime = parseDateTimeFromUnixTimeWithTimezoneOffset(transaction.value.time, transaction.value.utcOffset);
    const todayDateTime = parseDateTimeFromUnixTimeWithTimezoneOffset(getCurrentUnixTime(), transaction.value.utcOffset);

    if (formatDateTimeToShortDate(dateTime) === formatDateTimeToShortDate(todayDateTime)) {
        return tt('Today');
    }

    return formatDateTimeToShortDate(dateTime);
});

const tagsChipText = computed<string>(() => {
    if (transaction.value.tagIds && transaction.value.tagIds.length) {
        return `${tt('Tags')} (${transaction.value.tagIds.length})`;
    }

    return tt('Tags');
});

const picturesChipText = computed<string>(() => {
    const count = transaction.value.pictures ? transaction.value.pictures.length : 0;

    if (count) {
        return `${tt('Pictures')} (${count})`;
    }

    return tt('Pictures');
});

const sourceAmountDisplay = computed<string>(() => {
    if (transaction.value.hideAmount) {
        return getDisplayAmount(transaction.value.sourceAmount, true, sourceAccountCurrency.value);
    }

    return getKeypadDisplayText(sourceAmountKeypadValue.value, sourceAccountCurrency.value);
});

const destinationAmountDisplay = computed<string>(() => {
    if (transaction.value.hideAmount) {
        return getDisplayAmount(transaction.value.destinationAmount, true, destinationAccountCurrency.value);
    }

    return getKeypadDisplayText(destinationAmountKeypadValue.value, destinationAccountCurrency.value);
});

watch(() => transaction.value.sourceAmount, (newValue) => {
    if (parseAmountFromWesternArabicNumerals(sourceAmountKeypadValue.value) === newValue) {
        return;
    }

    sourceAmountKeypadValue.value = amountCentsToKeypadValue(newValue, sourceAccountCurrency.value);
});

watch(() => transaction.value.destinationAmount, (newValue) => {
    if (parseAmountFromWesternArabicNumerals(destinationAmountKeypadValue.value) === newValue) {
        return;
    }

    destinationAmountKeypadValue.value = amountCentsToKeypadValue(newValue, destinationAccountCurrency.value);
});

const destinationAmountClass = computed<Record<string, boolean>>(() => {
    const classes: Record<string, boolean> = {
        'readonly': mode.value === TransactionEditPageMode.View
    };

    classes[getFontClassByAmount(transaction.value.destinationAmount)] = true;

    return classes;
});

const transactionDisplayDate = computed<string>(() => {
    if (mode.value !== TransactionEditPageMode.View || !showTimeInDefaultTimezone.value) {
        const dateTime = parseDateTimeFromUnixTimeWithTimezoneOffset(transaction.value.time, transaction.value.utcOffset);
        return formatDateTimeToLongDate(dateTime);
    }

    const dateTime = parseDateTimeFromUnixTimeWithTimezoneOffset(transaction.value.time, getTimezoneOffsetMinutes(transaction.value.time));
    return formatDateTimeToLongDate(dateTime);
});

const transactionDisplayTime = computed<string>(() => {
    if (mode.value !== TransactionEditPageMode.View || !showTimeInDefaultTimezone.value) {
        const dateTime = parseDateTimeFromUnixTimeWithTimezoneOffset(transaction.value.time, transaction.value.utcOffset);
        return formatDateTimeToLongTime(dateTime);
    }

    const dateTime = parseDateTimeFromUnixTimeWithTimezoneOffset(transaction.value.time, getTimezoneOffsetMinutes(transaction.value.time));
    const utcOffset = numeralSystem.value.replaceWesternArabicDigitsToLocalizedDigits(getTimezoneOffset(transaction.value.time));
    return `${formatDateTimeToLongTime(dateTime)} (UTC${utcOffset})`;
});

const transactionDisplayTimezoneName = computed<string>(() => {
    for (const timezone of allTimezones.value) {
        if (timezone.name === transaction.value.timeZone) {
            return timezone.displayName;
        }
    }

    return '';
});

const transactionPictures = computed<Record<string, string | undefined>[]>(() => {
    const thumbs: Record<string, string | undefined>[] = [];

    if (!transaction.value.pictures || !transaction.value.pictures.length) {
        return thumbs;
    }

    for (const picture of transaction.value.pictures) {
        thumbs.push({
            url: getTransactionPictureUrl(picture)
        });
    }

    return thumbs;
});

const transactionThumbs = computed<(string | undefined)[]>(() => {
    const thumbs: (string | undefined)[] = [];

    if (!transaction.value.pictures || !transaction.value.pictures.length) {
        return thumbs;
    }

    for (const picture of transaction.value.pictures) {
        thumbs.push(getTransactionPictureUrl(picture, true));
    }

    return thumbs;
});

const transactionDisplayScheduledFrequency = computed<string>(() => {
    if (pageTypeAndMode?.type !== TransactionEditPageType.Template) {
        return '';
    }

    const template = transaction.value as TransactionTemplate;

    if (template.scheduledFrequencyType === ScheduledTemplateFrequencyType.Disabled.type) {
        return tt('Disabled');
    }

    const items = (template.scheduledFrequency || '').split(',');
    const scheduledFrequencyValues: number[] = [];

    for (const item of items) {
        if (item) {
            scheduledFrequencyValues.push(parseInt(item));
        }
    }

    if (template.scheduledFrequencyType === ScheduledTemplateFrequencyType.Daily.type) {
        return tt('Daily');
    } else if (template.scheduledFrequencyType === ScheduledTemplateFrequencyType.Weekly.type) {
        if (scheduledFrequencyValues.length) {
            return tt('format.misc.everyMultiDaysOfWeek', {
                days: getMultiWeekdayLongNames(scheduledFrequencyValues, firstDayOfWeek.value)
            });
        } else {
            return tt('Weekly');
        }
    } else if (template.scheduledFrequencyType === ScheduledTemplateFrequencyType.Monthly.type) {
        if (scheduledFrequencyValues.length) {
            return tt('format.misc.everyMultiDaysOfMonth', {
                days: getMultiMonthdayShortNames(scheduledFrequencyValues)
            });
        } else {
            return tt('Monthly');
        }
    } else if (template.scheduledFrequencyType === ScheduledTemplateFrequencyType.Yearly.type) {
        if (scheduledFrequencyValues.length) {
            return tt('format.misc.everyMultiDaysOfYear', {
                days: getMultiMonthAndDayLongNames(scheduledFrequencyValues)
            });
        } else {
            return tt('Yearly');
        }
    } else {
        return '';
    }
});

const transactionDisplayScheduledStartDate = computed<string>(() => {
    if (pageTypeAndMode?.type !== TransactionEditPageType.Template) {
        return '';
    }

    const template = transaction.value as TransactionTemplate;

    if (template.scheduledStartDate) {
        return formatGregorianTextualYearMonthDayToLongDate(template.scheduledStartDate);
    } else {
        return tt('No limit');
    }
});

const transactionDisplayScheduledEndDate = computed<string>(() => {
    if (pageTypeAndMode?.type !== TransactionEditPageType.Template) {
        return '';
    }

    const template = transaction.value as TransactionTemplate;

    if (template.scheduledEndDate) {
        return formatGregorianTextualYearMonthDayToLongDate(template.scheduledEndDate);
    } else {
        return tt('No limit');
    }
});

function getPageTypeNameMode(): { type: TransactionEditPageType, mode: TransactionEditPageMode } | null {
    if (props.f7route.path === '/transaction/add') {
        return {
            type: TransactionEditPageType.Transaction,
            mode: TransactionEditPageMode.Add
        };
    } else if (props.f7route.path === '/transaction/edit') {
        return {
            type: TransactionEditPageType.Transaction,
            mode: TransactionEditPageMode.Edit
        };
    } else if (props.f7route.path === '/transaction/detail') {
        return {
            type: TransactionEditPageType.Transaction,
            mode: TransactionEditPageMode.View
        };
    } else if (props.f7route.path === '/template/add') {
        return {
            type: TransactionEditPageType.Template,
            mode: TransactionEditPageMode.Add
        };
    } else if (props.f7route.path === '/template/edit') {
        return {
            type: TransactionEditPageType.Template,
            mode: TransactionEditPageMode.Edit
        };
    } else {
        return null;
    }
}

function getFontClassByAmount(amount: number): string {
    if (amount >= 100000000 || amount <= -100000000) {
        return 'ebk-small-amount';
    } else if (amount >= 1000000 || amount <= -1000000) {
        return 'ebk-normal-amount';
    } else {
        return 'ebk-large-amount';
    }
}

function getQueryTransactionOptions(): SetTransactionOptions {
    return {
        time: query['time'] ? parseInt(query['time']) : undefined,
        type: query['type'] ? parseInt(query['type']) : 0,
        categoryId: query['categoryId'],
        accountId: query['accountId'],
        destinationAccountId: query['destinationAccountId'],
        amount: query['amount'] ? parseInt(query['amount']) : undefined,
        destinationAmount: query['destinationAmount'] ? parseInt(query['destinationAmount']) : undefined,
        tagIds: query['tagIds'],
        comment: query['comment']
    };
}

function init(): void {
    if (!pageTypeAndMode) {
        showToast('Parameter Invalid');
        loadingError.value = 'Parameter Invalid';
        return;
    }

    loading.value = true;

    const promises: Promise<unknown>[] = [
        accountsStore.loadAllAccounts({ force: false }),
        transactionCategoriesStore.loadAllCategories({ force: false }),
        transactionTagsStore.loadAllTags({ force: false }),
        transactionTemplatesStore.loadAllTemplates({ force: false, templateType: TemplateType.Normal.type })
    ];

    if (pageTypeAndMode.type === TransactionEditPageType.Transaction) {
        if (query['id']) {
            if (mode.value === TransactionEditPageMode.Edit) {
                editId.value = query['id'];
            } else if (mode.value === TransactionEditPageMode.Add) {
                duplicateFromId.value = query['id'];
                shouldClearAmountOnFocus.value = true;
            }

            promises.push(transactionsStore.getTransaction({ transactionId: query['id'], withPictures: mode.value !== TransactionEditPageMode.Add }));
        }
    } else if (pageTypeAndMode.type === TransactionEditPageType.Template) {
        const template = TransactionTemplate.createNewTransactionTemplate(transaction.value);
        template.name = '';

        if (query['templateType']) {
            template.templateType = parseInt(query['templateType']);
        }

        if (template.templateType === TemplateType.Schedule.type) {
            template.scheduledFrequencyType = ScheduledTemplateFrequencyType.Disabled.type;
            template.scheduledFrequency = '';
        }

        transaction.value = template;

        if (query['id']) {
            if (mode.value === TransactionEditPageMode.Edit) {
                editId.value = query['id'];
            }

            promises.push(transactionTemplatesStore.getTemplate({ templateId: query['id'] }));
        }
    }

    const initOptions = getQueryTransactionOptions();

    if (initOptions.type &&
        initOptions.type >= TransactionType.Income &&
        initOptions.type <= TransactionType.Transfer) {
        transaction.value.type = initOptions.type;
    } else if (initOptions.type === TransactionType.ModifyBalance &&
        pageTypeAndMode.type === TransactionEditPageType.Transaction &&
        mode.value === TransactionEditPageMode.View) {
        transaction.value.type = initOptions.type;
    }

    if (mode.value === TransactionEditPageMode.Add) {
        clientSessionId.value = generateRandomUUID();
    }

    Promise.all(promises).then(function (responses) {
        if (query['id'] && !responses[4]) {
            if (pageTypeAndMode.type === TransactionEditPageType.Transaction) {
                showToast('Unable to retrieve transaction');
                loadingError.value = 'Unable to retrieve transaction';
            } else if (pageTypeAndMode.type === TransactionEditPageType.Template) {
                showToast('Unable to retrieve template');
                loadingError.value = 'Unable to retrieve template';
            }

            return;
        }

        let fromTransaction: Transaction | TransactionTemplate | null = null;

        if (pageTypeAndMode.type === TransactionEditPageType.Transaction) {
            if (query['id'] && responses[4] instanceof Transaction) {
                fromTransaction = responses[4];
            } else if (query['templateId'] && transactionTemplatesStore.allTransactionTemplatesMap && transactionTemplatesStore.allTransactionTemplatesMap[TemplateType.Normal.type]) {
                fromTransaction = (transactionTemplatesStore.allTransactionTemplatesMap[TemplateType.Normal.type] as Record<string, TransactionTemplate>)[query['templateId']] ?? null;

                if (fromTransaction) {
                    addByTemplateId.value = fromTransaction.id;
                }
            } else if (query['noTransactionDraft'] !== 'true' && (settingsStore.appSettings.autoSaveTransactionDraft === 'enabled' || settingsStore.appSettings.autoSaveTransactionDraft === 'confirmation') && transactionsStore.transactionDraft) {
                fromTransaction = Transaction.ofDraft(transactionsStore.transactionDraft);
            }
        } else if (pageTypeAndMode.type === TransactionEditPageType.Template && responses[4] instanceof TransactionTemplate) {
            if (query['id']) {
                fromTransaction = responses[4];
            }
        }

        setTransactionModel(
            fromTransaction,
            initOptions,
            pageTypeAndMode.type === TransactionEditPageType.Transaction && (mode.value === TransactionEditPageMode.Edit || mode.value === TransactionEditPageMode.View)
        );

        if (pageTypeAndMode.type === TransactionEditPageType.Transaction && query['id'] && responses[4] instanceof Transaction) {
            if (fromTransaction && query['withTime'] && query['withTime'] === 'true') {
                transaction.value.time = fromTransaction.time;
                transaction.value.timeZone = fromTransaction.timeZone;
                transaction.value.utcOffset = fromTransaction.utcOffset;
            }

            if (fromTransaction && query['withGeoLocation'] && query['withGeoLocation'] === 'true') {
                transaction.value.setGeoLocation(fromTransaction.geoLocation);
            }
        } else if (pageTypeAndMode.type === TransactionEditPageType.Template && query['id'] && responses[4] instanceof TransactionTemplate) {
            const template = responses[4];
            transaction.value.id = template.id;

            if (!(transaction.value instanceof TransactionTemplate)) {
                transaction.value = TransactionTemplate.createNewTransactionTemplate(transaction.value);
            }

            (transaction.value as TransactionTemplate).fillFrom(template);
        }

        loading.value = false;
    }).catch(error => {
        logger.error('failed to load essential data for editing transaction', error);

        if (error.processed) {
            loading.value = false;
        } else {
            loadingError.value = error;
            showToast(error.message || error);
        }
    });
}

function save(afterAction: AfterSaveAction): void {
    const router = props.f7router;

    if (mode.value === TransactionEditPageMode.View) {
        return;
    }

    const problemMessage = inputEmptyProblemMessage.value;

    if (problemMessage) {
        showAlert(problemMessage);
        return;
    }

    if (pageTypeAndMode?.type === TransactionEditPageType.Transaction && (mode.value === TransactionEditPageMode.Add || mode.value === TransactionEditPageMode.Edit)) {
        const doSubmit = function () {
            submitting.value = true;
            showLoading(() => submitting.value);

            transactionsStore.saveTransaction({
                transaction: transaction.value as Transaction,
                defaultCurrency: defaultCurrency.value,
                isEdit: mode.value === TransactionEditPageMode.Edit,
                clientSessionId: clientSessionId.value
            }).then(() => {
                submitting.value = false;
                submitted.value = true;
                hideLoading();

                if (mode.value === TransactionEditPageMode.Add && query['noTransactionDraft'] !== 'true' && !addByTemplateId.value && !duplicateFromId.value) {
                    transactionsStore.clearTransactionDraft();
                }

                if (mode.value === TransactionEditPageMode.Add && (afterAction === AfterSaveAction.StayWithNewTransaction || afterAction === AfterSaveAction.StayWithCurrentTransaction)) {
                    showToast('You have added a new transaction');
                    updateTransactionModelByAfterSaveAction(afterAction, getQueryTransactionOptions());
                    clientSessionId.value = generateRandomUUID();
                } else {
                    if (mode.value === TransactionEditPageMode.Add) {
                        showToast('You have added a new transaction');
                    } else if (mode.value === TransactionEditPageMode.Edit) {
                        showToast('You have saved this transaction');
                    }

                    if (duplicateFromId.value) {
                        router.navigate('/transaction/list');
                    } else {
                        router.back();
                    }
                }
            }).catch(error => {
                submitting.value = false;
                hideLoading();

                if (error.error && (error.error.errorCode === KnownErrorCode.TransactionCannotCreateInThisTime || error.error.errorCode === KnownErrorCode.TransactionCannotModifyInThisTime)) {
                    showConfirm('You have set this time range to prevent editing transactions. Would you like to change the editable transaction range to All?', () => {
                        submitting.value = true;
                        showLoading(() => submitting.value);

                        userStore.updateUserTransactionEditScope({
                            transactionEditScope: TransactionEditScopeType.All.type
                        }).then(() => {
                            submitting.value = false;
                            hideLoading();

                            showToast('Your editable transaction range has been set to All');
                        }).catch(error => {
                            submitting.value = false;
                            hideLoading();

                            if (!error.processed) {
                                showToast(error.message || error);
                            }
                        });
                    });
                } else if (!error.processed) {
                    showToast(error.message || error);
                }
            });
        };

        if (transaction.value.sourceAmount === 0) {
            showConfirm('Are you sure you want to save this transaction with a zero amount?', () => {
                doSubmit();
            });
        } else {
            doSubmit();
        }
    } else if (pageTypeAndMode?.type === TransactionEditPageType.Template && (mode.value === TransactionEditPageMode.Add || mode.value === TransactionEditPageMode.Edit)) {
        submitting.value = true;
        showLoading(() => submitting.value);

        transactionTemplatesStore.saveTemplateContent({
            template: transaction.value as TransactionTemplate,
            isEdit: mode.value === TransactionEditPageMode.Edit,
            clientSessionId: clientSessionId.value
        }).then(() => {
            submitting.value = false;
            submitted.value = true;
            hideLoading();

            if (mode.value === TransactionEditPageMode.Add) {
                showToast('You have added a new template');
            } else if (mode.value === TransactionEditPageMode.Edit) {
                showToast('You have saved this template');
            }

            router.back();
        }).catch(error => {
            submitting.value = false;
            hideLoading();

            if (!error.processed) {
                showToast(error.message || error);
            }
        });
    }
}

function quickSave(): void {
    if (mode.value === TransactionEditPageMode.View) {
        return;
    }

    if (pageTypeAndMode?.type === TransactionEditPageType.Transaction && mode.value === TransactionEditPageMode.Add) {
        const quickAddActionType = settingsStore.appSettings.quickAddButtonActionInMobileTransactionEditPage;

        if (quickAddActionType === TransactionQuickAddButtonActionType.OpenMenu.type) {
            showQuickSavePopover.value = true;
            return;
        } else if (quickAddActionType === TransactionQuickAddButtonActionType.SaveAndAddNewTransaction.type) {
            save(AfterSaveAction.StayWithNewTransaction);
            return;
        } else if (quickAddActionType === TransactionQuickAddButtonActionType.SaveAndKeepCurrentData.type) {
            save(AfterSaveAction.StayWithCurrentTransaction);
            return;
        }
    }

    save(AfterSaveAction.GoBack);
}

function getKeypadDisplayText(keypadValue: string, currency?: string): string {
    const zeroText = formatAmountToWesternArabicNumeralsWithoutDigitGrouping(0, currency);
    return numeralSystem.value.replaceWesternArabicDigitsToLocalizedDigits(keypadValue || zeroText);
}

function amountCentsToKeypadValue(value: number, currency?: string): string {
    if (!isNumber(value) || value === 0) {
        return '';
    }

    const textualNumber = formatAmountToWesternArabicNumeralsWithoutDigitGrouping(value, currency);
    const decimalSeparatorPos = textualNumber.indexOf(decimalSeparator.value);

    if (decimalSeparatorPos < 0) {
        return textualNumber;
    }

    let trimmedValue = textualNumber;

    while (trimmedValue.endsWith('0')) {
        trimmedValue = trimmedValue.substring(0, trimmedValue.length - 1);
    }

    if (trimmedValue.endsWith(decimalSeparator.value)) {
        trimmedValue = trimmedValue.substring(0, trimmedValue.length - decimalSeparator.value.length);
    }

    return trimmedValue;
}

function getCurrentKeypadValue(): string {
    return activeAmountField.value === 'destination' ? destinationAmountKeypadValue.value : sourceAmountKeypadValue.value;
}

function setCurrentKeypadValue(keypadValue: string, amount: number): void {
    if (activeAmountField.value === 'destination') {
        destinationAmountKeypadValue.value = keypadValue;
        transaction.value.destinationAmount = amount;
    } else {
        sourceAmountKeypadValue.value = keypadValue;
        transaction.value.sourceAmount = amount;
    }
}

function inputDigit(digit: number): void {
    const zeroDigit = keypadDigits.value[0];
    let base = getCurrentKeypadValue();

    if (base === zeroDigit || base === `-${zeroDigit}`) {
        base = '';
    }

    const separatorPos = base.indexOf(decimalSeparator.value);

    if (separatorPos >= 0 && base.length - separatorPos - decimalSeparator.value.length >= amountFractionDigits.value) {
        return;
    }

    const newValue = base + digit.toString();
    const parsedAmount = parseAmountFromWesternArabicNumerals(newValue);

    if (parsedAmount > TRANSACTION_MAX_AMOUNT) {
        showToast('Numeric Overflow');
        return;
    }

    setCurrentKeypadValue(newValue, parsedAmount);
}

function inputDecimalSeparator(): void {
    if (amountFractionDigits.value <= 0) {
        return;
    }

    const current = getCurrentKeypadValue();

    if (current.indexOf(decimalSeparator.value) >= 0) {
        return;
    }

    const newValue = (current || '0') + decimalSeparator.value;
    setCurrentKeypadValue(newValue, parseAmountFromWesternArabicNumerals(newValue));
}

function backspaceAmount(): void {
    const current = getCurrentKeypadValue();

    if (!current) {
        return;
    }

    const newValue = current.substring(0, current.length - 1);
    setCurrentKeypadValue(newValue, newValue ? parseAmountFromWesternArabicNumerals(newValue) : 0);
}

function clearAmountInput(): void {
    setCurrentKeypadValue('', 0);
}

function onMinusKey(): void {
    if (transaction.value.type === TransactionType.Transfer) {
        activeAmountField.value = 'source';
        return;
    }

    switchTransactionType(TransactionType.Expense);
}

function onPlusKey(): void {
    if (transaction.value.type === TransactionType.Transfer) {
        activeAmountField.value = 'destination';
        return;
    }

    switchTransactionType(TransactionType.Income);
}

function switchTransactionType(type: TransactionType): void {
    if (loading.value) {
        return;
    }

    transaction.value.type = type;
    activeAmountField.value = 'source';
}

function selectPrimaryCategory(category: TransactionCategory): void {
    const subCategories = (category.subCategories ?? []).filter(subCategory => !subCategory.hidden);

    if (subCategories.length && subCategories[0]) {
        transaction.value.setCategoryId(subCategories[0].id);
    } else {
        transaction.value.setCategoryId(category.id);
    }
}

function selectSubCategory(subCategory: TransactionCategory): void {
    transaction.value.setCategoryId(subCategory.id);
}

function getCategoryCircleStyle(category: TransactionCategory): Record<string, string> {
    if (category.id !== selectedPrimaryCategoryId.value) {
        return {};
    }

    const color = category.color && category.color !== DEFAULT_CATEGORY_COLOR ? `#${category.color}` : 'var(--f7-theme-color)';

    return {
        'background-color': color,
        'border-color': color
    };
}

function goBack(): void {
    if (loading.value) {
        return;
    }

    props.f7router.back();
}

function updateSourceAmount(value: string): void {
    if (mode.value === TransactionEditPageMode.View) {
        return;
    }

    // Store the raw input value for display during editing
    sourceAmountInputValue.value = value;

    // Remove all non-numeric characters except decimal point
    const cleanedValue = value.replace(/[^0-9.]/g, '');
    
    // Prevent multiple decimal points
    const parts = cleanedValue.split('.');
    if (parts.length > 2) {
        // Keep only the first decimal point
        sourceAmountInputValue.value = parts[0] + '.' + parts.slice(1).join('');
        return;
    }

    const parsedAmount = parseAmountFromLocalizedNumerals(cleanedValue || '0');

    if (Number.isNaN(parsedAmount) || !Number.isFinite(parsedAmount)) {
        return;
    }

    if (parsedAmount < TRANSACTION_MIN_AMOUNT || parsedAmount > TRANSACTION_MAX_AMOUNT) {
        showToast('Numeric Overflow');
        return;
    }

    transaction.value.sourceAmount = parsedAmount;
}

function updateDestinationAmount(value: string): void {
    if (mode.value === TransactionEditPageMode.View) {
        return;
    }

    // Store the raw input value for display during editing
    destinationAmountInputValue.value = value;

    // Remove all non-numeric characters except decimal point
    const cleanedValue = value.replace(/[^0-9.]/g, '');
    
    // Prevent multiple decimal points
    const parts = cleanedValue.split('.');
    if (parts.length > 2) {
        // Keep only the first decimal point
        destinationAmountInputValue.value = parts[0] + '.' + parts.slice(1).join('');
        return;
    }

    const parsedAmount = parseAmountFromLocalizedNumerals(cleanedValue || '0');

    if (Number.isNaN(parsedAmount) || !Number.isFinite(parsedAmount)) {
        return;
    }

    if (parsedAmount < TRANSACTION_MIN_AMOUNT || parsedAmount > TRANSACTION_MAX_AMOUNT) {
        showToast('Numeric Overflow');
        return;
    }

    transaction.value.destinationAmount = parsedAmount;
}

function onSourceAmountFocus(): void {
    isSourceAmountFocused.value = true;

    if (shouldClearAmountOnFocus.value) {
        sourceAmountInputValue.value = '';
        transaction.value.sourceAmount = 0;
        shouldClearAmountOnFocus.value = false;
        return;
    }

    // Initialize with current amount as plain number for editing
    if (transaction.value.sourceAmount === 0) {
        sourceAmountInputValue.value = '';
    } else {
        sourceAmountInputValue.value = (transaction.value.sourceAmount / 100).toString();
    }
}

function onSourceAmountBlur(): void {
    isSourceAmountFocused.value = false;
    // Clear the input value if it's empty or invalid
    if (!sourceAmountInputValue.value || sourceAmountInputValue.value === '0' || sourceAmountInputValue.value === '0.') {
        sourceAmountInputValue.value = '';
        if (transaction.value.sourceAmount === 0) {
            transaction.value.sourceAmount = 0;
        }
    }
}

function onDestinationAmountFocus(): void {
    isDestinationAmountFocused.value = true;

    if (shouldClearAmountOnFocus.value) {
        destinationAmountInputValue.value = '';
        transaction.value.destinationAmount = 0;
        shouldClearAmountOnFocus.value = false;
        return;
    }

    // Initialize with current amount as plain number for editing
    if (transaction.value.destinationAmount === 0) {
        destinationAmountInputValue.value = '';
    } else {
        destinationAmountInputValue.value = (transaction.value.destinationAmount / 100).toString();
    }
}

function onDestinationAmountBlur(): void {
    isDestinationAmountFocused.value = false;
    // Clear the input value if it's empty or invalid
    if (!destinationAmountInputValue.value || destinationAmountInputValue.value === '0' || destinationAmountInputValue.value === '0.') {
        destinationAmountInputValue.value = '';
        if (transaction.value.destinationAmount === 0) {
            transaction.value.destinationAmount = 0;
        }
    }
}

function pasteAmount(type: 'sourceAmount' | 'destinationAmount'): void {
    if (mode.value === TransactionEditPageMode.View || !isSupportClipboard) {
        return;
    }

    navigator.clipboard.readText().then(text => {
        if (!text) {
            return;
        }

        const parsedAmount = parseAmountFromLocalizedNumerals(text);

        if (Number.isNaN(parsedAmount) || !Number.isFinite(parsedAmount)) {
            showToast('Cannot parse amount from clipboard');
            return;
        }

        if (parsedAmount < TRANSACTION_MIN_AMOUNT || parsedAmount > TRANSACTION_MAX_AMOUNT) {
            showToast('Numeric Overflow');
            return;
        }

        if (type === 'sourceAmount') {
            transaction.value.sourceAmount = parsedAmount;
        } else if (type === 'destinationAmount') {
            transaction.value.destinationAmount = parsedAmount;
        }
    }).catch(error => {
        logger.error('failed to read clipboard text', error);
        showToast('Unable to read clipboard text');
    });
}

function updateGeoLocation(forceUpdate: boolean): void {
    if (!isSupportGeoLocation) {
        logger.warn('this browser does not support geo location');

        if (forceUpdate) {
            showToast('Unable to retrieve current position');
        }
        return;
    }

    navigator.geolocation.getCurrentPosition(function (position) {
        if (!position || !position.coords) {
            logger.error('current position is null');
            geoLocationStatus.value = GeoLocationStatus.Error;

            if (forceUpdate) {
                showToast('Unable to retrieve current position');
            }

            return;
        }

        geoLocationStatus.value = GeoLocationStatus.Success;

        transaction.value.setLatitudeAndLongitude(position.coords.latitude, position.coords.longitude);
    }, function (err) {
        logger.error('cannot retrieve current position', err);
        geoLocationStatus.value = GeoLocationStatus.Error;

        if (forceUpdate) {
            showToast('Unable to retrieve current position');
        }
    });

    geoLocationStatus.value = GeoLocationStatus.Getting;
}

function clearGeoLocation(): void {
    geoLocationStatus.value = null;
    transaction.value.removeGeoLocation();
}

function showDateTimeDialog(sheetMode: string): void {
    if (mode.value === TransactionEditPageMode.View) {
        showTimeInDefaultTimezone.value = !showTimeInDefaultTimezone.value;
    } else {
        transactionDateTimeSheetMode.value = sheetMode;
        showTransactionDateTimeSheet.value = true;
    }
}

function showOpenPictureDialog(): void {
    if (!canAddTransactionPicture.value || submitting.value) {
        return;
    }

    pictureInput.value?.click();
}

async function uploadPicture(event: Event): Promise<void> {
    if (!event || !event.target) {
        return;
    }

    const el = event.target as HTMLInputElement;

    if (!el.files || !el.files.length) {
        return;
    }

    const pictureFile = el.files[0] as File;

    el.value = '';

    uploadingPicture.value = true;
    submitting.value = true;

    const finalFile = await compressTransactionPicture(pictureFile);

    transactionsStore.uploadTransactionPicture({ pictureFile: finalFile }).then(response => {
        transaction.value.addPicture(response);
        uploadingPicture.value = false;
        submitting.value = false;
    }).catch(error => {
        uploadingPicture.value = false;
        submitting.value = false;

        if (!error.processed) {
            showToast(error.message || error);
        }
    });
}

function viewOrRemovePicture(pictureInfo: TransactionPictureInfoBasicResponse): void {
    if (mode.value !== TransactionEditPageMode.Add && mode.value !== TransactionEditPageMode.Edit && transaction.value.pictures && transaction.value.pictures.length) {
        pictureBrowser.value?.open();
        return;
    }

    showConfirm('Are you sure you want to remove this transaction picture?', () => {
        removingPictureId.value = pictureInfo.pictureId;
        submitting.value = true;

        transactionsStore.removeUnusedTransactionPicture({ pictureInfo }).then(response => {
            if (response) {
                transaction.value.removePicture(pictureInfo);
            }

            removingPictureId.value = '';
            submitting.value = false;
        }).catch(error => {
            if (error.error && error.error.errorCode === KnownErrorCode.TransactionPictureNotFound) {
                transaction.value.removePicture(pictureInfo);
            } else if (!error.processed) {
                showToast(error.message || error);
            }

            removingPictureId.value = '';
            submitting.value = false;
        });
    });
}

function duplicate(withTime?: boolean, withGeoLocation?: boolean): void {
    props.f7router.navigate(`/transaction/add?id=${transaction.value.id}&type=${transaction.value.type}&withTime=${withTime ?? false}&withGeoLocation=${withGeoLocation ?? false}`);
}

function onPageAfterIn(): void {
    routeBackOnError(props.f7router, loadingError);

    if (settingsStore.appSettings.autoGetCurrentGeoLocation && mode.value === TransactionEditPageMode.Add
        && !geoLocationStatus.value && !transaction.value.geoLocation) {
        updateGeoLocation(false);
    }
}

function onPageBeforeOut(): void {
    if (submitted.value || pageTypeAndMode?.type !== TransactionEditPageType.Transaction || mode.value !== TransactionEditPageMode.Add || query['noTransactionDraft'] === 'true' || addByTemplateId.value || duplicateFromId.value) {
        return;
    }

    const initAmount: number | undefined = query['amount'] ? parseInt(query['amount']) : undefined;

    if (settingsStore.appSettings.autoSaveTransactionDraft === 'confirmation') {
        if (transactionsStore.isTransactionDraftModified(transaction.value, initAmount, query['categoryId'], query['accountId'], query['tagIds'], firstVisibleAccountId.value)) {
            showConfirm('Do you want to save this transaction draft?', () => {
                transactionsStore.saveTransactionDraft(transaction.value, initAmount, query['categoryId'], query['accountId'], query['tagIds'], firstVisibleAccountId.value);
            }, () => {
                transactionsStore.clearTransactionDraft();
            });
        } else {
            transactionsStore.clearTransactionDraft();
        }
    } else if (settingsStore.appSettings.autoSaveTransactionDraft === 'enabled') {
        transactionsStore.saveTransactionDraft(transaction.value, initAmount, query['categoryId'], query['accountId'], query['tagIds'], firstVisibleAccountId.value);
    }
}

init();
</script>

<style>
.category-separate-icon.icon {
    margin-inline-start: 5px;
    margin-inline-end: 5px;
    font-size: var(--ebk-category-separate-icon-font-size);
    line-height: 16px;
    color: var(--f7-color-gray-tint);
}

.transaction-edit-amount {
    line-height: 53px;
}

.transaction-edit-amount .item-title {
    font-weight: bolder;
}

.transaction-edit-amount .item-header {
    padding-top: calc(var(--f7-typography-padding) / 2);
}

.amount-native-input-large {
    width: 100%;
    border: none;
    outline: none;
    background: transparent;
    font-size: 29px;
    font-weight: bolder;
    color: inherit;
    text-align: right;
    padding: 8px 0;
}

.amount-native-input-large::placeholder {
    color: var(--f7-color-gray);
    opacity: 0.6;
    font-weight: normal;
}

.transaction-edit-datetime .item-title {
    width: 100%;
}

.transaction-edit-datetime .item-title > .item-header > .transaction-edit-datetime-header {
    display: block;
    width: 100%;
}

.transaction-edit-datetime .item-title > .transaction-edit-datetime-title {
    display: flex;
    width: 100%;
}

.transaction-edit-datetime .item-title > .transaction-edit-datetime-title > .transaction-edit-datetime-time {
    flex-grow: 1;
    overflow: hidden;
    text-overflow: ellipsis;
}

.transaction-edit-timezone-name {
    padding-inline-start: 4px;
}

.transaction-edit-tag {
    --f7-chip-bg-color: var(--ebk-transaction-tag-chip-bg-color);
    margin-inline-end: 4px;
    max-width: 100%;
    overflow: hidden;
    text-overflow: ellipsis;
}

.chip.transaction-edit-tag .chip-media+.chip-label {
    margin-inline-start: 0;
}

.chip.transaction-edit-tag .chip-media i.icon {
    font-size: calc(var(--f7-chip-media-size) - 12px);
    height: calc(var(--f7-chip-media-size) - 12px);
}

.transaction-pictures {
    height: var(--ebk-transaction-picture-size);
}

.transaction-picture-container,
.transaction-picture {
    width: var(--ebk-transaction-picture-size);
    height: var(--ebk-transaction-picture-size);
}

.transaction-picture .transaction-picture-control-backdrop {
    width: 100%;
    height: 100%;
    position: absolute;
    z-index: 10;
    background-color: rgba(0, 0, 0, 0.4);
    border-radius: 8px;
}

.transaction-picture .picture-control-icon {
    z-index: 15;
    font-size: var(--ebk-transaction-picture-add-icon-size);
}

.transaction-picture .picture-remove-icon {
    background-color: transparent;
    color: rgba(255, 255, 255, 0.8);
    font-size: var(--ebk-transaction-picture-remove-icon-size);
}

.transaction-picture > img {
    object-fit: cover;
    position: absolute;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    border-radius: 8px;
}

.transaction-picture-add {
    width: calc(var(--ebk-transaction-picture-size) - 2px);
    height: calc(var(--ebk-transaction-picture-size) - 4px);
    border: 2px dashed #ccc;
    border-radius: 8px;
}

/* Quick edit layout (add/edit transaction) */
.quick-edit-layout {
    overflow: hidden;
}

.quick-edit-layout > .page-content {
    display: flex;
    flex-direction: column;
    min-height: 0;
    overflow: hidden;
    padding-top: var(--f7-safe-area-top);
}

.quick-edit-header {
    display: flex;
    flex-shrink: 0;
    align-items: center;
    height: 52px;
    padding: 0 8px;
    background: var(--f7-navbar-bg-color);
}

.quick-edit-header-side {
    display: flex;
    flex: 0 0 44px;
    justify-content: center;
}

.quick-edit-header-side-right {
    flex-basis: 44px;
}

.quick-edit-header-icon {
    font-size: 23px;
    color: var(--f7-theme-color);
}

.quick-edit-type-segmented {
    flex: 1;
    min-width: 0;
    margin: 0 6px;
}

.quick-edit-body {
    display: flex;
    flex: 1;
    flex-direction: column;
    min-height: 0;
}

.quick-edit-category-area {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    padding: 12px 10px 4px;
}

.quick-edit-category-grid {
    display: grid;
    grid-template-columns: repeat(5, 1fr);
    row-gap: 14px;
    column-gap: 4px;
}

.quick-edit-category-item {
    display: flex;
    flex-direction: column;
    align-items: center;
    cursor: pointer;
    user-select: none;
}

.quick-edit-category-icon {
    display: flex;
    width: 46px;
    height: 46px;
    align-items: center;
    justify-content: center;
    border: 1px solid transparent;
    border-radius: 50%;
    background: rgba(var(--f7-color-black-rgb), 0.05);
    box-sizing: border-box;
    transition: background-color var(--ebk-transition-fast);
}

.dark .quick-edit-category-icon {
    background: rgba(var(--f7-color-white-rgb), 0.10);
}

.quick-edit-category-icon.active {
    background-color: var(--f7-theme-color);
}

.quick-edit-category-icon .icon {
    font-size: 23px;
    color: var(--ebk-secondary-text-color);
}

.quick-edit-category-icon.active .icon {
    color: #ffffff;
}

.quick-edit-category-name {
    max-width: 100%;
    margin-top: 5px;
    overflow: hidden;
    font-size: 13px;
    line-height: 1.3;
    color: var(--f7-color-black);
    text-align: center;
    white-space: nowrap;
    text-overflow: ellipsis;
}

.dark .quick-edit-category-name {
    color: var(--f7-color-white);
}

.quick-edit-category-name.active {
    color: var(--f7-theme-color);
    font-weight: 600;
}

.quick-edit-subcategory-bar {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    margin-top: 12px;
}

.quick-edit-subcategory-chip {
    --f7-chip-bg-color: rgba(var(--f7-color-black-rgb), 0.05);
    --f7-chip-text-color: var(--ebk-secondary-text-color);
    cursor: pointer;
}

.dark .quick-edit-subcategory-chip {
    --f7-chip-bg-color: rgba(var(--f7-color-white-rgb), 0.10);
}

.quick-edit-subcategory-chip.active {
    --f7-chip-bg-color: var(--f7-theme-color);
    --f7-chip-text-color: #ffffff;
}

.quick-edit-pictures {
    margin-top: 12px;
}

.quick-edit-chips-bar {
    display: flex;
    flex-shrink: 0;
    gap: 8px;
    align-items: center;
    padding: 6px 12px 8px;
    overflow-x: auto;
    scrollbar-width: none;
}

.quick-edit-chips-bar::-webkit-scrollbar {
    display: none;
}

.quick-edit-chip {
    --f7-chip-bg-color: #ffffff;
    --f7-chip-text-color: var(--f7-color-black);
    --f7-chip-height: 32px;
    flex-shrink: 0;
    border: 1px solid var(--ebk-divider-color);
    font-weight: normal;
}

.dark .quick-edit-chip {
    --f7-chip-bg-color: rgba(var(--f7-color-white-rgb), 0.08);
    --f7-chip-text-color: var(--f7-color-white);
}

.quick-edit-chip .icon {
    font-size: 16px;
    color: var(--ebk-secondary-text-color);
}

.quick-edit-input-bar {
    display: flex;
    flex-shrink: 0;
    align-items: center;
    margin: 0 10px;
    padding: 4px 12px;
    border-radius: 12px;
    background: #ffffff;
    min-height: 52px;
}

.dark .quick-edit-input-bar {
    background: rgba(var(--f7-color-white-rgb), 0.08);
}

.quick-edit-input-bar-second {
    margin-top: 8px;
    min-height: 44px;
}

.quick-edit-input-bar-label {
    flex-shrink: 0;
    font-size: 15px;
    color: var(--ebk-secondary-text-color);
}

.quick-edit-note-input {
    flex: 1;
    min-width: 0;
    border: none;
    outline: none;
    background: transparent;
    font-size: 16px;
    color: var(--f7-color-black);
}

.dark .quick-edit-note-input {
    color: var(--f7-color-white);
}

.quick-edit-note-input::placeholder {
    color: var(--ebk-secondary-text-color);
    opacity: 0.7;
}

.quick-edit-amount {
    flex-shrink: 0;
    padding-inline-start: 10px;
    border-inline-start: 1px solid var(--ebk-divider-color);
    user-select: none;
}

.quick-edit-amount-text {
    display: block;
    font-size: 25px;
    font-weight: 700;
    line-height: 1.2;
}

.quick-edit-amount.inactive .quick-edit-amount-text {
    color: var(--ebk-secondary-text-color);
    font-weight: 500;
}

.quick-edit-keypad {
    display: grid;
    flex-shrink: 0;
    grid-template-columns: repeat(4, 1fr);
    gap: 7px;
    margin-top: 10px;
    padding: 7px 7px calc(7px + var(--f7-safe-area-bottom));
}

.quick-edit-key {
    height: 52px;
    border-radius: 10px;
    background: #ffffff;
    box-shadow: none;
}

.dark .quick-edit-key {
    background: rgba(var(--f7-color-white-rgb), 0.08);
}

.quick-edit-key.active-state {
    background: rgba(var(--f7-color-black-rgb), 0.08);
}

.dark .quick-edit-key.active-state {
    background: rgba(var(--f7-color-white-rgb), 0.16);
}

.quick-edit-key-text {
    display: block;
    font-size: 22px;
    font-weight: 500;
    line-height: 1;
    color: var(--f7-color-black);
}

.dark .quick-edit-key-text {
    color: var(--f7-color-white);
}

.quick-edit-key-text .icon {
    font-size: 23px;
}

.quick-edit-key-action .quick-edit-key-text {
    font-size: 17px;
}

.quick-edit-key-save .quick-edit-key-text {
    color: var(--f7-theme-color);
    font-weight: 700;
}

.quick-edit-key-span-2 {
    grid-column: span 2;
}

.quick-edit-key-active-side {
    background: var(--ebk-primary-50);
}

.dark .quick-edit-key-active-side {
    background: rgba(var(--ebk-primary-color), 0.20);
}
</style>
