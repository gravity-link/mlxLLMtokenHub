import Foundation

/// Protocol component in a libp2p multiaddress
public enum MultiaddrProtocol: Equatable, Sendable {
    case ip4(String)
    case ip6(String)
    case dns4(String)
    case dns6(String)
    case tcp(UInt16)
    case udp(UInt16)
    case quicV1
    case quic
    case p2p(String)
    case p2pCircuit
    case unknown(String, String?)
}

/// libp2p Multiaddress parser and formatter
public struct Multiaddr: Equatable, Hashable, CustomStringConvertible, Sendable {
    public let protocols: [String]
    public let stringValue: String

    public var description: String {
        return stringValue
    }

    public init(_ string: String) {
        self.stringValue = string
        self.protocols = string.split(separator: "/").map { String($0) }
    }

    /// Extract IP or DNS host
    public var host: String? {
        let parts = stringValue.split(separator: "/")
        for i in 0..<parts.count {
            let part = parts[i]
            if (part == "ip4" || part == "ip6" || part == "dns4" || part == "dns6") && i + 1 < parts.count {
                return String(parts[i + 1])
            }
        }
        return nil
    }

    /// Extract UDP port
    public var udpPort: UInt16? {
        let parts = stringValue.split(separator: "/")
        for i in 0..<parts.count {
            if parts[i] == "udp" && i + 1 < parts.count {
                return UInt16(parts[i + 1])
            }
        }
        return nil
    }

    /// Extract TCP port
    public var tcpPort: UInt16? {
        let parts = stringValue.split(separator: "/")
        for i in 0..<parts.count {
            if parts[i] == "tcp" && i + 1 < parts.count {
                return UInt16(parts[i + 1])
            }
        }
        return nil
    }

    /// Whether this multiaddr specifies QUIC-v1 or QUIC
    public var isQUIC: Bool {
        return stringValue.contains("/quic-v1") || stringValue.contains("/quic")
    }

    /// Extract peer ID
    public var peerId: String? {
        let parts = stringValue.split(separator: "/")
        for i in 0..<parts.count {
            if parts[i] == "p2p" && i + 1 < parts.count {
                return String(parts[i + 1])
            }
        }
        return nil
    }

    /// Whether this address routes through Circuit Relay
    public var isCircuitRelay: Bool {
        return stringValue.contains("/p2p-circuit")
    }

    /// Formats a complete multiaddress
    public static func make(host: String, port: UInt16, isQUIC: Bool = true, peerId: String? = nil) -> Multiaddr {
        let ipProto = host.contains(":") ? "ip6" : (host.first?.isNumber == true ? "ip4" : "dns4")
        let transProto = isQUIC ? "udp/\(port)/quic-v1" : "tcp/\(port)"
        var addr = "/\(ipProto)/\(host)/\(transProto)"
        if let peerId = peerId {
            addr += "/p2p/\(peerId)"
        }
        return Multiaddr(addr)
    }
}
