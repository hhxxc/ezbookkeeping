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

// 5. @font-face：指向仓库内的子集字体；regular（lar- 前缀）全项目未使用，整条删掉
let finalCss = withFontPath;
const faces = [...finalCss.matchAll(/@font-face \{[^}]*\}/g)].reverse();

for (const face of faces) {
    const block = face[0];
    let replacement = null;

    if (block.includes("'Line Awesome Brands'")) {
        replacement = `@font-face {
  font-family: 'Line Awesome Brands';
  font-style: normal;
  font-weight: normal;
  font-display: swap;
  src: url("../assets/fonts/la-brands-400-subset.woff2") format("woff2"); }`;
    } else if (block.includes('font-weight: 900;')) {
        replacement = `@font-face {
  font-family: 'Line Awesome Free';
  font-style: normal;
  font-weight: 900;
  font-display: swap;
  src: url("../assets/fonts/la-solid-900-subset.woff2") format("woff2"); }`;
    } else if (block.includes('font-weight: 400;')) {
        replacement = '';
    }

    if (replacement !== null) {
        finalCss = finalCss.slice(0, face.index) + replacement + finalCss.slice(face.index + block.length);
    }
}

fs.writeFileSync(OUTPUT_CSS, finalCss, 'utf8');

const kb = size => `${(size / 1024).toFixed(1)}KB`;

// 同时导出 codepoint 列表，供字体子集化使用（pyftsubset --unicodes-file）
const codes = [...pruned.matchAll(/\.la-([a-z0-9-]+):before\s*\{\s*content:\s*"\\([0-9a-f]+)"\s*;\s*\}/g)]
    .map(m => 'U+' + m[2]);
const CODES_FILE = path.join(SRC_DIR, 'assets/fonts/la-codepoints.txt');

fs.writeFileSync(CODES_FILE, codes.join('\n'), 'utf8');

console.log(`扫描文件: ${files.length}`);
console.log(`源码中出现的图标名: ${used.size}`);
console.log(`CSS 中共有图标规则: ${totalIcons}，保留 ${keptIcons}，删除 ${totalIcons - keptIcons}`);
console.log(`输出: ${path.relative(ROOT, OUTPUT_CSS)}  ${kb(Buffer.byteLength(source))} -> ${kb(Buffer.byteLength(withFontPath))}`);
console.log(`字符集: ${path.relative(ROOT, CODES_FILE)}  ${codes.length} 个 codepoint`);
console.log(`白名单中不在 CSS 里的名字（修饰类/误匹配，可忽略）: ${missing.length ? missing.slice(0, 10).join(', ') : '无'}`);
console.log('');
console.log('⚠️ 图标有增减时，除了本脚本还要重新生成子集字体（否则新图标没有字形）：');
console.log('   uvx --from fonttools --with brotli pyftsubset node_modules/line-awesome/dist/line-awesome/fonts/la-solid-900.woff2 \\');
console.log('     --unicodes-file=src/assets/fonts/la-codepoints.txt --flavor=woff2 --output-file=src/assets/fonts/la-solid-900-subset.woff2');
console.log('   （brands 同理，把 la-solid-900 换成 la-brands-400）');
console.log('   子集字体只保留 CSS 里出现的字符，solid 覆盖约 236 个、brands 约 44 个，两者互补。');
