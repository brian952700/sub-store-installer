# Sub-Store 一键安装（Debian 12 / 13）

在没有域名的 VPS 上通过 Docker 部署 Sub-Store，集中管理多条 VLESS 链接，输出 Mihomo / Clash Meta 订阅。

此仓库提供安装脚本，不提供代理节点，也不是 Sub-Store 官方项目。

## 一键安装

SSH 登录 VPS，以 root 身份执行。不是 root 时先运行 `sudo -i`。

```bash
apt-get update && apt-get install -y ca-certificates curl && curl -fL --retry 3 https://raw.githubusercontent.com/brian952700/sub-store-installer/main/install.sh -o /tmp/sub-store-install.sh && bash /tmp/sub-store-install.sh
```

输入 VPS 的公网 IPv4 地址即可。也可先下载并查看脚本，再执行。

脚本使用 Debian 软件源安装依赖；已有可用 Docker 时复用现有安装。拉取 `xream/sub-store:latest`，发布 IPv4 TCP 3001，自动生成随机的 48 位十六进制后端路径，配置容器自动重启、日志大小限制和数据持久化。重复执行会拒绝覆盖已有安装。

脚本不会更改防火墙，也不会停止已有服务。若 3001 被占用会停止安装。镜像版本为安装时的 latest，不保证未来版本行为不变。

## 打开网页

1. 在 VPS 服务商控制台的安全组中允许 TCP 3001；如果系统另有防火墙，也需对应配置。Docker 发布端口可能绕过 UFW 常规规则，推荐在服务商安全组限制来源 IP。
2. 打开安装结束显示的「快捷入口」。
3. 如提示设置后端，填写安装结束显示的「后端地址」。
4. 新建订阅，来源选择「本地」，把 VLESS 链接每行一条粘贴进去并保存。
5. 选择 Mihomo / Clash Meta 格式，复制导出的订阅地址。界面名称可能随版本变化。

管理网页地址和节点订阅地址不是同一个地址。不要把管理入口填到客户端订阅栏。

## 在 Clash Verge Rev 使用

如果导出的是完整配置，可以在「订阅」中粘贴 URL 导入。

如果导出的是只有 `proxies:` 的节点列表，请使用仓库提供的 [clash-template.yaml](clash-template.yaml)：

1. 下载这个模板，把 `REPLACE_WITH_SUB_STORE_MIHOMO_URL` 替换成刚才复制的订阅地址，保留双引号。
2. 保存后作为本地配置文件导入 Clash Verge Rev。
3. 选择「节点选择」中的一个节点，或者使用「自动选择」。节点列表每小时自动更新。

模板是完整的最小配置：私有网络 IP 直连，其余流量走所选节点；未加入国内外域名分流，未开启 TUN。DNS 解析和系统代理可按客户端设置调整。

VLESS 参数必须受客户端内核支持；转换成功并不等于节点可连接，尤其是较新的传输方式。订阅转换不能补齐缺失的 UUID、Reality 公钥等参数。

## 数据和排查

```bash
# 查看安装时生成的访问地址（包含密钥，勿公开输出）
cat /opt/sub-store/access.txt

# 查看容器和日志（分享日志前遮住节点和密钥）
docker ps -a --filter name=sub-store
docker logs --tail 80 sub-store

# 重启服务；不删除数据
docker restart sub-store
```

数据保存在 `/opt/sub-store/data`，环境配置在 `/opt/sub-store/service.env`。备份时保存整个 `/opt/sub-store` 目录，备份内容包含访问凭据，勿上传到公开仓库。健康检查失败时脚本保留容器、配置与数据，以便排查。

网页打不开时：确认公网 IPv4 填写正确，服务商放行 3001，容器正在运行。如果网页能打开但后端连接失败，重新填写 `access.txt` 内的后端地址，并使用安装时同一 IP/端口访问。

本脚本不提供自动升级或卸载，以免在不了解现有数据的情况下替换容器或删除内容。

## 无域名模式的限制

当前使用 HTTP，管理密钥和节点数据在传输过程中不加密。随机路径用于减少未授权访问，不能代替 HTTPS。不要公开管理入口、订阅地址或访问记录，避免在不可信网络中管理服务。管理密钥泄露后，对方可能读取或修改订阅数据。

本项目只把带随机路径的前端代理端口发布出去，不发布内部裸后端 3000 端口。CORS 不是身份认证。以后配置 HTTPS 时需同步调整前端来源地址和客户端订阅 URL。

## 上游文档

- [Sub-Store 项目](https://github.com/sub-store-org/Sub-Store)
- [Docker 安装说明](https://sub-store-org.github.io/doc/guide/installation)
- [环境变量说明](https://sub-store-org.github.io/doc/reference/environment-variables)
- [Mihomo 代理集合](https://wiki.metacubex.one/config/proxy-providers/)

## 验证范围

GitHub Actions 自动检查 Bash 语法、ShellCheck，并使用上游 Docker 镜像验证前端与带随机路径的后端接口。检查结果请查看仓库 Actions 页面；没有接入你的 VPS，不代表已经在你的服务器部署，也不保证你的节点可用。首次安装前仍应确认 Actions 检查通过。
