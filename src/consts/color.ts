import type { ColorValue, ColorStyleValue } from '@/core/color.ts';

const defaultColor: ColorValue = '000000';

export const DEFAULT_ICON_COLOR: ColorValue = defaultColor;
export const DEFAULT_ACCOUNT_COLOR: ColorValue = defaultColor;
export const DEFAULT_CATEGORY_COLOR: ColorValue = defaultColor;

export const DEFAULT_COLOR_STYLE_VARIABLE: ColorStyleValue = 'var(--default-icon-color)';

const allAvailableColors: ColorValue[] = [
    '000000', // black
    '8e8e93', // gray
    'ff3b30', // red
    'ff2d55', // pink
    'ff6b22', // deep orange
    'ff9500', // orange
    'ffcc00', // yellow
    'cddc39', // lime
    '009688', // teal
    '4cd964', // green
    '5ac8fa', // light blue
    '2196f3', // blue
    '673ab7', // deep purple
    '9c27b0', // purple
];

export const ALL_ACCOUNT_COLORS: ColorValue[] = allAvailableColors;
export const ALL_CATEGORY_COLORS: ColorValue[] = allAvailableColors;

export const DEFAULT_CHART_COLORS: ColorValue[] = [
    '8EB69B',
    '235347',
    '5A9E7E',
    '3D7A63',
    'A8CFB4',
    '6BB592',
    '2C5E4E',
    '163832',
    '7FC4A0',
    '4A8B72'
];
