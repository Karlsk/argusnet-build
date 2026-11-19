# argusnet-build

ArgusNet（argusnet-server / argusnet-web / argusnet-agent）统一编译、打包、部署入口。
Makefile + shell 实现，部署形态为单机 Docker Compose：**PostgreSQL + Redis + VictoriaMetrics + n9e(server) + categraf(agent)**，前端 pub 经 statik 嵌入 n9e 二进制。

## 快速开始

```bash
make init                        # 环境检查 + 拉取三仓库到 src/ + 安装 statik
make build-deploy MODE=dev       # 一键编译本地代码并部署
# 浏览器访问 http://127.0.0.1:17000  默认账号 root/root.2020
```

## 目标

| 目标 | 说明 |
|---|---|
| `init` | 检查 go(>=1.26)/node(^20.19\|\|>=22.12)/docker/compose/buildx，clone 三仓库到 `src/`，安装 statik |
| `build` | 编译二进制/pub 到 `pkg/`。`PROJECT=server\|agent\|web\|all` |
| `docker-build` | 用 `pkg/` 产物构建镜像；产物缺失自动调 build |
| `deploy` | 镜像已存在直接 compose up；缺失自动 docker-build |
| `build-deploy` | build + docker-build + deploy 全链 |
| `pack` | 部署 tar 包 → `pkg/`（PROJECT 可选单项目） |
| `docker-pack` | docker save 离线镜像包 → `docker-pkg/`（含 install.sh） |
| `up/down/restart/logs/ps` | 操作已部署的 compose |
| `clean` | `SCOPE=work`(默认)`\|pkg\|docker\|data\|all` |

## 变量（config.mk 可改，命令行覆盖）

- `MODE=dev|prod`
  - **dev**：编译本地代码。源码优先取相邻工作区仓库 `../argusnet-{server,web,agent}`（含未提交改动），其次 `src/`
  - **prod**：每次**删除 `src/` 旧代码与 `pkg/` 旧产物**，从 git 拉取最新代码再编译（只删本目录内的克隆，不碰工作区仓库）
- `PROJECT=server|agent|web|all`（默认 all）
- `ARCH=amd64|arm64`（默认自动跟随宿主芯片，产物名与镜像 tag 带架构后缀；跨架构打包时显式指定）
- `FORCE=1`（deploy/离线安装时架构与宿主芯片不一致默认阻断，FORCE=1 允许跨架构模拟部署）
- `BRANCH`（默认 main）、`GIT_BASE`（默认 git@github.com:Karlsk）
- `PG_USER/PG_PASSWORD/PG_DB`（默认 root/1234/n9e_v6）
- `HTTP_PORT/IBEX_PORT/VM_PORT`（默认 17000/20090/8428）
- `DATA_ROOT`（compose 持久化数据目录，默认 ./data）
- `SERVER_SRC/WEB_SRC/AGENT_SRC`：dev 模式显式指定源码目录
- `PUB_DIR`：build-server 时显式指定前端 pub 目录

## 目录约定

```
src/         prod 模式克隆的源码（构建专用，勿手改，每次 prod 会删掉重拉）
pkg/         编译产物（部署就绪，可手工替换）
  server/    n9e-linux-<arch> 二进制 + etc/ + integrations/ + initsql/ + VERSION
  web/       pub/ + VERSION
  agent/     categraf-linux-<arch> + conf/ + VERSION
docker-pkg/  docker save 离线包
data/        PG/VM/Redis 持久化数据
.work/       临时区（server 副本构建、镜像上下文、compose 运行目录）
deploy/      部署模板（compose、Dockerfile、配置模板、categraf conf、SQL 快照）
```

## 手工替换产物部署（dev）

`pkg/<proj>/` 下的固定名文件是部署就绪产物，可直接替换：

```bash
# 替换 server 二进制后重建镜像部署（不触发源码编译）
cp /path/to/my-n9e pkg/server/n9e-linux-amd64
make docker-build && make deploy

# 替换前端后重新嵌入 server（只编 server，不编 web/agent）
rm -rf pkg/web/pub && cp -R /path/to/pub pkg/web/pub
make build PROJECT=server && make docker-build && make deploy
```

链式兜底只在**缺失**时触发：deploy 缺镜像 → docker-build；docker-build 缺产物 → build；build 缺源码 → init。已存在的产物不会被静默重编覆盖。
注意：deploy 复用已存在的镜像，替换产物后必须先 `make docker-build` 再 deploy。

## 离线部署

```bash
make docker-pack ARCH=amd64
# 拷贝 docker-pkg/argusnet-docker-<ver>-linux-amd64.tar.gz 到目标机（只需 docker + compose 插件）
tar xzf argusnet-docker-*.tar.gz && cd argusnet-docker-* && ./install.sh
```

## 注意事项

- server 构建在 `.work/server-build` 临时副本中进行 statik 嵌入，**源仓库零污染**；不调用源仓库 fe.sh（它会静默下载 n9e 官方前端）
- 版本号取 `git describe`；仓库无 tag 时为 `v0.0.0-g<sha>`，dev 脏工作区追加 `-dirty`
- PG 初始化 SQL 仅在 **空数据卷首次启动**时执行；schema 升级需手工执行 server 仓库 `docker/migratesql`；`make clean SCOPE=data` 会删库重来（交互确认）
- 在 arm64 Mac 上构建 amd64 镜像走 qemu 模拟，pip/apt 步骤较慢属正常
- 镜像构建需要网络（pip/apt/基础镜像拉取）；离线目标机靠 docker-pack 闭环
- categraf 容器只读挂载宿主根目录与 docker.sock 用于主机监控