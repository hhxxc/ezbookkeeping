import en from './en.json';

export interface LanguageInfo {
    readonly name: string;
    readonly displayName: string;
    readonly alternativeLanguageTag: string;
    readonly aliases?: string[];
    readonly textDirection: 'ltr' | 'rtl';
    readonly content?: object;
    readonly load?: () => Promise<object>;
}

export interface LanguageOption {
    readonly languageTag: string;
    readonly displayName: string;
    readonly nativeDisplayName: string;
}

export const DEFAULT_LANGUAGE: string = 'en';

// To add new languages, please refer to https://ezbookkeeping.mayswind.net/translating
//
// Only the default language is bundled into the initial package. The content of every
// other language is loaded on demand through its loader (each language becomes a separate
// chunk), which keeps the startup payload small over slow networks. Use loadLanguageContent()
// before displaying a language, and getLoadedLanguageMessages() to seed the i18n instance.
export const ALL_LANGUAGES: Record<string, LanguageInfo> = {
    'de': {
        name: 'German',
        displayName: 'Deutsch',
        alternativeLanguageTag: 'de-DE',
        textDirection: 'ltr',
        load: () => import('./de.json').then(module => module.default)
    },
    'en': {
        name: 'English',
        displayName: 'English',
        alternativeLanguageTag: 'en-US',
        textDirection: 'ltr',
        content: en
    },
    'es': {
        name: 'Spanish',
        displayName: 'Español',
        alternativeLanguageTag: 'es-ES',
        textDirection: 'ltr',
        load: () => import('./es.json').then(module => module.default)
    },
    'fr': {
        name: "French",
        displayName: "Français",
        alternativeLanguageTag: "fr-FR",
        textDirection: "ltr",
        load: () => import('./fr.json').then(module => module.default)
    },
    'it': {
        name: 'Italian',
        displayName: 'Italiano',
        alternativeLanguageTag: 'it-IT',
        textDirection: 'ltr',
        load: () => import('./it.json').then(module => module.default)
    },
    'ja': {
        name: 'Japanese',
        displayName: '日本語',
        alternativeLanguageTag: 'ja-JP',
        textDirection: 'ltr',
        load: () => import('./ja.json').then(module => module.default)
    },
    'kn': {
        name: 'Kannada',
        displayName: 'ಕನ್ನಡ',
        alternativeLanguageTag: 'kn-IN',
        textDirection: 'ltr',
        load: () => import('./kn.json').then(module => module.default)
    },
    'ko': {
        name: 'Korean',
        displayName: '한국어',
        alternativeLanguageTag: 'ko-KR',
        textDirection: 'ltr',
        load: () => import('./ko.json').then(module => module.default)
    },
    'nl': {
        name: 'Dutch',
        displayName: 'Nederlands',
        alternativeLanguageTag: 'nl-NL',
        textDirection: 'ltr',
        load: () => import('./nl.json').then(module => module.default)
    },
    'pt-BR': {
        name: 'Portuguese (Brazil)',
        displayName: 'Português (Brasil)',
        alternativeLanguageTag: 'pt-BR',
        textDirection: 'ltr',
        load: () => import('./pt_BR.json').then(module => module.default)
    },
    'ru': {
        name: 'Russian',
        displayName: 'Русский',
        alternativeLanguageTag: 'ru-RU',
        textDirection: 'ltr',
        load: () => import('./ru.json').then(module => module.default)
    },
    'sl': {
        name: 'Slovenian',
        displayName: 'Slovenščina',
        alternativeLanguageTag: 'sl-SI',
        textDirection: 'ltr',
        load: () => import('./sl.json').then(module => module.default)
    },
    'ta': {
        name: 'Tamil',
        displayName: 'தமிழ்',
        alternativeLanguageTag: 'ta-IN',
        textDirection: 'ltr',
        load: () => import('./ta.json').then(module => module.default)
    },
    'th': {
        name: 'Thai',
        displayName: 'ภาษาไทย',
        alternativeLanguageTag: 'th-TH',
        textDirection: 'ltr',
        load: () => import('./th.json').then(module => module.default)
    },
    'tr': {
        name: 'Turkish',
        displayName: 'Türkçe',
        alternativeLanguageTag: 'tr-TR',
        textDirection: 'ltr',
        load: () => import('./tr.json').then(module => module.default)
    },
    'uk': {
        name: 'Ukrainian',
        displayName: 'Українська',
        alternativeLanguageTag: 'uk-UA',
        textDirection: 'ltr',
        load: () => import('./uk.json').then(module => module.default)
    },
    'vi': {
        name: 'Vietnamese',
        displayName: 'Tiếng Việt',
        alternativeLanguageTag: 'vi-VN',
        textDirection: 'ltr',
        load: () => import('./vi.json').then(module => module.default)
    },
    'zh-Hans': {
        name: 'Chinese (Simplified)',
        displayName: '中文 (简体)',
        alternativeLanguageTag: 'zh-CN',
        aliases: ['zh-CHS', 'zh-CN', 'zh-SG'],
        textDirection: 'ltr',
        load: () => import('./zh_Hans.json').then(module => module.default)
    },
    'zh-Hant': {
        name: 'Chinese (Traditional)',
        displayName: '中文 (繁體)',
        alternativeLanguageTag: 'zh-TW',
        aliases: ['zh-CHT', 'zh-TW', 'zh-HK', 'zh-MO'],
        textDirection: 'ltr',
        load: () => import('./zh_Hant.json').then(module => module.default)
    },
};

const loadedLanguageContents: Record<string, object> = {
    [DEFAULT_LANGUAGE]: en
};

export function isLanguageContentLoaded(languageKey: string): boolean {
    return !!loadedLanguageContents[languageKey];
}

export async function loadLanguageContent(languageKey: string): Promise<object | undefined> {
    if (loadedLanguageContents[languageKey]) {
        return loadedLanguageContents[languageKey];
    }

    const languageInfo = ALL_LANGUAGES[languageKey];

    if (!languageInfo) {
        return undefined;
    }

    const content = languageInfo.load ? await languageInfo.load() : languageInfo.content;

    if (content) {
        loadedLanguageContents[languageKey] = content;
    }

    return content;
}

export function getLoadedLanguageMessages(): Record<string, object> {
    return { ...loadedLanguageContents };
}
