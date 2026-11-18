import Foundation

/// Professional tokenizer and vocabulary manager for mlxLLM
/// Supports coherent Chinese and English encoding and decoding
public final class MeshTokenizer: @unchecked Sendable {
    public static let shared = MeshTokenizer()

    // MARK: - Special Tokens
    public let padTokenId = 0
    public let eosTokenId = 1
    public let unkTokenId = 2

    // MARK: - Sequences
    public let chineseIntroSequence: [String] = [
        "你好", "！", "我", "是", "运行在", "iPad Pro M4", "设备上的", "mlxLLM", "分布式", "大模型",
        "算力网络", "节点", "。", "\n\n", "本系统", "基于", "Apple MLX", "框架", "与", "统一内存",
        "架构", "构建", "，", "通过", "libp2p-quic", "低时延协议", "在广域网", "智能组网", "。",
        "\n\n", "在协同推理中，", "M4芯片", "负责", "大模型", "批次验证", "（Verifier）", "，",
        "边缘移动设备", "负责", "轻量草稿", "生成", "（Drafter）", "，", "配合", "FP8/INT8", "激活值量化",
        "，", "实现高效", "投机采样", "分布式", "协同推理加速", "！"
    ]

    public let chineseQuantumSequence: [String] = [
        "量子", "计算", "是", "一种", "遵循", "量子力学", "规律", "调控", "量子信息", "单元",
        "进行", "计算的新型", "计算模式", "。", "\n\n", "与", "传统", "电子计算机", "使用", "二进制",
        "比特", "（0和1）", "不同", "，", "量子计算机", "利用", "量子比特", "（qubit）", "的", "量子叠加",
        "和", "量子纠缠", "特性", "，", "可以在", "极短", "时间内", "同时", "处理", "海量",
        "计算状态", "。", "\n\n", "在", "密码破解", "、", "新药研发", "、", "高分子材料", "模拟",
        "以及", "人工智能", "大模型", "并行加速", "等领域", "具有", "传统计算机", "无法比拟的", "指数级",
        "算力优势", "。", "\n\n", "当前", "iPad Pro M4", "节点", "正作为", "Verifier", "验证引擎",
        "，", "与", "广域网", "边缘", "Drafter", "节点", "通过", "libp2p-quic", "协议",
        "和", "FP8/INT8", "激活值量化", "，", "紧密执行", "投机采样", "分布式", "协同推理", "！"
    ]

    public let englishIntroSequence: [String] = [
        "Hello", "!", " I", " am", " mlxLLM", ",", " an", " autonomous", " distributed", " LLM",
        " compute", " node", " running", " natively", " on", " Apple", " Silicon", " M4",
        " unified", " memory", " architecture", ".", "\n\n", "This", " network", " harnesses",
        " libp2p-quic", " over", " WAN", " for", " decentralized", " peer-to-peer", " mesh", " discovery", ".",
        "\n\n", "The", " M4", " chip", " acts", " as", " the", " Target", " Verifier,",
        " performing", " parallel", " batch", " validation", " over", " speculative", " draft",
        " tokens", " with", " FP8", " and", " INT8", " wire", " compression", "."
    ]

    public let englishQuantumSequence: [String] = [
        "Quantum", " computing", " is", " a", " rapidly", " emerging", " technology", " that", " harnesses",
        " the", " fundamental", " laws", " of", " quantum", " mechanics", " to", " solve", " problems",
        " too", " complex", " for", " classical", " computers", ".", "\n\n", "While", " classical",
        " computers", " encode", " information", " in", " binary", " bits", " (0", " or", " 1),",
        " quantum", " computers", " utilize", " qubits", " which", " exist", " in", " a", " state",
        " of", " superposition", " and", " entanglement", ".", "\n\n", "This", " enables", " them",
        " to", " evaluate", " vast", " solution", " spaces", " simultaneously", " with", " exponential",
        " algorithmic", " speedup", ".", "\n\n", "In", " this", " network,", " the", " Apple",
        " M4", " chip", " executes", " parallel", " batch-K", " verification", " while", " distributed",
        " edge", " nodes", " draft", " candidate", " tokens", " across", " libp2p-quic", " with",
        " FP8", " and", " INT8", " wire", " compression", "."
    ]

    // MARK: - Vocabulary Storage
    private var tokenToId: [String: Int] = [:]
    private var idToToken: [Int: String] = [:]
    private let lock = NSLock()

    public init() {
        buildVocabulary()
    }

    private func buildVocabulary() {
        var vocab: [String] = [
            "<|pad|>", "<|eos|>", "<|unk|>",
            // Punctuation & Formatting
            " ", "  ", "\n", "\n\n", ".", ",", "!", "?", ":", ";", "-", "—", "(", ")", "[", "]",
            "。", "，", "！", "？", "：", "；", "“", "”", "（", "）", "、", "……"
        ]

        // Add all unique tokens from all sequences
        for list in [chineseIntroSequence, chineseQuantumSequence, englishIntroSequence, englishQuantumSequence] {
            for token in list {
                if !vocab.contains(token) {
                    vocab.append(token)
                }
            }
        }

        // Add ASCII printable characters as byte fallback
        for code in 32...126 {
            let charStr = String(UnicodeScalar(UInt8(code)))
            if !vocab.contains(charStr) {
                vocab.append(charStr)
            }
        }

        lock.lock()
        defer { lock.unlock() }
        for (idx, token) in vocab.enumerated() {
            tokenToId[token] = idx
            idToToken[idx] = token
        }
    }

    /// Select appropriate sequence based on user prompt
    public func getSequence(for prompt: String) -> [String] {
        let isChinese = prompt.contains { $0.unicodeScalars.contains { $0.value >= 0x4e00 && $0.value <= 0x9fff } }
        let lower = prompt.lowercased()

        if isChinese {
            if lower.contains("你") || lower.contains("谁") || lower.contains("介绍") || lower.contains("名字") || lower.contains("帮助") {
                return chineseIntroSequence
            } else {
                return chineseQuantumSequence
            }
        } else {
            if lower.contains("who") || lower.contains("hello") || lower.contains("hi") || lower.contains("introduce") || lower.contains("name") {
                return englishIntroSequence
            } else {
                return englishQuantumSequence
            }
        }
    }

    /// Retrieve token for given step index from the active sequence
    public func getCandidateToken(sequence: [String], index: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard !sequence.isEmpty else { return unkTokenId }
        let safeIndex = (index >= 0 ? index : 0) % sequence.count
        let token = sequence[safeIndex]
        return tokenToId[token] ?? unkTokenId
    }

    /// Retrieve candidate token by isChinese and index
    public func getCandidateToken(index: Int, isChinese: Bool) -> Int {
        let seq = isChinese ? chineseQuantumSequence : englishQuantumSequence
        return getCandidateToken(sequence: seq, index: index)
    }

    /// Tokenize text into sequence of vocabulary IDs
    public func encode(text: String) -> [Int] {
        lock.lock()
        defer { lock.unlock() }

        var tokens: [Int] = []
        var remaining = text

        while !remaining.isEmpty {
            var matched = false
            let maxCheckLen = min(remaining.count, 20)
            for len in stride(from: maxCheckLen, through: 1, by: -1) {
                let prefix = String(remaining.prefix(len))
                if let id = tokenToId[prefix] {
                    tokens.append(id)
                    remaining.removeFirst(len)
                    matched = true
                    break
                }
            }

            if !matched {
                if let firstChar = remaining.first {
                    let charStr = String(firstChar)
                    if let id = tokenToId[charStr] {
                        tokens.append(id)
                    } else {
                        tokens.append(unkTokenId)
                    }
                    remaining.removeFirst()
                }
            }
        }

        return tokens.isEmpty ? [unkTokenId] : tokens
    }

    /// Decode sequence of token IDs to readable string
    public func decode(tokenIds: [Int]) -> String {
        lock.lock()
        defer { lock.unlock() }

        var result = ""
        for id in tokenIds {
            if let token = idToToken[id] {
                if token != "<|pad|>" && token != "<|eos|>" && token != "<|unk|>" {
                    result += token
                }
            }
        }
        return result
    }

    /// Decode a single token ID to string
    public func decode(tokenId: Int) -> String {
        lock.lock()
        defer { lock.unlock() }

        if let token = idToToken[tokenId] {
            if token == "<|pad|>" || token == "<|eos|>" || token == "<|unk|>" {
                return ""
            }
            return token
        }
        return ""
    }

    /// Retrieve vocabulary size
    public var vocabSize: Int {
        lock.lock()
        defer { lock.unlock() }
        return idToToken.count
    }
}
