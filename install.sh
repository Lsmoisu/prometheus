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

# 安装 Prometheus 的逻辑
if [ "$INSTALL_PROMETHEUS" == "y" ]; then
    # 此处省略 Prometheus 安装逻辑，与原脚本一致
    echo -e "${GREEN}Prometheus 安装完成！${NC}"
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
    cat > "$NODE_EXPORTER_SERVICE_FILE" <<EOF
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
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误：创建 Node Exporter 服务文件失败！${NC}"
        exit 1
    fi
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
systemctl reset-failed

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
    if [ -f "$NODE_EXPORTER_SERVICE_FILE" ]; then
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
    else
        echo -e "${RED}错误：Node Exporter 服务文件未找到 ($NODE_EXPORTER_SERVICE_FILE)！${NC}"
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
