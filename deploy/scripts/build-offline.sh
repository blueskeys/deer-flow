#!/bin/bash
#
# build-offline.sh - 在 x86 Ubuntu 开发机构建 ARM64 离线镜像
#
# 用法:
#   ./build-offline.sh                    # 默认构建所有镜像
#   ./build-offline.sh --skip-sandbox     # 跳过 sandbox 镜像
#   ./build-offline.sh --output-dir /path # 指定输出目录
#
# 环境要求:
#   - Docker 24.0+
#   - Docker buildx + QEMU
#   - 约 4GB 磁盘空间

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 默认参数
OUTPUT_DIR=""
PLATFORM="linux/arm64"
SKIP_SANDBOX=false

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-sandbox)
            SKIP_SANDBOX=true
            shift
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --platform)
            PLATFORM="$2"
            shift 2
            ;;
        -h|--help)
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  --skip-sandbox      跳过 sandbox 镜像"
            echo "  --output-dir DIR    指定输出目录"
            echo "  --platform ARCH     目标平台 (默认: linux/arm64)"
            echo "  -h, --help          显示帮助"
            exit 0
            ;;
        *)
            echo -e "${RED}未知参数: $1${NC}"
            exit 1
            ;;
    esac
done

# 确定目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OFFLINE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$OFFLINE_ROOT/.." && pwd)"

# 设置输出目录
if [ -z "$OUTPUT_DIR" ]; then
    OUTPUT_DIR="$OFFLINE_ROOT/images"
fi

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  DeerFlow 离线镜像构建工具${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo -e "${BLUE}项目根目录: $PROJECT_ROOT${NC}"
echo -e "${BLUE}输出目录: $OUTPUT_DIR${NC}"
echo -e "${BLUE}目标平台: $PLATFORM${NC}"
echo ""

# 创建输出目录
mkdir -p "$OUTPUT_DIR"

# ========================================
# 检查 Docker 和 buildx
# ========================================
echo -e "${YELLOW}检查 Docker 环境...${NC}"

if ! command -v docker &> /dev/null; then
    echo -e "${RED}错误: Docker 未安装${NC}"
    echo "安装: sudo apt install docker.io docker-buildx"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo -e "${RED}错误: Docker 服务未运行或权限不足${NC}"
    echo "尝试: sudo systemctl start docker"
    echo "或者将用户加入 docker 组: sudo usermod -aG docker \$USER"
    exit 1
fi

# 检查/创建 buildx 构建器
if ! docker buildx inspect multiarch &> /dev/null; then
    echo -e "${BLUE}  创建 buildx 构建器 'multiarch'...${NC}"
    docker buildx create --name multiarch --driver docker-container --use
fi

# 启动构建器并安装 QEMU
echo -e "${BLUE}  初始化 buildx 和 QEMU...${NC}"
docker buildx inspect --bootstrap

# 安装 QEMU (如果需要)
if ! command -v qemu-aarch64 &> /dev/null; then
    echo -e "${BLUE}  安装 QEMU 模拟器...${NC}"
    sudo apt update
    sudo apt install -y qemu-user-static
    docker run --privileged --rm tonistiigi/binfmt --install all
fi

echo -e "${GREEN}  ✓ Docker 环境就绪${NC}"
echo ""

# 切换到项目根目录
cd "$PROJECT_ROOT"

# ========================================
# 构建前端镜像
# ========================================
echo -e "${YELLOW}构建前端镜像 (deer-flow-frontend)...${NC}"

FRONTEND_TAG="deer-flow-frontend:offline-arm64"

docker buildx build \
    --platform "$PLATFORM" \
    --tag "$FRONTEND_TAG" \
    --file frontend/Dockerfile \
    --target prod \
    --load \
    .

if [ $? -ne 0 ]; then
    echo -e "${RED}前端镜像构建失败${NC}"
    exit 1
fi
echo -e "${GREEN}  ✓ 前端镜像构建成功${NC}"

# 导出
FRONTEND_TAR="$OUTPUT_DIR/deer-flow-frontend.tar"
echo -e "${BLUE}  导出: $FRONTEND_TAR${NC}"
docker save "$FRONTEND_TAG" -o "$FRONTEND_TAR"
echo -e "${GREEN}  ✓ 前端镜像导出成功${NC}"
echo ""

# ========================================
# 构建后端镜像
# ========================================
echo -e "${YELLOW}构建后端镜像 (deer-flow-backend)...${NC}"

BACKEND_TAG="deer-flow-backend:offline-arm64"

docker buildx build \
    --platform "$PLATFORM" \
    --tag "$BACKEND_TAG" \
    --file backend/Dockerfile \
    --load \
    .

if [ $? -ne 0 ]; then
    echo -e "${RED}后端镜像构建失败${NC}"
    exit 1
fi
echo -e "${GREEN}  ✓ 后端镜像构建成功${NC}"

# 导出
BACKEND_TAR="$OUTPUT_DIR/deer-flow-backend.tar"
echo -e "${BLUE}  导出: $BACKEND_TAR${NC}"
docker save "$BACKEND_TAG" -o "$BACKEND_TAR"
echo -e "${GREEN}  ✓ 后端镜像导出成功${NC}"
echo ""

# ========================================
# 拉取 nginx 镜像
# ========================================
echo -e "${YELLOW}拉取 nginx 镜像...${NC}"

NGINX_TAG="nginx:alpine-offline-arm64"

docker pull --platform "$PLATFORM" nginx:alpine
docker tag nginx:alpine "$NGINX_TAG"

# 导出
NGINX_TAR="$OUTPUT_DIR/nginx.tar"
echo -e "${BLUE}  导出: $NGINX_TAR${NC}"
docker save "$NGINX_TAG" -o "$NGINX_TAR"
echo -e "${GREEN}  ✓ nginx 镜像导出成功${NC}"
echo ""

# ========================================
# 拉取 sandbox 镜像 (可选)
# ========================================
if [ "$SKIP_SANDBOX" = false ]; then
    echo -e "${YELLOW}拉取 sandbox 镜像...${NC}"
    echo -e "${BLUE}  注意: sandbox 镜像较大 (约 2GB)，请耐心等待${NC}"

    SANDBOX_IMAGE="enterprise-public-cn-beijing.cr.volces.com/vefaas-public/all-in-one-sandbox:latest"
    SANDBOX_TAG="deer-flow-sandbox:offline-arm64"

    if docker pull --platform "$PLATFORM" "$SANDBOX_IMAGE"; then
        docker tag "$SANDBOX_IMAGE" "$SANDBOX_TAG"

        # 导出
        SANDBOX_TAR="$OUTPUT_DIR/sandbox.tar"
        echo -e "${BLUE}  导出: $SANDBOX_TAR${NC}"
        docker save "$SANDBOX_TAG" -o "$SANDBOX_TAR"
        echo -e "${GREEN}  ✓ sandbox 镜像导出成功${NC}"
    else
        echo -e "${YELLOW}  ⚠ sandbox 镜像拉取失败，跳过${NC}"
        echo -e "${BLUE}  提示: 如果内网已有该镜像，可以使用 --skip-sandbox 参数跳过${NC}"
    fi
    echo ""
fi

# ========================================
# 复制配置文件
# ========================================
echo -e "${YELLOW}复制配置文件...${NC}"

CONFIG_SRC="$OFFLINE_ROOT/config"
mkdir -p "$CONFIG_SRC"

# docker-compose.yaml 已经存在于 config 目录
# nginx.conf 已经存在于 config 目录

# 复制项目配置模板
if [ -f "$PROJECT_ROOT/config.example.yaml" ]; then
    cp "$PROJECT_ROOT/config.example.yaml" "$CONFIG_SRC/"
fi

if [ -f "$PROJECT_ROOT/.env.example" ]; then
    cp "$PROJECT_ROOT/.env.example" "$CONFIG_SRC/"
fi

if [ -f "$PROJECT_ROOT/extensions_config.example.json" ]; then
    cp "$PROJECT_ROOT/extensions_config.example.json" "$CONFIG_SRC/"
fi

echo -e "${GREEN}  ✓ 配置文件复制完成${NC}"
echo ""

# ========================================
# 完成总结
# ========================================
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  构建完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 计算总大小
echo -e "${CYAN}镜像文件:${NC}"
TOTAL_SIZE=0
for tar_file in "$OUTPUT_DIR"/*.tar; do
    if [ -f "$tar_file" ]; then
        SIZE=$(stat -c%s "$tar_file" 2>/dev/null || stat -f%z "$tar_file" 2>/dev/null)
        SIZE_MB=$((SIZE / 1024 / 1024))
        TOTAL_SIZE=$((TOTAL_SIZE + SIZE))
        FILENAME=$(basename "$tar_file")
        echo -e "  - $FILENAME ($SIZE_MB MB)"
    fi
done

TOTAL_SIZE_MB=$((TOTAL_SIZE / 1024 / 1024))
echo ""
echo -e "${CYAN}总大小: $TOTAL_SIZE_MB MB${NC}"
echo ""
echo -e "${CYAN}输出目录: $OUTPUT_DIR${NC}"
echo ""
echo -e "${YELLOW}下一步:${NC}"
echo -e "  1. 打包传输: cd $OFFLINE_ROOT && tar -czvf deerflow-offline.tar.gz images config scripts README.md"
echo -e "  2. 传输到内网 ARM 服务器"
echo -e "  3. 在内网服务器执行: tar -xzvf deerflow-offline.tar.gz && sudo ./scripts/deploy-offline.sh"
echo ""
