#!/bin/bash
# 打部署 tar 包到 pkg/。PROJECT=all 整包; 单项目打对应子集。
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

check_arch
check_project

SERVER_VER="$(cat "$BUILD_ROOT/pkg/server/VERSION" 2>/dev/null || echo manual)"
STAGE_ROOT="$BUILD_ROOT/.work/pack"
rm -rf "$STAGE_ROOT"
mkdir -p "$STAGE_ROOT"

pack_server() {
    find_artifact server "n9e-linux-$ARCH" >/dev/null || die "缺少 server 产物, 先 make build PROJECT=server ARCH=$ARCH"
    ensure_server_assets
    local stage="$1"
    mkdir -p "$stage"
    cp "$BUILD_ROOT/pkg/server/n9e-linux-$ARCH" "$stage/n9e"
    cp -R "$BUILD_ROOT/pkg/server/etc" "$stage/etc"
    cp -R "$BUILD_ROOT/pkg/server/integrations" "$stage/integrations"
    cp -R "$BUILD_ROOT/pkg/server/initsql" "$stage/initsql"
    cp "$BUILD_ROOT/pkg/server/VERSION" "$stage/VERSION"
}

pack_agent() {
    find_artifact agent "categraf-linux-$ARCH" >/dev/null || die "缺少 agent 产物, 先 make build PROJECT=agent ARCH=$ARCH"
    local stage="$1"
    mkdir -p "$stage"
    cp "$BUILD_ROOT/pkg/agent/categraf-linux-$ARCH" "$stage/categraf"
    cp -R "$BUILD_ROOT/pkg/agent/conf" "$stage/conf"
    cp "$BUILD_ROOT/pkg/agent/VERSION" "$stage/VERSION"
}

case "$PROJECT" in
    server)
        NAME="n9e-$SERVER_VER-linux-$ARCH"
        pack_server "$STAGE_ROOT/$NAME"
        tar -czf "$BUILD_ROOT/pkg/server/$NAME.tar.gz" -C "$STAGE_ROOT" "$NAME"
        log "打包完成: pkg/server/$NAME.tar.gz"
        ;;
    agent)
        AGENT_VER="$(cat "$BUILD_ROOT/pkg/agent/VERSION" 2>/dev/null || echo manual)"
        NAME="categraf-$AGENT_VER-linux-$ARCH"
        pack_agent "$STAGE_ROOT/$NAME"
        tar -czf "$BUILD_ROOT/pkg/agent/$NAME.tar.gz" -C "$STAGE_ROOT" "$NAME"
        log "打包完成: pkg/agent/$NAME.tar.gz"
        ;;
    web)
        if [ ! -d "$BUILD_ROOT/pkg/web/pub" ]; then
            find_artifact web pub >/dev/null || die "缺少 web 产物, 先 make build PROJECT=web"
        fi
        WEB_VER="$(cat "$BUILD_ROOT/pkg/web/VERSION" 2>/dev/null || echo manual)"
        tar -czf "$BUILD_ROOT/pkg/web/pub-$WEB_VER.tar.gz" -C "$BUILD_ROOT/pkg/web" pub
        log "打包完成: pkg/web/pub-$WEB_VER.tar.gz"
        ;;
    all)
        NAME="argusnet-$SERVER_VER-linux-$ARCH"
        STAGE="$STAGE_ROOT/$NAME"
        mkdir -p "$STAGE"
        pack_server "$STAGE/server"
        pack_agent "$STAGE/categraf"
        # 部署用 conf (容器名版) 覆盖分发用 conf
        rm -rf "$STAGE/categraf/conf"
        cp -R "$BUILD_ROOT/deploy/categraf/conf" "$STAGE/categraf/conf"
        if [ -d "$BUILD_ROOT/pkg/web/pub" ]; then
            cp -R "$BUILD_ROOT/pkg/web/pub" "$STAGE/pub"
        fi
        cp -R "$BUILD_ROOT/deploy" "$STAGE/deploy"
        {
            echo "server: $SERVER_VER"
            echo "agent:  $(cat "$BUILD_ROOT/pkg/agent/VERSION" 2>/dev/null || echo manual)"
            echo "web:    $(cat "$BUILD_ROOT/pkg/web/VERSION" 2>/dev/null || echo absent)"
            echo "arch:   linux/$ARCH"
        } > "$STAGE/VERSIONS"
        tar -czf "$BUILD_ROOT/pkg/$NAME.tar.gz" -C "$STAGE_ROOT" "$NAME"
        log "打包完成: pkg/$NAME.tar.gz"
        ;;
esac