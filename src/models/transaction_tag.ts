export const TRANSACTION_TAG_NO_ICON = '0';

export class TransactionTag implements TransactionTagInfoResponse {
    public id: string;
    public name: string;
    public groupId: string;
    public displayOrder: number;
    public hidden: boolean;
    public icon: string;
    public color: string;

    private constructor(id: string, name: string, groupId: string, displayOrder: number, hidden: boolean, icon: string, color: string) {
        this.id = id;
        this.name = name;
        this.groupId = groupId;
        this.displayOrder = displayOrder;
        this.hidden = hidden;
        this.icon = icon;
        this.color = color;
    }

    public toCreateRequest(): TransactionTagCreateRequest {
        return {
            name: this.name,
            groupId: this.groupId,
            icon: this.icon,
            color: this.color
        };
    }

    public toModifyRequest(): TransactionTagModifyRequest {
        return {
            id: this.id,
            groupId: this.groupId,
            name: this.name,
            icon: this.icon,
            color: this.color
        };
    }

    public clone(): TransactionTag {
        return new TransactionTag(this.id, this.name, this.groupId, this.displayOrder, this.hidden, this.icon, this.color);
    }

    public static of(tagResponse: TransactionTagInfoResponse): TransactionTag {
        return new TransactionTag(tagResponse.id, tagResponse.name, tagResponse.groupId, tagResponse.displayOrder, tagResponse.hidden, tagResponse.icon || TRANSACTION_TAG_NO_ICON, tagResponse.color || '');
    }

    public static ofMulti(tagResponses: TransactionTagInfoResponse[]): TransactionTag[] {
        const tags: TransactionTag[] = [];

        for (const tagResponse of tagResponses) {
            tags.push(TransactionTag.of(tagResponse));
        }

        return tags;
    }

    public static createNewTag(name?: string, groupId?: string): TransactionTag {
        return new TransactionTag('', name || '', groupId || '0', 0, false, TRANSACTION_TAG_NO_ICON, '');
    }
}

export interface TransactionTagCreateRequest {
    readonly groupId: string;
    readonly name: string;
    readonly icon: string;
    readonly color: string;
}

export interface TransactionTagCreateBatchRequest {
    readonly tags: TransactionTagCreateRequest[];
    readonly groupId: string;
    readonly skipExists: boolean;
}

export interface TransactionTagModifyRequest {
    readonly id: string;
    readonly groupId: string;
    readonly name: string;
    readonly icon: string;
    readonly color: string;
}

export interface TransactionTagHideRequest {
    readonly id: string;
    readonly hidden: boolean;
}

export interface TransactionTagMoveRequest {
    readonly newDisplayOrders: TransactionTagNewDisplayOrderRequest[];
}

export interface TransactionTagNewDisplayOrderRequest {
    readonly id: string;
    readonly displayOrder: number;
}

export interface TransactionTagDeleteRequest {
    readonly id: string;
}

export interface TransactionTagInfoResponse {
    readonly id: string;
    readonly name: string;
    readonly groupId: string;
    readonly displayOrder: number;
    readonly hidden: boolean;
    readonly icon: string;
    readonly color: string;
}
