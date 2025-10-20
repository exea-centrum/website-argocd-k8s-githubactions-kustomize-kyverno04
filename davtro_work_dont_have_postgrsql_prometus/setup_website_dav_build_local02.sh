#!/bin/bash

# ====================================================================
# Skrypt inicjalizacyjny GitOps dla davtrogr Website (CI/CD + ArgoCD)
# - GitHub Actions: Buduje obraz Docker, pushuje do GHCR i aktualizuje tag w Kustomize.
# - ArgoCD: Synchronizuje zaktualizowane manifesty z repozytorium GitHub i wdraża na MicroK8s.
# - Skrypt LOKALNY: Generuje strukturę plików, NIE BUDUJE LOKALNIE.
# ====================================================================

set -e # Przerwij w przypadku błędu

# --- 1. Konfiguracja i zmienne ---
# ZMIEŃ REPO_OWNER NA TWOJĄ NAZWĘ UŻYTKOWNIKA/ORGANIZACJI NA GITHUB!
REPO_OWNER="exea-centrum" 
REPO_NAME="website-argocd-k8s-githubactions-kustomize-kyverno04"
NAMESPACE="davtrogr"

IMAGE_REGISTRY_PATH="ghcr.io/${REPO_OWNER}/${REPO_NAME}"
IMAGE_TAG="latest" # Domyślny tag

echo "🚀 Rozpoczynam LOKALNE tworzenie struktury GitOps dla repozytorium na GitHub (CI/CD + ArgoCD)..."
echo "Używana przestrzeń nazw: ${NAMESPACE}"
echo "Docelowy obraz GHCR: ${IMAGE_REGISTRY_PATH}:${IMAGE_TAG}"

# --- 2. Funkcje pomocnicze ---
check_microk8s() {
    echo "🔍 Sprawdzanie statusu MicroK8s..."
    if ! command -v microk8s &> /dev/null; then
        echo "❌ BŁĄD: MicroK8s nie jest zainstalowany. Zainstaluj MicroK8s."
        exit 1
    fi

    if ! microk8s status | grep -q "running"; then
        echo "⚠️ MicroK8s nie jest uruchomione. Próbuję uruchomić (wymagane hasło sudo)..."
        sudo microk8s start
        microk8s status --wait-ready --timeout 60 || { echo "❌ BŁĄD: MicroK8s nie uruchomiło się poprawnie."; exit 1; }
    fi
    echo "✅ MicroK8s działa i jest gotowe."
}

# --- 3. Weryfikacja MicroK8s i dodatków ---
check_microk8s
echo "ℹ️  UWAGA: Musisz ręcznie aktywować dodatek ArgoCD: microk8s enable argocd"
echo "ℹ️  UWAGA: Nie aktywuję dodatków MicroK8s. Zakładam, że ingress, prometheus i grafana są już włączone."

# --- 4. Tworzenie lokalnej struktury katalogów (symulacja repo) ---
echo "📂 Tworzenie lokalnej struktury plików GitOps..."
APP_DIR="${REPO_NAME}"
rm -rf ${APP_DIR} # Wyczyść poprzednie wdrożenia
mkdir -p ${APP_DIR}/src \
         ${APP_DIR}/manifests/base \
         ${APP_DIR}/manifests/production \
         ${APP_DIR}/manifests/argocd \
         ${APP_DIR}/.github/workflows

# --- 5. Generowanie plików aplikacji Go z danymi ---
echo "📝 Generowanie aplikacji Go (src/main.go) i Dockerfile..."
# --- Dane symulujące zawartość strony Dawida Trojanowskiego ---
MOCKED_CONTENT=$(cat <<'EOF_DATA'
<h2>O Mnie</h2>
<p>Jestem entuzjastą DevOps, specjalizującym się w automatyzacji, konteneryzacji (Docker, Kubernetes) oraz CI/CD. To wdrożenie jest zarządzane przez ArgoCD, które synchronizuje manifesty z repozytorium GitHub.</p>
<h2>Technologie w Użyciu</h2>
<ul>
    <li><strong>Język Backend:</strong> GoLang (z metrykami Prometheus)</li>
    <li><strong>Orkiestracja:</strong> MicroK8s</li>
    <li><strong>Wdrożenie GitOps:</strong> ArgoCD (Synchronizacja) & GitHub Actions (Budowanie)</li>
    <li><strong>CI/CD:</strong> GitHub Actions (Build & Push do GHCR)</li>
    <li><strong>Baza Danych:</strong> PostgreSQL (w osobnym Deployment)</li>
</ul>
EOF_DATA
)

# Wprowadzenie MOCKED_CONTENT do pliku Go
cat <<EOF_GO > ${APP_DIR}/src/main.go
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

// Mock dla konfiguracji połączenia z bazą danych
const (
  DB_HOST = "postgres-service"
  DB_PORT = "5432"
  DB_USER = "appuser"
  DB_NAME = "davtrogrdb"
)

var (
  // Metryki Prometheus
  httpRequestsTotal = prometheus.NewCounterVec(
    prometheus.CounterOpts{Name: "http_requests_total", Help: "Liczba zapytań HTTP."},
    []string{"path", "method", "code"},
  )
  httpRequestDuration = prometheus.NewHistogramVec(
    prometheus.HistogramOpts{Name: "http_request_duration_seconds", Help: "Histogram czasu trwania zapytań HTTP."},
    []string{"path", "method"},
  )
  // Treść strony pobrana ze wskazanej witryny (zasymulowana)
  pageContent = \`${MOCKED_CONTENT}\`
)

func init() {
  prometheus.MustRegister(httpRequestsTotal)
  prometheus.MustRegister(httpRequestDuration)
}

func main() {
  log.SetFlags(log.Ldate | log.Ltime | log.Lshortfile)
  
  dbPassword := os.Getenv("DB_PASSWORD")
  log.Printf("Baza danych: host=%s, user=%s, hasło_status=%t", DB_HOST, DB_USER, dbPassword != "")
  // W tym miejscu w prawdziwej aplikacji nastąpiłoby połączenie z DB

  http.HandleFunc("/", loggingMiddleware(homeHandler))
  http.HandleFunc("/healthz", healthzHandler)
  http.Handle("/metrics", promhttp.Handler())

  port := os.Getenv("PORT")
  if port == "" {
    port = "8080"
  }

  log.Printf("Serwer nasłuchuje na :%s", port)
  if err := http.ListenAndServe(":"+port, nil); err != nil {
    log.Fatalf("Błąd uruchomienia serwera: %v", err)
  }
}

// Handler głównej strony z HTML/CSS i wstrzykniętą treścią
func homeHandler(w http.ResponseWriter, r *http.Request) {
  dbStatus := "Baza Danych: Osiągalna (postgres-service)"
  
  htmlContent := fmt.Sprintf(\`
<!DOCTYPE html>
<html lang="pl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>davtrogr Website - %s</title>
    <style>
        body { font-family: 'Arial', sans-serif; background-color: #f4f7f6; color: #333; margin: 0; padding: 40px; text-align: center; }
        .container { max-width: 800px; margin: 0 auto; background: #ffffff; padding: 30px; border-radius: 12px; box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1); text-align: left; }
        h1 { color: #0056b3; border-bottom: 3px solid #0056b3; padding-bottom: 10px; margin-bottom: 20px; text-align: center;}
        h2 { color: #007bff; margin-top: 25px; }
        ul { list-style-type: none; padding: 0; }
        li { margin-bottom: 10px; padding: 5px 0; border-bottom: 1px dashed #eee; }
        .status-box { margin-top: 30px; padding: 15px; background-color: #e6f7ff; border-left: 5px solid #007bff; font-size: 0.9em; text-align: left;}
        .status-ok { color: green; font-weight: bold; }
        .status-monitoring { color: orange; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Strona Dawida Trojanowskiego (Wdrożenie GitOps przez ArgoCD)</h1>
        %s
        <div class="status-box">
            <h2>Status Środowiska K8s</h2>
            <p><strong>Aplikacja Go:</strong> <span class="status-ok">Działa</span> (Metrics /metrics)</p>
            <p><strong>PostgreSQL Service:</strong> %s</p>
            <p><strong>Monitoring:</strong> <span class="status-monitoring">Prometheus/Grafana</span> jest aktywny w klastrze.</p>
        </div>
    </div>
</body>
</html>
\`, DB_NAME, pageContent, dbStatus)

  w.Header().Set("Content-Type", "text/html; charset=utf-8")
  w.WriteHeader(http.StatusOK)
  w.Write([]byte(htmlContent))
}

// --- Funkcje pomocnicze do monitoringu (Logging Middleware, Healthz, Wrapper) ---
type responseWriterWrapper struct { http.ResponseWriter; statusCode int }
func (lrw *responseWriterWrapper) WriteHeader(code int) { lrw.statusCode = code; lrw.ResponseWriter.WriteHeader(code) }
func loggingMiddleware(next http.HandlerFunc) http.HandlerFunc {
  return func(w http.ResponseWriter, r *http.Request) {
    start := time.Now()
    lw := &responseWriterWrapper{ResponseWriter: w}
    next(lw, r)
    duration := time.Since(start).Seconds()
    path := r.URL.Path
    method := r.Method
    statusCode := fmt.Sprintf("%d", lw.statusCode)
    log.Printf("Zapytanie: %s %s | Status: %s | Czas: %v", method, path, statusCode, duration)
    httpRequestsTotal.WithLabelValues(path, method, statusCode).Inc()
    httpRequestDuration.WithLabelValues(path, method).Observe(duration)
  }
}
func healthzHandler(w http.ResponseWriter, r *http.Request) {
  w.WriteHeader(http.StatusOK)
  w.Write([]byte("ok"))
}
EOF_GO

# Pliki Go i Dockerfile
cat <<EOF_MOD > ${APP_DIR}/go.mod
module ${REPO_OWNER}/${REPO_NAME}
go 1.21
require (
  github.com/prometheus/client_golang v1.17.0
)
EOF_MOD

cat <<EOF_DOCKER > ${APP_DIR}/Dockerfile
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
EOF_DOCKER
echo "✅ Aplikacja Go i pliki budowania wygenerowane."

# --- 6. Generowanie Manifestów Kustomize (Standardowe Wdrożenie) ---
echo "📝 Generowanie manifestów Kustomize (Standardowe Wdrożenie)..."

# Manifesty PostgreSQL (bez zmian)
cat <<EOF_PG_DEP > ${APP_DIR}/manifests/base/postgres-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres-deployment
  labels: { app: postgres }
spec:
  selector: { matchLabels: { app: postgres } }
  template:
    metadata: { labels: { app: postgres } }
    spec:
      containers:
      - name: postgres
        image: postgres:15-alpine
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_USER
          value: appuser
        - name: POSTGRES_DB
          value: davtrogrdb
        - name: POSTGRES_PASSWORD
          valueFrom: { secretKeyRef: { name: postgres-secret, key: password } }
        volumeMounts:
        - name: postgres-storage
          mountPath: /var/lib/postgresql/data
      volumes:
      - name: postgres-storage
        emptyDir: {}
EOF_PG_DEP

cat <<EOF_PG_SVC > ${APP_DIR}/manifests/base/postgres-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres-service
  labels: { app: postgres }
spec:
  type: ClusterIP
  selector: { app: postgres }
  ports:
  - port: 5432
    targetPort: 5432
EOF_PG_SVC

# Deployment z placeholderem do nadpisania przez GitHub Actions
cat <<EOF_WEB_DEP > ${APP_DIR}/manifests/base/website-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: davtrogr-website-deployment
  labels:
    app: davtrogr-website-app
spec:
  replicas: 2
  selector: { matchLabels: { app: davtrogr-website-app } }
  template:
    metadata: { labels: { app: davtrogr-website-app } }
    spec:
      serviceAccountName: default 
      imagePullSecrets:
      - name: regcred # Wymagany do pobierania z GHCR
      containers:
      - name: davtrogr-website-container
        # Placeholder obrazu, który zostanie zaktualizowany przez GitHub Actions
        image: ${IMAGE_REGISTRY_PATH}:latest 
        ports:
        - containerPort: 8080
        resources: { limits: { memory: "128Mi", cpu: "500m" } }
        env:
        - name: DB_PASSWORD
          valueFrom: { secretKeyRef: { name: postgres-secret, key: password } }
        livenessProbe: { httpGet: { path: /healthz, port: 8080 }, initialDelaySeconds: 5 }
        readinessProbe: { httpGet: { path: /healthz, port: 8080 }, initialDelaySeconds: 10 }
EOF_WEB_DEP

cat <<EOF_WEB_SVC > ${APP_DIR}/manifests/base/website-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: davtrogr-website-service
  labels:
    app: davtrogr-website-app
    release: prometheus-stack # Wymagane przez Prometheus Operator
spec:
  type: ClusterIP
  selector: { app: davtrogr-website-app }
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
    name: http
EOF_WEB_SVC

# Kustomization Base z definicją images do nadpisania
cat <<EOF_K_BASE > ${APP_DIR}/manifests/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- postgres-deployment.yaml
- postgres-service.yaml
- website-deployment.yaml
- website-service.yaml

secretGenerator:
- name: postgres-secret
  literals:
  - password=bardzotajnehaslo123 

# Definicja obrazu, która zostanie nadpisana przez GitHub Actions
images:
- name: ${IMAGE_REGISTRY_PATH}
  newTag: latest # Tag zostanie zaktualizowany przez CI/CD
EOF_K_BASE


# Manifesty Production (Ingress, ServiceMonitor)
cat <<EOF_NS > ${APP_DIR}/manifests/production/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
  labels: { logging-target: davtrogr }
EOF_NS

cat <<EOF_ING > ${APP_DIR}/manifests/production/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: davtrogr-website-ingress
  annotations:
    kubernetes.io/ingress.class: nginx 
spec:
  rules:
  - host: davtrogr.local.exea-centrum.pl 
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: davtrogr-website-service
            port: { number: 80 }
EOF_ING

cat <<EOF_SM > ${APP_DIR}/manifests/production/servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: davtrogr-website-monitor
  labels: { release: prometheus-stack }
spec:
  selector: { matchLabels: { app: davtrogr-website-app } }
  namespaceSelector: { matchNames: [ "${NAMESPACE}" ] }
  endpoints:
  - port: http 
    path: /metrics
    interval: 30s
EOF_SM

# Główny Kustomization Production - bez patchy
cat <<EOF_K_PROD > ${APP_DIR}/manifests/production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${NAMESPACE}

resources:
- ../base
- namespace.yaml
- ingress.yaml
- servicemonitor.yaml

namePrefix:
EOF_K_PROD
echo "✅ Manifesty Kustomize (standard) wygenerowane."

# --- 7. Generowanie pliku definicji ArgoCD Application ---
REPO_HTTPS_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}.git"

# Używam Twojej definicji ArgoCD Application (bez sekcji "retry", która była potrzebna tylko dla Kaniko)
cat <<EOF_ARGO_APP > ${APP_DIR}/manifests/argocd/davtrogr-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: davtrogr-website
  namespace: argocd 
  finalizers: ["resources-finalizer.argocd.argoproj.io"]
spec:
  project: default
  source:
    repoURL: ${REPO_HTTPS_URL}
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
      - ServerSideApply=true
EOF_ARGO_APP

cat <<EOF_K_ARGO > ${APP_DIR}/manifests/argocd/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- davtrogr-app.yaml
EOF_K_ARGO
echo "✅ Manifest ArgoCD Application wygenerowany. Wskaże na repo: ${REPO_HTTPS_URL}"


# --- 8. Tworzenie pliku GitHub Actions (CI/CD) ---
# Plik ci-cd.yaml jest tworzony na podstawie aktualnego pliku w immersive.
cat <<EOF_CI_CD > ${APP_DIR}/.github/workflows/ci-cd.yaml
name: CI/CD Build & Deploy (GitHub Actions)

on:
  push:
    branches:
      - main
    paths:
      - 'src/**'
      - 'Dockerfile'
      - 'go.mod'

# Uprawnienia kluczowe do pushowania do GHCR (packages: write)
# oraz do commitowania zmian w plikach Kustomize (contents: write)
permissions:
  contents: write 
  packages: write 
  
env:
  # Pełna ścieżka do obrazu (np. ghcr.io/exea-centrum/repo-name)
  IMAGE_REPOSITORY: ghcr.io/\${{ github.repository }}
  # Ścieżka do katalogu Kustomize, który zawiera kustomization.yaml do edycji
  KUSTOMIZE_PATH: manifests/production
  # Stała nazwa obrazu używana jako PLACEHOLDER w manifests/base/website-deployment.yaml
  KUSTOMIZE_IMAGE_NAME: website-argocd-k8s-githubactions-kustomize-kyverno04
  # Stały tag 'latest'
  STABLE_TAG: latest

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4
      
      # Logowanie do GitHub Container Registry
      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: \${{ github.actor }}
          password: \${{ secrets.GITHUB_TOKEN }}
          
      # Ustalanie TAGu na podstawie SHA commitu (pierwsze 7 znaków)
      - name: Set Image Tag
        id: set_tag
        run: echo "TAG=\$(echo \${{ github.sha }} | head -c 7)" >> \$GITHUB_OUTPUT

      # Budowanie i push obrazu
      - name: Build and Push Docker Image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          # Tagujemy dwoma tagami: commit-sha i latest
          tags: |
            \${{ env.IMAGE_REPOSITORY }}:\${{ steps.set_tag.outputs.TAG }}
            \${{ env.IMAGE_REPOSITORY }}:\${{ env.STABLE_TAG }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
          
      # Aktualizacja taga w pliku Kustomize (dla ArgoCD)
      - name: Update Image Tag in Kustomize
        id: kustomize_update
        # Instalacja kustomize
        run: |
          curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"  | bash
          sudo mv kustomize /usr/local/bin/
          
          # Aktualizujemy obraz w głównym pliku kustomization.yaml (production)
          kustomize edit set image \\
            \${{ env.KUSTOMIZE_IMAGE_NAME }}:\${{ env.STABLE_TAG }}=\\
            \${{ env.IMAGE_REPOSITORY }}:\${{ steps.set_tag.outputs.TAG }} \\
            --kustomization \${{ env.KUSTOMIZE_PATH }}
            
          cat \${{ env.KUSTOMIZE_PATH }}/kustomization.yaml # Weryfikacja

      # Commit i Push zaktualizowanego pliku Kustomize
      - name: Commit and Push Kustomize Update
        uses: EndBug/add-and-commit@v9
        with:
          author_name: github-actions[bot]
          author_email: 41898282+github-actions[bot]@users.noreply.github.com
          message: "GitOps: Update image tag to \${{ steps.set_tag.outputs.TAG }}"
          add: '\${{ env.KUSTOMIZE_PATH }}/kustomization.yaml'
EOF_CI_CD
echo "✅ Plik GitHub Actions (CI/CD) wygenerowany."


# --- 9. Wdrożenie Application ArgoCD ---
echo "💾 Wdrożenie pliku ArgoCD Application na MicroK8s..."
microk8s kubectl apply -k ${APP_DIR}/manifests/argocd
echo "✅ Definicja ArgoCD Application wdrożona."

# --- 10. Instrukcje końcowe ---
echo "================================================================"
echo "                   Proces Inicjalizacji GitOps (CI/CD + ArgoCD) Zakończony!"
echo "================================================================="
echo "!!! KROK 1: KRYTYCZNE! Utwórz Secret 'regcred' (dla GHCR) w przestrzeni nazw ${NAMESPACE}."
echo "   Deployment potrzebuje tego sekreta do pobrania obrazu z GHCR."
echo "   Sekret MUSI zawierać dane logowania do GHCR (GitHub Container Registry)."
echo "   Komenda: microk8s kubectl create secret docker-registry regcred \\"
echo "     --docker-server=https://ghcr.io \\"
echo "     --docker-username=${REPO_OWNER} \\"
echo "     --docker-password='<Twój_PAT_Token>' -n ${NAMESPACE}"
echo "   UWAGA: Token PAT musi mieć uprawnienie 'read:packages'!"
echo ""
echo "!!! KROK 2: Utwórz repozytorium na GitHub i wyślij pliki:"
echo "   cd ${APP_DIR}"
echo "   git init"
echo "   git add ."
echo "   git commit -m 'Initial commit of CI/CD GitOps structure'"
echo "   git remote add origin https://github.com/${REPO_OWNER}/${REPO_NAME}.git"
echo "   git push -u origin main"
echo ""
echo "!!! KROK 3: W GitHub, w sekcji Settings -> Actions -> General -> Workflow Permissions, upewnij się, że 'Read and write permissions' jest włączone."
echo "   Jest to krytyczne, aby GitHub Actions mógł zacommitować zaktualizowany plik kustomization.yaml z nowym tagiem obrazu."
echo ""
echo "➡️  Przepływ: PUSH -> GitHub Action buduje i pushuje do GHCR -> GitHub Action aktualizuje tag w Kustomize -> ArgoCD widzi zmianę i synchronizuje Deployment."
echo "================================================================"
