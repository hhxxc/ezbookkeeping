import { reversed } from '@/core/base.ts';
import { TransactionTag } from '@/models/transaction_tag.ts';
import { TRANSACTION_TAG_NO_ICON } from '@/models/transaction_tag.ts';
import { ALL_CATEGORY_ICONS } from '@/consts/icon.ts';

export function isNoAvailableTag(tags: TransactionTag[], showHidden: boolean): boolean {
    for (const tag of tags) {
        if (showHidden || !tag.hidden) {
            return false;
        }
    }

    return true;
}

export function getAvailableTagCount(tags: TransactionTag[], showHidden: boolean): number {
    let count = 0;

    for (const tag of tags) {
        if (showHidden || !tag.hidden) {
            count++;
        }
    }

    return count;
}

export function getFirstShowingId(tags: TransactionTag[], showHidden: boolean): string | null {
    for (const tag of tags) {
        if (showHidden || !tag.hidden) {
            return tag.id;
        }
    }

    return null;
}

export function getLastShowingId(tags: TransactionTag[], showHidden: boolean): string | null {
    for (const tag of reversed(tags)) {
        if (showHidden || !tag.hidden) {
            return tag.id;
        }
    }

    return null;
}

export function hasCustomTransactionTagIcon(tag: { icon?: string; color?: string } | null | undefined): boolean {
    return !!tag && !!tag.icon && tag.icon !== TRANSACTION_TAG_NO_ICON && !!ALL_CATEGORY_ICONS[tag.icon];
}
