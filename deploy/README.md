# DeerFlow 离线部署指南

本目录包含 DeerFlow 在离线 ARM 服务器上部署所需的所有文件和脚本。

## 目录结构

```
offline-deerflow/
├── images/                    # Docker 镜像 (构建后生成)
│   ├── deer-flow-frontend.tar
│   ├── deer-flow-backend.tar
│   ├── nginx.tar
│   └── sandbox.tar
├── config/                    # 配置文件
│   ├── docker-compose.yaml    # 离线部署专用 compose
│   ├── nginx.conf             # nginx 配置
│   ├── config.example.yaml    # 应用配置模板
│   ├── .env.example           # 环境变量模板
│   └── extensions_config.example.json
├── scripts/
│   ├── build-offline.sh       # 构建脚本 (x86 Ubuntu)
│   ├── deploy-offline.sh      # 部署脚本 (ARM 服务器)
│   ├── check-offline.sh       # 状态检查脚本
│   └── update-offline.sh      # 更新脚本
└── README.md                  # 本文件
```

## 部署流程

### 第一步：在 x86 Ubuntu 开发机构建镜像

**环境要求：**
- Ubuntu 22.04 (x86_64)
- Docker 24.0+
- Docker buildx
- QEMU (用于跨架构构建)
- 约 4GB 磁盘空间

**安装依赖：**

```bash
# 安装 Docker
sudo apt update
sudo apt install -y docker.io docker-buildx

# 安装 QEMU (用于 ARM 模拟)
sudo apt install -y qemu-user-static

# 将当前用户加入 docker 组 (可选，避免每次 sudo)
sudo usermod -aG docker $USER
# 重新登录生效

# 启动 Docker 服务
sudo systemctl start docker
sudo systemctl enable docker
```

**执行构建：**

```bash
# 进入脚本目录
cd offline-deerflow/scripts

# 添加执行权限
chmod +x *.sh

# 执行构建
./build-offline.sh

# 可选参数:
# --skip-sandbox      跳过 sandbox 镜像 (如果内网已有)
# --output-dir DIR    指定输出目录
./build-offline.sh --skip-sandbox
```

**构建产物：**
- `images/deer-flow-frontend.tar` - 前端镜像 (~200MB)
- `images/deer-flow-backend.tar` - 后端镜像 (~500MB)
- `images/nginx.tar` - nginx 镜像 (~25MB)
- `images/sandbox.tar` - sandbox 镜像 (~2GB，可选)

### 第二步：打包传输

```bash
# 打包
cd offline-deerflow
tar -czvf ../deerflow-offline.tar.gz images config scripts README.md

# 查看大小
du -h ../deerflow-offline.tar.gz
```

**传输方式：**

```bash
# 方式 1: SCP (通过跳板机)
scp ../deerflow-offline.tar.gz user@internal-server:/tmp/

# 方式 2: rsync
rsync -avz --progress ../deerflow-offline.tar.gz user@internal-server:/tmp/

# 方式 3: 安全介质 (U盘等)
# 直接复制 tar.gz 文件
```

### 第三步：在内网 ARM 服务器部署

**环境要求：**
- Linux ARM64 (如鲲鹏、Ampere 等)
- Docker 24.0+
- Docker Compose v2+

**安装 Docker (如果未安装)：**

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y docker.io docker-compose-v2

# 启动服务
sudo systemctl start docker
sudo systemctl enable docker
```

**执行部署：**

```bash
# 解压
cd /opt
sudo mkdir -p deerflow
sudo tar -xzvf /tmp/deerflow-offline.tar.gz -C deerflow

# 进入目录
cd /opt/deerflow

# 添加执行权限
chmod +x scripts/*.sh

# 执行部署
sudo ./scripts/deploy-offline.sh

# 检查状态
sudo ./scripts/check-offline.sh
```

### 第四步：配置模型 API

```bash
# 编辑配置文件
sudo vi /opt/deerflow/config.yaml

# 示例配置 (千问模型):
# models:
#   - name: qwen-max
#     display_name: Qwen Max
#     use: langchain_openai:ChatOpenAI
#     model: qwen-max
#     api_key: $DASHSCOPE_API_KEY
#     base_url: https://dashscope.aliyuncs.com/compatible-mode/v1

# 设置环境变量
sudo vi /opt/deerflow/.env
# 添加: DASHSCOPE_API_KEY=your-api-key

# 重启服务
cd /opt/deerflow
sudo docker compose restart
```

## 服务管理

```bash
# 查看服务状态
sudo docker compose ps

# 查看日志
sudo docker compose logs -f
sudo docker compose logs -f frontend
sudo docker compose logs -f gateway
sudo docker compose logs -f langgraph

# 重启服务
sudo docker compose restart

# 停止服务
sudo docker compose down

# 启动服务
sudo docker compose up -d
```

## 访问地址

- Web 界面: http://localhost:2026
- Gateway API: http://localhost:2026/api/*
- LangGraph API: http://localhost:2026/api/langgraph/*

## 更新部署

当需要更新时：

```bash
# 1. 在 x86 Ubuntu 开发机执行构建
cd offline-deerflow/scripts
./build-offline.sh

# 2. 打包传输
cd ..
tar -czvf deerflow-offline-update.tar.gz images
scp deerflow-offline-update.tar.gz user@internal-server:/tmp/

# 3. 在内网服务器执行更新
cd /opt/deerflow
tar -xzvf /tmp/deerflow-offline-update.tar.gz
sudo ./scripts/update-offline.sh
```

## 常见问题

### Q: buildx 创建失败

```bash
# 手动创建 buildx 构建器
docker buildx create --name multiarch --driver docker-container --use
docker buildx inspect --bootstrap

# 安装 QEMU
sudo apt install -y qemu-user-static
docker run --privileged --rm tonistiigi/binfmt --install all
```

### Q: 镜像导入失败

```bash
# 检查文件完整性
md5sum images/*.tar

# 手动导入
docker load -i images/deer-flow-frontend.tar
```

### Q: Docker socket 权限问题

```bash
# 将当前用户加入 docker 组
sudo usermod -aG docker $USER

# 重新登录后生效
```

### Q: 端口被占用

```bash
# 查看端口占用
ss -tlnp | grep 2026

# 修改端口 (编辑 docker-compose.yaml)
# ports:
#   - "8080:2026"  # 改为其他端口
```

### Q: 容器无法访问宿主机 Docker

```bash
# 检查 Docker socket 权限
ls -la /var/run/docker.sock

# 确保 docker 组有读写权限
sudo chmod 660 /var/run/docker.sock
```

## 技术细节

### 镜像架构

所有镜像都使用 `--platform linux/arm64` 构建，确保在 ARM 服务器上原生运行。

### DooD (Docker-out-of-Docker)

Gateway 和 LangGraph 容器通过挂载宿主机的 `/var/run/docker.sock` 来管理沙箱容器。

### 网络模式

服务使用 Docker bridge 网络 `deer-flow`，容器间通过服务名通信。nginx 作为唯一的外部入口，监听 2026 端口。
