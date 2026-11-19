#!/bin/bash
# 编译分发器。PROJECT=server|agent|web|all; MODE=prod 时先全量刷新 src/ 与 pkg/
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

check_arch
check_mode
check_project

if [ "$MODE" = "prod" ]; then
    log "MODE=prod: 全量刷新 (删除旧代码与编译产物, 拉取 git 最新)"
    if [ "$PROJECT" = "all" ]; then
        rm -rf "$BUILD_ROOT/src" "$BUILD_ROOT/pkg"
    else
        rm -rf "$BUILD_ROOT/src/argusnet-$PROJECT" "$BUILD_ROOT/pkg/$PROJECT"
    fi
    bash "$SCRIPTS_DIR/init.sh"
fi

case "$PROJECT" in
    web)    bash "$SCRIPTS_DIR/build-web.sh" ;;
    server) bash "$SCRIPTS_DIR/build-server.sh" ;;
    agent)  bash "$SCRIPTS_DIR/build-agent.sh" ;;
    all)
        # 顺序关键: web 先产出 pub 供 server 嵌入
        bash "$SCRIPTS_DIR/build-web.sh"
        bash "$SCRIPTS_DIR/build-server.sh"
        bash "$SCRIPTS_DIR/build-agent.sh"
        ;;
esac

log "build 完成 (PROJECT=$PROJECT MODE=$MODE ARCH=$ARCH)"