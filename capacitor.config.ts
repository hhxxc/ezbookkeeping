import { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
    appId: 'com.nestkeep.app',
    appName: '巢记',
    webDir: 'dist',
    server: {
        androidScheme: 'https',
        iosScheme: 'capacitor'
    }
};

export default config;
