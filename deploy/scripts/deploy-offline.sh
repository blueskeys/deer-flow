#!/bin/bash
#
# deploy-offline.sh - 在离线 ARM 服务器上部署 DeerFlow
#
# 用法:
#   chmod +x scripts/deploy-offline.sh
#   ./scripts/deploy-offline.sh
#
# 前提条件:
#   - Docker 和 Docker Compose 已安装
#   - 已将 offline-deerflow 目录传输到服务器

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OFFLINE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
IMAGES_DIR="$OFFLINE_ROOT/images"
CONFIG_DIR="$OFFLINE_ROOT/config"

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  DeerFlow 离线部署 (ARM64)${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo -e "${BLUE}离线包目录: $OFFLINE_ROOT${NC}"
echo ""

# ========================================
# 步骤 1: 检查 Docker
# ========================================
echo -e "${YELLOW}步骤 1/6: 检查 Docker...${NC}"

if ! command -v docker &> /dev/null; then
    echo -e "${RED}错误: Docker 未安装${NC}"
    echo "请先安装 Docker: https://docs.docker.com/engine/install/"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo -e "${RED}错误: Docker 服务未运行${NC}"
    echo "请启动 Docker 服务: systemctl start docker"
    exit 1
fi

DOCKER_VERSION=$(docker --version)
echo -e "${GREEN}  ✓ Docker 已安装: $DOCKER_VERSION${NC}"
echo ""

# ========================================
# 步骤 2: 导入 Docker 镜像
# ========================================
echo -e "${YELLOW}步骤 2/6: 导入 Docker 镜像...${NC}"

if [ ! -d "$IMAGES_DIR" ]; then
    echo -e "${RED}错误: 镜像目录不存在: $IMAGES_DIR${NC}"
    exit 1
fi

TAR_COUNT=$(find "$IMAGES_DIR" -name "*.tar" -type f | wc -l)
if [ "$TAR_COUNT" -eq 0 ]; then
    echo -e "${RED}错误: 未找到镜像文件 (*.tar)${NC}"
    exit 1
fi

echo -e "${BLUE}  找到 $TAR_COUNT 个镜像文件${NC}"

for tar_file in "$IMAGES_DIR"/*.tar; do
    if [ -f "$tar_file" ]; then
        filename=$(basename "$tar_file")
        filesize=$(du -h "$tar_file" | cut -f1)
        echo -e "${BLUE}  导入: $filename ($filesize)${NC}"

        if docker load -i "$tar_file"; then
            echo -e "${GREEN}  ✓ 导入成功${NC}"
        else
            echo -e "${RED}  ✗ 导入失败: $filename${NC}"
            exit 1
        fi
    fi
done
echo ""

# ========================================
# 步骤 3: 重命名镜像标签
# ========================================
echo -e "${YELLOW}步骤 3/6: 配置镜像标签...${NC}"

# 重命名镜像以匹配 docker-compose.yaml
docker tag deer-flow-frontend:offline-arm64 deer-flow-frontend:latest 2>/dev/null || true
docker tag deer-flow-backend:offline-arm64 deer-flow-backend:latest 2>/dev/null || true
docker tag nginx:alpine-offline-arm64 nginx:alpine 2>/dev/null || true
docker tag deer-flow-sandbox:offline-arm64 enterprise-public-cn-beijing.cr.volces.com/vefaas-public/all-in-one-sandbox:latest 2>/dev/null || true

echo -e "${GREEN}  ✓ 镜像标签配置完成${NC}"
echo ""

# 列出导入的镜像
echo -e "${BLUE}  已导入的镜像:${NC}"
docker images | grep -E "deer-flow|nginx|all-in-one-sandbox" || true
echo ""

# ========================================
# 步骤 4: 创建必要目录和配置
# ========================================
echo -e "${YELLOW}步骤 4/6: 创建目录和配置文件...${NC}"

# 部署目录 (默认 /opt/deerflow)
DEPLOY_DIR="${DEER_FLOW_DEPLOY_DIR:-/opt/deerflow}"
sudo mkdir -p "$DEPLOY_DIR"
sudo mkdir -p "$DEPLOY_DIR/backend/.deer-flow"
sudo mkdir -p "$DEPLOY_DIR/skills"

# 检查配置文件
CONFIG_FILE="$DEPLOY_DIR/config.yaml"
if [ ! -f "$CONFIG_FILE" ]; then
    if [ -f "$CONFIG_DIR/config.example.yaml" ]; then
        sudo cp "$CONFIG_DIR/config.example.yaml" "$CONFIG_FILE"
        echo -e "${GREEN}  ✓ 创建配置文件: $CONFIG_FILE${NC}"
    fi
fi

EXTENSIONS_FILE="$DEPLOY_DIR/extensions_config.json"
if [ ! -f "$EXTENSIONS_FILE" ]; then
    echo '{"mcpServers":{},"skills":{}}' | sudo tee "$EXTENSIONS_FILE" > /dev/null
    echo -e "${GREEN}  ✓ 创建扩展配置: $EXTENSIONS_FILE${NC}"
fi

# 复制 docker-compose.yaml
if [ -f "$CONFIG_DIR/docker-compose.yaml" ]; then
    sudo cp "$CONFIG_DIR/docker-compose.yaml" "$DEPLOY_DIR/docker-compose.yaml"
    echo -e "${GREEN}  ✓ 复制 docker-compose.yaml${NC}"
fi

# 复制 nginx 配置
if [ -f "$CONFIG_DIR/nginx.conf" ]; then
    sudo mkdir -p "$DEPLOY_DIR/docker/nginx"
    sudo cp "$CONFIG_DIR/nginx.conf" "$DEPLOY_DIR/docker/nginx/nginx.conf"
    echo -e "${GREEN}  ✓ 复制 nginx.conf${NC}"
fi

echo ""

# ========================================
# 步骤 5: 生成必要密钥
# ========================================
echo -e "${YELLOW}步骤 5/6: 生成安全密钥...${NC}"

AUTH_SECRET_FILE="$DEPLOY_DIR/backend/.deer-flow/.better-auth-secret"
if [ ! -f "$AUTH_SECRET_FILE" ]; then
    SECRET=$(openssl rand -hex 32)
    echo "$SECRET" | sudo tee "$AUTH_SECRET_FILE" > /dev/null
    sudo chmod 600 "$AUTH_SECRET_FILE"
    echo -e "${GREEN}  ✓ 生成 BETTER_AUTH_SECRET${NC}"
else
    echo -e "${BLUE}  BETTER_AUTH_SECRET 已存在${NC}"
fi
echo ""

# ========================================
# 步骤 6: 启动服务
# ========================================
echo -e "${YELLOW}步骤 6/6: 启动 DeerFlow 服务...${NC}"

cd "$DEPLOY_DIR"

# 设置环境变量
export DEER_FLOW_HOME="$DEPLOY_DIR/backend/.deer-flow"
export DEER_FLOW_CONFIG_PATH="$DEPLOY_DIR/config.yaml"
export DEER_FLOW_EXTENSIONS_CONFIG_PATH="$DEPLOY_DIR/extensions_config.json"
export DEER_FLOW_REPO_ROOT="$DEPLOY_DIR"
export DEER_FLOW_DOCKER_SOCKET="/var/run/docker.sock"
export BETTER_AUTH_SECRET=$(cat "$AUTH_SECRET_FILE")

# 检测 sandbox 模式
detect_sandbox_mode() {
    local config_file="$DEER_FLOW_CONFIG_PATH"
    local sandbox_use=""

    if [ ! -f "$config_file" ]; then
        echo "local"
        return
    fi

    sandbox_use=$(grep -A 5 "^sandbox:" "$config_file" 2>/dev/null | grep "use:" | head -1 | awk '{print $2}' || echo "")

    if [[ "$sandbox_use" == *"AioSandboxProvider"* ]]; then
        echo "aio"
    else
        echo "local"
    fi
}

SANDBOX_MODE=$(detect_sandbox_mode)
echo -e "${BLUE}  Sandbox 模式: $SANDBOX_MODE${NC}"

# 启动 Docker Compose
echo -e "${BLUE}  启动容器...${NC}"
sudo docker compose -p deer-flow up -d

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  部署成功！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${CYAN}  访问地址:${NC}"
    echo -e "    http://localhost:2026"
    echo ""
    echo -e "${CYAN}  配置文件:${NC}"
    echo -e "    $CONFIG_FILE"
    echo ""
    echo -e "${CYAN}  常用命令:${NC}"
    echo -e "    查看日志:   cd $DEPLOY_DIR && sudo docker compose logs -f"
    echo -e "    重启服务:   cd $DEPLOY_DIR && sudo docker compose restart"
    echo -e "    停止服务:   cd $DEPLOY_DIR && sudo docker compose down"
    echo ""
    echo -e "${YELLOW}  重要提示:${NC}"
    echo -e "    请编辑 $CONFIG_FILE 配置模型 API 密钥"
    echo -e "    配置完成后重启服务: sudo docker compose restart"
    echo ""
else
    echo -e "${RED}部署失败，请检查日志${NC}"
    exit 1
fi
