#!/bin/bash
set -e

REMOTE_HOST="ociecs"
REMOTE_DIR="/opt/mlxmesh"

echo "=================================================="
echo "  Deploying mlxmesh-relay to OCI server ($REMOTE_HOST)..."
echo "=================================================="

# 1. Create remote directory
echo "[1/4] Preparing remote directories on $REMOTE_HOST..."
ssh "$REMOTE_HOST" "sudo mkdir -p $REMOTE_DIR/data && sudo chown -R opc:opc $REMOTE_DIR"

# 2. Sync server files to remote
echo "[2/4] Copying files to $REMOTE_HOST:$REMOTE_DIR..."
scp Server/main.go Server/Dockerfile Server/docker-compose.yml "$REMOTE_HOST:$REMOTE_DIR/"

# 3. Build and launch container
echo "[3/4] Building and launching Docker container on $REMOTE_HOST..."
ssh "$REMOTE_HOST" "cd $REMOTE_DIR && sudo docker rm -f mlxmesh-relay 2>/dev/null || true"
ssh "$REMOTE_HOST" "cd $REMOTE_DIR && sudo docker build -t mlxmesh-relay:latest ."
ssh "$REMOTE_HOST" "sudo docker run -d --name mlxmesh-relay --restart always -p 4001:4001/udp -p 4001:4001/tcp -p 8088:8088/tcp -v /opt/mlxmesh/data:/data mlxmesh-relay:latest"

# 4. Check status and print bootstrap multiaddr
echo "[4/4] Verifying deployment and fetching canonical multiaddr..."
sleep 2
ssh "$REMOTE_HOST" "sudo docker ps | grep mlxmesh-relay"
echo ""
echo "Relay Node Logs:"
ssh "$REMOTE_HOST" "sudo docker logs --tail 15 mlxmesh-relay"

echo ""
echo "Fetching /bootstrap info via HTTP API..."
ssh "$REMOTE_HOST" "curl -s http://127.0.0.1:8088/bootstrap" || true
echo ""
echo "=================================================="
echo "  Deployment Complete! "
echo "=================================================="
