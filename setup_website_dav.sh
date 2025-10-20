#!/bin/bash
# ====================================================================
# Skrypt inicjalizacyjny GitOps dla Website (CI/CD + ArgoCD)
# - Tworzy lokalną strukturę repozytorium GitOps (Go, Dockerfile, Kustomize, ArgoCD, GitHub Actions)
# - NIE buduje lokalnie obrazu, NIE używa Kaniko.
# - Po puszu na GitHub: GitHub Actions zbuduje obraz i wypchnie go do GHCR,
#   a ArgoCD z MicroK8s pobierze manifesty i wdroży aplikację.
# ====================================================================

set -e

# --- 1. Konfiguracja ---
REPO_OWNER="exea-centrum"
REPO_NAME="website-argocd-k8s-githubactions-kustomize-kyverno04"
NAMESPACE="davtrogr"
IMAGE_REGISTRY_PATH="ghcr.io/${REPO_OWNER}/${REPO_NAME}"
IMAGE_TAG="latest"

echo "🚀 Tworzenie struktury GitOps dla repozytorium ${REPO_OWNER}/${REPO_NAME}"
echo "🗂️ Namespace: ${NAMESPACE}"
echo "📦 Docelowy obraz: ${IMAGE_REGISTRY_PATH}:${IMAGE_TAG}"

# --- 2. Sprawdzenie MicroK8s ---
if ! command -v microk8s &>/dev/null; then
  echo "❌ MicroK8s nie znaleziono. Zainstaluj zanim użyjesz tego skryptu."
  exit 1
fi

if ! microk8s status | grep -q "running"; then
  echo "⚠️ MicroK8s nie działa — uruchamiam..."
  sudo microk8s start
  microk8s status --wait-ready --timeout 60 || { echo "❌ MicroK8s nie gotowe."; exit 1; }
fi

echo "✅ MicroK8s działa."
echo "ℹ️  Włącz ręcznie ArgoCD:  microk8s enable argocd"

# --- 3. Tworzenie struktury katalogów ---
APP_DIR="${REPO_NAME}"
rm -rf "${APP_DIR}"
mkdir -p ${APP_DIR}/{src,manifests/{base,production,argocd},.github/workflows}

# --- 4. Generowanie plików aplikacji ---
echo "📝 Tworzenie pliku Go i Dockerfile..."

cat <<'EOF_GO' > ${APP_DIR}/src/main.go
package main

import (
  "fmt"
  "log"
  "net/http"
)

func main() {
  http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
    fmt.Fprintln(w, "<h1>Witaj w aplikacji davtrogr!</h1><p>GitOps + ArgoCD + GitHub Actions</p>")
  })
  log.Println("Serwer działa na porcie :8080")
  log.Fatal(http.ListenAndServe(":8080", nil))
}
EOF_GO

cat <<EOF_MOD > ${APP_DIR}/go.mod
module ${REPO_OWNER}/${REPO_NAME}
go 1.21
EOF_MOD

cat <<'EOF_DOCKER' > ${APP_DIR}/Dockerfile
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY go.mod ./
RUN go mod download
COPY src/*.go ./
RUN go build -o /app/app main.go

FROM alpine:latest
WORKDIR /root/
COPY --from=builder /app/app .
EXPOSE 8080
CMD ["./app"]
EOF_DOCKER

echo "✅ Pliki aplikacji wygenerowane."

# --- 5. Manifesty Kustomize ---
echo "📦 Tworzenie manifestów Kubernetes..."

cat <<EOF_DEPLOY > ${APP_DIR}/manifests/base/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: website
  labels: { app: website }
spec:
  replicas: 1
  selector: { matchLabels: { app: website } }
  template:
    metadata: { labels: { app: website } }
    spec:
      imagePullSecrets:
      - name: regcred
      containers:
      - name: website
        image: ${IMAGE_REGISTRY_PATH}:${IMAGE_TAG}
        ports:
        - containerPort: 8080
EOF_DEPLOY

cat <<EOF_SVC > ${APP_DIR}/manifests/base/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: website-service
spec:
  selector: { app: website }
  ports:
  - port: 80
    targetPort: 8080
EOF_SVC

cat <<EOF_KUSTOM > ${APP_DIR}/manifests/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
- service.yaml

images:
- name: ${IMAGE_REGISTRY_PATH}
  newTag: ${IMAGE_TAG}
EOF_KUSTOM

cat <<EOF_NS > ${APP_DIR}/manifests/production/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
EOF_NS

cat <<EOF_PROD_KUST > ${APP_DIR}/manifests/production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${NAMESPACE}
resources:
- ../base
- namespace.yaml
EOF_PROD_KUST

# --- 6. ArgoCD Application ---
cat <<EOF_ARGO > ${APP_DIR}/manifests/argocd/application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: website
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/${REPO_OWNER}/${REPO_NAME}.git
    targetRevision: HEAD
    path: manifests/production
  destination:
    server: https://kubernetes.default.svc
    namespace: ${NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF_ARGO

# --- 7. GitHub Actions workflow ---
cat <<'EOF_GHA' > ${APP_DIR}/.github/workflows/ci-cd.yaml
name: Build and Deploy to GHCR

on:
  push:
    branches: [main]
    paths:
      - 'src/**'
      - 'Dockerfile'
      - 'go.mod'

permissions:
  contents: write
  packages: write

env:
  IMAGE_REPOSITORY: ghcr.io/${{ github.repository }}
  KUSTOMIZE_PATH: manifests/production
  IMAGE_NAME: ${{ github.repository }}

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

      - name: Set image tag
        id: tag
        run: echo "TAG=$(echo ${{ github.sha }} | cut -c1-7)" >> $GITHUB_OUTPUT

      - name: Build and push image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: |
            ${{ env.IMAGE_REPOSITORY }}:${{ steps.tag.outputs.TAG }}
            ${{ env.IMAGE_REPOSITORY }}:latest

      - name: Update Kustomize image tag
        run: |
          curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
          sudo mv kustomize /usr/local/bin/
          kustomize edit set image ${{ env.IMAGE_REPOSITORY }}=${{ env.IMAGE_REPOSITORY }}:${{ steps.tag.outputs.TAG }} --kustomization ${{ env.KUSTOMIZE_PATH }}
          cat ${{ env.KUSTOMIZE_PATH }}/kustomization.yaml

      - name: Commit and push changes
        uses: EndBug/add-and-commit@v9
        with:
          author_name: github-actions[bot]
          author_email: 41898282+github-actions[bot]@users.noreply.github.com
          message: "Update image tag to ${{ steps.tag.outputs.TAG }}"
          add: '${{ env.KUSTOMIZE_PATH }}/kustomization.yaml'
EOF_GHA

# --- 8. Wdrożenie Application ---
microk8s kubectl apply -k ${APP_DIR}/manifests/argocd

echo "✅ Struktura repozytorium stworzona w katalogu ${APP_DIR}"
echo ""
echo "📌 Kolejne kroki:"
echo "1️⃣  Utwórz sekret do GHCR:"
echo "    microk8s kubectl create secret docker-registry regcred \\"
echo "      --docker-server=https://ghcr.io \\"
echo "      --docker-username=${REPO_OWNER} \\"
echo "      --docker-password='<TWÓJ_PAT>' -n ${NAMESPACE}"
echo ""
echo "2️⃣  Zainicjuj repozytorium i zrób push:"
echo "    cd ${APP_DIR}"
echo "    git init && git add . && git commit -m 'Initial commit'"
echo "    git remote add origin https://github.com/${REPO_OWNER}/${REPO_NAME}.git"
echo "    git branch -M main && git push -u origin main"
echo ""
echo "3️⃣  Upewnij się w GitHub Settings → Actions → General → Workflow permissions = Read and write."
echo ""
echo "🚀  Gotowe! Po pushu GitHub Actions zbuduje obraz i ArgoCD wdroży go automatycznie w MicroK8s."
