#!/bin/bash
set -e

echo "🚀 [1/10] Tworzenie struktury katalogów..."
mkdir -p src manifests/base manifests/production .github/workflows

# --- Aplikacja Go ---
echo "🦦 [2/10] Generowanie aplikacji Go z metrykami Prometheus..."
cat <<'EOF' > src/main.go
package main

import (
    "fmt"
    "net/http"
    "github.com/prometheus/client_golang/prometheus"
    "github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
    httpRequests = prometheus.NewCounter(prometheus.CounterOpts{
        Name: "http_requests_total",
        Help: "Liczba wszystkich żądań HTTP",
    })
)

func main() {
    prometheus.MustRegister(httpRequests)
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        httpRequests.Inc()
        fmt.Fprintf(w, "Hello ArgoCD + GitHub Actions + Kustomize + Kyverno!")
    })
    http.Handle("/metrics", promhttp.Handler())

    fmt.Println("Serwer działa na porcie :8080")
    http.ListenAndServe(":8080", nil)
}
EOF

echo "🧠 [3/10] Inicjalizacja modułu Go i zależności..."
cat <<EOF > go.mod
module example.com/app

go 1.21

require (
    github.com/prometheus/client_golang v1.18.0
)
EOF

cd src
go mod tidy
cd ..

# --- Dockerfile ---
echo "🐳 [4/10] Tworzenie Dockerfile..."
cat <<'EOF' > Dockerfile
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod tidy && go mod download
COPY src/*.go ./
RUN go build -o app

FROM alpine:latest
WORKDIR /root/
COPY --from=builder /app/app .
EXPOSE 8080
CMD ["./app"]
EOF

# --- PostgreSQL + Base Kustomize ---
echo "🧩 [5/10] Tworzenie manifestów Kustomize base..."
cat <<EOF > manifests/base/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: go-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: go-app
  template:
    metadata:
      labels:
        app: go-app
    spec:
      containers:
      - name: go-app
        image: ghcr.io/USERNAME/APPNAME:latest
        ports:
        - containerPort: 8080
EOF

cat <<EOF > manifests/base/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: go-app
spec:
  type: ClusterIP
  selector:
    app: go-app
  ports:
  - port: 80
    targetPort: 8080
EOF

cat <<EOF > manifests/base/postgres.yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret
type: Opaque
data:
  POSTGRES_PASSWORD: cG9zdGdyZXM=  # base64: postgres
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
spec:
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
  type: ClusterIP
  selector:
    app: postgres
  ports:
  - port: 5432
    targetPort: 5432
EOF

cat <<EOF > manifests/base/kustomization.yaml
resources:
  - deployment.yaml
  - service.yaml
  - postgres.yaml
EOF

# --- Production Overlay ---
echo "🏗️ [6/10] Tworzenie overlay production..."
cat <<EOF > manifests/production/kustomization.yaml
namespace: production
resources:
  - ../base
patchesStrategicMerge: []
EOF

cat <<EOF > manifests/production/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: go-app
spec:
  rules:
  - host: go-app.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: go-app
            port:
              number: 80
EOF

cat <<EOF >> manifests/production/kustomization.yaml
resources:
  - ingress.yaml
EOF

# --- ArgoCD Application ---
echo "🧭 [7/10] Tworzenie manifestu ArgoCD Application..."
cat <<EOF > manifests/argocd-application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: go-app
  namespace: argocd
spec:
  destination:
    namespace: production
    server: https://kubernetes.default.svc
  source:
    repoURL: https://github.com/USERNAME/REPO.git
    targetRevision: main
    path: manifests/production
  project: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

# --- GitHub Actions workflow ---
echo "⚙️ [8/10] Tworzenie GitHub Actions workflow..."
cat <<'EOF' > .github/workflows/deploy.yml
name: Build and Deploy
on:
  push:
    branches: [ main ]

env:
  IMAGE_NAME: ghcr.io/${{ github.repository }}
  KUSTOMIZE_PATH: manifests/production
  PLACEHOLDER: APPNAME:placeholder

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4

    - name: Log in to GitHub Container Registry
      run: echo "${{ secrets.GITHUB_TOKEN }}" | docker login ghcr.io -u ${{ github.actor }} --password-stdin

    - name: Build and Push Docker Image
      uses: docker/build-push-action@v5
      with:
        context: .
        push: true
        tags: ${{ env.IMAGE_NAME }}:${{ github.sha }},${{ env.IMAGE_NAME }}:latest

    - name: Update Kustomize image
      run: |
        sed -i "s|${{ env.PLACEHOLDER }}|${{ env.IMAGE_NAME }}:${{ github.sha }}|" ${{ env.KUSTOMIZE_PATH }}/kustomization.yaml

    - name: Commit and push updated manifests
      run: |
        git config user.name "github-actions"
        git config user.email "actions@github.com"
        git add ${{ env.KUSTOMIZE_PATH }}/kustomization.yaml
        git commit -m "Update image tag to ${{ github.sha }}"
        git push
EOF

# --- README ---
echo "📘 [9/10] Tworzenie README.md..."
cat <<EOF > README.md
# 🔥 Aplikacja Go + ArgoCD + Kustomize + GitHub Actions + PostgreSQL

## Struktura
| Element | Opis |
|----------|------|
| **Aplikacja Go** | Generowana przez Twój skrypt (src/main.go) z metrykami Prometheus |
| **PostgreSQL** | Deployment + Service + Secret postgres-secret z hasłem |
| **Kustomize Base / Production** | base definiuje aplikację i bazę, production dodaje Ingress, ServiceMonitor i namespace |
| **ArgoCD Application** | Automatycznie śledzi repo i wdraża zmiany po commicie |
| **GitHub Actions** | Buduje obraz, pushuje do GHCR i aktualizuje kustomization.yaml |

EOF

echo "✅ [10/10] Projekt gotowy!"
echo "Teraz wykonaj: git init && git add . && git commit -m 'Initial commit' && git push"
