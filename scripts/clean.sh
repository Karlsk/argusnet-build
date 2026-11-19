#!/bin/bash
# 清理。SCOPE=work(默认)|pkg|docker|data|all。永不触碰 src/ 与相邻工作区仓库。
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

clean_data() {
    local ans
    read -r -p "即将删除 data/ (PG/VM/Redis 数据将丢失, 下次部署重新初始化 SQL), 确认? [y/N] " ans
    if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
        rm -rf "$BUILD_ROOT/data"
        mkdir -p "$BUILD_ROOT/data"
        log "data/ 已清理"
    else
        log "已取消 data/ 清理"
    fi
}

case "$SCOPE" in
    work)
        rm -rf "$BUILD_ROOT/.work"
        log ".work/ 已清理"
        ;;
    pkg)
        rm -rf "$BUILD_ROOT/pkg"
        mkdir -p "$BUILD_ROOT/pkg/server" "$BUILD_ROOT/pkg/web" "$BUILD_ROOT/pkg/agent"
        log "pkg/ 已清理"
        ;;
    docker)
        rm -rf "$BUILD_ROOT/docker-pkg"
        mkdir -p "$BUILD_ROOT/docker-pkg"
        log "docker-pkg/ 已清理"
        ;;
    data)
        clean_data
        ;;
    all)
        if [ -f "$BUILD_ROOT/.work/run/docker-compose.yaml" ]; then
            compose_cmd down || true
        fi
        rm -rf "$BUILD_ROOT/.work" "$BUILD_ROOT/pkg" "$BUILD_ROOT/docker-pkg"
        mkdir -p "$BUILD_ROOT/pkg/server" "$BUILD_ROOT/pkg/web" "$BUILD_ROOT/pkg/agent" "$BUILD_ROOT/docker-pkg"
        clean_data
        log "清理完成 (src/ 未动)"
        ;;
    *)
        die "SCOPE 必须是 work|pkg|docker|data|all (当前: $SCOPE)"
        ;;
esac