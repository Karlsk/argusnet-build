#!/bin/bash
# 一键部署: 组装运行目录 → 镜像存在直接起, 缺失自动 docker-build → compose up
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

check_arch
check_mode
ensure_docker
check_deploy_arch

SIMG="$(server_image)"
AIMG="$(agent_image)"
if docker image inspect "$SIMG" >/dev/null 2>&1 && docker image inspect "$AIMG" >/dev/null 2>&1; then
    log "镜像已存在, 直接启动 ($SIMG / $AIMG)"
else
    log "镜像缺失, 自动构建..."
    bash "$SCRIPTS_DIR/docker-build.sh"
fi

# 必须在自动 build/docker-build 之后组装: VERSION 可能刚生成, 镜像 tag 随之变化
assemble_run

log "启动 compose..."
# compose 用 pull_policy: never (离线友好), 基础镜像缺失时在此预拉 (含加速站回退)
for img in postgres:12-alpine redis:7.0-alpine victoriametrics/victoria-metrics:v1.79.12; do
    if need_base_image "$img"; then
        log "拉取基础镜像 $img (linux/$ARCH)..."
        pull_image "$img" || die "拉取 $img 失败 (需要网络或可用的 REGISTRY_MIRROR)"
    fi
done
compose_cmd up -d || die "compose up 失败"

log "等待 server 就绪 (http://127.0.0.1:$HTTP_PORT)..."
code=000
for _ in $(seq 1 60); do
    code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$HTTP_PORT/" || true)"
    if [ "$code" = "200" ]; then
        break
    fi
    sleep 2
done
if [ "$code" != "200" ]; then
    compose_cmd logs --tail=50 || true
    die "server 120s 内未就绪 (HTTP $code), 见上方日志"
fi

log "部署完成!"
log "  访问地址: http://127.0.0.1:$HTTP_PORT (默认账号 root/root.2020)"
log "  查看状态: make ps    查看日志: make logs    停止: make down"