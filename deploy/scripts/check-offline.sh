#!/bin/bash
#
# check-offline.sh - 检查离线部署状态
#
# 用法: ./check-offline.sh

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

DEPLOY_DIR="${DEER_FLOW_DEPLOY_DIR:-/opt/deerflow}"

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  DeerFlow 离线部署状态检查${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# 检查 Docker
echo -e "${YELLOW}Docker 状态:${NC}"
if docker info &> /dev/null; then
    echo -e "  ${GREEN}✓ Docker 运行正常${NC}"
else
    echo -e "  ${RED}✗ Docker 未运行${NC}"
fi
echo ""

# 检查镜像
echo -e "${YELLOW}已导入镜像:${NC}"
images=("deer-flow-frontend" "deer-flow-backend" "nginx" "enterprise-public-cn-beijing.cr.volces.com/vefaas-public/all-in-one-sandbox")
for img in "${images[@]}"; do
    if docker image inspect "$img" &> /dev/null || docker image inspect "$img:latest" &> /dev/null; then
        size=$(docker images --format "{{.Size}}" "$img" 2>/dev/null || docker images --format "{{.Size}}" "$img:latest" 2>/dev/null)
        echo -e "  ${GREEN}✓ $img${NC} ($size)"
    else
        echo -e "  ${RED}✗ $img (未导入)${NC}"
    fi
done
echo ""

# 检查容器
echo -e "${YELLOW}容器状态:${NC}"
containers=("deer-flow-nginx" "deer-flow-frontend" "deer-flow-gateway" "deer-flow-langgraph")
for container in "${containers[@]}"; do
    status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "not_found")
    case $status in
        running)
            echo -e "  ${GREEN}✓ $container${NC} (运行中)"
            ;;
        exited)
            echo -e "  ${YELLOW}○ $container${NC} (已停止)"
            ;;
        *)
            echo -e "  ${RED}✗ $container${NC} ($status)"
            ;;
    esac
done
echo ""

# 检查端口
echo -e "${YELLOW}端口监听:${NC}"
if command -v ss &> /dev/null; then
    port_2026=$(ss -tlnp 2>/dev/null | grep ":2026" || true)
    port_8001=$(ss -tlnp 2>/dev/null | grep ":8001" || true)
    port_2024=$(ss -tlnp 2>/dev/null | grep ":2024" || true)
    port_3000=$(ss -tlnp 2>/dev/null | grep ":3000" || true)
else
    port_2026=$(netstat -tlnp 2>/dev/null | grep ":2026" || true)
    port_8001=$(netstat -tlnp 2>/dev/null | grep ":8001" || true)
    port_2024=$(netstat -tlnp 2>/dev/null | grep ":2024" || true)
    port_3000=$(netstat -tlnp 2>/dev/null | grep ":3000" || true)
fi

if [ -n "$port_2026" ]; then
    echo -e "  ${GREEN}✓ 端口 2026 (nginx)${NC}"
else
    echo -e "  ${RED}✗ 端口 2026 (nginx)${NC}"
fi

if [ -n "$port_3000" ]; then
    echo -e "  ${GREEN}✓ 端口 3000 (frontend)${NC}"
else
    echo -e "  ${YELLOW}○ 端口 3000 (frontend 内部端口)${NC}"
fi

if [ -n "$port_8001" ]; then
    echo -e "  ${GREEN}✓ 端口 8001 (gateway)${NC}"
else
    echo -e "  ${YELLOW}○ 端口 8001 (gateway 内部端口)${NC}"
fi

if [ -n "$port_2024" ]; then
    echo -e "  ${GREEN}✓ 端口 2024 (langgraph)${NC}"
else
    echo -e "  ${YELLOW}○ 端口 2024 (langgraph 内部端口)${NC}"
fi
echo ""

# 检查配置文件
echo -e "${YELLOW}配置文件:${NC}"
config_files=("$DEPLOY_DIR/config.yaml" "$DEPLOY_DIR/extensions_config.json" "$DEPLOY_DIR/.env")
for cfg in "${config_files[@]}"; do
    if [ -f "$cfg" ]; then
        echo -e "  ${GREEN}✓ $cfg${NC}"
    else
        echo -e "  ${YELLOW}○ $cfg (不存在)${NC}"
    fi
done
echo ""

# 健康检查
echo -e "${YELLOW}服务健康检查:${NC}"
if command -v curl &> /dev/null; then
    # 检查 nginx/前端
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:2026" | grep -q "200\|304"; then
        echo -e "  ${GREEN}✓ 前端页面 (http://localhost:2026)${NC}"
    else
        echo -e "  ${RED}✗ 前端页面 (http://localhost:2026)${NC}"
    fi

    # 检查 gateway API
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:2026/api/models" | grep -q "200"; then
        echo -e "  ${GREEN}✓ Gateway API (http://localhost:2026/api/models)${NC}"
    else
        echo -e "  ${RED}✗ Gateway API${NC}"
    fi
else
    echo -e "  ${YELLOW}需要 curl 进行健康检查${NC}"
fi
echo ""

# 磁盘空间
echo -e "${YELLOW}磁盘空间:${NC}"
df -h "$DEPLOY_DIR" 2>/dev/null | tail -1 | awk '{print "  使用: "$3" / "$2" ("$5" 已用)"}'
echo ""

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  检查完成${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
