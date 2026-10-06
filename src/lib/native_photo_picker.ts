import { Capacitor } from '@capacitor/core';
import { Camera, CameraResultType, CameraSource } from '@capacitor/camera';

/**
 * Whether the native photo library picker is available.
 *
 * Only the app shell with the Capacitor Camera plugin compiled in can open the photo library
 * directly; in browsers and old shells the file input (with the system "Photo Library /
 * Take Photo / Choose File" action sheet) is the fallback.
 *
 * isPluginAvailable alone is not enough: the plugin ships a web implementation, so it reports
 * available on web and (as a JS fallback) in shells without the native plugin. Requiring
 * isNativePlatform() excludes browsers, and excludes old shells because on a native platform
 * without the compiled-in plugin the header lookup fails.
 */
export function isNativePhotoLibraryPickerAvailable(): boolean {
    return Capacitor.isNativePlatform() && Capacitor.isPluginAvailable('Camera');
}

/**
 * Open the native photo library picker and return the selected image as a Blob.
 * Returns null when the user cancels; throws for real failures (permission, plugin error).
 */
export async function pickImageFromPhotoLibrary(): Promise<Blob | null> {
    let photo;

    try {
        photo = await Camera.getPhoto({
            source: CameraSource.Photos,
            resultType: CameraResultType.DataUrl,
            width: 1600,
            height: 1600,
            quality: 90
        });
    } catch (error) {
        const message = error instanceof Error ? error.message : String(error);

        if (/cancel/i.test(message)) {
            return null;
        }

        throw error;
    }

    if (!photo.dataUrl) {
        return null;
    }

    const response = await fetch(photo.dataUrl);

    return await response.blob();
}
