include config.mk
export

.DEFAULT_GOAL := help

COMPOSE = docker compose -f .work/run/docker-compose.yaml --env-file .work/run/.env

.PHONY: help init build deploy build-deploy pack docker-build docker-pack up down restart logs ps clean

help:
	@echo "argusnet-build —— ArgusNet 一键编译/打包/部署"
	@echo ""
	@echo "目标:"
	@echo "  init          环境检查 + 拉取三仓库到 src/ + 安装 statik"
	@echo "  build         编译二进制/pub 到 pkg/ (PROJECT=server|agent|web|all)"
	@echo "  docker-build  用 pkg/ 产物构建 docker 镜像 (产物缺失自动 build)"
	@echo "  deploy        部署: 镜像存在直接起, 缺失自动 docker-build"
	@echo "  build-deploy  一键编译部署: build + docker-build + deploy"
	@echo "  pack          打部署 tar 包到 pkg/ (PROJECT 可选单项目)"
	@echo "  docker-pack   docker save 离线镜像包到 docker-pkg/ (含 install.sh)"
	@echo "  up/down/restart/logs/ps   操作已部署的 compose"
	@echo "  clean         清理 SCOPE=work(默认)|pkg|docker|data|all"
	@echo ""
	@echo "变量 (config.mk 可改, 命令行可覆盖):"
	@echo "  MODE=dev|prod   dev=编译本地代码(相邻工作区仓库优先); prod=每次删旧代码/产物, 拉 git 最新编译"
	@echo "  PROJECT=server|agent|web|all   ARCH=amd64|arm64   BRANCH=main"
	@echo "  PG_USER/PG_PASSWORD/PG_DB  HTTP_PORT/IBEX_PORT/VM_PORT  DATA_ROOT"
	@echo ""
	@echo "示例:"
	@echo "  make init"
	@echo "  make build-deploy MODE=dev              # 开发: 编译本地代码并部署"
	@echo "  make build-deploy MODE=prod ARCH=arm64  # 生产: 拉最新代码全量编译部署"
	@echo "  make build PROJECT=server               # 只编译 server"
	@echo "  make docker-build && make deploy        # 手工替换 pkg/ 产物后重建镜像部署"
	@echo "  make docker-pack                        # 生成离线部署包"

init:
	@bash scripts/init.sh

build:
	@bash scripts/build.sh

docker-build:
	@bash scripts/docker-build.sh

deploy:
	@bash scripts/deploy.sh

build-deploy:
	@bash scripts/build.sh && bash scripts/docker-build.sh && bash scripts/deploy.sh

pack:
	@bash scripts/pack.sh

docker-pack:
	@bash scripts/docker-pack.sh

up:
	@test -f .work/run/docker-compose.yaml || { echo "尚未部署, 先执行 make deploy"; exit 1; }
	@$(COMPOSE) up -d

down:
	@test -f .work/run/docker-compose.yaml || { echo "尚未部署, 先执行 make deploy"; exit 1; }
	@$(COMPOSE) down

restart:
	@test -f .work/run/docker-compose.yaml || { echo "尚未部署, 先执行 make deploy"; exit 1; }
	@$(COMPOSE) restart

logs:
	@test -f .work/run/docker-compose.yaml || { echo "尚未部署, 先执行 make deploy"; exit 1; }
	@$(COMPOSE) logs -f --tail=100

ps:
	@test -f .work/run/docker-compose.yaml || { echo "尚未部署, 先执行 make deploy"; exit 1; }
	@$(COMPOSE) ps

clean:
	@bash scripts/clean.sh