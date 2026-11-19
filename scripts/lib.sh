#!/bin/bash
# argusnet-build 公共库, 由各脚本 source。所有变量可被 make/config.mk 或环境变量覆盖。
set -euo pipefail

BUILD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$BUILD_ROOT/scripts"

export MODE="${MODE:-dev}"
export PROJECT="${PROJECT:-all}"
export ARCH="${ARCH:-$(uname -m | sed -e 's/^x86_64$/amd64/' -e 's/^aarch64$/arm64/')}"
export FORCE="${FORCE:-0}"
export BRANCH="${BRANCH:-main}"
export GIT_BASE="${GIT_BASE:-git@github.com:Karlsk}"
export GO_MIN="${GO_MIN:-1.26}"
export SERVER_IMAGE_REPO="${SERVER_IMAGE_REPO:-argusnet/server}"
export AGENT_IMAGE_REPO="${AGENT_IMAGE_REPO:-argusnet/categraf}"
export PG_USER="${PG_USER:-root}"
export PG_PASSWORD="${PG_PASSWORD:-1234}"
export PG_DB="${PG_DB:-n9e_v6}"
export HTTP_PORT="${HTTP_PORT:-17000}"
export IBEX_PORT="${IBEX_PORT:-20090}"
export VM_PORT="${VM_PORT:-8428}"
export DATA_ROOT="${DATA_ROOT:-$BUILD_ROOT/data}"
export SCOPE="${SCOPE:-work}"
export REGISTRY_MIRROR="${REGISTRY_MIRROR:-docker.m.daocloud.io}"

log()  { printf '[argusnet-build] %s\n' "$*"; }
warn() { printf '[argusnet-build][WARN] %s\n' "$*" >&2; }
die()  { printf '[argusnet-build][ERROR] %s\n' "$*" >&2; exit 1; }

check_arch() {
    case "$ARCH" in amd64|arm64) ;; *) die "ARCH 必须是 amd64 或 arm64 (当前: $ARCH)" ;; esac
}
check_mode() {
    case "$MODE" in dev|prod) ;; *) die "MODE 必须是 dev 或 prod (当前: $MODE)" ;; esac
}
check_project() {
    case "$PROJECT" in server|agent|web|all) ;; *) die "PROJECT 必须是 server|agent|web|all (当前: $PROJECT)" ;; esac
}

# 宿主芯片架构 (Docker Desktop VM 架构跟随宿主芯片)
host_arch() {
    local raw
    raw="$(docker info --format '{{.Architecture}}' 2>/dev/null || uname -m)"
    case "$raw" in
        x86_64|amd64) printf 'amd64' ;;
        aarch64|arm64) printf 'arm64' ;;
        *) printf '%s' "$raw" ;;
    esac
}
check_deploy_arch() {
    local harch
    harch="$(host_arch)"
    if [ "$ARCH" != "$harch" ] && [ "$FORCE" != "1" ]; then
        die "架构不匹配: ARCH=$ARCH 但宿主芯片为 $harch (跨架构需模拟运行, 性能差)。请用 ARCH=$harch, 或 FORCE=1 强制部署"
    fi
}

# version_ge A B: A >= B (按 major.minor 数值比较, 不依赖 GNU sort -V)
version_ge() {
    local a1 a2 b1 b2
    IFS='.' read -r a1 a2 _ <<<"$1"
    IFS='.' read -r b1 b2 _ <<<"$2"
    [ "$a1" -gt "$b1" ] || { [ "$a1" -eq "$b1" ] && [ "${a2:-0}" -ge "${b2:-0}" ]; }
}

# 版本号: git describe; 无 tag 时 v0.0.0-g<sha>; 脏工作区追加 -dirty
repo_version() {
    local dir="$1" v
    v="$(git -C "$dir" describe --tags --abbrev=14 2>/dev/null || true)"
    if [ -z "$v" ]; then
        v="v0.0.0-g$(git -C "$dir" rev-parse --short=14 HEAD)"
    fi
    if [ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]; then
        v="$v-dirty"
    fi
    printf '%s' "$v"
}

# 源码定位, 结果写入 SRC_DIR。缺失时自动 init 拉取。
# dev: 相邻工作区仓库优先(含未提交改动), 其次 src/; prod: 一律 src/
resolve_src() {
    local name="$1" src override=""
    case "$name" in
        server) override="${SERVER_SRC:-}" ;;
        web)    override="${WEB_SRC:-}" ;;
        agent)  override="${AGENT_SRC:-}" ;;
        *) die "未知项目: $name" ;;
    esac
    if [ "$MODE" != "prod" ] && [ -n "$override" ]; then
        [ -d "$override" ] || die "${name}_SRC 指定的目录不存在: $override"
        SRC_DIR="$override"
        return 0
    fi
    if [ "$MODE" = "prod" ]; then
        src="$BUILD_ROOT/src/argusnet-$name"
    elif [ -d "$BUILD_ROOT/../argusnet-$name/.git" ]; then
        src="$(cd "$BUILD_ROOT/../argusnet-$name" && pwd)"
    else
        src="$BUILD_ROOT/src/argusnet-$name"
    fi
    if [ ! -d "$src/.git" ]; then
        log "源码 argusnet-$name 缺失, 自动执行 init 拉取..."
        bash "$SCRIPTS_DIR/init.sh"
    fi
    [ -d "$src/.git" ] || die "init 后仍找不到 argusnet-$name 源码: $src"
    SRC_DIR="$src"
}

ensure_docker() {
    command -v docker >/dev/null 2>&1 || die "未安装 docker"
    docker info >/dev/null 2>&1 || die "docker daemon 无法连接 (Docker Desktop 是否已启动?)"
    docker compose version >/dev/null 2>&1 || die "缺少 docker compose v2 插件"
}

image_tag() {
    local proj="$1" ver
    ver="$(cat "$BUILD_ROOT/pkg/$proj/VERSION" 2>/dev/null || true)"
    [ -n "$ver" ] || ver="manual"
    printf '%s-%s' "$ver" "$ARCH"
}
server_image() { printf '%s:%s' "$SERVER_IMAGE_REPO" "$(image_tag server)"; }
agent_image()  { printf '%s:%s' "$AGENT_IMAGE_REPO" "$(image_tag agent)"; }

render_server_config() {
    sed -e "s|@PG_USER@|$PG_USER|g" \
        -e "s|@PG_PASSWORD@|$PG_PASSWORD|g" \
        -e "s|@PG_DB@|$PG_DB|g" \
        "$BUILD_ROOT/deploy/server/config.toml.tmpl" > "$1"
}

# 部署资产 etc/integrations/initsql 缺失时从源码仓库补齐(只拷贝, 不编译)
ensure_server_assets() {
    if [ ! -d "$BUILD_ROOT/pkg/server/etc" ] || [ ! -d "$BUILD_ROOT/pkg/server/integrations" ]; then
        resolve_src server
        mkdir -p "$BUILD_ROOT/pkg/server"
        rm -rf "$BUILD_ROOT/pkg/server/etc" "$BUILD_ROOT/pkg/server/integrations"
        cp -R "$SRC_DIR/etc" "$BUILD_ROOT/pkg/server/etc"
        cp -R "$SRC_DIR/integrations" "$BUILD_ROOT/pkg/server/integrations"
    fi
    if [ ! -d "$BUILD_ROOT/pkg/server/initsql" ]; then
        resolve_src server
        cp -R "$SRC_DIR/docker/compose-postgres/initsql_for_postgres" "$BUILD_ROOT/pkg/server/initsql"
    fi
}

# 固定名产物优先; 缺失时从 pkg/<proj>/ 最新单项目 tar 恢复。成功 echo 路径。
find_artifact() {
    local proj="$1" fixed="$2" dir tar tmp path d
    dir="$BUILD_ROOT/pkg/$proj"
    path="$dir/$fixed"
    if [ -e "$path" ]; then
        printf '%s' "$path"
        return 0
    fi
    tar="$(ls -t "$dir"/*.tar.gz 2>/dev/null | head -n1 || true)"
    [ -n "$tar" ] || return 1
    log "固定名产物 $fixed 缺失, 从 $(basename "$tar") 恢复..."
    tmp="$BUILD_ROOT/.work/restore-$proj"
    rm -rf "$tmp"
    mkdir -p "$tmp"
    tar -xzf "$tar" -C "$tmp"
    case "$proj" in
        server)
            [ -f "$tmp/n9e" ] || return 1
            cp "$tmp/n9e" "$path"
            for d in etc integrations initsql; do
                if [ -d "$tmp/$d" ]; then
                    rm -rf "$dir/$d"
                    cp -R "$tmp/$d" "$dir/$d"
                fi
            done
            ;;
        agent)
            [ -f "$tmp/categraf" ] || return 1
            cp "$tmp/categraf" "$path"
            if [ -d "$tmp/conf" ]; then
                rm -rf "$dir/conf"
                cp -R "$tmp/conf" "$dir/conf"
            fi
            ;;
        web)
            [ -d "$tmp/pub" ] || return 1
            rm -rf "$dir/pub"
            cp -R "$tmp/pub" "$dir/pub"
            ;;
    esac
    if [ -f "$tmp/VERSION" ]; then
        cp "$tmp/VERSION" "$dir/VERSION"
    fi
    printf '%s' "$path"
}

# 组装 compose 运行目录 .work/run/ (幂等), deploy 与 docker-pack 共用
assemble_run() {
    local RUN="$BUILD_ROOT/.work/run"
    ensure_server_assets
    rm -rf "$RUN"
    mkdir -p "$RUN/server" "$RUN/initsql"
    cp "$BUILD_ROOT/deploy/docker-compose.yaml" "$RUN/"
    cp -R "$BUILD_ROOT/pkg/server/etc" "$RUN/server/etc"
    cp -R "$BUILD_ROOT/pkg/server/integrations" "$RUN/server/integrations"
    render_server_config "$RUN/server/etc/config.toml"
    if [ -d "$BUILD_ROOT/pkg/server/initsql" ]; then
        cp "$BUILD_ROOT/pkg/server/initsql/"*.sql "$RUN/initsql/"
    else
        cp "$BUILD_ROOT/deploy/initsql/"*.sql "$RUN/initsql/"
    fi
    cp -R "$BUILD_ROOT/deploy/categraf/conf" "$RUN/categraf-conf"
    cat > "$RUN/.env" <<EOF
SERVER_IMAGE=$(server_image)
AGENT_IMAGE=$(agent_image)
TARGET_ARCH=$ARCH
DATA_ROOT=$DATA_ROOT
PG_USER=$PG_USER
PG_PASSWORD=$PG_PASSWORD
PG_DB=$PG_DB
HTTP_PORT=$HTTP_PORT
IBEX_PORT=$IBEX_PORT
VM_PORT=$VM_PORT
EOF
}

compose_cmd() {
    docker compose -f "$BUILD_ROOT/.work/run/docker-compose.yaml" \
        --env-file "$BUILD_ROOT/.work/run/.env" "$@"
}

# 拉取镜像: Docker Hub 直连失败时回退加速站, 成功后 retag 为官方名
pull_image() {
    local img="$1"
    if docker pull --platform "linux/$ARCH" "$img"; then
        return 0
    fi
    if [ -n "$REGISTRY_MIRROR" ]; then
        warn "直拉 $img 失败, 尝试加速站 $REGISTRY_MIRROR ..."
        local mirrored="$REGISTRY_MIRROR/$img"
        case "$img" in
            */*) ;;
            *) mirrored="$REGISTRY_MIRROR/library/$img" ;;
        esac
        if docker pull --platform "linux/$ARCH" "$mirrored"; then
            docker tag "$mirrored" "$img"
            return 0
        fi
    fi
    return 1
}

# 基础镜像是否需要(重)拉: tag 缺失, 或 containerd 存储下多平台索引缺目标平台 blob (tree 显示 0B)
need_base_image() {
    local img="$1" line
    docker image inspect "$img" >/dev/null 2>&1 || return 0
    line="$(docker image ls --tree "$img" 2>/dev/null | grep -E "linux/$ARCH([/[:space:]]|$)" | head -1)"
    if [ -z "$line" ]; then
        [ "$(docker image inspect "$img" --format '{{.Architecture}}' 2>/dev/null)" = "$ARCH" ] && return 1
        return 0
    fi
    echo "$line" | grep -q '0B' && return 0
    return 1
}