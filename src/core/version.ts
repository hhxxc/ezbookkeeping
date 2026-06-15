export interface VersionInfo {
    readonly version: string;
    readonly commitHash: string;
    readonly buildTime?: string;
}

export interface ClientUpdateInfo {
    readonly latestVersion: string;
}
