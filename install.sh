#!/bin/bash

# 脚本名称：install_prometheus.sh
# 功能：自动安装或卸载 Prometheus、Node Exporter 和 Grafana，支持用户选择安装组件及指定版本或默认安装最新版本，适配系统架构
# 作者：运维工程师
# 使用方法：chmod +x install_prometheus.sh && ./install_prometheus.sh [uninstall]

# 设置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查是否为 root 用户或有 sudo 权限
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误：请以 root 用户或使用 sudo 权限运行此脚本！${NC}"
    exit 1
fi

# 定义常量
INSTALL_DIR="/opt/prometheus"
DATA_DIR="/opt/prometheus/data"
SERVICE_FILE="/etc/systemd/system/prometheus.service"
NODE_EXPORTER_INSTALL_DIR="/opt/node_exporter"
NODE_EXPORTER_SERVICE_FILE="/etc/systemd/system/node-exporter.service"
GRAFANA_CONFIG_DIR="/etc/grafana"
GRAFANA_SERVICE_FILE="/etc/systemd/system/grafana-server.service"

# 卸载函数
uninstall_components() {
    echo -e "${YELLOW}正在卸载已安装的组件...${NC}"

    # 检查并停止 Prometheus 服务
    if systemctl is-active --quiet prometheus; then
        echo -e "${YELLOW}正在停止 Prometheus 服务...${NC}"
        systemctl stop prometheus
    fi
    if systemctl is-enabled --quiet prometheus; then
        echo -e "${YELLOW}正在禁用 Prometheus 服务...${NC}"
        systemctl disable prometheus
    fi
    if [ -f "$SERVICE_FILE" ]; then
        echo -e "${YELLOW}正在删除 Prometheus systemd 服务文件...${NC}"
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
        systemctl reset-failed
    fi

    # 检查并停止 Node Exporter 服务
    if systemctl is-active --quiet node-exporter; then
        echo -e "${YELLOW}正在停止 Node Exporter 服务...${NC}"
        systemctl stop node-exporter
    fi
    if systemctl is-enabled --quiet node-exporter; then
        echo -e "${YELLOW}正在禁用 Node Exporter 服务...${NC}"
        systemctl disable node-exporter
    fi
    if [ -f "$NODE_EXPORTER_SERVICE_FILE" ]; then
        echo -e "${YELLOW}正在删除 Node Exporter systemd 服务文件...${NC}"
        rm -f "$NODE_EXPORTER_SERVICE_FILE"
        systemctl daemon-reload
        systemctl reset-failed
    fi

    # 检查并停止 Grafana 服务
    if systemctl is-active --quiet grafana-server; then
        echo -e "${YELLOW}正在停止 Grafana 服务...${NC}"
        systemctl stop grafana-server
    fi
    if systemctl is-enabled --quiet grafana-server; then
        echo -e "${YELLOW}正在禁用 Grafana 服务...${NC}"
        systemctl disable grafana-server
    fi
    if [ -f "$GRAFANA_SERVICE_FILE" ] || command -v grafana-server &> /dev/null; then
        echo -e "${YELLOW}正在删除 Grafana systemd 服务文件...${NC}"
        rm -f "$GRAFANA_SERVICE_FILE"
        systemctl daemon-reload
        systemctl reset-failed
    fi

    # 删除安装目录和数据目录
    if [ -d "$INSTALL_DIR" ]; then
        echo -e "${YELLOW}正在删除 Prometheus 安装目录 ($INSTALL_DIR)...${NC}"
        rm -rf "$INSTALL_DIR"
    fi
    if [ -d "$DATA_DIR" ]; then
        echo -e "${YELLOW}正在删除 Prometheus 数据目录 ($DATA_DIR)...${NC}"
        rm -rf "$DATA_DIR"
    fi
    if [ -d "$NODE_EXPORTER_INSTALL_DIR" ]; then
        echo -e "${YELLOW}正在删除 Node Exporter 安装目录 ($NODE_EXPORTER_INSTALL_DIR)...${NC}"
        rm -rf "$NODE_EXPORTER_INSTALL_DIR"
    fi
    if [ -d "$GRAFANA_CONFIG_DIR" ]; then
        echo -e "${YELLOW}正在删除 Grafana 配置目录 ($GRAFANA_CONFIG_DIR)...${NC}"
        rm -rf "$GRAFANA_CONFIG_DIR"
    fi

    # 删除用户和组
    if id prometheus &> /dev/null; then
        echo -e "${YELLOW}正在删除 Prometheus 用户和组...${NC}"
        userdel prometheus || true
        groupdel prometheus || true
    fi
    if id node_exporter &> /dev/null; then
        echo -e "${YELLOW}正在删除 Node Exporter 用户和组...${NC}"
        userdel node_exporter || true
        groupdel node_exporter || true
    fi

    # 卸载 Grafana 包（如果通过包管理器安装）
    if command -v apt &> /dev/null; then
        apt remove -y grafana || true
    elif command -v yum &> /dev/null; then
        yum remove -y grafana || true
    fi

    echo -e "${GREEN}Prometheus、Node Exporter 和 Grafana 已成功卸载！${NC}"
    exit 0
}

# 检查是否为卸载模式
if [ "$1" == "uninstall" ]; then
    uninstall_components
fi

# 获取系统架构
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        PROM_ARCH="linux-amd64"
        ;;
    aarch64|arm64)
        PROM_ARCH="linux-arm64"
        ;;
    *)
        echo -e "${RED}错误：不支持的系统架构 ($ARCH)！${NC}"
        exit 1
        ;;
esac
echo -e "${GREEN}检测到系统架构：$ARCH，使用 Prometheus 架构：$PROM_ARCH${NC}"

# 检查 wget 是否安装
if ! command -v wget &> /dev/null; then
    echo -e "${YELLOW}wget 未安装，正在安装...${NC}"
    if command -v apt &> /dev/null; then
        apt update && apt install -y wget
    elif command -v yum &> /dev/null; then
        yum install -y wget
    else
        echo -e "${RED}错误：无法确定包管理器，无法安装 wget！${NC}"
        exit 1
    fi
fi

# 交互式选择安装的组件
echo -e "${YELLOW}请选择要安装的组件（默认：是）[y/n]：${NC}"
echo -e "${YELLOW}是否安装 Prometheus？（默认：是）[y/n]：${NC}"
read INSTALL_PROMETHEUS
if [ -z "$INSTALL_PROMETHEUS" ] || [[ "$INSTALL_PROMETHEUS" =~ ^[Yy]$ ]]; then
    INSTALL_PROMETHEUS="y"
    echo -e "${GREEN}将安装 Prometheus。${NC}"
else
    echo -e "${YELLOW}将不安装 Prometheus。${NC}"
fi

echo -e "${YELLOW}是否安装 Node Exporter 用于收集系统指标？（默认：是）[y/n]：${NC}"
read INSTALL_NODE_EXPORTER
if [ -z "$INSTALL_NODE_EXPORTER" ] || [[ "$INSTALL_NODE_EXPORTER" =~ ^[Yy]$ ]]; then
    INSTALL_NODE_EXPORTER="y"
    echo -e "${GREEN}将安装 Node Exporter。${NC}"
else
    echo -e "${YELLOW}将不安装 Node Exporter。${NC}"
fi

echo -e "${YELLOW}是否安装 Grafana 用于可视化监控数据？（默认：是）[y/n]：${NC}"
read INSTALL_GRAFANA
if [ -z "$INSTALL_GRAFANA" ] || [[ "$INSTALL_GRAFANA" =~ ^[Yy]$ ]]; then
    INSTALL_GRAFANA="y"
    echo -e "${GREEN}将安装 Grafana。${NC}"
else
    echo -e "${YELLOW}将不安装 Grafana。${NC}"
fi

# 如果没有选择安装任何组件，则退出
if [ "$INSTALL_PROMETHEUS" != "y" ] && [ "$INSTALL_NODE_EXPORTER" != "y" ] && [ "$INSTALL_GRAFANA" != "y" ]; then
    echo -e "${RED}错误：未选择安装任何组件，脚本退出！${NC}"
    exit 1
fi

# 安装 Prometheus 的逻辑
if [ "$INSTALL_PROMETHEUS" == "y" ]; then
    # 提示用户输入 Prometheus 版本
    echo -e "${YELLOW}请输入要安装的 Prometheus 版本（例如：2.47.0），直接回车将安装最新版本：${NC}"
    read VERSION

    # 如果未输入版本，则获取最新版本
    if [ -z "$VERSION" ]; then
        echo -e "${YELLOW}正在获取 Prometheus 最新版本...${NC}"
        VERSION=$(curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
        if [ -z "$VERSION" ]; then
            echo -e "${RED}错误：无法获取最新版本，请检查网络或手动指定版本！${NC}"
            exit 1
        fi
        echo -e "${GREEN}最新版本为：$VERSION${NC}"
    fi

    # 构建 Prometheus 下载链接
    DOWNLOAD_URL="https://github.com/prometheus/prometheus/releases/download/v${VERSION}/prometheus-${VERSION}.${PROM_ARCH}.tar.gz"

    # 检查下载链接是否有效
    echo -e "${YELLOW}正在验证 Prometheus 下载链接...${NC}"
    HTTP_STATUS=$(curl -s -I "$DOWNLOAD_URL" | grep -i "HTTP/" | awk '{print $2}' | head -1)
    if [[ "$HTTP_STATUS" != "200" && "$HTTP_STATUS" != "302" ]]; then
        echo -e "${RED}错误：无效的版本号或下载链接 ($DOWNLOAD_URL)，请检查输入的版本！${NC}"
        echo -e "${YELLOW}HTTP 状态码：$HTTP_STATUS${NC}"
        exit 1
    fi
    echo -e "${GREEN}Prometheus 下载链接有效，HTTP 状态码：$HTTP_STATUS${NC}"

    # 创建 Prometheus 安装目录和数据目录
    echo -e "${YELLOW}正在创建 Prometheus 安装目录和数据目录...${NC}"
    mkdir -p "$INSTALL_DIR" "$DATA_DIR"
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误：创建目录失败！${NC}"
        exit 1
    fi

    # 下载 Prometheus
    echo -e "${YELLOW}正在下载 Prometheus v${VERSION}...${NC}"
    wget -O /tmp/prometheus.tar.gz "$DOWNLOAD_URL"
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误：下载失败，请检查网络或版本号！${NC}"
        exit 1
    fi

    # 解压并安装 Prometheus
    echo -e "${YELLOW}正在解压并安装 Prometheus...${NC}"
    tar -xzf /tmp/prometheus.tar.gz -C /tmp
    mv /tmp/prometheus-${VERSION}.${PROM_ARCH}/* "$INSTALL_DIR"
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误：解压或移动文件失败！${NC}"
        exit 1
    fi

    # 清理临时文件
    rm -rf /tmp/prometheus.tar.gz /tmp/prometheus-${VERSION}.${PROM_ARCH}

    # 创建 Prometheus 用户和组
    echo -e "${YELLOW}正在创建 Prometheus 用户和组...${NC}"
    useradd -M -s /bin/false prometheus || true
    chown -R prometheus:prometheus "$INSTALL_DIR" "$DATA_DIR"

    # 创建基本配置文件，并添加 Node Exporter 采集配置（如果安装）
    echo -e "${YELLOW}正在创建 Prometheus 配置文件...${NC}"
    PROMETHEUS_CONFIG="global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
"
    if [ "$INSTALL_NODE_EXPORTER" == "y" ]; then
        PROMETHEUS_CONFIG="$PROMETHEUS_CONFIG
  - job_name: 'node_exporter'
    static_configs:
      - targets: ['localhost:9100']
"
    fi
    echo "$PROMETHEUS_CONFIG" > "$INSTALL_DIR/prometheus.yml"

    # 创建 Prometheus systemd 服务文件
    echo -e "${YELLOW}正在创建 Prometheus systemd 服务文件...${NC}"
    cat > /etc/systemd/system/prometheus.service <<EOF
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=$INSTALL_DIR/prometheus \\
    --config.file=$INSTALL_DIR/prometheus.yml \\
    --storage.tsdb.path=$DATA_DIR

[Install]
WantedBy=multi-user.target
EOF
fi

# 安装 Node Exporter 的逻辑
if [ "$INSTALL_NODE_EXPORTER" == "y" ]; then
    echo -e "${YELLOW}正在获取 Node Exporter 最新版本...${NC}"
    NODE_EXPORTER_VERSION=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
    if [ -z "$NODE_EXPORTER_VERSION" ]; then
        echo -e "${RED}错误：无法获取 Node Exporter 最新版本，请检查网络！${NC}"
        exit 1
    fi
    echo -e "${GREEN}Node Exporter 最新版本为：$NODE_EXPORTER_VERSION${NC}"
    NODE_EXPORTER_DOWNLOAD_URL="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.${PROM_ARCH}.tar.gz"

    # 检查 Node Exporter 下载链接是否有效
    echo -e "${YELLOW}正在验证 Node Exporter 下载链接...${NC}"
    HTTP_STATUS=$(curl -s -I "$NODE_EXPORTER_DOWNLOAD_URL" | grep -i "HTTP/" | awk '{print $2}' | head -1)
    if [[ "$HTTP_STATUS" != "200" && "$HTTP_STATUS" != "302" ]]; then
        echo -e "${RED}错误：无效的 Node Exporter 下载链接 ($NODE_EXPORTER_DOWNLOAD_URL)！${NC}"
        echo -e "${YELLOW}HTTP 状态码：$HTTP_STATUS${NC}"
        exit 1
    fi
    echo -e "${GREEN}Node Exporter 下载链接有效，HTTP 状态码：$HTTP_STATUS${NC}"

    echo -e "${YELLOW}正在创建 Node Exporter 安装目录...${NC}"
    mkdir -p "$NODE_EXPORTER_INSTALL_DIR"
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误：创建 Node Exporter 目录失败！${NC}"
        exit 1
    fi

    echo -e "${YELLOW}正在下载 Node Exporter v${NODE_EXPORTER_VERSION}...${NC}"
    wget -O /tmp/node_exporter.tar.gz "$NODE_EXPORTER_DOWNLOAD_URL"
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误：下载 Node Exporter 失败，请检查网络！${NC}"
        exit 1
    fi

    echo -e "${YELLOW}正在解压并安装 Node Exporter...${NC}"
    tar -xzf /tmp/node_exporter.tar.gz -C /tmp
    mv /tmp/node_exporter-${NODE_EXPORTER_VERSION}.${PROM_ARCH}/* "$NODE_EXPORTER_INSTALL_DIR"
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误：解压或移动 Node Exporter 文件失败！${NC}"
        exit 1
    fi

    # 清理临时文件
    rm -rf /tmp/node_exporter.tar.gz /tmp/node_exporter-${NODE_EXPORTER_VERSION}.${PROM_ARCH}

    # 创建 Node Exporter 用户和组
    echo -e "${YELLOW}正在创建 Node Exporter 用户和组...${NC}"
    useradd -M -s /bin/false node_exporter || true
    chown -R node_exporter:node_exporter "$NODE_EXPORTER_INSTALL_DIR"

    # 创建 Node Exporter systemd 服务文件
    echo -e "${YELLOW}正在创建 Node Exporter systemd 服务文件...${NC}"
    cat > /etc/systemd/system/node-exporter.service <<EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=$NODE_EXPORTER_INSTALL_DIR/node_exporter

[Install]
WantedBy=multi-user.target
EOF
fi

# 安装 Grafana 的逻辑
if [ "$INSTALL_GRAFANA" == "y" ]; then
    echo -e "${YELLOW}正在安装 Grafana...${NC}"
    if command -v apt &> /dev/null; then
        # Debian/Ubuntu 系统
        apt update
        apt install -y software-properties-common
        add-apt-repository -y "deb https://packages.grafana.com/oss/deb stable main"
        wget -q -O - https://packages.grafana.com/gpg.key | apt-key add -
        apt update
        apt install -y grafana
    elif command -v yum &> /dev/null; then
        # CentOS/RHEL 系统
        cat > /etc/yum.repos.d/grafana.repo <<EOF
[grafana]
name=grafana
baseurl=https://packages.grafana.com/oss/rpm
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://packages.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF
        yum install -y grafana
    else
        echo -e "${RED}错误：无法确定包管理器，无法安装 Grafana！${NC}"
        exit 1
    fi
    echo -e "${GREEN}Grafana 安装完成！${NC}"
fi

# 重新加载 systemd 并启动服务
echo -e "${YELLOW}正在启动已安装的服务...${NC}"
systemctl daemon-reload

if [ "$INSTALL_PROMETHEUS" == "y" ]; then
    systemctl start prometheus
    systemctl enable prometheus
    if systemctl is-active --quiet prometheus; then
        echo -e "${GREEN}Prometheus 安装成功并已启动！${NC}"
        echo -e "${GREEN}访问 http://你的服务器IP:9090 查看 Prometheus Web UI。${NC}"
    else
        echo -e "${RED}错误：Prometheus 服务启动失败！${NC}"
        echo -e "${YELLOW}请检查日志：journalctl -u prometheus -f${NC}"
        exit 1
    fi
fi

if [ "$INSTALL_NODE_EXPORTER" == "y" ]; then
    systemctl start node-exporter
    systemctl enable node-exporter
    if systemctl is-active --quiet node-exporter; then
        echo -e "${GREEN}Node Exporter 安装成功并已启动！${NC}"
        echo -e "${GREEN}访问 http://你的服务器IP:9100/metrics 查看 Node Exporter 指标。${NC}"
    else
        echo -e "${RED}错误：Node Exporter 服务启动失败！${NC}"
        echo -e "${YELLOW}请检查日志：journalctl -u node-exporter -f${NC}"
        exit 1
    fi
fi

if [ "$INSTALL_GRAFANA" == "y" ]; then
    systemctl start grafana-server
    systemctl enable grafana-server
    if systemctl is-active --quiet grafana-server; then
        echo -e "${GREEN}Grafana 安装成功并已启动！${NC}"
        echo -e "${GREEN}访问 http://你的服务器IP:3000 查看 Grafana Web UI（默认用户/密码：admin/admin）。${NC}"
    else
        echo -e "${RED}错误：Grafana 服务启动失败！${NC}"
        echo -e "${YELLOW}请检查日志：journalctl -u grafana-server -f${NC}"
        exit 1
    fi
fi

# 总结安装结果
echo -e "${GREEN}安装完成！${NC}"
if [ "$INSTALL_PROMETHEUS" == "y" ]; then
    echo -e "${GREEN}Prometheus 版本：v${VERSION}${NC}"
fi
if [ "$INSTALL_NODE_EXPORTER" == "y" ]; then
    echo -e "${GREEN}Node Exporter 版本：v${NODE_EXPORTER_VERSION}${NC}"
fi
if [ "$INSTALL_GRAFANA" == "y" ]; then
    echo -e "${GREEN}Grafana 已安装（版本由包管理器确定）${NC}"
fi

