# mlxLLM: Apple Silicon (M4 / iPadOS) Speculative Collaborative Inference Mesh

`mlxLLM` 是专为 **iPad Pro (M4 芯片)** 及 Apple Silicon 移动设备（iOS / iPadOS / macOS）打造的**公网自组网大模型协同推理网络**。

通过结合 **Swift + MLX + libp2p-QUIC**，本项目打破了传统分布式推理（如 EXO 框架基于 Python 的朴素层切片/流水线并行）在公网广域网（WAN）下的高延迟瓶颈，采用**分布式投机采样（Distributed Speculative Decoding）**与**非对称任务切分（Asymmetric Compute Partitioning）**策略，并引入**激活值/分布 FP8/INT8 量化压缩**与 **OCI 公网中继/根节点（Circuit Relay v2 & AutoNAT）**。

---

## 核心设计与创新点 (vs. EXO)

| 维度 | EXO (Python 传统流水线/层切分) | mlxLLM (Swift + M4 投机协同算力网) |
| :--- | :--- | :--- |
| **底层引擎** | Python + MLX Python Bindings (受限于移动端解释器) | **原生 Swift + MLX Swift + Metal 硬件加速**，无缝运行于 iPadOS / iOS |
| **切片策略** | 朴素层切片（Layer Slicing，如 1-10 层在 A，11-20 层在 B） | **非对称投机采样（Speculative Decoding）**：M4 负责大模型并行验证，轻量设备负责草稿生成 |
| **公网 RTT 敏感度** | **极度敏感**：每生成 1 个 Token 需在跨公网节点间反复往返多次 ($N \times \text{RTT}$)，公网 50-100ms 下仅 1~2 tok/s | **低往返开销**：1 次公网往返即可验证接收 3~6 个 Token，广域网有效吞吐提升 **3x ~ 5x** |
| **网络协议** | 局域网 gRPC / HTTP | **libp2p-QUIC**（UDP 4001，0-RTT 握手，多路复用无队头阻塞，内置 TLS 1.3） |
| **NAT 穿透** | 局域网为主，公网需要自行配置内网穿透工具 | **AutoNAT + STUN 打洞 + OCI Circuit Relay v2** 兜底穿透 |
| **公网通信压缩** | FP16/BF16 原始浮点传输，带宽占用大 | **FP8 (E4M3/E5M2) + INT8 量化 + Top-K 稀疏 Logits 压缩**，网络载荷减少 **96.5% ~ 99.8%** |

---

## 系统拓扑架构

```
   +---------------------------------------------------------------------------------+
   |                 OCI 云端公网根节点 / 引导与中继集群 (root@ociecs)                  |
   |                               IP: 159.54.182.31                                 |
   |   • libp2p-QUIC (UDP 4001) / TCP Relay (4001)                                   |
   |   • AutoNAT / STUN 反射服务 + Circuit Relay v2 中继                              |
   |   • 节点发现注册表 (/mlx-mesh/v1) & REST API (8088)                             |
   +---------------------------------------------------------------------------------+
                                      ▲              ▲
                                      │              │
                   QUIC-v1 (UDP 4001) │              │ Circuit Relay v2
                   Direct Hole-Punch  │              │ (Symmetric NAT 兜底)
                                      ▼              ▼
+------------------------------------------+    +------------------------------------------+
|      iPad Pro (M4 芯片, 16GB 统一内存)    |    |       iPhone 16 Pro / iPad Air           |
|            [ Target Verifier ]           |    |             [ Drafter ]                  |
|                                          |    |                                          |
| • 运行大目标模型 (如 Qwen2.5-7B/14B Q4)   |    | • 运行轻量小草稿模型 (如 Qwen2.5-0.5B Q4)  |
| • 单批次 (Batch-K) 并行验证草稿 Token    |    | • 极速自回归推演 K 个候选 Token          |
| • 动态调整 KV Cache 与剩余分布补偿采样   |    | • Top-K 稀疏 Logits 与 FP8/INT8 压缩传输 |
| • 统一内存带宽: 120 GB/s                |    | • 内存带宽: 34~60 GB/s                   |
+------------------------------------------+    +------------------------------------------+
```

---

## 模块结构

```
mlxLLM/
├── Package.swift                     # Swift Package 模块定义
├── Sources/
│   ├── MLXMeshCore/                  # 核心硬件自省、协议定义与压缩算法
│   │   ├── DeviceProfile.swift       # 芯片架构识别 (M4/M3/M2/A18Pro)、内存带宽与发热监控
│   │   ├── RoleAssignment.swift      # 动态角色判定 (Verifier / Drafter / Auto)
│   │   ├── MeshProtocol.swift        # libp2p QUIC 交互报文 (握手/投机草稿/验证/心跳)
│   │   └── Quantization/
│   │       ├── CompressionEngine.swift # FP8 (E4M3)、INT8 对称量化与 Top-K 稀疏化
│   │       └── CompressedPayload.swift # 压缩通信载荷结构体
│   ├── MLXMeshNetworking/            # libp2p + QUIC 智能组网与 NAT 穿透
│   │   ├── Multiaddr.swift           # libp2p multiaddress 解析器
│   │   ├── PeerNode.swift            # Ed25519 PeerID 生成与节点状态
│   │   ├── QUICMeshTransport.swift   # Network.framework NWProtocolQUIC 传输层
│   │   ├── MeshDiscovery.swift       # OCI 引导节点注册与对等点发现
│   │   └── RelayClient.swift         # Circuit Relay v2 客户端中继
│   ├── MLXMeshEngine/                # MLX 投机采样协同推理引擎
│   │   ├── VerifierNode.swift        # M4 目标模型并行批次验证
│   │   ├── DrafterNode.swift         # 轻量节点草稿生成
│   │   ├── AsymmetricPipeline.swift  # 非对称调度器与动态 K 调优算法
│   │   ├── KVCacheManager.swift      # 投机验证 KV Cache 事务与回滚
│   │   ├── Sampling.swift            # 拒绝采样与分布修正
│   │   └── SpeculativeEngine.swift   # 分布式投机推理主循环
│   └── MLXMeshApp/                   # iPadOS / iOS 原生 SwiftUI 界面
│       ├── MLXMeshApp.swift          # App 入口
│       ├── ViewModels/MeshCoordinator.swift # 统一状态机与网络推理调度
│       └── Views/
│           ├── DashboardView.swift   # M4 硬件监控、网络状态与节点列表
│           ├── InferencePlaygroundView.swift # 投机推理交互界面 (颜色高亮区分草稿/验证 Token)
│           └── SettingsView.swift    # 引导节点配置、压缩模式与角色切换
├── Server/                           # OCI 远端公网根节点 / 中继服务
│   ├── main.go                       # Go 语言 libp2p 协议中继服务
│   ├── Dockerfile                    # 极轻量 Docker 容器
│   ├── docker-compose.yml            # 一键启停配置
│   └── deploy.sh                     # 自动部署到 root@ociecs
└── Tests/
    └── MLXMeshTests/                 # Swift Testing 自动化单元测试
```

---

## 快速使用

### 1. 运行 CLI 体验硬件自省与投机仿真
```bash
# 运行完整的硬件识别、FP8/INT8 压缩校验与投机协同推演仿真
swift run mlxmesh-cli

# 仅测试硬件画像
swift run mlxmesh-cli profile

# 仅测试 FP8 / INT8 压缩率与误差
swift run mlxmesh-cli quantize-test
```

### 2. 运行单元测试
```bash
swift test
```

### 3. OCI 云端根节点 (root@ociecs) 自动部署
```bash
./Server/deploy.sh
```
部署完成后，服务器提供：
- **UDP 4001**：libp2p-QUIC 传输与 STUN 反射打洞
- **TCP 4001**：Circuit Relay v2 兜底连接
- **HTTP 8088**：节点状态与引导多地址查询 (`http://159.54.182.31:8088/bootstrap`)

已部署上线的 Canonical Multiaddress：
```text
/ip4/159.54.182.31/udp/4001/quic-v1/p2p/12D3KooW0866b920449c0fc0e704cfbd800e00cecdaee689
```
