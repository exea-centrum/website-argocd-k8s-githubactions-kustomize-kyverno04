# Etap 1: build
FROM golang:1.23-alpine AS builder

WORKDIR /app

# Skopiuj źródła
COPY src/*.go ./

# Utwórz moduł Go, jeśli nie istnieje
RUN if [ ! -f go.mod ]; then go mod init exea-centrum/website-argocd-k8s-githubactions-kustomize-kyverno04; fi

# Dodaj zależności Prometheus
RUN go get github.com/prometheus/client_golang/prometheus \
    && go get github.com/prometheus/client_golang/prometheus/promhttp \
    && go mod tidy

# Zbuduj binarkę
RUN go build -o app .

# Etap 2: minimalny obraz
FROM alpine:latest

WORKDIR /root/
COPY --from=builder /app/app .

CMD ["./app"]
