#!/bin/bash
# 用 pkg/ 产物构建 docker 镜像。产物缺失自动调 build (链式兜底, MODE/ARCH 透传)。
# 产物存在(含手工替换的)时直接构建镜像, 不编译。
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

check_arch
check_mode
ensure_docker

if ! find_artifact server "n9e-linux-$ARCH" >/dev/null; then
    log "server 产物缺失, 自动编译..."
    bash "$SCRIPTS_DIR/build-server.sh"
fi
if ! find_artifact agent "categraf-linux-$ARCH" >/dev/null; then
    log "agent 产物缺失, 自动编译..."
    bash "$SCRIPTS_DIR/build-agent.sh"
fi
ensure_server_assets

# 预拉基础镜像 (Docker Hub 受限时走加速站), 避免 buildx 卡在远端元数据解析
for img in python:3-slim ubuntu:24.04; do
    if need_base_image "$img"; then
        log "拉取基础镜像 $img (linux/$ARCH)..."
        pull_image "$img" || die "拉取 $img 失败 (需要网络或可用的 REGISTRY_MIRROR)"
    fi
done

SIMG="$(server_image)"
AIMG="$(agent_image)"

CTX="$BUILD_ROOT/.work/image-server"
rm -rf "$CTX"
mkdir -p "$CTX"
cp "$BUILD_ROOT/pkg/server/n9e-linux-$ARCH" "$CTX/n9e"
cp -R "$BUILD_ROOT/pkg/server/etc" "$CTX/etc"
render_server_config "$CTX/etc/config.toml"
cp -R "$BUILD_ROOT/pkg/server/integrations" "$CTX/integrations"
cp "$BUILD_ROOT/deploy/server/Dockerfile" "$CTX/"
log "构建镜像 $SIMG (linux/$ARCH)..."
docker buildx build --platform "linux/$ARCH" --load -t "$SIMG" "$CTX" || die "server 镜像构建失败"

CTX="$BUILD_ROOT/.work/image-categraf"
rm -rf "$CTX"
mkdir -p "$CTX"
cp "$BUILD_ROOT/pkg/agent/categraf-linux-$ARCH" "$CTX/categraf"
cp -R "$BUILD_ROOT/deploy/categraf/conf" "$CTX/conf"
cp "$BUILD_ROOT/deploy/categraf/Dockerfile" "$CTX/"
cp "$BUILD_ROOT/deploy/categraf/entrypoint.sh" "$CTX/"
log "构建镜像 $AIMG (linux/$ARCH)..."
docker buildx build --platform "linux/$ARCH" --load -t "$AIMG" "$CTX" || die "categraf 镜像构建失败"

log "镜像构建完成: $SIMG / $AIMG"