# CharDiff 字体字符对比

把两种字体并排放在**原点对齐**的网格里比较同一批字——看字形差异、字身宽窄、重心高低。给字体设计师做校对用的。

## 界面

- 左右两个字体槽：拖入字体文件，点槽（或右侧小箭头）从最近用过的字体里选，✕ 清除
- 中间「字符」输入框：粘贴要对比的字符，顺序随意、重复的照样显示；点「字符」两个字可以从 txt 读取
- 字号输入框：回车生效，鼠标停在上面滚轮也行
- 叠字模式：两种字体重叠在同一基线上，直接看轮廓差
- 参考线：标出每个字符的原点与基线
- 写 txt：选一个已有文件，点过的字**追加**进去，不会清空；也可以新建一个

## 命令行

```
CharDiff --a 字体A.ttf --b 字体B.ttf --text "永国这们" [--overlay] [--dark] [--export out.png]
```

`--export` 会等排版画完再截，长文本也能导出完整的 png。不带任何参数启动就是图形界面。

## 下载

编译好的 app 在 [Releases](https://github.com/birchmoonlight/CharDiff/releases)，解压拖进「应用程序」即可。要求 macOS 13 以上。

## 从源码构建

```
swift build -c release        # 只编译命令行版
./make-app.sh                 # 打包成可双击的 CharDiff.app（含图标）
python3 make-icon.py --out AppIcon.icns   # 单独重生成图标
```

偏好设置存在 `local.chardiff` 这个 suite 里，命令行版和 app 版共用。

---

# CharDiff

Compare the same batch of characters in two fonts side by side on an **origin-aligned** grid — for type designers reviewing glyphs during production.

- Two font slots (drag and drop), a character field (paste anything; duplicates show as-is), adjustable point size
- Overlay mode draws both fonts on the same baseline; guide lines mark each character's origin and baseline
- Characters clicked in the canvas are **appended** to a chosen txt file — existing content is never cleared
- CLI: `--a`/`--b`/`--text`/`--overlay`/`--dark`/`--export` — exports wait for layout to finish before capturing
- Prebuilt app on the [Releases](https://github.com/birchmoonlight/CharDiff/releases) page; macOS 13 or later
- `swift build -c release`, or `./make-app.sh` for the full app bundle with the avocado icon
