#!/bin/sh
# 导出网页版到 build/web。不会自己下载任何东西。
root="$(cd "$(dirname "$0")/../.." && pwd)" || exit 1
if ! command -v godot >/dev/null 2>&1; then
	echo "找不到 godot 命令：请先安装 Godot 4.7.2，并确保终端里能直接运行 godot。"
	exit 1
fi
tpl="$HOME/Library/Application Support/Godot/export_templates/4.7.2.stable"
if [ ! -f "$tpl/web_nothreads_release.zip" ]; then
	echo "缺少网页导出模板：$tpl 下没有 web_nothreads_release.zip（导出预设用的是不带线程的版本）"
	echo "安装办法（二选一）："
	echo "  1. 打开 Godot 编辑器 → Editor → Manage Export Templates → 下载并安装 4.7.2 的模板"
	echo "  2. 到 Godot 官方发布页下载 4.7.2 的导出模板（Export templates 的 .tpz 文件），"
	echo "     解压后把里面 templates 文件夹的内容放进上面那个目录"
	echo "装好后再运行本脚本。"
	exit 1
fi
cd "$root" || exit 1
mkdir -p build/web || exit 1
godot --headless --path game --export-release Web || exit 1
echo "导出完成：$root/build/web/index.html"
echo "本地预览：python3 -m http.server -d \"$root/build/web\" 8060，然后打开 http://localhost:8060"
