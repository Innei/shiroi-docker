# Docker 镜像标签策略

## 标签格式

每个构建的 Docker 镜像会被打上三个标签：

### 1. `latest`
- 始终指向最新构建的镜像
- 用于生产部署的默认标签

### 2. Git Commit Hash (`[a-f0-9]{7}`)
- 例如：`abc1234`
- 基于 Git commit 的短 hash
- 提供与代码版本的直接关联
- 用于回滚到特定的代码版本

### 3. 时间戳 (`YYYYMMDD_HHMM`)
- 例如：`20250105_1432`
- 格式：`年月日_时分`（UTC 时间）
- 提供构建时间的精确标识
- 用于按时间顺序进行回滚

## 优势

1. **避免空标签**：每次构建都会生成唯一的标签
2. **版本追溯**：可以通过 git hash 追溯到具体的代码版本
3. **时间排序**：可以按构建时间进行版本管理
4. **回滚支持**：提供多种回滚选择（按代码版本或时间）

## 镜像清理策略

- 保留最新的 10 个版本（可通过 `KEEP_IMAGE_VERSIONS` 环境变量配置）
- 分别管理 hash 标签和日期标签
- 自动清理悬空镜像
- 保留 `latest` 标签

## 使用示例

```bash
# 部署特定的 commit 版本
./deploy-zero-downtime.sh deploy shiroi:abc1234

# 部署特定时间的构建
./deploy-zero-downtime.sh deploy shiroi:20250105_1432

# 回滚到上一个版本（优先使用 git hash 标签）
./rollback.sh prev

# 回滚到特定版本
./rollback.sh rollback abc1234
```

## 标签优先级

回滚脚本的标签选择优先级：

1. Git Hash 标签（最稳定）
2. 日期标签（时间顺序）
3. 其他自定义标签 