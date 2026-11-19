#!/bin/bash
# 一键初始化: 环境检查 + 拉取三仓库到 src/ + 安装 statik
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

log "检查基础工具..."
for t in git curl rsync tar; do
    command -v "$t" >/dev/null 2>&1 || die "缺少工具: $t"
done

command -v go >/dev/null 2>&1 || die "未安装 Go (需要 >= $GO_MIN): https://go.dev/dl/"
GO_VER="$(go version | awk '{print $3}' | sed 's/^go//')"
version_ge "$GO_VER" "$GO_MIN" || die "Go 版本 $GO_VER 过低, 需要 >= $GO_MIN (argusnet-agent go.mod 要求)"
log "go $GO_VER OK"

command -v node >/dev/null 2>&1 || die "未安装 Node.js (需要 ^20.19.0 || >=22.12.0)"
NODE_VER="$(node --version | sed 's/^v//')"
NODE_MAJOR="${NODE_VER%%.*}"
NODE_REST="${NODE_VER#*.}"
NODE_MINOR="${NODE_REST%%.*}"
node_ok=0
if [ "$NODE_MAJOR" -eq 20 ] && [ "$NODE_MINOR" -ge 19 ]; then node_ok=1; fi
if [ "$NODE_MAJOR" -gt 22 ]; then node_ok=1; fi
if [ "$NODE_MAJOR" -eq 22 ] && [ "$NODE_MINOR" -ge 12 ]; then node_ok=1; fi
[ "$node_ok" = 1 ] || die "Node 版本 $NODE_VER 不满足 engines (^20.19.0 || >=22.12.0)"
command -v npm >/dev/null 2>&1 || die "缺少 npm"
log "node $NODE_VER OK"

ensure_docker
docker buildx version >/dev/null 2>&1 || die "缺少 docker buildx"
log "docker / compose / buildx OK"

STATIK="$(go env GOPATH)/bin/statik"
if [ ! -x "$STATIK" ]; then
    log "安装 statik (前端嵌入工具)..."
    go install github.com/rakyll/statik@latest || die "statik 安装失败"
fi
log "statik OK"

if ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    log "GitHub SSH 连通 OK"
else
    warn "GitHub SSH 认证未通过 (dev 模式可用相邻工作区仓库; prod 模式必须能访问 git)"
fi

mkdir -p "$BUILD_ROOT/src"
for name in server web agent; do
    repo="argusnet-$name"
    if [ -d "$BUILD_ROOT/src/$repo/.git" ]; then
        log "src/$repo 已存在, fetch 最新..."
        git -C "$BUILD_ROOT/src/$repo" fetch origin "$BRANCH" || warn "fetch 失败: $repo"
    else
        log "clone $repo → src/$repo ..."
        git clone --branch "$BRANCH" "$GIT_BASE/$repo.git" "$BUILD_ROOT/src/$repo" \
            || die "clone 失败: $repo (检查 SSH key 与网络)"
    fi
done

mkdir -p "$BUILD_ROOT/pkg/server" "$BUILD_ROOT/pkg/web" "$BUILD_ROOT/pkg/agent" \
         "$BUILD_ROOT/docker-pkg" "$BUILD_ROOT/data" "$BUILD_ROOT/.work"
if [ ! -f "$BUILD_ROOT/.env" ]; then
    cp "$BUILD_ROOT/.env.example" "$BUILD_ROOT/.env"
fi

log "init 完成:"
for name in server web agent; do
    log "  src/argusnet-$name @ $(git -C "$BUILD_ROOT/src/argusnet-$name" rev-parse --short HEAD 2>/dev/null || echo '?')"
done
log "下一步: make build-deploy MODE=dev"