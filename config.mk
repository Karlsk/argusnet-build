# argusnet-build default variables. Override on the command line, e.g.
#   make build-deploy MODE=prod ARCH=arm64
MODE    ?= dev
PROJECT ?= all
# 默认跟随宿主芯片 (x86_64→amd64, aarch64/arm64→arm64); 跨架构打包时显式覆盖
ARCH    ?= $(shell uname -m | sed -e 's/^x86_64$$/amd64/' -e 's/^aarch64$$/arm64/')
# deploy 架构与宿主不一致时默认阻断; FORCE=1 允许跨架构模拟部署
FORCE   ?= 0
BRANCH  ?= main
GIT_BASE ?= git@github.com:Karlsk
GO_MIN  ?= 1.26

SERVER_IMAGE_REPO ?= argusnet/server
AGENT_IMAGE_REPO  ?= argusnet/categraf

PG_USER     ?= root
PG_PASSWORD ?= 1234
PG_DB       ?= n9e_v6

HTTP_PORT ?= 17000
IBEX_PORT ?= 20090
VM_PORT   ?= 8428

DATA_ROOT ?= $(CURDIR)/data
SCOPE     ?= work
# Docker Hub 直连失败时回退的镜像加速站 (置空则禁用回退)
REGISTRY_MIRROR ?= docker.m.daocloud.io