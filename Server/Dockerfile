# Multi-stage Dockerfile for mlxLLM libp2p bootstrap & relay daemon
FROM golang:alpine AS builder
WORKDIR /app
COPY main.go .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o mlxmesh-relay main.go

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /
COPY --from=builder /app/mlxmesh-relay /usr/local/bin/mlxmesh-relay
VOLUME /data
EXPOSE 4001/udp 4001/tcp 8088/tcp
ENTRYPOINT ["/usr/local/bin/mlxmesh-relay"]
