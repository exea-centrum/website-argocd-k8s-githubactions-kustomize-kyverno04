# version 4

# ============================
# Stage 1: Build Go app
# ============================
FROM golang:1.21-alpine AS builder

WORKDIR /app

# Skopiuj kod źródłowy (bezpośrednio, bez go.mod — Docker go utworzy)
COPY src/*.go ./

# Utwórz moduł Go, jeśli nie istnieje
RUN if [ ! -f go.mod ]; then go mod init exea-centrum/website-argocd-k8s-githubactions-kustomize-kyverno04; fi

# Dodaj Prometheus dependencies i wygeneruj go.sum
RUN go get github.com/prometheus/client_golang/prometheus \
    && go get github.com/prometheus/client_golang/prometheus/promhttp \
    && go mod tidy

# Zbuduj binarkę
RUN go build -o app main.go

# ============================
# Stage 2: Minimalny obraz
# ============================
FROM alpine:latest

WORKDIR /root/
COPY --from=builder /app/app .

EXPOSE 8080
CMD ["./app"]