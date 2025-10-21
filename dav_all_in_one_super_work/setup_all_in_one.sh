#!/bin/bash
set -e

# ========================================
#  DAVTROGR Website - Full GitOps Init
# ========================================

REPO_OWNER="exea-centrum"
REPO_NAME="website-argocd-k8s-githubactions-kustomize-kyverno04"
IMAGE_REGISTRY="ghcr.io/${REPO_OWNER}/${REPO_NAME}"
NAMESPACE="production"
APP_DIR="${REPO_NAME}"

echo "🚀 Tworzenie kompletnego środowiska GitOps (${APP_DIR})"

# ========================================
# 1️⃣ Struktura katalogów
# ========================================
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}"/{src,manifests/{base,production},.github/workflows}

# ========================================
# 2️⃣ Aplikacja Go (z metrykami Prometheus)
# ========================================
cat <<'EOF' > ${APP_DIR}/src/main.go
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
	log.Println("🌍 Start serwera na :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}

func handler(w http.ResponseWriter, r *http.Request) {
	httpRequests.WithLabelValues(r.URL.Path, r.Method).Inc()
	t := time.Now().Format("2006-01-02 15:04:05")
	fmt.Fprintf(w, "<h1>davtrogr Website</h1><p>Serwer działa: %s</p>", t)
}
EOF

cat <<EOF > ${APP_DIR}/go.mod
module ${REPO_OWNER}/${REPO_NAME}
go 1.21
require github.com/prometheus/client_golang v1.17.0
EOF

cat <<EOF > ${APP_DIR}/Dockerfile
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY go.mod ./
RUN go mod download
COPY src/*.go ./
RUN go build -o app

FROM alpine:latest
WORKDIR /root/
COPY --from=builder /app/app .
EXPOSE 8080
CMD ["./app"]
EOF

# ========================================
# 3️⃣ Manifesty base (App + PostgreSQL)
# ========================================
cat <<EOF > ${APP_DIR}/manifests/base/kustomization.yaml
resources:
  - deployment-app.yaml
  - service-app.yaml
  - deployment-postgres.yaml
  - service-postgres.yaml
  - secret-postgres.yaml
EOF

# Deployment aplikacji
cat <<EOF > ${APP_DIR}/manifests/base/deployment-app.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: website
  labels:
    app: website
spec:
  replicas: 2
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
          image: ${IMAGE_REGISTRY}:latest
          ports:
            - containerPort: 8080
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: DATABASE_URL
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 10
          readinessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 5
EOF

# Service aplikacji
cat <<EOF > ${APP_DIR}/manifests/base/service-app.yaml
apiVersion: v1
kind: Service
metadata:
  name: website
  labels:
    app: website
spec:
  selector:
    app: website
  ports:
    - port: 80
      targetPort: 8080
EOF

# PostgreSQL Deployment
cat <<EOF > ${APP_DIR}/manifests/base/deployment-postgres.yaml
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
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_DB
              value: appdb
            - name: POSTGRES_USER
              value: appuser
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: POSTGRES_PASSWORD
          volumeMounts:
            - name: pgdata
              mountPath: /var/lib/postgresql/data
      volumes:
        - name: pgdata
          emptyDir: {}
EOF

# PostgreSQL Service
cat <<EOF > ${APP_DIR}/manifests/base/service-postgres.yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres
spec:
  ports:
    - port: 5432
      targetPort: 5432
  selector:
    app: postgres
EOF

# Secret PostgreSQL
cat <<EOF > ${APP_DIR}/manifests/base/secret-postgres.yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret
type: Opaque
stringData:
  POSTGRES_PASSWORD: "supersecurepassword"
  DATABASE_URL: "postgres://appuser:supersecurepassword@postgres:5432/appdb?sslmode=disable"
EOF

# ========================================
# 4️⃣ Manifesty production
# ========================================
cat <<EOF > ${APP_DIR}/manifests/production/kustomization.yaml
namespace: ${NAMESPACE}
resources:
  - ../../manifests/base
  - ingress.yaml
  - servicemonitor.yaml
  - namespace.yaml
images:
  - name: ${REPO_NAME}:placeholder
    newName: ${IMAGE_REGISTRY}
    newTag: latest
EOF

cat <<EOF > ${APP_DIR}/manifests/production/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
EOF

cat <<EOF > ${APP_DIR}/manifests/production/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: website-ingress
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
    - host: website.local.exea-centrum.pl
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: website
                port:
                  number: 80
EOF

cat <<EOF > ${APP_DIR}/manifests/production/servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: website-servicemonitor
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app: website
  endpoints:
    - port: 80
      path: /metrics
      interval: 15s
EOF

# ========================================
# 5️⃣ ArgoCD Application
# ========================================
cat <<EOF > ${APP_DIR}/manifests/production/argocd-application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: website
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/${REPO_OWNER}/${REPO_NAME}.git
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

# ========================================
# 6️⃣ GitHub Actions CI/CD
# ========================================
cat <<'EOF' > ${APP_DIR}/.github/workflows/ci-cd.yaml
name: CI/CD Build & Deploy
on:
  push:
    branches: [ "main" ]
env:
  IMAGE_NAME: ghcr.io/${{ github.repository }}
  KUSTOMIZE_PATH: manifests/production
  PLACEHOLDER: website-argocd-k8s-githubactions-kustomize-kyverno04:placeholder

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Set tag
        id: tag
        run: echo "TAG=$(echo $GITHUB_SHA | cut -c1-7)" >> $GITHUB_OUTPUT

      - name: Build & Push image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: |
            ${{ env.IMAGE_NAME }}:${{ steps.tag.outputs.TAG }}
            ${{ env.IMAGE_NAME }}:latest

      - name: Update Kustomize Tag
        uses: karancode/kustomize-image-tag-update@v1
        with:
          kustomize_path: ${{ env.KUSTOMIZE_PATH }}
          image_name: ${{ env.PLACEHOLDER }}
          new_tag: ${{ steps.tag.outputs.TAG }}

      - name: Commit and Push
        uses: EndBug/add-and-commit@v9
        with:
          add: 'manifests/production/kustomization.yaml'
          message: "Update image tag to ${{ steps.tag.outputs.TAG }}"
          author_name: github-actions[bot]
          author_email: 41898282+github-actions[bot]@users.noreply.github.com
EOF

# ========================================
# 7️⃣ Wdrożenie ArgoCD Application
# ========================================
echo "💾 Wdrażam ArgoCD Application..."
microk8s kubectl apply -f ${APP_DIR}/manifests/production/argocd-application.yaml

echo "✅ Gotowe! Repozytorium ${REPO_NAME} ma pełną strukturę GitOps."
echo "📂 Teraz zrób:"
echo "   cd ${APP_DIR}"
echo "   git init && git add . && git commit -m 'Initial commit'"
echo "   git remote add origin https://github.com/${REPO_OWNER}/${REPO_NAME}.git"
echo "   git push -u origin main"
echo ""
echo "💡 Po pushu GitHub Actions zbuduje obraz i ArgoCD wdroży aplikację w MicroK8s."
