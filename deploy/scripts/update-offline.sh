#!/bin/bash
#
# update-offline.sh - 更新 DeerFlow 服务
#
# 用法: ./update-offline.sh [镜像目录]
#
# 此脚本用于更新已部署的 DeerFlow 服务
# 无需重新执行完整部署，只需导入新镜像并重启

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

IMAGES_DIR="${1:-./images}"
DEPLOY_DIR="${DEER_FLOW_DEPLOY_DIR:-/opt/deerflow}"

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  DeerFlow 服务更新${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo -e "${BLUE}镜像目录: $IMAGES_DIR${NC}"
echo -e "${BLUE}部署目录: $DEPLOY_DIR${NC}"
echo ""

# 检查镜像目录
if [ ! -d "$IMAGES_DIR" ]; then
    echo -e "${RED}错误: 镜像目录不存在: $IMAGES_DIR${NC}"
    exit 1
fi

# 检查 tar 文件
TAR_COUNT=$(find "$IMAGES_DIR" -name "*.tar" -type f | wc -l)
if [ "$TAR_COUNT" -eq 0 ]; then
    echo -e "${RED}错误: 未找到镜像文件 (*.tar)${NC}"
    exit 1
fi

echo -e "${YELLOW}找到 $TAR_COUNT 个镜像文件${NC}"
echo ""

# 确认更新
read -p "是否继续更新? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "取消更新"
    exit 0
fi

cd "$DEPLOY_DIR"

# 停止服务
echo -e "${YELLOW}停止服务...${NC}"
sudo docker compose down
echo -e "${GREEN}  ✓ 服务已停止${NC}"
echo ""

# 导入新镜像
echo -e "${YELLOW}导入新镜像...${NC}"
for tar_file in "$IMAGES_DIR"/*.tar; do
    if [ -f "$tar_file" ]; then
        filename=$(basename "$tar_file")
        echo -e "${BLUE}  导入: $filename${NC}"
        docker load -i "$tar_file"
    fi
done

# 重命名标签
echo ""
echo -e "${YELLOW}配置镜像标签...${NC}"
docker tag deer-flow-frontend:offline-arm64 deer-flow-frontend:latest 2>/dev/null || true
docker tag deer-flow-backend:offline-arm64 deer-flow-backend:latest 2>/dev/null || true
docker tag nginx:alpine-offline-arm64 nginx:alpine 2>/dev/null || true
docker tag deer-flow-sandbox:offline-arm64 enterprise-public-cn-beijing.cr.volces.com/vefaas-public/all-in-one-sandbox:latest 2>/dev/null || true
echo -e "${GREEN}  ✓ 标签配置完成${NC}"
echo ""

# 清理旧镜像
echo -e "${YELLOW}清理未使用镜像...${NC}"
docker image prune -f
echo ""

# 启动服务
echo -e "${YELLOW}启动服务...${NC}"
sudo docker compose up -d

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  更新完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${CYAN}  访问地址: http://localhost:2026${NC}"
    echo -e "${CYAN}  查看日志: sudo docker compose logs -f${NC}"
    echo ""
else
    echo -e "${RED}更新失败，请检查日志${NC}"
    exit 1
fi
