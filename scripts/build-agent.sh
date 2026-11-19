#!/bin/bash
# 编译 agent (categraf): 交叉编译, 输出到 .work/out, 源仓库零污染
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

check_arch
resolve_src agent
log "编译 argusnet-agent: $SRC_DIR"

VER="$(repo_version "$SRC_DIR")"

mkdir -p "$BUILD_ROOT/.work/out"
log "交叉编译 categraf (linux/$ARCH, CGO_ENABLED=0, 版本 $VER)..."
(cd "$SRC_DIR" && CGO_ENABLED=0 GOOS=linux GOARCH="$ARCH" \
    go build -ldflags "-w -s -X flashcat.cloud/categraf/config.Version=$VER" \
    -o "$BUILD_ROOT/.work/out/categraf" .) || die "go build 失败"

mkdir -p "$BUILD_ROOT/pkg/agent"
cp "$BUILD_ROOT/.work/out/categraf" "$BUILD_ROOT/pkg/agent/categraf-linux-$ARCH"
rm -rf "$BUILD_ROOT/pkg/agent/conf"
cp -R "$SRC_DIR/conf" "$BUILD_ROOT/pkg/agent/conf"
printf '%s\n' "$VER" > "$BUILD_ROOT/pkg/agent/VERSION"

log "agent 产物: pkg/agent/categraf-linux-$ARCH ($VER)"