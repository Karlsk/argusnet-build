#!/bin/bash
# 编译前端: npm ci + npm run build → pkg/web/pub + pub tar
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

check_arch
resolve_src web
log "编译 argusnet-web: $SRC_DIR"

VER="$(node -p "require('$SRC_DIR/package.json').version")"
case "$VER" in v*) ;; *) VER="v$VER" ;; esac

cd "$SRC_DIR"
npm ci || die "npm ci 失败 (若为 @flashcatcloud 私有包, 检查 .npmrc/registry 认证)"
npm run build || die "npm run build 失败"
[ -f pub/index.html ] || die "构建产物异常: pub/index.html 不存在"

mkdir -p "$BUILD_ROOT/pkg/web"
rm -rf "$BUILD_ROOT/pkg/web/pub"
cp -R pub "$BUILD_ROOT/pkg/web/pub"
printf '%s\n' "$VER" > "$BUILD_ROOT/pkg/web/VERSION"
tar -czf "$BUILD_ROOT/pkg/web/pub-$VER.tar.gz" -C "$BUILD_ROOT/pkg/web" pub

log "web 产物: pkg/web/pub/ ($VER)"