#!/bin/bash
set -e

APP_NAME="website-argocd-k8s-githubactions-kustomize-kyverno04"
IMAGE="ghcr.io/exea-centrum/${APP_NAME}"
PORT=8088
MON_NS="monitoring"
PROD_NS="production"

echo "🚀 1/10 Tworzenie struktur katalogów i namespace’ów..."
mkdir -p src manifests/base manifests/production manifests/monitoring

kubectl create ns ${PROD_NS} --dry-run=client -o yaml | kubectl apply -f -
kubectl create ns ${MON_NS} --dry-run=client -o yaml | kubectl apply -f -

echo "🧱 2/10 Generowanie aplikacji Go z metrykami Prometheus..."
cat > src/main.go <<'EOF'
package main

import (
	"fmt"
	"log"
	"net/http"
	"time"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	httpRequests = prometheus.NewCounterVec(
		prometheus.CounterOpts{Name: "http_requests_total", Help: "Liczba zapytań HTTP"},
		[]string{"path", "method"},
	)
)

func init() {
	prometheus.MustRegister(httpRequests)
}

func main() {
	http.HandleFunc("/", handler)
	http.Handle("/metrics", promhttp.Handler())
	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("ok"))
	})
	log.Println("🌍 Start serwera na :8088")
	log.Fatal(http.ListenAndServe(":8088", nil))
}

func handler(w http.ResponseWriter, r *http.Request) {
	httpRequests.WithLabelValues(r.URL.Path, r.Method).Inc()
	t := time.Now().Format("2006-01-02 15:04:05")
	fmt.Fprintf(w, "<h1>davtrogr Website</h1><p>Serwer działa: %s</p>", t)
}
EOF

echo "🧠 3/10 Inicjalizacja modułu Go..."
apk add --no-cache go git 2>/dev/null || sudo apt-get install -y golang git
cd src
go mod init ${APP_NAME}
go get github.com/prometheus/client_golang/prometheus
go get github.com/prometheus/client_golang/prometheus/promhttp
go mod tidy
cd ..

echo "🐳 4/10 Tworzenie Dockerfile..."
cat > Dockerfile <<EOF
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY src/*.go ./
RUN go mod init ${APP_NAME} && \
    go get github.com/prometheus/client_golang/prometheus && \
    go get github.com/prometheus/client_golang/prometheus/promhttp && \
    go mod tidy && \
    go build -o app

FROM alpine:latest
WORKDIR /root/
COPY --from=builder /app/app .
EXPOSE ${PORT}
CMD ["./app"]
EOF

echo "🏗️ 5/10 Budowanie obrazu..."
docker build -t ${IMAGE}:latest .

echo "📦 6/10 Push do GHCR..."
echo $GHCR_TOKEN | docker login ghcr.io -u $GHCR_USER --password-stdin
docker push ${IMAGE}:latest

echo "⚙️ 7/10 Generowanie manifestów K8s..."
cat > manifests/base/deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  labels:
    app: website
spec:
  replicas: 1
  selector:
    matchLabels:
      app: website
  template:
    metadata:
      labels:
        app: website
    spec:
      containers:
        - name: website
          image: ${IMAGE}:latest
          ports:
            - containerPort: ${PORT}
          env:
            - name: PORT
              value: "${PORT}"
---
apiVersion: v1
kind: Service
metadata:
  name: website
  labels:
    app: website
spec:
  ports:
    - port: 80
      targetPort: ${PORT}
      name: http
  selector:
    app: website
EOF

echo "🌍 8/10 Dodanie PostgreSQL i monitoring stack..."
cat > manifests/base/postgres.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret
type: Opaque
stringData:
  POSTGRES_PASSWORD: postgres
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  labels:
    app: postgres
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:15
          env:
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: POSTGRES_PASSWORD
          ports:
            - containerPort: 5432
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
spec:
  ports:
    - port: 5432
  selector:
    app: postgres
EOF

echo "🔗 9/10 Dodanie monitoring stack (Prometheus, Grafana, Loki, Promtail)..."
kubectl apply -k manifests/monitoring/ -n ${MON_NS}

echo "🚢 10/10 Wdrażanie aplikacji i bazy..."
kubectl apply -k manifests/base/ -n ${PROD_NS}


echo "✅ Gotowe! 🌐"
echo "➡ Aplikacja: http://localhost:${PORT}"
echo "➡ Grafana:   http://localhost:32000 (admin/admin)"

