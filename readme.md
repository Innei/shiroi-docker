# Shiroi Docker Deploy Workflow

这是一个利用 GitHub Action 构建 Shiroi Docker 镜像并部署到远程服务器的工作流。

## Why?

Shiroi 是 [Shiro](https://github.com/Innei/Shiro) 的闭源开发版本。

开源版本提供了预构建的 Docker 镜像或者编译产物可直接使用，但是闭源版本并没有提供。

因为 Next.js build 需要大量内存，很多服务器并吃不消这样的开销。

因此这里提供利用 GitHub Action 去构建 Docker 镜像然后推送到服务器，使用 Docker 容器化部署。

你可以使用定时任务去定时更新 Shiroi。

## How to

开始之前，你的服务器首先需要安装 Docker。

Fork 此项目，然后你需要填写下面的信息。

## 服务器准备

#### 1. 安装 Docker

确保你的服务器已经安装了 Docker：

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install docker.io docker-compose

# CentOS/RHEL
sudo yum install docker docker-compose

# 启动 Docker 服务
sudo systemctl start docker
sudo systemctl enable docker

# 将用户添加到 docker 组（可选，避免每次使用 sudo）
sudo usermod -aG docker $USER
```

#### 2. 准备配置文件

在服务器上创建必要的目录和配置文件：

```bash
# 创建项目目录
mkdir -p $HOME/shiroi/{data,logs}

# 创建环境变量文件
touch $HOME/shiroi/.env
```

编辑 `$HOME/shiroi/.env` 文件，添加 Shiroi 所需的环境变量（参考 `env.example` 文件）：

## Secrets

在 GitHub 仓库的 Settings > Secrets and variables > Actions 中添加以下 secrets：

- `HOST` - 服务器地址
- `USER` - 服务器用户名
- `PASSWORD` - 服务器密码
- `PORT` - 服务器 SSH 端口（默认 22）
- `KEY` - 服务器 SSH Key（可选，与密码二选一）
- `GH_PAT` - 可访问 Shiroi 仓库的 Github Token
- `AFTER_DEPLOY_SCRIPT` - 部署后执行的脚本（可选）

### Github Token

1. 你的账号可以访问 Shiroi 仓库。
2. 进入 [tokens](https://github.com/settings/tokens) - Personal access tokens - Tokens (classic) - Generate new token - Generate new token (classic)
3. 选择适当的权限范围，至少需要 `repo` 权限来访问私有仓库。

![](https://github.com/innei-dev/shiroi-deploy-action/assets/41265413/e55d32cb-bd30-46b7-a603-7d00b3f8a413)

## 工作流程说明

1. **准备阶段**：读取当前构建哈希
2. **检查阶段**：对比远程仓库最新提交，判断是否需要重新构建
3. **构建阶段**：
   - 检出 Shiroi 源码
   - 使用 Docker Buildx 构建镜像
   - 将镜像保存为 tar 文件
   - 上传为 GitHub artifact
4. **部署阶段**：
   - 下载构建的 Docker 镜像
   - 通过 SCP 传输到远程服务器
   - 在服务器上加载镜像
   - 停止旧容器，启动新容器
   - 清理旧镜像和临时文件
5. **存储阶段**：更新构建哈希文件

## 容器配置

部署的 Docker 容器会使用以下配置：

- **端口映射**：`3000:3000`
- **环境变量**：从 `$HOME/shiroi/.env` 文件加载
- **数据持久化**：
  - `$HOME/shiroi/data:/app/data` - 应用数据
  - `$HOME/shiroi/logs:/app/logs` - 日志文件
- **重启策略**：`unless-stopped`

## 手动管理

### 查看容器状态

```bash
docker ps -a | grep shiroi-app
```

### 查看容器日志

```bash
docker logs shiroi-app
docker logs -f shiroi-app  # 实时查看
```

### 手动重启容器

```bash
docker restart shiroi-app
```

### 清理旧镜像

```bash
docker images shiroi
docker rmi shiroi:old-tag  # 删除指定标签的镜像
```

## 故障排除

### 容器启动失败

1. 检查环境变量文件是否正确配置
2. 查看容器日志获取错误信息
3. 确保数据目录权限正确

### 镜像构建失败

1. 检查 GitHub Token 权限
2. 确认 Shiroi 仓库中存在 Dockerfile
3. 查看 GitHub Actions 日志

### 部署失败

1. 检查服务器 SSH 连接
2. 确认 Docker 服务正在运行
3. 检查磁盘空间是否充足
