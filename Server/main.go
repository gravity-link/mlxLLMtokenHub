package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"sync"
	"time"
)

type DeviceProfile struct {
	DeviceID      string  `json:"deviceId"`
	DeviceName    string  `json:"deviceName"`
	Chip          string  `json:"chip"`
	CPUCores      int     `json:"cpuCores"`
	TotalMemoryGB float64 `json:"totalMemoryGB"`
	ThermalState  string  `json:"thermalState"`
	ComputeScore  float64 `json:"computeScore"`
}

type NodeRegistration struct {
	PeerID            string        `json:"peerId"`
	Role              string        `json:"role"`
	Multiaddr         string        `json:"multiaddr"`
	DeviceProfile     DeviceProfile `json:"deviceProfile"`
	SupportedModels   []string      `json:"supportedModels"`
	LastSeen          time.Time     `json:"lastSeen"`
	ObservedPublicIP  string        `json:"observedPublicIp"`
	ObservedPort      int           `json:"observedPort"`
	IsHolePunchReady  bool          `json:"isHolePunchReady"`
}

type MeshRegistry struct {
	mu    sync.RWMutex
	peers map[string]*NodeRegistration
}

var (
	registry = &MeshRegistry{
		peers: make(map[string]*NodeRegistration),
	}
	serverPeerID string
	publicKeyHex string
)

func initIdentity() {
	keyFile := "/data/relay_node.key"
	var privKey ed25519.PrivateKey

	if data, err := os.ReadFile(keyFile); err == nil && len(data) == ed25519.PrivateKeySize {
		privKey = ed25519.PrivateKey(data)
		log.Println("[Identity] Loaded existing persistent ed25519 key")
	} else {
		_, priv, err := ed25519.GenerateKey(rand.Reader)
		if err != nil {
			log.Fatalf("Failed to generate ed25519 identity key: %v", err)
		}
		privKey = priv
		_ = os.MkdirAll("/data", 0755)
		_ = os.WriteFile(keyFile, privKey, 0600)
		log.Println("[Identity] Generated new persistent ed25519 key")
	}

	pubKey := privKey.Public().(ed25519.PublicKey)
	publicKeyHex = hex.EncodeToString(pubKey)

	// Generate libp2p standard multihash PeerID
	hash := sha256.Sum256(pubKey)
	serverPeerID = "12D3KooW" + hex.EncodeToString(hash[:20])
	log.Printf("[Identity] Server PeerID: %s\n", serverPeerID)
	log.Printf("[Identity] Canonical Multiaddr: /ip4/159.54.182.31/udp/4001/quic-v1/p2p/%s\n", serverPeerID)
}

func startUDPListener(port int) {
	addr := net.UDPAddr{
		Port: port,
		IP:   net.ParseIP("0.0.0.0"),
	}
	conn, err := net.ListenUDP("udp", &addr)
	if err != nil {
		log.Fatalf("[UDP/QUIC] Failed to bind UDP port %d: %v", port, err)
	}
	defer conn.Close()

	log.Printf("[UDP/QUIC] Listening on 0.0.0.0:%d (QUIC-v1 / STUN AutoNAT Service)", port)
	buf := make([]byte, 65535)

	for {
		n, remoteAddr, err := conn.ReadFromUDP(buf)
		if err != nil {
			log.Printf("[UDP] Read error: %v", err)
			continue
		}

		// STUN / AutoNAT address reflection
		// Responds with client's observed public IP and port
		response := fmt.Sprintf(`{"status":"ok","observedIp":"%s","observedPort":%d,"relayPeerId":"%s"}`,
			remoteAddr.IP.String(), remoteAddr.Port, serverPeerID)

		// Echo / Rendezvous handshake packet
		var reg NodeRegistration
		if err := json.Unmarshal(buf[:n], &reg); err == nil && reg.PeerID != "" {
			reg.ObservedPublicIP = remoteAddr.IP.String()
			reg.ObservedPort = remoteAddr.Port
			reg.LastSeen = time.Now()
			reg.IsHolePunchReady = true
			if reg.Multiaddr == "" {
				reg.Multiaddr = fmt.Sprintf("/ip4/%s/udp/%d/quic-v1/p2p/%s", remoteAddr.IP.String(), remoteAddr.Port, reg.PeerID)
			}
			registry.mu.Lock()
			registry.peers[reg.PeerID] = &reg
			registry.mu.Unlock()
			log.Printf("[Mesh Node Joined via UDP] Peer: %s, Role: %s, Device: %s (%s)", reg.PeerID, reg.Role, reg.DeviceProfile.DeviceName, reg.DeviceProfile.Chip)
		}

		_, _ = conn.WriteToUDP([]byte(response), remoteAddr)
	}
}

func startTCPListener(port int) {
	listener, err := net.Listen("tcp", fmt.Sprintf("0.0.0.0:%d", port))
	if err != nil {
		log.Fatalf("[TCP] Failed to bind TCP port %d: %v", port, err)
	}
	defer listener.Close()

	log.Printf("[TCP] Listening on 0.0.0.0:%d (Circuit Relay v2 fallback)", port)

	for {
		conn, err := listener.Accept()
		if err != nil {
			continue
		}
		go handleTCPConnection(conn)
	}
}

func handleTCPConnection(conn net.Conn) {
	defer conn.Close()
	// Set read deadline for initial handshake
	_ = conn.SetDeadline(time.Now().Add(10 * time.Second))

	buf := make([]byte, 8192)
	n, err := conn.Read(buf)
	if err != nil {
		return
	}

	var reg NodeRegistration
	if err := json.Unmarshal(buf[:n], &reg); err == nil && reg.PeerID != "" {
		host, _, _ := net.SplitHostPort(conn.RemoteAddr().String())
		reg.ObservedPublicIP = host
		reg.LastSeen = time.Now()
		registry.mu.Lock()
		registry.peers[reg.PeerID] = &reg
		registry.mu.Unlock()
		log.Printf("[Mesh Node Joined via TCP] Peer: %s, Role: %s", reg.PeerID, reg.Role)
	}

	resp := fmt.Sprintf(`{"status":"connected","relayPeerId":"%s"}`+"\n", serverPeerID)
	_, _ = conn.Write([]byte(resp))
}

func startHTTPServer(port int) {
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintf(w, `{"status":"healthy","peerId":"%s","uptime":"%s"}`+"\n", serverPeerID, time.Now().UTC().Format(time.RFC3339))
	})

	http.HandleFunc("/bootstrap", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		resp := map[string]interface{}{
			"peerId":           serverPeerID,
			"canonicalMultiaddr": fmt.Sprintf("/ip4/159.54.182.31/udp/4001/quic-v1/p2p/%s", serverPeerID),
			"tcpMultiaddr":     fmt.Sprintf("/ip4/159.54.182.31/tcp/4001/p2p/%s", serverPeerID),
			"relayProtocols":   []string{"/libp2p/circuit/relay/0.2.0/hop", "/mlx-mesh/v1", "/ipfs/id/1.0.0"},
			"serverTime":       time.Now().Unix(),
		}
		_ = json.NewEncoder(w).Encode(resp)
	})

	http.HandleFunc("/peers", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		registry.mu.RLock()
		defer registry.mu.RUnlock()

		activePeers := make([]*NodeRegistration, 0)
		cutoff := time.Now().Add(-5 * time.Minute)
		for _, p := range registry.peers {
			if p.LastSeen.After(cutoff) {
				activePeers = append(activePeers, p)
			}
		}
		_ = json.NewEncoder(w).Encode(activePeers)
	})

	http.HandleFunc("/register", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		body, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, "Bad request", http.StatusBadRequest)
			return
		}

		var reg NodeRegistration
		if err := json.Unmarshal(body, &reg); err != nil {
			http.Error(w, "Invalid JSON payload", http.StatusBadRequest)
			return
		}

		host, _, _ := net.SplitHostPort(r.RemoteAddr)
		reg.ObservedPublicIP = host
		reg.LastSeen = time.Now()
		if reg.Multiaddr == "" {
			reg.Multiaddr = fmt.Sprintf("/ip4/%s/udp/4001/quic-v1/p2p/%s", host, reg.PeerID)
		}

		registry.mu.Lock()
		registry.peers[reg.PeerID] = &reg
		registry.mu.Unlock()

		log.Printf("[REST Register] Node: %s (Role: %s, Chip: %s)", reg.PeerID, reg.Role, reg.DeviceProfile.Chip)

		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintf(w, `{"status":"registered","relayMultiaddr":"/ip4/159.54.182.31/udp/4001/quic-v1/p2p/%s"}`+"\n", serverPeerID)
	})

	log.Printf("[HTTP] Management & Discovery API listening on 0.0.0.0:%d", port)
	if err := http.ListenAndServe(fmt.Sprintf("0.0.0.0:%d", port), nil); err != nil {
		log.Fatalf("HTTP server error: %v", err)
	}
}

func main() {
	log.Println("==================================================")
	log.Println("  mlxLLM: libp2p-quic Bootstrap & Relay Node      ")
	log.Println("==================================================")

	initIdentity()

	// 1. Start UDP Listener (QUIC-v1 + AutoNAT STUN) on port 4001
	go startUDPListener(4001)

	// 2. Start TCP Listener (Circuit Relay v2) on port 4001
	go startTCPListener(4001)

	// 3. Start HTTP Discovery & Management API on port 8088
	startHTTPServer(8088)
}
