# singbox-lite Docker

[singbox-lite](https://github.com/0xdabiaoge/singbox-lite) 的 Docker 部署配置。本仓库只维护 Docker 配置和使用说明；容器每次启动都会从上游 `main` 分支下载最新管理脚本，下载或脚本检查失败时不会继续启动。

## 快速开始

需要安装 Docker 和 Docker Compose 插件，构建及启动时需能访问 Alpine 软件源、GitHub 和 raw.githubusercontent.com。

```bash
git clone https://github.com/bymao/singbox-lite-docker.git
cd singbox-lite-docker
docker compose up -d --build
docker compose logs -f
```

日志显示“容器已启动”后，按 `Ctrl+C` 退出日志查看，再进入管理菜单：

```bash
docker compose exec singbox sb
```

首次使用，在菜单中选择 **[15] 安装 sing-box**，或 **[16] 安装 Xray**，然后按菜单提示添加节点。退出菜单不会停止容器或核心服务。

## 配置端口

默认使用 bridge 网络。请编辑 `docker-compose.yml`，取消 `ports` 的注释，并按节点的实际监听端口填写映射，例如：

```yaml
    ports:
      - "443:443/tcp"
      - "443:443/udp"
```

TCP/UDP 按协议需要配置；使用云服务器时，还需在安全组及宿主机防火墙中放行对应端口。修改 Compose 配置后执行：

```bash
docker compose up -d
```

## 更新与常用命令

```bash
# 更新管理脚本：重启时自动重新下载，无需重建镜像
docker compose restart singbox

# 进入上游菜单；核心更新也通过此菜单操作
docker compose exec singbox sb

# 查看容器启动日志
docker compose logs --tail=100 singbox

# 查看 sing-box 核心日志（核心启动后使用）
docker compose exec singbox tail -f /var/log/sing-box.log

# 查看 Xray 核心日志（核心启动后使用）
docker compose exec singbox tail -f /var/log/xray.log

# 停止并移除容器，保留配置和核心数据
docker compose down
```

更新本仓库的 Docker 配置后，执行 `git pull` 和 `docker compose up -d --build`。

## 数据保存与迁移

| 数据 | 保存位置 |
| --- | --- |
| sing-box 配置、节点信息及子脚本 | `./config/sing-box` |
| Xray 配置 | `./config/xray` |
| 已安装核心、sb 和 yq 等工具 | Docker 命名卷 `binaries`（实际名称通常带项目名前缀） |

重启或重建容器会保留上述数据，并在配置及核心存在时自动启动服务。核心日志保存在容器内，重建后不会保留。

备份时先执行 `docker compose down`，再保存整个 `config` 目录。迁移到新机器后恢复该目录，通过菜单重新安装核心即可；如需同时保留核心和工具，也应备份并恢复 `binaries` 卷。

**不要执行 `docker compose down -v`，除非确实需要删除核心和工具所在的命名卷。** 从本仓库旧版迁移时可沿用 `./config/sing-box`，但需要在菜单中重新安装一次核心。

更多协议、节点管理和进阶功能说明请参考[上游文档](https://github.com/0xdabiaoge/singbox-lite#readme)。
