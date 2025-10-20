#!/usr/bin/env bash
set -e

# ==========================================
# 🦾 Auto-bootstrap Go environment
# ==========================================

if ! command -v go &> /dev/null; then
  echo "⚠️ Go nie jest zainstalowane w systemie."
  echo "🐳 Uruchamiam skrypt wewnątrz kontenera golang:1.21..."
  docker run --rm -v "$(pwd)":/app -w /app golang:1.21 bash all-in-one.sh
  exit 0
fi

# ==========================================
# 1️⃣ Struktura katalogów
# ==========================================
echo "🧱 [1/10] Tworzenie struktury katalogów..."
mkdir -p src manifests/base manifests/production .github/workflows

# ==========================================
# 2️⃣ Aplikacja Go z Prometheus
# ==========================================
echo "🦦 [2/10] Generowanie aplikacji Go z metrykami Prometheus..."
cat > src/main.go <<'EOF'
package main

import (
    "fmt"
    "net/http"
    "github.com/prometheus/client_golang/prometheus"
    "github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
    requests = prometheus.NewCounter(prometheus.CounterOpts{
        Name: "app_requests_total",
        Help: "Total number of requests processed",
    })
)

func handler(w http.ResponseWriter, r *http.Request) {
    requests.Inc()
    fmt.Fprintf(w, "Hello from Go + Prometheus + ArgoCD + PostgreSQL!\n")
}

func main() {
    prometheus.MustRegister(requests)
    http.Handle("/metrics", promhttp.Handler())
    http.HandleFunc("/", handler)
    fmt.Println("🚀 Server running on :8080")
    http.ListenAndServe(":8080", nil)
}
EOF

# ==========================================
# 3️⃣ Go modules
# ==========================================
echo "🧠 [3/10] Inicjalizacja modułu Go i zależności..."
cd src
if [ ! -f go.mod ]; then
    go mod init exea-centrum/website-argocd-k8s-githubactions-kustomize-kyverno04
fi
go get github.com/prometheus/client_golang/prometheus
go get github.com/prometheus/client_golang/prometheus/promhttp
go mod tidy
cd ..

# ==========================================
# 4️⃣ Dockerfile
# ==========================================
echo "🐋 [4/10] Tworzenie Dockerfile..."
cat > Dockerfile <<'EOF'
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY src/*.go ./
RUN go mod init exea-centrum/website-argocd-k8s-githubactions-kustomize-kyverno04 || true
RUN go get github.com/prometheus/client_golang/prometheus \
    && go get github.com/prometheus/client_golang/prometheus/promhttp \
    && go mod tidy
RUN go build -o app main.go

FROM alpine:latest
WORKDIR /root/
COPY --from=builder /app/app .
EXPOSE 8080
CMD ["./app"]
EOF

# ==========================================
# 5️⃣ PostgreSQL + Secret
# ==========================================
echo "🐘 [5/10] Tworzenie manifestów PostgreSQL..."
cat > manifests/base/postgres.yaml <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret
type: Opaque
stringData:
  POSTGRES_PASSWORD: examplepassword
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
        image: postgres:14
        env:
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: POSTGRES_PASSWORD
        ports:
        - containerPort: 5432
EOF

# ==========================================
# 6️⃣ Deployment aplikacji
# ==========================================
echo "🧩 [6/10] Tworzenie manifestów aplikacji..."
cat > manifests/base/app.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: website
spec:
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
        image: ghcr.io/exea-centrum/website-argocd-k8s-githubactions-kustomize-kyverno04:latest
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: website
spec:
  selector:
    app: website
  ports:
  - port: 80
    targetPort: 8080
EOF

# ==========================================
# 7️⃣ Kustomize base + production
# ==========================================
echo "🧩 [7/10] Tworzenie Kustomize base + production..."
cat > manifests/base/kustomization.yaml <<'EOF'
resources:
- app.yaml
- postgres.yaml
EOF

cat > manifests/production/kustomization.yaml <<'EOF'
namespace: production
resources:
- ../base
- ingress.yaml
- servicemonitor.yaml
EOF

cat > manifests/production/ingress.yaml <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: website
spec:
  rules:
  - host: example.local
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

cat > manifests/production/servicemonitor.yaml <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: website
spec:
  selector:
    matchLabels:
      app: website
  endpoints:
  - port: 80
    path: /metrics
EOF

# ==========================================
# 8️⃣ ArgoCD Application
# ==========================================
echo "🚀 [8/10] Tworzenie manifestu ArgoCD..."
cat > manifests/argocd-application.yaml <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: website
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/exea-centrum/website-argocd-k8s-githubactions-kustomize-kyverno04.git
    path: manifests/production
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
EOF

# ==========================================
# 9️⃣ GitHub Actions CI/CD
# ==========================================
echo "⚙️ [9/10] Tworzenie workflow GitHub Actions..."
cat > .github/workflows/deploy.yml <<'EOF'
name: Build and Deploy
on:
  push:
    branches: [ "main" ]
jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build and Push Docker image
        uses: docker/build-push-action@v5
        with:
          push: true
          tags: ghcr.io/exea-centrum/website-argocd-k8s-githubactions-kustomize-kyverno04:${{ github.sha }}
      - name: Install kustomize
        run: |
          curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
          sudo mv kustomize /usr/local/bin/
      - name: Update image in Kustomize
        run: |
          cd manifests/production
          kustomize edit set image ghcr.io/exea-centrum/website-argocd-k8s-githubactions-kustomize-kyverno04=ghcr.io/exea-centrum/website-argocd-k8s-githubactions-kustomize-kyverno04:${{ github.sha }}
      - name: Commit and push manifest update
        run: |
          git config user.name "GitHub Actions"
          git config user.email "actions@github.com"
          git add manifests/production/kustomization.yaml
          git commit -m "Update image to ${{ github.sha }}"
          git push
EOF

# ==========================================
# 🔟 Podsumowanie
# ==========================================
echo "✅ [10/10] Wszystko gotowe!"
echo "Projekt zawiera:"
echo "- Aplikację Go z metrykami Prometheus"
echo "- PostgreSQL (Deployment + Secret + Service)"
echo "- Kustomize Base + Production"
echo "- ArgoCD Application"
echo "- GitHub Actions CI/CD pipeline"
