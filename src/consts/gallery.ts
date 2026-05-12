export interface GalleryBackground {
    id: string;
    name: string;
    css: string;
}

export const GALLERY_BACKGROUNDS: GalleryBackground[] = [
    // === Warm / Amber ===
    { id: 'warm-sunrise', name: '晨曦', css: 'linear-gradient(135deg, #f5af19 0%, #f12711 100%)' },
    { id: 'warm-amber', name: '琥珀', css: 'linear-gradient(135deg, #c67e48 0%, #e8a87c 50%, #f5d5b0 100%)' },
    { id: 'warm-autumn', name: '秋意', css: 'linear-gradient(160deg, #d66d75 0%, #e29587 100%)' },
    { id: 'warm-peach', name: '蜜桃', css: 'linear-gradient(135deg, #ff9a9e 0%, #fecfef 100%)' },
    { id: 'warm-fire', name: '火焰', css: 'linear-gradient(135deg, #f83600 0%, #f9d423 100%)' },
    { id: 'warm-coral', name: '珊瑚', css: 'linear-gradient(135deg, #ff7e5f 0%, #feb47b 100%)' },

    // === Cool / Blue ===
    { id: 'cool-ocean', name: '海洋', css: 'linear-gradient(135deg, #2193b0 0%, #6dd5ed 100%)' },
    { id: 'cool-sky', name: '天空', css: 'linear-gradient(160deg, #4facfe 0%, #00f2fe 100%)' },
    { id: 'cool-ice', name: '冰川', css: 'linear-gradient(135deg, #a1c4fd 0%, #c2e9fb 100%)' },
    { id: 'cool-deep', name: '深海', css: 'linear-gradient(135deg, #0f2027 0%, #203a43 50%, #2c5364 100%)' },
    { id: 'cool-mint', name: '薄荷', css: 'linear-gradient(135deg, #84fab0 0%, #8fd3f4 100%)' },
    { id: 'cool-twilight', name: '暮光', css: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)' },

    // === Nature / Green ===
    { id: 'nature-forest', name: '森林', css: 'linear-gradient(135deg, #11998e 0%, #38ef7d 100%)' },
    { id: 'nature-spring', name: '春天', css: 'linear-gradient(135deg, #a8e063 0%, #56ab2f 100%)' },
    { id: 'nature-tea', name: '抹茶', css: 'linear-gradient(135deg, #d4fc79 0%, #96e6a1 100%)' },
    { id: 'nature-moss', name: '青苔', css: 'linear-gradient(160deg, #3a7bd5 0%, #3a6073 50%, #2c8c5e 100%)' },
    { id: 'nature-bamboo', name: '翠竹', css: 'linear-gradient(135deg, #0ba360 0%, #3cba92 100%)' },
    { id: 'nature-herb', name: '草本', css: 'linear-gradient(135deg, #96c93d 0%, #5b8c2a 100%)' },

    // === Sunset / Evening ===
    { id: 'sunset-dusk', name: '黄昏', css: 'linear-gradient(135deg, #ff6e7f 0%, #bf8f60 100%)' },
    { id: 'sunset-purple', name: '紫霞', css: 'linear-gradient(135deg, #b224ef 0%, #5721b5 100%)' },
    { id: 'sunset-rose', name: '玫瑰', css: 'linear-gradient(135deg, #eecda3 0%, #ef629f 100%)' },
    { id: 'sunset-magenta', name: '洋红', css: 'linear-gradient(135deg, #f953c6 0%, #b91d73 100%)' },
    { id: 'sunset-golden', name: '金辉', css: 'linear-gradient(135deg, #f2994a 0%, #f2c94c 100%)' },
    { id: 'sunset-lavender', name: '薰衣草', css: 'linear-gradient(135deg, #a18cd1 0%, #fbc2eb 100%)' },

    // === Minimal / Monochrome ===
    { id: 'minimal-snow', name: '初雪', css: 'linear-gradient(135deg, #e6e9f0 0%, #eef1f5 100%)' },
    { id: 'minimal-ash', name: '灰阶', css: 'linear-gradient(135deg, #bdc3c7 0%, #8e9eab 100%)' },
    { id: 'minimal-ink', name: '水墨', css: 'linear-gradient(135deg, #2c3e50 0%, #1a1a2e 100%)' },
    { id: 'minimal-pearl', name: '珍珠', css: 'linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%)' },
    { id: 'minimal-charcoal', name: '炭灰', css: 'linear-gradient(135deg, #434343 0%, #1a1a1a 100%)' },
    { id: 'minimal-cloud', name: '云朵', css: 'linear-gradient(135deg, #d7d2cc 0%, #98969a 100%)' },
];
