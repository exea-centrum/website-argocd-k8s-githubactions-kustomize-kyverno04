#!/bin/bash
set -Eeuo pipefail

# === 1. KONFIGURACJA ===
REPO_OWNER="exea-centrum"
REPO_NAME="website-argocd-k8s-githubactions-kustomize-kyverno04"
NAMESPACE="davtrogr"
IMAGE_REGISTRY_PATH="ghcr.io/${REPO_OWNER}/${REPO_NAME}"
IMAGE_TAG="latest"
REPO_HTTPS_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}.git"
APP_DIR="${REPO_NAME}"

echo -e "\n🚀 Inicjalizacja GitOps dla repozytorium: \e[36m${REPO_OWNER}/${REPO_NAME}\e[0m"
echo "Używana przestrzeń nazw: ${NAMESPACE}"
echo "Docelowy obraz GHCR: ${IMAGE_REGISTRY_PATH}:${IMAGE_TAG}"

# === 2. SPRAWDZENIE MICROK8S ===
check_microk8s() {
    echo "🔍 Sprawdzanie MicroK8s..."
    if ! command -v microk8s &>/dev/null; then
        echo "❌ MicroK8s nie jest zainstalowany."; exit 1
    fi
    if ! microk8s status | grep -q "running"; then
        echo "⚠️ Uruchamiam MicroK8s..."
        sudo microk8s start
        microk8s status --wait-ready --timeout 60 || {
            echo "❌ MicroK8s nie uruchomiło się."; exit 1;
        }
    fi
    echo "✅ MicroK8s działa."
}
check_microk8s

echo "ℹ️ Upewnij się, że ArgoCD jest włączone: microk8s enable argocd"

# === 3. STRUKTURA PROJEKTU ===
echo "📂 Tworzę strukturę katalogów..."
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/src" \
         "${APP_DIR}/manifests/base" \
         "${APP_DIR}/manifests/production" \
         "${APP_DIR}/manifests/argocd" \
         "${APP_DIR}/.github/workflows"

# === 4. APLIKACJA GO ===
echo "📝 Generowanie aplikacji Go..."
cat > "${APP_DIR}/src/main.go" <<'EOF'
package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

const (
	DB_HOST = "postgres-service"
	DB_PORT = "5432"
	DB_USER = "appuser"
	DB_NAME = "davtrogrdb"
)

var (
	httpRequestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{Name: "http_requests_total", Help: "Liczba zapytań HTTP."},
		[]string{"path", "method", "code"},
	)
	httpRequestDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{Name: "http_request_duration_seconds", Help: "Czas trwania zapytań HTTP."},
		[]string{"path", "method"},
	)
)

func init() {
	prometheus.MustRegister(httpRequestsTotal)
	prometheus.MustRegister(httpRequestDuration)
}

func main() {
	log.SetFlags(log.Ldate | log.Ltime | log.Lshortfile)
	dbPassword := os.Getenv("DB_PASSWORD")
	log.Printf("DB host=%s, user=%s, password_set=%t", DB_HOST, DB_USER, dbPassword != "")

	http.HandleFunc("/", loggingMiddleware(homeHandler))
	http.HandleFunc("/healthz", healthzHandler)
	http.Handle("/metrics", promhttp.Handler())

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Printf("Serwer działa na porcie :%s", port)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}

func homeHandler(w http.ResponseWriter, r *http.Request) {
	page := `
	<h2>O Mnie</h2>
	<p>Jestem entuzjastą DevOps, specjalizującym się w CI/CD, Kubernetes, GitOps i ArgoCD.</p>
	<h2>Stack</h2>
	<ul><li>GoLang</li><li>MicroK8s</li><li>ArgoCD</li><li>GitHub Actions</li></ul>
	`
	html := fmt.Sprintf(`
	<html><head><title>dawtrogr Website</title></head>
	<body style="font-family:Arial;background:#f7f7f7;padding:40px;">
	<div style="max-width:800px;margin:auto;background:#fff;padding:20px;border-radius:10px;">
	<h1>davtrogr Website (GitOps)</h1>%s
	<p><b>Status:</b> OK</p></div></body></html>`, page)
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(html))
}

type responseWriterWrapper struct {
	http.ResponseWriter
	statusCode int
}
func (lrw *responseWriterWrapper) WriteHeader(code int) {
	lrw.statusCode = code
	lrw.ResponseWriter.WriteHeader(code)
}

func loggingMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		lrw := &responseWriterWrapper{ResponseWriter: w, statusCode: 200}
		start := time.Now()
		next(lrw, r)
		dur := time.Since(start).Seconds()
		httpRequestsTotal.WithLabelValues(r.URL.Path, r.Method, fmt.Sprint(lrw.statusCode)).Inc()
		httpRequestDuration.WithLabelValues(r.URL.Path, r.Method).Observe(dur)
		log.Printf("%s %s -> %d (%.3fs)", r.Method, r.URL.Path, lrw.statusCode, dur)
	}
}

func healthzHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("ok"))
}
EOF

cat > "${APP_DIR}/go.mod" <<EOF
module ${REPO_OWNER}/${REPO_NAME}
go 1.21
require github.com/prometheus/client_golang v1.17.0
EOF

cat > "${APP_DIR}/Dockerfile" <<'EOF'
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY src/*.go ./
RUN go build -o /davtrogr-website ./main.go

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /davtrogr-website .
EXPOSE 8080
CMD ["./davtrogr-website"]
EOF

# === 5. MANIFESTY K8S ===
echo "🧩 Tworzę manifesty Kubernetes..."
cat > "${APP_DIR}/manifests/base/deployment.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: davtrogr-website
  labels:
    app: davtrogr-website
spec:
  replicas: 1
  selector:
    matchLabels:
      app: davtrogr-website
  template:
    metadata:
      labels:
        app: davtrogr-website
    spec:
      containers:
        - name: davtrogr-website
          image: ${IMAGE_REGISTRY_PATH}:${IMAGE_TAG}
          ports:
            - containerPort: 8080
          readinessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 5
EOF

cat > "${APP_DIR}/manifests/base/service.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: davtrogr-website
spec:
  selector:
    app: davtrogr-website
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8080
  type: ClusterIP
EOF

cat > "${APP_DIR}/manifests/base/kustomization.yaml" <<EOF
resources:
  - deployment.yaml
  - service.yaml
EOF

mkdir -p "${APP_DIR}/manifests/production"
cat > "${APP_DIR}/manifests/production/kustomization.yaml" <<EOF
resources:
  - ../base
namespace: ${NAMESPACE}
EOF

# === 6. ARGOCD APPLICATION ===
cat > "${APP_DIR}/manifests/argocd/application.yaml" <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: davtrogr-website
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ${REPO_HTTPS_URL}
    targetRevision: main
    path: manifests/production
  destination:
    server: https://kubernetes.default.svc
    namespace: ${NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

cat > "${APP_DIR}/manifests/argocd/kustomization.yaml" <<EOF
resources:
  - application.yaml
EOF

# === 7. GITHUB ACTIONS ===
echo "⚙️ Tworzę workflow GitHub Actions..."
cat > "${APP_DIR}/.github/workflows/deploy.yaml" <<'EOF'
name: Build and Deploy
on:
  push:
    branches: [ "main" ]
permissions:
  contents: write
  packages: write

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and Push Docker Image
        run: |
          IMAGE="ghcr.io/${{ github.repository }}:$(git rev-parse --short HEAD)"
          docker build -t "$IMAGE" .
          docker push "$IMAGE"
          echo "IMAGE=$IMAGE" >> $GITHUB_ENV

      - name: Update Kustomize Image
        run: |
          cd manifests/production
          kustomize edit set image ghcr.io/${{ github.repository }}=${IMAGE}
          cd ../..
          git config user.name "github-actions"
          git config user.email "actions@github.com"
          git add manifests/production/kustomization.yaml
          git commit -m "Update image to ${IMAGE}"
          git push
EOF

# === 8. GIT INIT + PUSH ===
echo "📤 Inicjalizacja Gita i wysyłka na GitHub..."
cd "${APP_DIR}"
git init
git branch -m main
git add .
git commit -m "Initial GitOps project setup"
git remote add origin "${REPO_HTTPS_URL}"
git push -u origin main

# === 9. DEPLOY ARGOCD ===
echo "💾 Deploy ArgoCD Application..."
microk8s kubectl apply -k manifests/argocd --validate=false || true
echo "✅ ArgoCD Application utworzony."
echo -e "\n🎉 Skrypt zakończony pomyślnie! Projekt wypchnięty i gotowy do GitOps 🚀"
