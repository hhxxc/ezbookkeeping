/**
 * 精简 line-awesome 图标字体 CSS。
 *
 * 完整版 line-awesome.css 定义了 1000+ 个图标（110KB，移动端首屏 CSS 里占 78.9KB /
 * 15.8KB gzip，而且是渲染阻塞资源），项目实际只用到其中两三百个 —— 图标名全部来自
 * src/consts/icon.ts 的数组常量与模板里的字面量类名，没有运行时拼接，所以可以安全裁剪。
 *
 * 只删除「独立图标定义」规则（`.la-xxx:before { content: "\fxxx"; }`），
 * 基础类、尺寸修饰类（.la-lg/.la-2x…）、组合类（.la.la-xxx-o）一律保留。
 *
 * 用法：node scripts/prune-line-awesome.cjs
 * 新增图标后需要重跑一次（脚本会打印新增/缺失情况）。
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const SRC_DIR = path.join(ROOT, 'src');
const SOURCE_CSS = path.join(ROOT, 'node_modules/line-awesome/dist/line-awesome/css/line-awesome.css');
const OUTPUT_CSS = path.join(SRC_DIR, 'styles/line-awesome-pruned.css');

function walk(dir, exts, out = []) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, entry.name);

        if (full.includes('node_modules') || full.includes('.workbuddy')) {
            continue;
        }

        if (entry.isDirectory()) {
            walk(full, exts, out);
        } else if (exts.some(ext => entry.name.endsWith(ext))) {
            out.push(full);
        }
    }

    return out;
}

// 1. 收集用到的图标名（去掉 la- 前缀）
const used = new Set();
const files = walk(SRC_DIR, ['.vue', '.ts', '.scss', '.html']);

for (const file of files) {
    const text = fs.readFileSync(file, 'utf8');
    const matches = text.match(/la-[a-z0-9-]+/g);

    if (!matches) {
        continue;
    }

    for (const match of matches) {
        used.add(match.slice(3));
    }
}

// 2. 裁剪
const source = fs.readFileSync(SOURCE_CSS, 'utf8');
const iconRule = /\.la-([a-z0-9-]+):before\s*\{\s*content:\s*"[^"]*"\s*;\s*\}/g;
let totalIcons = 0;
let keptIcons = 0;
const keptNames = new Set();

const pruned = source.replace(iconRule, (full, name) => {
    totalIcons++;

    if (used.has(name)) {
        keptIcons++;
        keptNames.add(name);
        return full;
    }

    return '';
});

// 3. 检查白名单里有没有 CSS 中不存在的图标名（多半是修饰类或误匹配，正常）
const missing = [...used].filter(name => !keptNames.has(name) && /^[a-z0-9]+(-[a-z0-9]+)*$/.test(name));

// 4. 字体路径：原 CSS 在 node_modules/line-awesome/dist/line-awesome/css/ 下用 ../fonts/，
//    精简版落在 src/styles/，要指回同一个 node_modules 目录，Vite 才会把字体当 asset 处理
//    （并按 assetFileNames 规则输出带 hash 的 fonts/xxx）
const withFontPath = pruned.replace(/url\("\.\.\/fonts\//g, 'url("../../node_modules/line-awesome/dist/line-awesome/fonts/');

fs.writeFileSync(OUTPUT_CSS, withFontPath, 'utf8');

const kb = size => `${(size / 1024).toFixed(1)}KB`;

console.log(`扫描文件: ${files.length}`);
console.log(`源码中出现的图标名: ${used.size}`);
console.log(`CSS 中共有图标规则: ${totalIcons}，保留 ${keptIcons}，删除 ${totalIcons - keptIcons}`);
console.log(`输出: ${path.relative(ROOT, OUTPUT_CSS)}  ${kb(Buffer.byteLength(source))} -> ${kb(Buffer.byteLength(withFontPath))}`);
console.log(`白名单中不在 CSS 里的名字（修饰类/误匹配，可忽略）: ${missing.length ? missing.slice(0, 10).join(', ') : '无'}`);
