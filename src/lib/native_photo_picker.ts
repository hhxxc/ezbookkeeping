import { Capacitor } from '@capacitor/core';
import { Filesystem } from '@capacitor/filesystem';
import { PhotoLibrary } from '@capgo/capacitor-photo-library';

/**
 * Upper bound for one pick — each selected image triggers one recognition request,
 * so the limit keeps accidental mass selections from flooding the LLM backend.
 */
const MAX_SELECTION = 9;

/**
 * Whether the native multi-select photo library picker is fully usable.
 *
 * Only the app shell with both the PhotoLibrary and Filesystem plugins compiled in can open
 * the photo library directly; in browsers and old shells the file input (with the system
 * "Photo Library / Take Photo / Choose File" action sheet) is the fallback.
 *
 * isPluginAvailable alone is not enough: these plugins ship web implementations, so they report
 * available on web and (as a JS fallback) in shells without the native plugins. Requiring
 * isNativePlatform() excludes browsers, and excludes old shells because on a native platform
 * without the compiled-in plugin the header lookup fails.
 *
 * Filesystem is required because the shell loads the web app from a remote server: picked
 * files are only exposed as capacitor:// webPaths, which the page origin can neither fetch
 * nor draw onto a canvas without tainting it, so the bytes must come through the bridge.
 */
export function isNativePhotoLibraryPickerAvailable(): boolean {
    return Capacitor.isNativePlatform()
        && Capacitor.isPluginAvailable('PhotoLibrary')
        && Capacitor.isPluginAvailable('Filesystem');
}

function base64ToBlob(base64: string, mimeType: string): Blob {
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);

    for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
    }

    return new Blob([bytes], { type: mimeType || 'image/jpeg' });
}

/**
 * Open the native photo library picker (multi-select) and return the selected images as Blobs.
 * Returns null when the user cancels; throws for real failures (permission, plugin error).
 */
export async function pickImagesFromPhotoLibrary(): Promise<Blob[] | null> {
    let result;

    try {
        result = await PhotoLibrary.pickMedia({
            selectionLimit: MAX_SELECTION,
            includeImages: true,
            includeVideos: false
        });
    } catch (error) {
        const message = error instanceof Error ? error.message : String(error);

        if (/cancel/i.test(message)) {
            return null;
        }

        throw error;
    }

    const assets = (result.assets || []).filter(asset => asset.type === 'image' && asset.file && asset.file.path);

    if (assets.length === 0) {
        return null;
    }

    const blobs: Blob[] = [];

    for (const asset of assets) {
        if (!asset.file) {
            continue;
        }

        // 拷进缓存的原图经 bridge 读回（base64），页面源是远程服务器时无法 fetch capacitor:// 路径
        const file = await Filesystem.readFile({ path: asset.file.path });

        if (typeof file.data !== 'string') {
            throw new Error('unexpected binary file data');
        }

        blobs.push(base64ToBlob(file.data, asset.mimeType));
    }

    return blobs.length > 0 ? blobs : null;
}
