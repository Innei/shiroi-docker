# 🔵🟢 Shiroi 负载均衡部署指南

这个项目支持两种部署模式：

## 1. 蓝绿部署模式 (默认)
- **用途**: 零停机更新，在蓝绿两个环境之间切换
- **特点**: 同时只有一个环境处理请求
- **脚本**: `deploy-zero-downtime.sh`

## 2. 负载均衡模式 (新增)
- **用途**: 提高性能，两个实例同时处理请求
- **特点**: 蓝绿两个环境同时运行，平均分配负载
- **脚本**: `deploy-load-balanced.sh`

---

## 🚀 快速开始

### 启用负载均衡模式

```bash
# 1. 部署应用到负载均衡模式
./deploy-load-balanced.sh deploy shiroi:latest

# 2. 查看负载均衡状态
./deploy-load-balanced.sh status

# 3. 如果已有运行的服务，可以直接启用负载均衡
./deploy-load-balanced.sh enable-lb
```

### 切换回蓝绿模式

```bash
# 切换回传统的蓝绿部署模式
./deploy-load-balanced.sh switch-to-bg
```

---

## 📋 负载均衡配置

### Nginx Upstream 配置

负载均衡使用 `nginx/upstream-balanced.conf`:

```nginx
upstream shiroi_backend {
    # Blue container
    server shiroi-app-blue:2323 weight=1 max_fails=3 fail_timeout=30s;
    
    # Green container  
    server shiroi-app-green:2323 weight=1 max_fails=3 fail_timeout=30s;
    
    # 负载均衡算法 (可选)
    # ip_hash;           # 基于客户端IP的会话亲和性
    # least_conn;        # 路由到连接数最少的服务器
    # fair;              # 基于响应时间路由 (需要nginx-upstream-fair模块)
    
    # 连接池配置
    keepalive 32;
    keepalive_requests 100;
    keepalive_timeout 60s;
}
```

### Docker Compose 修改

修改后的 `docker-compose.yml` 允许两个容器同时运行：

```yaml
  shiroi-app-green:
    # ... 其他配置 ...
    # 移除了 profiles 限制，允许同时启动
    # profiles:
    #   - green
```

---

## 🔧 负载均衡模式的优势

### 1. **性能提升**
- 请求分散到两个容器
- 提高并发处理能力
- 减少单个容器的负载

### 2. **高可用性** 
- 如果一个容器故障，另一个继续服务
- 自动故障转移 (`max_fails=3 fail_timeout=30s`)
- 零停机时间

### 3. **弹性扩展**
- 可以根据负载调整权重
- 支持动态添加/移除后端服务器

---

## 📊 监控和测试

### 检查负载分布

```bash
# 查看容器状态
docker ps --filter "name=shiroi"

# 查看nginx配置
cat nginx/upstream.conf

# 测试负载分布 (发送多个请求)
for i in {1..10}; do
  curl -s http://localhost:12333/nginx-health
  echo " - Request $i"
done
```

### 容器资源使用

```bash
# 查看容器资源使用情况
docker stats shiroi-app-blue shiroi-app-green
```

---

## ⚠️ 注意事项

### 1. **会话状态**
- 如果应用有会话状态，考虑使用 `ip_hash` 指令
- 或者使用外部会话存储 (如 Redis)

### 2. **数据一致性**
- 确保两个容器访问相同的数据源
- 注意文件系统操作的一致性

### 3. **资源消耗**
- 负载均衡模式会消耗更多内存和CPU
- 当前每个容器限制 500MB 内存

### 4. **健康检查**
- 两个容器都必须通过健康检查
- 不健康的容器会自动从负载均衡中移除

---

## 🔄 模式切换

### 从蓝绿切换到负载均衡

```bash
# 确保两个容器都在运行
docker compose up -d

# 启用负载均衡
./deploy-load-balanced.sh enable-lb
```

### 从负载均衡切换到蓝绿

```bash
# 切换到蓝绿模式 (只保留蓝色容器)
./deploy-load-balanced.sh switch-to-bg

# 或者使用原始的部署脚本
./deploy-zero-downtime.sh deploy shiroi:latest
```

---

## 🛠️ 故障排除

### 常见问题

1. **容器启动失败**
   ```bash
   # 检查容器日志
   docker logs shiroi-app-blue
   docker logs shiroi-app-green
   ```

2. **负载不均衡**
   ```bash
   # 检查nginx配置
   docker exec shiroi-nginx cat /etc/nginx/conf.d/upstream.conf
   
   # 重新加载nginx配置
   docker exec shiroi-nginx nginx -s reload
   ```

3. **健康检查失败**
   ```bash
   # 检查容器健康状态
   docker inspect shiroi-app-blue --format='{{.State.Health.Status}}'
   docker inspect shiroi-app-green --format='{{.State.Health.Status}}'
   ```

### 调试模式

```bash
# 查看详细的部署信息
./deploy-zero-downtime.sh debug

# 查看负载均衡状态
./deploy-load-balanced.sh status
``` 