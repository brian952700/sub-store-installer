#!/usr/bin/env bash
# Sub-Store installer for Debian 12/13. Run with bash as root.
set -Eeuo pipefail
umask 077

APP_DIR=/opt/sub-store
CONTAINER=sub-store
IMAGE=xream/sub-store:latest
PORT=3001

die() { printf '错误：%s\n' "$*" >&2; exit 1; }
trap 'printf "安装未完成（第 %s 行）。请检查报错；已有数据不会自动删除。\n" "$LINENO" >&2' ERR

valid_ipv4() {
  local address=$1 octet
  local -a octets
  [[ $address =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS=. read -r -a octets <<< "$address"
  for octet in "${octets[@]}"; do
    (( 10#$octet <= 255 )) || return 1
  done
}

main() {
  [[ $EUID -eq 0 ]] || die '请先运行 sudo -i，再执行安装命令。'
  [[ -r /etc/os-release ]] || die '无法识别系统。'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ ${ID:-} == debian && ${VERSION_ID:-} =~ ^(12|13)$ ]] || die '仅支持 Debian 12/13。'

  if [[ -e $APP_DIR/access.txt || -e $APP_DIR/service.env ]]; then
    die '检测到上次安装。查看地址：cat /opt/sub-store/access.txt；本脚本不会覆盖密钥。'
  fi
  if command -v docker >/dev/null 2>&1; then
    docker info >/dev/null 2>&1 || die 'Docker 已安装但不可用，请先启动 Docker 服务。'
    if docker container inspect "$CONTAINER" >/dev/null 2>&1; then
      die '已有 sub-store 容器，停止安装以避免覆盖。'
    fi
  fi

  local vps_ip token base_url ready=0 attempt
  printf '无域名模式：通过公网 IP 使用 HTTP，传输不会加密。\n'
  read -r -p '请输入 VPS 公网 IPv4（不带端口）: ' vps_ip </dev/tty
  valid_ipv4 "$vps_ip" || die 'IPv4 地址格式不正确。'

  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl openssl iproute2 util-linux
  exec 9>/run/lock/sub-store-installer.lock
  flock -n 9 || die '另一个安装进程正在运行。'
  [[ ! -e $APP_DIR/service.env ]] || die '已有安装记录，请检查 /opt/sub-store。'
  if ss -ltnH "sport = :$PORT" | grep -q .; then
    die 'TCP 3001 已被占用，请先确认占用该端口的服务。'
  fi

  if ! command -v docker >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io
    systemctl enable --now docker
  fi
  docker info >/dev/null
  if docker container inspect "$CONTAINER" >/dev/null 2>&1; then
    die '已有 sub-store 容器。'
  fi
  docker pull "$IMAGE"

  mkdir -p "$APP_DIR/data"
  token=$(openssl rand -hex 24)
  base_url="http://$vps_ip:$PORT"
  printf '%s\n' \
    'SUB_STORE_BACKEND_API_HOST=127.0.0.1' \
    'SUB_STORE_FRONTEND_HOST=0.0.0.0' \
    "SUB_STORE_FRONTEND_BACKEND_PATH=/$token" \
    "SUB_STORE_CORS_ALLOWED_ORIGINS=$base_url" \
    > "$APP_DIR/service.env"
  {
    printf '网页地址：%s\n' "$base_url"
    printf '后端地址：%s/%s\n' "$base_url" "$token"
    printf '快捷入口：%s/?api=%s/%s\n' "$base_url" "$base_url" "$token"
    printf '数据目录：%s/data\n' "$APP_DIR"
  } > "$APP_DIR/access.txt"
  chmod 600 "$APP_DIR/service.env" "$APP_DIR/access.txt"

  docker run -d --name "$CONTAINER" --restart unless-stopped \
    --log-opt max-size=10m --log-opt max-file=3 \
    -p "0.0.0.0:$PORT:3001" \
    --env-file "$APP_DIR/service.env" \
    -v "$APP_DIR/data:/opt/app/data" "$IMAGE"

  for attempt in {1..30}; do
    if curl --noproxy '*' -fsS --max-time 3 \
      "http://127.0.0.1:$PORT/$token/api/utils/env" >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 2
  done
  if [[ $ready != 1 ]]; then
    printf '容器未就绪。运行 docker logs --tail 80 sub-store 排查。\n' >&2
    printf '安装记录和数据保留在 %s；无需重新生成密钥。\n' "$APP_DIR" >&2
    exit 1
  fi

  printf '\n安装成功！请保存下列地址，不要公开或上传到 GitHub：\n'
  cat "$APP_DIR/access.txt"
  printf '\n在服务商安全组中允许 TCP %s。脚本不会修改防火墙。\n' "$PORT"
  printf 'Docker 发布的端口可能绕过 UFW 常规规则，请在服务商安全组限制来源。\n'
  printf '打开快捷入口，新建本地订阅，粘贴 VLESS 链接（每行一条）。\n'
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
