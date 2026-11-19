#!/bin/bash
# 编译 server: 临时副本 + statik 嵌入前端 + 交叉编译, 源仓库零污染。
# 绝不运行源仓库 fe.sh (pub 缺失时它会静默下载 n9e 官方前端)。
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

check_arch
resolve_src server
log "编译 argusnet-server: $SRC_DIR"

VER="$(repo_version "$SRC_DIR")"

# pub 来源: PUB_DIR 显式指定 > pkg/web/pub (含手工替换的) > 自动补建 web
if [ -n "${PUB_DIR:-}" ]; then
    PUB="$PUB_DIR"
elif [ -d "$BUILD_ROOT/pkg/web/pub" ]; then
    PUB="$BUILD_ROOT/pkg/web/pub"
else
    log "缺少前端产物, 自动编译 web..."
    bash "$SCRIPTS_DIR/build-web.sh"
    PUB="$BUILD_ROOT/pkg/web/pub"
fi
[ -f "$PUB/index.html" ] || die "前端产物无效: $PUB/index.html 不存在"

STATIK="$(go env GOPATH)/bin/statik"
if [ ! -x "$STATIK" ]; then
    log "安装 statik..."
    go install github.com/rakyll/statik@latest || die "statik 安装失败"
fi

# 临时副本构建: statik 会重写 front/statik/statik.go, 不能污染源仓库
WORK="$BUILD_ROOT/.work/server-build"
rm -rf "$WORK"
mkdir -p "$WORK"
log "复制源码到临时构建目录 (排除 .git/pub/旧二进制)..."
rsync -a --exclude=.git --exclude=pub --exclude=n9e --exclude='n9e-*' "$SRC_DIR/" "$WORK/"
cp -R "$PUB" "$WORK/pub"

log "statik 嵌入前端..."
(cd "$WORK" && "$STATIK" -src=./pub -dest=./front) || die "statik 生成失败"
[ -f "$WORK/front/statik/statik.go" ] || die "statik.go 未生成"

mkdir -p "$BUILD_ROOT/.work/out"
log "交叉编译 n9e (linux/$ARCH, CGO_ENABLED=0, 版本 $VER)..."
(cd "$WORK" && CGO_ENABLED=0 GOOS=linux GOARCH="$ARCH" \
    go build -ldflags "-w -s -X github.com/ccfos/nightingale/v6/pkg/version.Version=$VER" \
    -o "$BUILD_ROOT/.work/out/n9e" ./cmd/center/main.go) || die "go build 失败"

mkdir -p "$BUILD_ROOT/pkg/server"
cp "$BUILD_ROOT/.work/out/n9e" "$BUILD_ROOT/pkg/server/n9e-linux-$ARCH"
rm -rf "$BUILD_ROOT/pkg/server/etc" "$BUILD_ROOT/pkg/server/integrations" "$BUILD_ROOT/pkg/server/initsql"
cp -R "$SRC_DIR/etc" "$BUILD_ROOT/pkg/server/etc"
cp -R "$SRC_DIR/integrations" "$BUILD_ROOT/pkg/server/integrations"
cp -R "$SRC_DIR/docker/compose-postgres/initsql_for_postgres" "$BUILD_ROOT/pkg/server/initsql"
printf '%s\n' "$VER" > "$BUILD_ROOT/pkg/server/VERSION"

log "server 产物: pkg/server/n9e-linux-$ARCH ($VER)"