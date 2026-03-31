# Cookey 架构设计

## 1. 设计目标

Cookey 的目标不是做一个通用账号系统，而是做一个极简、可自托管、以 CLI 为中心的“扫码登录并回收浏览器会话”工具。

核心约束如下：

- 无 APNs 依赖，无设备注册流程。
- 服务端零知识，只中转加密后的 session。
- 默认单机内存存储，可选长轮询或 WebSocket。
- 单次 session 负载上限 1 MB。
- CLI 本地持久化最少，但必须可恢复、可检查、可导出。

---

## 2. 组件与职责

系统由三部分组成：

1. CLI
   运行在用户终端，负责生成身份、公钥发布、等待 session、解密并落盘。

2. Mobile App
   扫码后在移动端完成目标网站登录，提取 cookies 和 localStorage，再使用 CLI 公钥加密上传。

3. Relay Server
   只保存短时元数据和加密 session，不理解明文 session 内容，不持久化到数据库。

信任边界：

- 用户信任本地 CLI 机器。
- 用户信任自己的移动端设备。
- 不信任 Relay Server。

---

## 3. 本地目录结构

CLI 的所有本地状态放在 `~/.cookey/` 下：

```text
~/.cookey/
├── keypair.json
├── config.json
├── sessions/
│   └── {rid}.json
└── daemons/
    └── {rid}.json
```

权限要求：

- `~/.cookey/` 为 `0700`
- `keypair.json` 为 `0600`
- `sessions/*.json` 为 `0600`
- `daemons/*.json` 为 `0600`

### 3.1 keypair.json

首次启动生成长期身份密钥，保存为 `~/.cookey/keypair.json`：

```json
{
  "version": 1,
  "algorithm": "ed25519",
  "public_key": "base64...",
  "private_key": "base64...",
  "created_at": "2026-03-28T12:00:00Z"
}
```

说明：

- 这里保存的是 CLI 的长期 `ed25519` 身份密钥。
- 在会话加密时，运行时将该密钥按标准方式转换为 `x25519` 用于 ECDH。
- 这样本地只需要一个稳定身份文件，不需要为每次 `login` 单独持久化私钥。

### 3.2 config.json

可选配置文件：

```json
{
  "default_server": "https://relay.example.com",
  "transport": "ws",
  "timeout_seconds": 300,
  "session_retention_days": 7
}
```

### 3.3 daemons/{rid}.json

后台等待进程的描述文件：

```json
{
  "rid": "r_8GQx8tY0j8x3Yw2N",
  "pid": 43127,
  "ppid": 1,
  "status": "waiting",
  "server_url": "https://relay.example.com",
  "transport": "ws",
  "started_at": "2026-03-28T12:01:03Z",
  "updated_at": "2026-03-28T12:01:03Z",
  "target_url": "https://example.com/login"
}
```

---

## 4. CLI 启动流程

每次 CLI 入口启动时都执行同一套 bootstrap 逻辑：

1. 创建 `~/.cookey/` 根目录，权限设为 `0700`。
2. 检查 `~/.cookey/keypair.json` 是否存在。
3. 如果不存在，生成 `ed25519 keypair`，写入 `~/.cookey/keypair.json`。
4. 生成设备指纹。
5. 创建 `~/.cookey/sessions/` 目录。
6. 创建 `~/.cookey/daemons/` 目录。
7. 读取 `config.json`，加载默认 server、transport、timeout。
8. 清理明显失效的 daemon 描述文件，例如 PID 不存在且状态仍为 `waiting`。

### 4.1 设备指纹

设备指纹用于诊断、审计和多设备区分，不用于加密主流程，不应作为认证因子。

推荐输入：

- `public_key`
- `hostname`
- `os`
- `arch`
- 可用时的 `machine-id`

推荐算法：

```text
fingerprint = base64url(sha256(public_key || hostname || os || arch || machine_id))
```

要求：

- 设备指纹稳定但不需要保密。
- 缺少 `machine-id` 时允许退化到 `public_key + hostname + os + arch`。
- 设备指纹进入 login manifest，并写入 session 元数据。

---

## 5. login 命令

`login` 是主入口，负责发起一次新的会话接收流程。

建议命令行：

```bash
cookey login <target_url> [--server URL] [--timeout 300] [--transport ws|poll] [--json] [--no-detach]
```

### 5.1 login 命令职责

执行 `cookey login` 时，CLI 需要完成以下动作：

1. 运行启动 bootstrap。
2. 生成新的请求 ID，记为 `rid`。
3. 读取本地 `ed25519` 公钥，并转换出本次会话可用的 `x25519` 公钥。
4. 构造 login manifest。
5. 将 manifest 注册到 Relay Server。
6. 输出二维码、深链接或可手输短码。
7. fork 子进程在后台等待 session。
8. 父进程立即退出。

### 5.2 rid 生成

`rid` 必须高熵且不可预测，建议：

- 128 bit 随机数
- 使用 `base62` 或 `base32 crockford` 编码
- 长度控制在 20 到 26 个字符之间

示例：

```text
r_8GQx8tY0j8x3Yw2N
```

### 5.3 login manifest

CLI 发送到 Relay Server 的 pending request 元数据：

```json
{
  "rid": "r_8GQx8tY0j8x3Yw2N",
  "target_url": "https://example.com/login",
  "server_url": "https://relay.example.com",
  "cli_public_key": "base64-x25519-pubkey",
  "device_fingerprint": "base64url-sha256",
  "transport_hint": "ws",
  "created_at": "2026-03-28T12:01:03Z",
  "expires_at": "2026-03-28T12:06:03Z"
}
```

说明：

- `target_url` 可以直接放进二维码，也可以只在 server 侧保留短时元数据。
- `cli_public_key` 是移动端加密 session 时使用的接收方公钥。
- `device_fingerprint` 只用于识别请求来自哪个 CLI 设备。

### 5.4 用户可见输出

`login` 至少输出以下信息：

- `rid`
- `target_url`
- `server_url`
- 二维码内容
- 手动输入码或深链接
- 后台 daemon PID

建议二维码内容：

```text
cookey://login?rid=<rid>&server=<server_url>&target=<target_url>&pubkey=<cli_public_key>
```

### 5.5 父进程行为

父进程只负责“发起”和“交出控制权”：

1. 完成 bootstrap。
2. 生成并注册 pending request。
3. fork 子进程。
4. 确认子进程 PID 已写入 `~/.cookey/daemons/{rid}.json`。
5. 打印 `rid` 和 PID。
6. 立即退出，退出码为 `0`。

如果 fork、注册或 PID 文件写入失败，父进程必须直接返回非零退出码。

---

## 6. 后台进程 fork/detach

这是 `login` 的核心运行模型。

### 6.1 进程模型

要求如下：

- 主进程 fork 子进程后立即退出。
- 子进程调用 `setsid()` 脱离控制终端。
- 子进程关闭或重定向标准输入输出。
- 子进程进入后台等待 session。
- 子进程 PID 写入 `~/.cookey/daemons/`。

推荐流程：

```text
CLI parent
  -> fork()
  -> child PID known
  -> wait until ~/.cookey/daemons/{rid}.json is durable
  -> print rid / pid
  -> exit(0)

CLI child
  -> setsid()
  -> redirect stdio
  -> write daemon descriptor
  -> connect server
  -> wait for encrypted session
  -> decrypt
  -> write ~/.cookey/sessions/{rid}.json
  -> update daemon status=ready
  -> exit(0)
```

### 6.2 daemon 描述文件语义

`~/.cookey/daemons/{rid}.json` 不是日志，而是状态单据。

允许的 `status`：

- `waiting`
- `receiving`
- `ready`
- `expired`
- `error`

状态更新规则：

- 启动后立刻写 `waiting`
- 收到服务器推送但尚未落盘时写 `receiving`
- `sessions/{rid}.json` 原子写入成功后写 `ready`
- 超时后写 `expired`
- 任意失败写 `error`

### 6.3 等待 session 的传输方式

后台子进程通过以下两种方式之一等待 session：

1. WebSocket
   连接 `GET /v1/requests/{rid}/ws`，等待服务器推送状态与加密 payload。

2. 长轮询
   循环请求 `GET /v1/requests/{rid}/wait?timeout=30`，直到返回 `ready`、`expired` 或超时。

要求：

- WebSocket 是首选。
- 长轮询是兼容回退。
- 两种模式返回的最终 payload 结构必须一致。

### 6.4 收到 session 后的本地处理

后台子进程在收到加密 session 后执行：

1. 校验 `rid`、版本号、payload 大小。
2. 使用本地私钥解密 session。
3. 校验解密结果是否包含合法的 Playwright `cookies` 和 `origins`。
4. 将 session 原子写入 `~/.cookey/sessions/{rid}.json`。
5. 更新 daemon 状态为 `ready`。
6. 从 Relay Server 删除已消费的加密包，或确认服务端已自动删除。

原子写入要求：

- 先写 `~/.cookey/sessions/{rid}.json.tmp`
- `fsync`
- `rename` 到最终文件名

### 6.5 超时与退出

子进程的默认生命周期与 `login --timeout` 一致，建议默认 300 秒。

退出条件：

- 成功落盘 session 后退出 `0`
- 请求过期后退出 `3`
- 网络错误重试耗尽后退出 `4`
- 解密或格式校验失败后退出 `5`

---

## 7. status 命令

`status` 用于查询请求或 session 的当前状态。

建议命令行：

```bash
cookey status [rid] [--latest] [--watch] [--json]
```

### 7.1 status 行为

如果提供 `rid`：

1. 先检查 `~/.cookey/sessions/{rid}.json` 是否存在。
2. 如果存在，状态为 `ready`。
3. 否则检查 `~/.cookey/daemons/{rid}.json`。
4. 如果 daemon 文件存在，再检查 PID 是否还活着。
5. 必要时向 server 查询远端状态。

如果不提供 `rid`：

- 默认显示最近的 pending daemon 和 ready session 摘要。

### 7.2 状态判定

建议对外暴露以下状态：

| 状态 | 含义 |
|------|------|
| `waiting` | daemon 已启动，正在等待移动端上传 |
| `receiving` | server 已返回 payload，正在解密或落盘 |
| `ready` | 本地 session 文件已存在 |
| `expired` | 请求已过期，未收到 session |
| `orphaned` | daemon 描述文件存在，但 PID 不存在且 session 也不存在 |
| `error` | 后台流程失败 |
| `missing` | 本地和服务端都找不到该 rid |

### 7.3 watch 模式

`cookey status <rid> --watch` 的目标是替代用户自己轮询。

行为：

- 每 1 到 2 秒刷新一次本地状态。
- 如果 transport 为 WebSocket，也可以直接订阅 server 状态。
- 当状态到达 `ready`、`expired` 或 `error` 时退出。

### 7.4 机器可读输出

`--json` 输出建议：

```json
{
  "rid": "r_8GQx8tY0j8x3Yw2N",
  "status": "ready",
  "pid": 43127,
  "target_url": "https://example.com/login",
  "session_path": "/home/user/.cookey/sessions/r_8GQx8tY0j8x3Yw2N.json",
  "updated_at": "2026-03-28T12:02:19Z"
}
```

---

## 8. export 命令

`export` 用于将本地 session 导出为 Playwright 直接可用的 `storageState` 文件，或导出完整原始 envelope。

建议命令行：

```bash
cookey export <rid> [--format playwright|raw] [--out FILE|-] [--pretty]
```

### 8.1 默认行为

默认格式为 `playwright`。

也就是说：

- 读取 `~/.cookey/sessions/{rid}.json`
- 只输出顶层 `cookies` 和 `origins`
- 丢弃 `_cookey` 元数据

默认输出文件建议：

```text
./storage-state.<rid>.json
```

### 8.2 raw 行为

`--format raw` 导出 session 文件的完整 JSON，包括：

- Playwright 兼容会话体
- Cookey 元数据
- 来源、时间戳、设备指纹、server 信息

### 8.3 Playwright 集成方式

导出的 `playwright` 文件应可直接用于：

```ts
import { chromium } from '@playwright/test';

const browser = await chromium.launch();
const context = await browser.newContext({
  storageState: './storage-state.r_8GQx8tY0j8x3Yw2N.json'
});
```

### 8.4 export 失败条件

以下情况返回非零退出码：

- `rid` 对应 session 不存在
- session JSON 非法
- 缺少 `cookies` 或 `origins`
- 输出路径不可写

---

## 9. Session JSON 格式

本地 session 文件路径固定为：

```text
~/.cookey/sessions/{rid}.json
```

该文件必须对 Playwright 友好。推荐格式为“Playwright 顶层结构 + Cookey 元数据命名空间”：

```json
{
  "cookies": [
    {
      "name": "sessionid",
      "value": "abc123",
      "domain": ".example.com",
      "path": "/",
      "expires": 1775068800,
      "httpOnly": true,
      "secure": true,
      "sameSite": "Lax"
    }
  ],
  "origins": [
    {
      "origin": "https://example.com",
      "localStorage": [
        {
          "name": "authToken",
          "value": "secret-token"
        },
        {
          "name": "theme",
          "value": "dark"
        }
      ]
    }
  ],
  "_cookey": {
    "version": 1,
    "rid": "r_8GQx8tY0j8x3Yw2N",
    "server_url": "https://relay.example.com",
    "target_url": "https://example.com/login",
    "device_fingerprint": "base64url-sha256",
    "transport": "ws",
    "captured_at": "2026-03-28T12:02:18Z",
    "received_at": "2026-03-28T12:02:19Z",
    "user_agent": "Mozilla/5.0 (...)",
    "source": "ios"
  }
}
```

### 9.1 兼容性规则

- `cookies` 和 `origins` 字段的结构必须与 Playwright `storageState` 一致。
- Cookey 自有元数据必须放在 `_cookey` 下，避免和 Playwright 字段冲突。
- `export --format playwright` 时必须剥离 `_cookey`。

### 9.2 字段约束

| 字段 | 要求 |
|------|------|
| `cookies` | 数组，可为空，不可缺省 |
| `origins` | 数组，可为空，不可缺省 |
| `_cookey.version` | 整数，当前为 `1` |
| `_cookey.rid` | 与文件名一致 |
| `_cookey.device_fingerprint` | 启动阶段生成 |
| `_cookey.captured_at` | 移动端抓取完成时间 |
| `_cookey.received_at` | CLI 落盘时间 |

---

## 10. 完整 CLI 命令参考

### 10.1 login

```bash
cookey login <target_url> [--server URL] [--timeout SEC] [--transport ws|poll] [--json] [--no-detach]
```

作用：

- 创建一次新的登录接收请求
- 启动后台 daemon 等待 session
- 输出 `rid`、二维码和 PID

### 10.2 status

```bash
cookey status [rid] [--latest] [--watch] [--json]
```

作用：

- 查询某个 `rid` 的状态
- 或列出最近请求状态摘要

### 10.3 export

```bash
cookey export <rid> [--format playwright|raw] [--out FILE|-] [--pretty]
```

作用：

- 导出 Playwright `storageState`
- 或导出本地完整 session 文件

### 10.4 list

```bash
cookey list [--sessions] [--daemons] [--state waiting|ready|expired|error] [--json]
```

作用：

- 列出本地 session 文件
- 列出后台 daemon 单据
- 支持按状态过滤

默认行为：

- 同时显示最近 session 与 daemon

### 10.5 rm

```bash
cookey rm <rid> [--kill] [--force]
cookey rm --expired
cookey rm --all
```

作用：

- 删除本地 session 文件
- 删除 daemon 描述文件
- 必要时杀掉对应后台进程

规则：

- `--kill` 用于结束仍在运行的 daemon
- 没有 `--force` 时，不删除运行中的 daemon

### 10.6 config

```bash
cookey config get <key>
cookey config set <key> <value>
cookey config list
```

建议支持的 key：

- `default_server`
- `transport`
- `timeout_seconds`
- `session_retention_days`

### 10.7 server

```bash
cookey server [--listen 0.0.0.0:8080] [--public-url URL] [--ttl 300] [--max-payload 1048576]
```

作用：

- 启动自托管 Relay Server
- 使用内存保存 pending request 和加密 session

要求：

- 默认 TTL 300 秒
- 默认最大 payload 1 MB
- 支持 WebSocket 和长轮询

---

## 11. Relay Server 协议

服务端协议只解决三件事：

1. 注册 pending request
2. 接收移动端上传的加密 session
3. 将加密 session 交付给等待中的 CLI daemon

### 11.1 API 设计

#### `POST /v1/requests`

注册一个 pending request。

请求体：

```json
{
  "rid": "r_8GQx8tY0j8x3Yw2N",
  "target_url": "https://example.com/login",
  "cli_public_key": "base64-x25519-pubkey",
  "device_fingerprint": "base64url-sha256",
  "expires_at": "2026-03-28T12:06:03Z"
}
```

#### `GET /v1/requests/{rid}`

查询 request 是否存在，以及当前状态。

#### `GET /v1/requests/{rid}/ws`

CLI daemon 使用 WebSocket 等待状态变化和 session 交付。

#### `GET /v1/requests/{rid}/wait?timeout=30`

CLI daemon 使用长轮询等待 session。

#### `POST /v1/requests/{rid}/session`

移动端上传加密 session。

请求体：

```json
{
  "version": 1,
  "algorithm": "x25519-xsalsa20poly1305",
  "ephemeral_public_key": "base64...",
  "nonce": "base64...",
  "ciphertext": "base64...",
  "captured_at": "2026-03-28T12:02:18Z"
}
```

### 11.2 服务端存储约束

服务端只保留：

- pending request 元数据
- 加密后的 session payload
- 过期时间

服务端不保留：

- 明文 cookies
- 明文 localStorage
- CLI 私钥
- 用户密码

### 11.3 交付语义

要求使用“一次上传，一次交付”模型：

- 移动端上传成功后，server 将状态切到 `ready`
- CLI daemon 成功收到 payload 后，server 立即删除加密 session
- 超时未消费则 TTL 到期自动删除

---

## 12. 安全与实现约束

### 12.1 加密模型

推荐模型：

- CLI 长期保存 `ed25519` 身份密钥
- 运行时转换为 `x25519` 密钥用于 ECDH
- 移动端为每次上传生成临时 `x25519` 密钥
- 使用共享密钥加密 session payload

这样可以同时满足：

- CLI 身份稳定
- 每次上传前向隔离
- 服务端无法解密

### 12.2 明文落盘边界

只有本地 CLI 主机允许保存明文 session，且只保存到：

```text
~/.cookey/sessions/{rid}.json
```

服务端绝不保存明文。

### 12.3 容错原则

- daemon 文件损坏时，`status` 必须返回 `error` 或 `orphaned`，不能静默忽略。
- session 文件写入失败时，不得把 daemon 状态更新为 `ready`。
- `export` 只依赖本地 session 文件，不依赖 server 在线。

### 12.4 清理策略

建议提供以下清理能力：

- `cookey rm --expired`
- 启动时清理孤儿 daemon 描述文件
- 按 `session_retention_days` 清理旧 session

---

## 13. 结论

这个版本的 Cookey 架构以 CLI 为核心，重点不是“浏览器自动化能力”，而是“可靠地把一次移动端登录结果送回本地终端，并以 Playwright 可消费的格式保存下来”。

关键决策如下：

- CLI 首次启动生成长期 `ed25519` 身份密钥。
- 每次启动生成设备指纹，并确保 `sessions/` 与 `daemons/` 目录存在。
- `login` 只负责发起请求并后台等待，不阻塞前台终端。
- 后台子进程通过 WebSocket 或长轮询接收 session。
- 收到 session 后固定写入 `~/.cookey/sessions/{rid}.json`。
- session 文件顶层保持 Playwright 兼容，CLI 元数据放在 `_cookey` 命名空间。
- `status`、`export`、`list`、`rm`、`config`、`server` 构成完整的 CLI 可操作面。

这套设计保持了极简、零知识和可自托管三个目标，同时把 CLI 的本地状态管理定义清楚，便于后续直接实现。
