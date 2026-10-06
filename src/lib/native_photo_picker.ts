import { Capacitor } from '@capacitor/core';
import { PhotoLibrary } from '@capgo/capacitor-photo-library';

/**
 * Upper bound for one pick — each selected image triggers one recognition request,
 * so the limit keeps accidental mass selections from flooding the LLM backend.
 */
const MAX_SELECTION = 9;

/**
 * Whether the native multi-select photo library picker is available.
 *
 * Only the app shell with the Capacitor PhotoLibrary plugin compiled in can open the photo
 * library directly; in browsers and old shells the file input (with the system
 * "Photo Library / Take Photo / Choose File" action sheet) is the fallback.
 *
 * isPluginAvailable alone is not enough: the plugin ships a web implementation, so it reports
 * available on web and (as a JS fallback) in shells without the native plugin. Requiring
 * isNativePlatform() excludes browsers, and excludes old shells because on a native platform
 * without the compiled-in plugin the header lookup fails.
 */
export function isNativePhotoLibraryPickerAvailable(): boolean {
    return Capacitor.isNativePlatform() && Capacitor.isPluginAvailable('PhotoLibrary');
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

    const assets = (result.assets || []).filter(asset => asset.type === 'image' && asset.file && asset.file.webPath);

    if (assets.length === 0) {
        return null;
    }

    const blobs: Blob[] = [];

    for (const asset of assets) {
        if (!asset.file) {
            continue;
        }

        const response = await fetch(asset.file.webPath);
        blobs.push(await response.blob());
    }

    return blobs.length > 0 ? blobs : null;
}
