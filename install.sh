#!/bin/sh
set -e

INSTALL_DIR="/usr/local/s-ui"
BIN_NAME="sui"
SERVICE_NAME="s-ui"
TMPDIR="$(mktemp -d)"
TARFILE="$TMPDIR/s-ui.tar.gz"

cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

# 检测必须为 Alpine Linux
if [ -f /etc/os-release ]; then
  . /etc/os-release
  case "$ID" in
    alpine) ;;
    Alpine) ;;
    *) echo "错误：此脚本只能在 Alpine Linux 上运行（检测到 ID=$ID）。" >&2; exit 1 ;;
  esac
else
  echo "错误：无法检测操作系统（/etc/os-release 不存在）。此脚本只能在 Alpine Linux 上运行。" >&2
  exit 1
fi

echo "1/6: 安装必要包 (curl tar)"
apk add --no-cache curl tar

echo "2/6: 创建安装目录"
mkdir -p "$INSTALL_DIR"

echo "3/6: 下载并解压"
    if [ $# == 0 ]; then
        last_version=$(curl -Ls "https://api.github.com/repos/alireza0/s-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}Failed to fetch s-ui version, it maybe due to Github API restrictions, please try it later${plain}"
            exit 1
        fi
        echo -e "Got s-ui latest version: ${last_version}, beginning the installation..."
        wget -N --no-check-certificate -O $TMPDIR/s-ui.tar.gz https://github.com/alireza0/s-ui/releases/download/${last_version}/s-ui-linux-amd64.tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Downloading s-ui failed, please be sure that your server can access Github ${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/alireza0/s-ui/releases/download/${last_version}/s-ui-linux-amd64.tar.gz"
        echo -e "Beginning the install s-ui v$1"
        wget -N --no-check-certificate -O $TMPDIR/s-ui.tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}download s-ui v$1 failed,please check the version exists${plain}"
            exit 1
        fi
    fi
tar -xz -C "$TMPDIR" -f "$TARFILE"

# 仅在压缩包根目录查找 sui
FOUND_BIN="$TMPDIR/$BIN_NAME"
if [ -f "$FOUND_BIN" ]; then
  chmod +x "$FOUND_BIN" || true
else
  echo "错误：压缩包根目录中未找到 '$BIN_NAME'（请确保文件位于压缩包根目录）。" >&2
  exit 1
fi

echo "4/6: 安装二进制到 $INSTALL_DIR"
mv "$FOUND_BIN" "$INSTALL_DIR/$BIN_NAME"

echo "5/6: 创建 openrc 服务脚本 /etc/init.d/$SERVICE_NAME"
cat > /etc/init.d/$SERVICE_NAME <<'EOF'
#!/sbin/openrc-run
# OpenRC init script for s-ui
command="/usr/local/s-ui/sui"
pidfile="/var/run/s-ui.pid"
name="s-ui"

depend() {
  need net
  after firewall
}

start() {
  ebegin "Starting ${name}"
  supervise-daemon --name "${name}" --respawn --start --exec "${command}" --user "$(command_user_split | awk -F: '{print $1}')" --group "$(command_user_split | awk -F: '{print $2}')" || eend 1
  eend 0
}

stop() {
  ebegin "Stopping ${name}"
  supervise-daemon --name "${name}" --stop || eend 1
  eend 0
}

status() {
  if [ -f "${pidfile}" ] && kill -0 "$(cat "${pidfile}")" 2>/dev/null; then
    einfo "${name} is running (pid $(cat "${pidfile}"))"
    return 0
  else
    eerror "${name} is not running"
    return 1
  fi
}
EOF

chmod +x /etc/init.d/$SERVICE_NAME

echo "6/6: 启用并启动服务"
rc-update add $SERVICE_NAME default
rc-service $SERVICE_NAME start

echo "安装完成：$INSTALL_DIR/$BIN_NAME ,service 名称：$SERVICE_NAME"