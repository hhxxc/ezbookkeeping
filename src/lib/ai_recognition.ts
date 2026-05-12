import services from './services.ts';
import { isNumber } from './common.ts';

import type { RecognizedReceiptImageResponse } from '@/models/large_language_model.ts';
import type { TransactionInfoResponse } from '@/models/transaction.ts';

const DUPLICATE_TIME_TOLERANCE_SECONDS = 86400; // ±1 day
const DUPLICATE_AMOUNT_TOLERANCE = 0.01;

export async function findPotentialDuplicateTransactions(
    result: RecognizedReceiptImageResponse
): Promise<TransactionInfoResponse[]> {
    if (!isNumber(result.time)) {
        return [];
    }

    const recognizedAmount = result.sourceAmount ?? result.destinationAmount;

    if (!isNumber(recognizedAmount)) {
        return [];
    }

    const startTime = result.time - DUPLICATE_TIME_TOLERANCE_SECONDS;
    const endTime = result.time + DUPLICATE_TIME_TOLERANCE_SECONDS;

    try {
        const response = await services.getAllTransactions({
            startTime,
            endTime,
            withPictures: false
        });

        if (!response.data || !response.data.success || !response.data.result) {
            return [];
        }

        const allTransactions = response.data.result;
        const duplicates: TransactionInfoResponse[] = [];

        const recognizedComment = (result.comment ?? '').trim();

        for (const transaction of allTransactions) {
            const sourceMatch = Math.abs(transaction.sourceAmount - recognizedAmount) <= DUPLICATE_AMOUNT_TOLERANCE;
            const destMatch = Math.abs(transaction.destinationAmount - recognizedAmount) <= DUPLICATE_AMOUNT_TOLERANCE;
            const amountMatch = sourceMatch || destMatch;

            const timeMatch = Math.abs(transaction.time - result.time) <= DUPLICATE_TIME_TOLERANCE_SECONDS;

            const txComment = (transaction.comment || '').trim();
            const commentMatch = recognizedComment === txComment;

            if (amountMatch && timeMatch && commentMatch) {
                duplicates.push(transaction);
            }
        }

        return duplicates;
    } catch {
        return [];
    }
}

export function buildDuplicateConfirmMessage(
    duplicates: TransactionInfoResponse[]
): string {
    let message = '';

    for (let i = 0; i < duplicates.length && i < 3; i++) {
        const tx = duplicates[i]!;
        const date = new Date(tx.time * 1000).toLocaleString();
        const amount = tx.sourceAmount || tx.destinationAmount;
        const comment = tx.comment || '';

        if (i > 0) {
            message += '\n';
        }

        message += `${date} | ${amount}`;

        if (comment) {
            message += ` | ${comment}`;
        }
    }

    if (duplicates.length > 3) {
        message += '\n...';
    }

    return message;
}
