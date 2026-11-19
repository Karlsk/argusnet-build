#!/bin/bash
# docker save 离线镜像包: 全套镜像 + compose + 配置 + install.sh → docker-pkg/*.tar.gz
# 目标机只需 docker + compose 插件, 解压执行 install.sh 即离线起全套。
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

check_arch
check_mode
ensure_docker

SIMG="$(server_image)"
AIMG="$(agent_image)"
if ! docker image inspect "$SIMG" >/dev/null 2>&1 || ! docker image inspect "$AIMG" >/dev/null 2>&1; then
    log "应用镜像缺失, 自动构建..."
    bash "$SCRIPTS_DIR/docker-build.sh"
fi

BASE_IMAGES="postgres:12-alpine redis:7.0-alpine victoriametrics/victoria-metrics:v1.79.12"
for img in $BASE_IMAGES; do
    if need_base_image "$img"; then
        log "拉取基础镜像 $img (linux/$ARCH)..."
        pull_image "$img" || die "拉取 $img 失败 (需要网络或可用的 REGISTRY_MIRROR)"
    fi
done

assemble_run

SERVER_VER="$(cat "$BUILD_ROOT/pkg/server/VERSION" 2>/dev/null || echo manual)"
NAME="argusnet-docker-$SERVER_VER-linux-$ARCH"
OUT="$BUILD_ROOT/docker-pkg/$NAME"
rm -rf "$OUT"
mkdir -p "$OUT"

# containerd 镜像存储下, 按平台拉取的多平台索引镜像缺少其他平台 blob, docker save 会失败。
# 用 buildx FROM 扁平化为单平台镜像后重新打回原 tag。
ensure_savable() {
    local img="$1"
    if docker save "$img" -o /dev/null 2>/dev/null; then
        return 0
    fi
    log "扁平化多平台镜像 $img (linux/$ARCH)..."
    local tmp="$BUILD_ROOT/.work/flatten"
    mkdir -p "$tmp"
    printf 'FROM %s\n' "$img" > "$tmp/Dockerfile"
    docker buildx build --platform "linux/$ARCH" --load -t "$img-flat" "$tmp" \
        || die "扁平化 $img 失败"
    docker tag "$img-flat" "$img"
    docker rmi "$img-flat" >/dev/null 2>&1 || true
}

for img in "$SIMG" "$AIMG" $BASE_IMAGES; do
    ensure_savable "$img"
done

log "docker save 镜像 (可能耗时数分钟)..."
# shellcheck disable=SC2086
docker save "$SIMG" "$AIMG" $BASE_IMAGES | gzip > "$OUT/images.tar.gz" || die "docker save 失败"

cp "$BUILD_ROOT/.work/run/docker-compose.yaml" "$OUT/"
cp "$BUILD_ROOT/.work/run/.env" "$OUT/"
cp -R "$BUILD_ROOT/.work/run/server" "$OUT/server"
cp -R "$BUILD_ROOT/.work/run/initsql" "$OUT/initsql"
cp -R "$BUILD_ROOT/.work/run/categraf-conf" "$OUT/categraf-conf"

cat > "$OUT/install.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
PKG_ARCH="$(grep '^TARGET_ARCH=' .env | cut -d= -f2)"
HOST_ARCH="$(docker info --format '{{.Architecture}}' 2>/dev/null || uname -m)"
case "$HOST_ARCH" in x86_64|amd64) HOST_ARCH=amd64 ;; aarch64|arm64) HOST_ARCH=arm64 ;; esac
if [ "$PKG_ARCH" != "$HOST_ARCH" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "[ERROR] 离线包架构 $PKG_ARCH 与宿主芯片 $HOST_ARCH 不一致 (跨架构需模拟运行)。FORCE=1 可强制安装" >&2
    exit 1
fi
echo "加载镜像..."
docker load -i images.tar.gz
sed -i.bak "s|^DATA_ROOT=.*|DATA_ROOT=$(pwd)/data|" .env
rm -f .env.bak
docker compose --env-file .env up -d
echo "ArgusNet 已部署: http://<本机IP>:17000 (默认账号 root/root.2020)"
EOF
chmod +x "$OUT/install.sh"

tar -czf "$BUILD_ROOT/docker-pkg/$NAME.tar.gz" -C "$BUILD_ROOT/docker-pkg" "$NAME"
log "离线包完成: docker-pkg/$NAME.tar.gz"
log "目标机使用: tar xzf $NAME.tar.gz && cd $NAME && ./install.sh"