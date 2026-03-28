# HelpMeIn 极简安全架构设计

## 核心原则

| 原则 | 实现方式 |
|------|---------|
| **无 APN** | 零配置，无需证书，无平台依赖 |
| **无状态无储存** | 纯内存/临时存储，服务器不持久化敏感数据 |
| **1MB 传输限制** | 防止滥用，限制单次传输大小 |
| **极致简单** | 最少组件，最少依赖，单文件部署 |

---

## 1. 系统架构图（文本版）

```
┌────────────────────────────────────────────────────────────────────────────────┐
│                            HelpMeIn 极简架构                                   │
├────────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│   ┌─────────────┐                                                              │
│   │ CLI Agent   │  1. 生成临时 ed25519 密钥对 (ephemeral)                      │
│   │  (终端)      │                                                              │
│   └──────┬──────┘                                                              │
│          │                                                                     │
│          │  2. 显示二维码/链接                                                  │
│          │     {request_id, server_url, cli_pubkey, target_url}                 │
│          │                                                                     │
│          ▼                                                                     │
│   ┌─────────────────────────────────────────┐                                  │
│   │  二维码 / 手动输入 / 链接分享              │                                  │
│   │  (无设备注册，无配对流程，扫码即连)        │                                  │
│   └─────────────────────────────────────────┘                                  │
│          │                                                                     │
│          │  3. 扫码/输入                                                       │
│          ▼                                                                     │
│   ┌─────────────┐     4. 直连 Server      ┌─────────────┐                     │
│   │  iOS App    │ ────────────────────────▶ │   Server    │                     │
│   │ (WKWebView) │    GET /r/:id (metadata) │  (Go/Rust)  │                     │
│   └─────────────┘                          └──────┬──────┘                     │
│          │                                         │                           │
│          │  5. 用户登录目标网站                      │  内存缓存 (TTL 5分钟)       │
│          │     - 自动填充账号密码                     │  - 无数据库                │
│          │     - 完成 CAPTCHA                        │  - 无持久化                │
│          │     - 提取 cookies                       │  - 1MB 限制                │
│          │     - 提取 localStorage                  │  - 一次性 URL              │
│          │                                          │                           │
│          │  6. X25519+AES 加密 session              │                           │
│          │     (用 cli_pubkey 加密，服务器零知识)     │                           │
│          │                                          │                           │
│          └─────────────────────────────────────────▶ │                           │
│                    POST /r/:id (加密 blob)           │                           │
│                                                      │                           │
│   ┌─────────────┐     7. 轮询获取               ◀───┘                           │
│   │ CLI Agent   │ ────────────────────────▶    (一次性，立即删除)                │
│   │  (终端)      │    GET /r/:id                                         │
│   └─────────────┘                                                              │
│          │                                                                     │
│          │  8. 解密 session                                                   │
│          │     - 使用临时私钥解密                                               │
│          │     - 应用到 HTTP 客户端                                            │
│          │                                                                     │
│          ▼                                                                     │
│   ┌─────────────────────────────────────────┐                                  │
│   │  Session 使用完毕，临时密钥销毁            │                                  │
│   │  服务器数据已删除，零残留                   │                                  │
│   └─────────────────────────────────────────┘                                  │
│                                                                                │
└────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. 数据流时序

```
时序图
═══════════════════════════════════════════════════════════════════════════════════

CLI                      iOS App                    Server
 │                          │                          │
 │  1. 生成密钥对            │                          │
 │  ed25519_keygen()        │                          │
 │ ───────────────────────▶ │                          │
 │                          │                          │
 │  2. 生成 request_id      │                          │
 │  base62(16 bytes)        │                          │
 │ ───────────────────────▶ │                          │
 │                          │                          │
 │  3. 显示二维码           │                          │
 │  {id, url, pubkey,       │                          │
 │   target}                │                          │
 │ ───────────────────────▶ │                          │
 │         │                │                          │
 │         │ 扫码/输入       │                          │
 │         └───────────────▶ │                          │
 │                          │                          │
 │                          │  4. 获取请求元数据        │
 │                          │  GET /r/:id              │
 │                          │ ───────────────────────▶ │
 │                          │                          │
 │                          │  5. 返回目标 URL         │
 │                          │  {target_url}            │
 │                          │ ◀─────────────────────── │
 │                          │                          │
 │                          │  6. WKWebView 登录       │
 │                          │  - 加载 target_url       │
 │                          │  - 注入登录脚本           │
 │                          │  - 提取 cookies          │
 │                          │  - 提取 localStorage     │
 │                          │                          │
 │                          │  7. 构建 session 包      │
 │                          │  {cookies, localStorage, │
 │                          │   userAgent, timestamp}  │
 │                          │                          │
 │                          │  8. X25519+AES 加密      │
 │                          │  - 生成临时 X25519 密钥对 │
 │                          │  - ECDH(cli_pubkey)      │
 │                          │  - AES-256-GCM 加密      │
 │                          │                          │
 │                          │  9. 上传加密包           │
 │                          │  POST /r/:id            │
 │                          │  {encrypted_blob,       │
 │                          │   ephemeral_pubkey,     │
 │                          │   nonce, tag}            │
 │                          │ ───────────────────────▶ │
 │                          │                          │ 10. 内存存储 (TTL 5m)
 │                          │                          │     set(id, blob, 300s)
 │                          │ 11. 返回 200 OK          │
 │                          │ ◀─────────────────────── │
 │                          │                          │
 │  12. 轮询请求            │                          │
 │  GET /r/:id (轮询)        │                          │
 │ ─────────────────────────────────────────────────▶ │
 │                          │                          │
 │                          │                          │ 13. 检查缓存
 │                          │                          │     if exists → return
 │                          │                          │     if not  → 404
 │                          │                          │
 │ 14. 返回加密包 (删除)     │                          │
 │ {encrypted_blob}        │                          │ del(id)  // 立即删除
 │ ◀─────────────────────────────────────────────────── │
 │                          │                          │
 │ 15. X25519+AES 解密       │                          │
 │ - ECDH(ephemeral_pubkey) │                          │
 │ - AES-256-GCM 解密       │                          │
 │ - 获取明文 session       │                          │
 │                          │                          │
 │ 16. 应用到 HTTP Client   │                          │
 │ - cookies → cookie jar   │                          │
 │ - localStorage → 按需使用 │                          │
 │                          │                          │
 │ 17. 密钥销毁             │                          │
 │ - 删除临时私钥           │                          │
 │ - 内存清零               │                          │
 │                          │                          │
 │                          │                          │ 18. 自动过期清理
 │                          │                          │ (Redis TTL / GC)
 │
═══════════════════════════════════════════════════════════════════════════════════
```

---

## 3. 加密流程详解

### 3.1 密钥交换流程

```
CLI (客户端)                           iOS (移动端)
────────────────────────────────────────────────────────────────────────────────

1. 生成 ed25519 签名密钥对 (长期或临时)
   cli_ed25519_keypair = ed25519_keygen()
   
2. 转换为 X25519 用于加密
   cli_x25519_pubkey = ed25519_to_x25519(cli_ed25519_keypair.pubkey)
   cli_x25519_seckey = ed25519_to_x25519(cli_ed25519_keypair.seckey)
                                       
                                       3. 生成临时 X25519 密钥对
                                          ios_x25519_keypair = x25519_keygen()
                                       
                                       4. ECDH 密钥交换
                                          shared_secret = X25519(ios_seckey, cli_pubkey)
                                       
                                       5. HKDF 派生加密密钥
                                          encryption_key = HKDF(shared_secret, salt, "HelpMeIn-v1")
                                       
                                       6. AES-256-GCM 加密
                                          ciphertext = AES-GCM-Encrypt(encryption_key, plaintext, nonce)
                                       
                                       7. 构造加密包
                                          encrypted_package = {
                                            ephemeral_pubkey: ios_x25519_pubkey,  // 32 bytes
                                            nonce: random(12 bytes),              // 12 bytes
                                            ciphertext: ciphertext,               // variable
                                            tag: gcm_auth_tag                     // 16 bytes
                                          }

8. 收到加密包
   
9. ECDH 密钥交换
   shared_secret = X25519(cli_x25519_seckey, ephemeral_pubkey)
   
10. HKDF 派生相同密钥
    encryption_key = HKDF(shared_secret, salt, "HelpMeIn-v1")
    
11. AES-256-GCM 解密
    plaintext = AES-GCM-Decrypt(encryption_key, ciphertext, nonce, tag)
```

### 3.2 数据包格式

```
// 二维码内容 (URL Encode 或 JSON)
helpmein://login?r=abc123&u=https://server.com&t=https://target.com&k=base64(cli_pubkey)

// 或简化文本格式 (手动输入友好)
abc123.server.com.target.com.base64pubkey

// 服务器响应 (GET /r/:id)
{
  "status": "pending" | "ready" | "expired",
  "target_url": "https://example.com/login",
  "created_at": 1234567890
}

// 加密 Session 上传 (POST /r/:id)
{
  "version": "1",
  "ephemeral_pubkey": "base64(32 bytes)",
  "nonce": "base64(12 bytes)",
  "ciphertext": "base64(variable)",
  "tag": "base64(16 bytes)"
}

// 解密后 Session 结构
{
  "cookies": [
    {"name": "session_id", "value": "xxx", "domain": ".example.com", ...}
  ],
  "local_storage": {
    "auth_token": "xxx",
    "user_prefs": "{...}"
  },
  "user_agent": "Mozilla/5.0 ...",
  "timestamp": 1234567890,
  "target_domain": "example.com"
}
```

---

## 4. 部署方案

### 4.1 Docker 单容器部署（推荐）

```dockerfile
# Dockerfile
FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY server.go .
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o helpmein-server server.go

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /app/helpmein-server .
EXPOSE 8080
CMD ["./helpmein-server"]
```

```yaml
# docker-compose.yml
version: '3.8'

services:
  helpmein:
    build: .
    ports:
      - "8080:8080"
    environment:
      - PORT=8080
      - MAX_SIZE=1048576        # 1MB
      - TTL_SECONDS=300         # 5分钟
      - REDIS_URL=              # 可选，留空使用内存
    restart: unless-stopped
    # 无外部依赖，单容器运行
```

### 4.2 纯内存模式 vs 可选 Redis

| 模式 | 配置 | 适用场景 |
|------|------|---------|
| **纯内存** (默认) | `REDIS_URL=` | 单机部署，低流量，极简 |
| **Redis 缓存** | `REDIS_URL=redis://host:6379` | 多实例部署，需要共享 |

```go
// 内存存储实现 (Go 伪代码)
type MemoryStore struct {
    mu    sync.RWMutex
    data  map[string]*Entry
}

type Entry struct {
    Data      []byte
    ExpiresAt time.Time
}

func (s *MemoryStore) Get(id string) ([]byte, bool) {
    s.mu.RLock()
    defer s.mu.RUnlock()
    
    entry, exists := s.data[id]
    if !exists || time.Now().After(entry.ExpiresAt) {
        return nil, false
    }
    return entry.Data, true
}

func (s *MemoryStore) Set(id string, data []byte, ttl time.Duration) {
    s.mu.Lock()
    defer s.mu.Unlock()
    
    s.data[id] = &Entry{
        Data:      data,
        ExpiresAt: time.Now().Add(ttl),
    }
}

func (s *MemoryStore) Delete(id string) {
    s.mu.Lock()
    defer s.mu.Unlock()
    delete(s.data, id)
}

// 自动清理 goroutine
func (s *MemoryStore) StartGC(interval time.Duration) {
    go func() {
        ticker := time.NewTicker(interval)
        for range ticker.C {
            s.mu.Lock()
            now := time.Now()
            for id, entry := range s.data {
                if now.After(entry.ExpiresAt) {
                    delete(s.data, id)
                }
            }
            s.mu.Unlock()
        }
    }()
}
```

### 4.3 环境变量配置

| 变量 | 默认值 | 说明 |
|------|-------|------|
| `PORT` | `8080` | HTTP 服务端口 |
| `MAX_SIZE` | `1048576` | 最大传输大小 (字节) |
| `TTL_SECONDS` | `300` | 数据存活时间 |
| `REDIS_URL` | `''` | 可选 Redis 连接 |
| `LOG_LEVEL` | `info` | 日志级别 |
| `RATE_LIMIT_RPM` | `60` | 每分钟请求限制 |

---

## 5. API 定义

### 5.1 基础信息

```
Base URL: https://server.com
Content-Type: application/json
```

### 5.2 端点列表

#### GET /r/:id
获取请求状态和目标 URL（iOS 使用）

**响应:**
```json
{
  "status": "pending",
  "target_url": "https://example.com/login",
  "created_at": 1234567890
}
```

**状态值:**
- `pending`: 等待 iOS 上传 session
- `ready`: session 已上传，可下载
- `expired`: 已过期或不存在

---

#### POST /r/:id
上传加密 session（iOS 使用）

**请求头:**
```
Content-Type: application/json
Content-Length: <size>
```

**请求体:**
```json
{
  "version": "1",
  "ephemeral_pubkey": "base64(32bytes)",
  "nonce": "base64(12bytes)",
  "ciphertext": "base64(max_1mb)",
  "tag": "base64(16bytes)"
}
```

**响应 (200 OK):**
```json
{
  "status": "uploaded",
  "expires_at": 1234568190
}
```

**错误响应:**
- `400`: 格式错误
- `413`: 超过 1MB 限制
- `404`: 请求 ID 不存在或已过期
- `429`: 频率限制

---

#### GET /r/:id/download
下载加密 session（CLI 使用，一次性）

**响应 (200 OK):**
```json
{
  "version": "1",
  "ephemeral_pubkey": "base64(32bytes)",
  "nonce": "base64(12bytes)",
  "ciphertext": "base64",
  "tag": "base64(16bytes)"
}
```

**重要**: 下载后立即删除服务器数据

**响应 (404 Not Found):**
```json
{
  "error": "not_found",
  "message": "Request expired or already downloaded"
}
```

---

#### GET /r/:id/ws (可选 WebSocket)
实时状态通知

**用途:**
- CLI 订阅状态变更，避免轮询
- iOS 上传完成后立即通知 CLI

**消息格式:**
```json
{"event": "uploaded", "timestamp": 1234567890}
{"event": "expired", "timestamp": 1234568190}
```

---

#### GET /health
健康检查

**响应:**
```json
{
  "status": "ok",
  "version": "1.0.0",
  "uptime": 3600
}
```

---

### 5.3 错误码统一格式

```json
{
  "error": "error_code",
  "message": "Human readable description",
  "request_id": "abc123"  // 用于追踪
}
```

| 错误码 | 说明 |
|-------|------|
| `not_found` | 请求不存在或已过期 |
| `already_downloaded` | 已被下载（一次性用完） |
| `payload_too_large` | 超过 1MB 限制 |
| `invalid_format` | 数据格式错误 |
| `rate_limited` | 请求过于频繁 |
| `internal_error` | 服务器内部错误 |

---

## 6. 安全模型

### 6.1 威胁模型分析

| 威胁 | 风险等级 | 缓解措施 |
|------|---------|---------|
| 服务器窃取 session | **消除** | 端到端加密，服务器零知识 |
| 中间人攻击 | **消除** | X25519 ECDH 密钥交换 |
| 重放攻击 | **低** | 一次性 URL，用完即焚 |
| 暴力破解 ID | **低** | 128-bit request_id，速率限制 |
| 服务器被攻破 | **中** | 内存存储，无持久化数据 |
| 传输拦截 | **低** | TLS 1.3 + 端到端加密 |
| iOS 设备被盗 | **低** | 无长期密钥存储，一次性使用 |

### 6.2 安全特性详解

#### 6.2.1 服务器零知识 (Zero-Knowledge)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         服务器零知识架构                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  服务器只存储:                                                                │
│  - 加密后的 blob (ciphertext)                                                 │
│  - 请求 ID (随机生成)                                                         │
│  - 创建时间戳                                                                 │
│  - 过期时间                                                                   │
│                                                                             │
│  服务器无法获取:                                                              │
│  - 明文 session 内容                                                         │
│  - cookies 值                                                                │
│  - localStorage 数据                                                         │
│  - 目标网站登录凭证                                                          │
│  - 用户信息                                                                   │
│                                                                             │
│  加密密钥由 CLI 和 iOS 通过 ECDH 协商，服务器从未参与                         │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 6.2.2 一次性 URL (One-Time URL)

```go
// 下载即删除逻辑
func handleDownload(w http.ResponseWriter, r *http.Request) {
    id := mux.Vars(r)["id"]
    
    // 获取并立即删除
    data, err := store.GetAndDelete(id)
    if err != nil {
        http.Error(w, "not found", 404)
        return
    }
    
    // 返回数据后，服务器不再保留任何副本
    w.Header().Set("Content-Type", "application/json")
    w.Write(data)
}
```

#### 6.2.3 自动过期清理

```
TTL 机制:
- 内存/Redis 设置 5 分钟 TTL
- 过期后自动删除，不可恢复
- GC 定期清理过期条目
```

#### 6.2.4 防重放保护

```
1. Request ID 128-bit 随机，不可预测
2. 上传后状态变为 ready
3. 下载后立即删除
4. 重复下载返回 404
5. 过期后 ID 失效
```

### 6.3 隐私保护

| 数据 | 处理方式 |
|------|---------|
| Cookies | 端到端加密传输，服务器不可读 |
| LocalStorage | 端到端加密传输，服务器不可读 |
| 目标 URL | 仅用于 iOS 端登录，不记录 |
| IP 地址 | 可选日志，可禁用 |
| User Agent | 随 session 加密传输 |
| 时间戳 | 仅用于 TTL 计算 |

---

## 7. 极简实现要点

### 7.1 服务端代码结构 (Go 单文件)

```
server.go (约 300-500 行)
├── main()
│   └── http.ListenAndServe()
├── handlers
│   ├── handleGetRequest()     // GET /r/:id
│   ├── handleUpload()         // POST /r/:id
│   ├── handleDownload()       // GET /r/:id/download
│   ├── handleWebSocket()      // WS /r/:id/ws
│   └── handleHealth()         // GET /health
├── storage
│   ├── MemoryStore            // 内存实现
│   └── RedisStore             // Redis 实现 (可选)
├── middleware
│   ├── rateLimiter()          // 速率限制
│   ├── maxBodySize()          // 1MB 限制
│   └── logging()              // 可选日志
└── types
    ├── Request                // 请求结构
    └── EncryptedPackage       // 加密包结构
```

### 7.2 依赖最小化

```go
// 标准库为主
import (
    "crypto/rand"
    "encoding/base64"
    "encoding/json"
    "net/http"
    "sync"
    "time"
    
    // 仅两个外部依赖
    "github.com/gorilla/websocket"    // WebSocket (可选)
    "github.com/redis/go-redis/v9"    // Redis (可选)
)
```

### 7.3 构建与运行

```bash
# 单文件构建
go build -o helpmein-server server.go

# 运行 (零配置)
./helpmein-server

# 或带参数
PORT=8080 MAX_SIZE=1048576 ./helpmein-server

# Docker 构建
docker build -t helpmein .
docker run -p 8080:8080 helpmein
```

---

## 8. 架构优势对比

| 特性 | 传统架构 | 新架构 (极简) |
|------|---------|--------------|
| 配置复杂度 | 高 (证书/依赖) | 零配置 |
| 组件数量 | 多 (多服务/DB) | 单文件 |
| 持久化 | 有 (数据库) | 无 (纯内存) |
| 设备注册 | 需要 | 不需要 |
| 配对流程 | 复杂 | 扫码即连 |
| 延迟 | 低 (实时) | 中 (轮询/WebSocket) |
| 部署难度 | 高 | 极低 |
| 维护成本 | 高 | 极低 |
| 隐私保护 | 较好 | 更好 (零知识) |
| 适用场景 | 企业级 | 个人/小团队 |

---

## 9. 总结

HelpMeIn 极简架构的核心价值:

1. **极致简单**: 单文件部署，零配置，5 分钟启动
2. **隐私优先**: 端到端加密，服务器零知识
3. **无负担**: 无证书管理，无数据库维护
4. **一次性**: 用完即焚，无数据残留
5. **可审计**: 代码量少，易于安全审查

```
部署口诀:
一个文件 server.go
一个镜像 docker build
一个端口 8080
一个命令 go run
运行即服务
```
