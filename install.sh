#!/bin/bash

# 功能：自动安装或卸载 Prometheus、Node Exporter 和 Grafana，支持用户选择安装组件及指定版本或默认安装最新版本，适配系统架构
# 作者：Grok3
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
    # 此处省略卸载函数的具体实现，与原脚本一致
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
echo -e "${YELLOW}请选择要安装的组件：${NC}"
echo -e "${YELLOW}1. Grafana${NC}"
echo -e "${YELLOW}2. Prometheus${NC}"
echo -e "${YELLOW}3. Node Exporter${NC}"
echo -e "${YELLOW}请输入要安装的组件编号（用空格分隔多个选项，例如：1 3）：${NC}"
read -r SELECTION

# 初始化安装标志
INSTALL_GRAFANA="n"
INSTALL_PROMETHEUS="n"
INSTALL_NODE_EXPORTER="n"

# 解析用户输入的选择
for SELECTED in $SELECTION; do
    case $SELECTED in
        1)
            INSTALL_GRAFANA="y"
            echo -e "${GREEN}将安装 Grafana。${NC}"
            ;;
        2)
            INSTALL_PROMETHEUS="y"
            echo -e "${GREEN}将安装 Prometheus。${NC}"
            ;;
        3)
            INSTALL_NODE_EXPORTER="y"
            echo -e "${GREEN}将安装 Node Exporter。${NC}"
            ;;
        *)
            echo -e "${RED}警告：无效选项 $SELECTED，已忽略。${NC}"
            ;;
    esac
done

# 如果没有选择安装任何组件，则退出
if [ "$INSTALL_PROMETHEUS" != "y" ] && [ "$INSTALL_NODE_EXPORTER" != "y" ] && [ "$INSTALL_GRAFANA" != "y" ]; then
    echo -e "${RED}错误：未选择安装任何组件，脚本退出！${NC}"
    exit 1
fi

# 以下是安装逻辑，与原脚本一致，仅根据标志位决定是否执行
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
    # 此处省略 Node Exporter 安装逻辑，与原脚本一致
    echo -e "${GREEN}Node Exporter 安装完成！${NC}"
fi

# 安装 Grafana 的逻辑
if [ "$INSTALL_GRAFANA" == "y" ]; then
    # 此处省略 Grafana 安装逻辑，与原脚本一致
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
