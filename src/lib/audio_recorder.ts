export type SupportedAudioMimeType = 'audio/mp4' | 'audio/webm';

export interface RecorderSupport {
    mediaRecorder: boolean;
    mimeType: SupportedAudioMimeType | null;
}

const MAX_RECORDING_DURATION_MS: number = 30 * 1000; // 30s auto stop
const AUDIO_BITS_PER_SECOND: number = 32000; // AAC 32kbps mono, low bitrate for voice

/// Probe MediaRecorder support and pick the best mime type.
/// iOS 14.3+ Safari/WKWebView supports MediaRecorder with audio/mp4 (AAC),
/// other browsers usually support audio/webm (opus).
/// Returns { mediaRecorder: false, mimeType: null } when MediaRecorder is
/// unavailable (e.g. iOS < 14.3), callers should hide the voice entry.
export function getRecorderSupport(): RecorderSupport {
    if (typeof MediaRecorder === 'undefined' || !navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
        return { mediaRecorder: false, mimeType: null };
    }

    const candidateMimeTypes: string[] = [
        'audio/mp4',
        'audio/webm;codecs=opus',
        'audio/webm'
    ];

    for (const mimeType of candidateMimeTypes) {
        if (MediaRecorder.isTypeSupported(mimeType)) {
            return {
                mediaRecorder: true,
                mimeType: mimeType.startsWith('audio/mp4') ? 'audio/mp4' : 'audio/webm'
            };
        }
    }

    return { mediaRecorder: false, mimeType: null };
}

const AUDIO_FILE_EXTENSIONS: Record<SupportedAudioMimeType, string> = {
    'audio/mp4': 'm4a',
    'audio/webm': 'webm'
};

export function getAudioFileExtension(mimeType: SupportedAudioMimeType): string {
    return AUDIO_FILE_EXTENSIONS[mimeType];
}

/// AudioRecorder wraps MediaRecorder with low-bitrate mono recording,
/// 30s auto stop and blob size validation (<= 2MB)
export class AudioRecorder {
    private mimeType: SupportedAudioMimeType;
    private mediaRecorder: MediaRecorder | null = null;
    private stream: MediaStream | null = null;
    private chunks: Blob[] = [];
    private autoStopTimer: number = 0;
    private startedAt: number = 0;

    constructor(mimeType: SupportedAudioMimeType) {
        this.mimeType = mimeType;
    }

    start(): Promise<void> {
        return navigator.mediaDevices.getUserMedia({
            audio: {
                channelCount: 1,
                echoCancellation: true,
                noiseSuppression: true
            }
        }).then(stream => {
            this.stream = stream;
            this.chunks = [];
            this.startedAt = Date.now();

            const options: MediaRecorderOptions = {
                mimeType: this.mimeType,
                audioBitsPerSecond: AUDIO_BITS_PER_SECOND
            };

            this.mediaRecorder = new MediaRecorder(stream, options);

            this.mediaRecorder.ondataavailable = (event: BlobEvent) => {
                if (event.data && event.data.size > 0) {
                    this.chunks.push(event.data);
                }
            };

            this.mediaRecorder.start();

            // 30s auto stop: backend only accepts audio <= 30s
            this.autoStopTimer = window.setTimeout(() => {
                if (this.mediaRecorder && this.mediaRecorder.state === 'recording') {
                    this.mediaRecorder.stop();
                }
            }, MAX_RECORDING_DURATION_MS);
        });
    }

    isRecording(): boolean {
        return !!this.mediaRecorder && this.mediaRecorder.state === 'recording';
    }

    getElapsedMilliseconds(): number {
        if (!this.startedAt) {
            return 0;
        }

        return Math.min(Date.now() - this.startedAt, MAX_RECORDING_DURATION_MS);
    }

    stop(): Promise<Blob> {
        return new Promise((resolve, reject) => {
            if (!this.mediaRecorder) {
                reject(new Error('recorder not started'));
                return;
            }

            const recorder = this.mediaRecorder;

            recorder.onstop = () => {
                this.cleanup();

                const blob = new Blob(this.chunks, { type: this.mimeType });

                if (blob.size > 2 * 1024 * 1024) {
                    reject(new Error('recording too large'));
                    return;
                }

                resolve(blob);
            };

            if (recorder.state === 'recording') {
                recorder.stop();
            } else {
                this.cleanup();
                reject(new Error('recorder not recording'));
            }
        });
    }

    cancel(): void {
        if (this.autoStopTimer) {
            clearTimeout(this.autoStopTimer);
            this.autoStopTimer = 0;
        }

        if (this.mediaRecorder && this.mediaRecorder.state === 'recording') {
            this.mediaRecorder.stop();
        }

        this.mediaRecorder = null;
        this.cleanup();
    }

    private cleanup(): void {
        if (this.autoStopTimer) {
            clearTimeout(this.autoStopTimer);
            this.autoStopTimer = 0;
        }

        if (this.stream) {
            for (const track of this.stream.getTracks()) {
                track.stop();
            }

            this.stream = null;
        }

        this.startedAt = 0;
    }
}
