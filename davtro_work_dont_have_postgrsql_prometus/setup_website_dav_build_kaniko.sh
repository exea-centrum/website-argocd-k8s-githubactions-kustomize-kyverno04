#!/bin/bash

# ====================================================================
# Skrypt inicjalizacyjny GitOps dla davtrogr Website (ArgoCD + Kaniko Build)
# - KANIKO: Używany do budowania obrazu DOCKER wewnątrz klastra K8s (poprzez Job).
# - ArgoCD: Synchronizuje Job Kaniko oraz Deploymenty.
# - Wymaga: Zainstalowanego MicroK8s z dodatkiem ArgoCD.
# ====================================================================

set -e # Przerwij w przypadku błędu

# --- 1. Konfiguracja i zmienne ---
# Zmień REPO_OWNER na Twoją nazwę użytkownika/organizacji na GitHub!
REPO_OWNER="exea-centrum" 
REPO_NAME="website-argocd-k8s-githubactions-kustomize-kyverno04"
NAMESPACE="davtrogr"

# Pamiętaj: Kaniko musi gdzieś PUSHOWAĆ obraz, aby Deployment mógł go pobrać.
# Upewnij się, że ten obraz jest dostępny na GHCR.
IMAGE_REGISTRY_PATH="ghcr.io/${REPO_OWNER}/${REPO_NAME}"
IMAGE_TAG="latest" # Kaniko zawsze nadpisuje ten tag po pomyślnym zbudowaniu

echo "🚀 Rozpoczynam LOKALNE tworzenie struktury GitOps dla repozytorium na GitHub (Kaniko Build)..."
echo "Używana przestrzeń nazw: ${NAMESPACE}"
echo "Docelowy obraz GHCR (zmień właściciela!): ${IMAGE_REGISTRY_PATH}:${IMAGE_TAG}"

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
         ${APP_DIR}/.github/workflows # Zostawiam dla przyszłych rozszerzeń

# --- 5. Generowanie plików aplikacji Go z danymi (BEZ ZMIAN W TREŚCI) ---
echo "📝 Generowanie aplikacji Go (src/main.go) z danymi davtrogr Website..."
# --- Dane symulujące zawartość strony Dawida Trojanowskiego ---
MOCKED_CONTENT=$(cat <<'EOF_DATA'
<h2>O Mnie</h2>
<p>Jestem entuzjastą DevOps, specjalizującym się w automatyzacji, konteneryzacji (Docker, Kubernetes) oraz CI/CD. To wdrożenie jest zarządzane przez ArgoCD, które synchronizuje manifesty z repozytorium GitHub.</p>
<h2>Technologie w Użyciu</h2>
<ul>
    <li><strong>Język Backend:</strong> GoLang (z metrykami Prometheus)</li>
    <li><strong>Orkiestracja:</strong> MicroK8s</li>
    <li><strong>Wdrożenie GitOps:</strong> ArgoCD & Kaniko (budowanie obrazu w klastrze)</li>
    <li><strong>CI/CD:</strong> Kube Native (Kaniko Job)</li>
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

# --- Funkcje pomocnicze do monitoringu (Logging Middleware, Healthz, Wrapper) ---
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

# --- 6. Generowanie Manifestów Kustomize (Kaniko Job i Deployment) ---
echo "📝 Generowanie manifestów Kustomize (Kaniko Build Integration)..."

# Nowy plik Job Kaniko w /base
cat <<EOF_KANIKO_JOB > ${APP_DIR}/manifests/base/kaniko-build-job.yaml
# UWAGA: Ten Job musi być uruchamiany RĘCZNIE lub przez zaawansowany wzorzec w ArgoCD
# (np. ApplicationSet z generatorami). Tutaj generujemy go jako zwykły Job do celów
# demonstracyjnych, który może być synchronizowany i uruchamiany przez ArgoCD.
#
# Wymaga sekretu 'regcred' (Docker Registry Credentials) w tej samej przestrzeni nazw!

apiVersion: batch/v1
kind: Job
metadata:
  name: kaniko-image-build
  labels: { app: davtrogr-website-build }
spec:
  template:
    spec:
      # Kaniko wymaga uprawnień roota (securityContext)
      serviceAccountName: default 
      restartPolicy: OnFailure
      containers:
      - name: kaniko
        image: gcr.io/kaniko-project/executor:latest
        args:
        - "--context=git://github.com/${REPO_OWNER}/${REPO_NAME}.git#${IMAGE_TAG}" # Używa brancha 'latest' lub 'HEAD'
        - "--destination=${IMAGE_REGISTRY_PATH}:${IMAGE_TAG}"
        - "--dockerfile=Dockerfile"
        # Argumenty Kaniko dla uwierzytelnienia (używamy kubelet's credentials)
        - "--cache=true"
        - "--single-snapshot"
        env:
        # Ten sekret musi istnieć! Użyje go Kaniko do pushowania.
        - name: DOCKER_CONFIG
          value: /kaniko/.docker
        volumeMounts:
        - name: docker-config
          mountPath: /kaniko/.docker
      volumes:
      - name: docker-config
        projected:
          sources:
          - secret:
              name: regcred # Standardowa nazwa sekreta dla pobierania obrazów, musi zawierać dane logowania do GHCR!
              items:
                - key: .dockerconfigjson
                  path: config.json

  # Ogranicznik, aby Job nie działał wiecznie
  backoffLimit: 3
EOF_KANIKO_JOB


# Wymagany Service Account dla Kaniko (potrzebuje uprawnień do tworzenia secret'ów lub wdrożenia)
cat <<EOF_SA > ${APP_DIR}/manifests/base/kaniko-sa.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kaniko-builder-sa
  labels: { app: davtrogr-website-build }
EOF_SA

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

# Zmieniony Deployment - Używa obrazu z GHCR (zbudowanego przez Kaniko)
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
      # ServiceAccount Name potrzebne do pobrania obrazu z GHCR,
      # jeśli regcred jest dołączony do tego SA.
      serviceAccountName: default 
      imagePullSecrets:
      - name: regcred # Wymagany do pobierania z GHCR
      containers:
      - name: davtrogr-website-container
        image: ${IMAGE_REGISTRY_PATH}:${IMAGE_TAG} # Używa obrazu zbudowanego przez Kaniko!
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

cat <<EOF_K_BASE > ${APP_DIR}/manifests/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- kaniko-build-job.yaml # Dodano Job Kaniko
- kaniko-sa.yaml        # Dodano Service Account (opcjonalnie)
- postgres-deployment.yaml
- postgres-service.yaml
- website-deployment.yaml
- website-service.yaml

secretGenerator:
- name: postgres-secret
  literals:
  - password=bardzotajnehaslo123 
  
# UWAGA: Kaniko Job musi być usunięty przed wdrożeniem, ponieważ nie jest
# komponentem trwałym. Dodamy tu adnotację ArgoCD do pominięcia.
# W kustomization.yaml Production dodamy adnotację:
# argocd.argoproj.io/sync-wave: "-1" dla Job'a, aby wykonał się pierwszy.
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

# Główny Kustomization Production - Nadpisanie Deploymentów i dodanie adnotacji SyncWave
cat <<EOF_K_PROD > ${APP_DIR}/manifests/production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${NAMESPACE}

resources:
- ../base
- namespace.yaml
- ingress.yaml
- servicemonitor.yaml

# Adnotacje dla Kaniko Job:
# 1. Sync Wave -1 (wykonaj Job przed Deploymentem)
# 2. Hook do usunięcia Job'a po sukcesie (w ArgoCD)
patches:
- patch: |-
    - op: add
      path: /metadata/annotations
      value:
        argocd.argoproj.io/sync-wave: "-1"
        argocd.argoproj.io/hook: PostSync
        argocd.argoproj.io/hook-delete-policy: HookSucceeded
  target:
    kind: Job
    name: kaniko-image-build

namePrefix:
EOF_K_PROD
echo "✅ Manifesty Kustomize (z Kaniko Job) wygenerowane."

# --- 7. Generowanie pliku definicji ArgoCD Application ---
REPO_HTTPS_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}.git"

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
    repoURL: ${REPO_HTTPS_URL} # Pamiętaj o zmianie właściciela na Twój!
    targetRevision: HEAD
    path: manifests/production # Ścieżka do głównego kustomization.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: ${NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    # Kaniko potrzebuje tego, aby ArgoCD wiedziało, że Deployment
    # może być niedostępny (np. obraz jeszcze nie istnieje)
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true # Użyteczne dla kustomize i patches
EOF_ARGO_APP

cat <<EOF_K_ARGO > ${APP_DIR}/manifests/argocd/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- davtrogr-app.yaml
EOF_K_ARGO
echo "✅ Manifest ArgoCD Application wygenerowany. Wskaże na repo: ${REPO_HTTPS_URL}"

# --- 8. Usunięcie niepotrzebnego pliku GitHub Actions ---
rm -rf ${APP_DIR}/.github/workflows/ci-cd.yaml
echo "🗑️ Usunięto plik GitHub Actions (budowanie przeniesione do Kaniko)."

# --- 9. Wdrożenie Application ArgoCD ---
echo "💾 Wdrożenie pliku ArgoCD Application na MicroK8s..."
microk8s kubectl apply -k ${APP_DIR}/manifests/argocd
echo "✅ Definicja ArgoCD Application wdrożona."

# --- 10. Instrukcje końcowe ---
echo "================================================================"
echo "                   Proces Inicjalizacji GitOps (Kaniko) Zakończony!"
echo "================================================================="
echo "!!! KROK 1: KRYTYCZNE! Utwórz Secret 'regcred' (dla GHCR) w przestrzeni nazw ${NAMESPACE}."
echo "   Kaniko (budowanie) i Deployment (pobieranie) potrzebują tego sekreta."
echo "   Sekret MUSI zawierać dane logowania do GHCR (GitHub Container Registry)."
echo "   Przykładowo, użyj tokenu PAT (Personal Access Token) z uprawnieniami 'write:packages'."
echo "   Komenda: microk8s kubectl create secret docker-registry regcred \\"
echo "     --docker-server=https://ghcr.io \\"
echo "     --docker-username=${REPO_OWNER} \\"
echo "     --docker-password='<Twój_PAT_Token>' -n ${NAMESPACE}"
echo ""
echo "!!! KROK 2: Utwórz repozytorium na GitHub i wyślij pliki:"
echo "   cd ${APP_DIR}"
echo "   git init"
echo "   git add ."
echo "   git commit -m 'Initial commit of Kaniko GitOps structure'"
echo "   git remote add origin https://github.com/${REPO_OWNER}/${REPO_NAME}.git"
echo "   git push -u origin main"
echo ""
echo "!!! KROK 3: Upewnij się, że ArgoCD jest włączone i sprawdź status:"
echo "   microk8s enable argocd"
echo "   microk8s kubectl get app -n argocd"
echo ""
echo "➡️  ArgoCD najpierw uruchomi Job Kaniko (Sync Wave -1), który zbuduje i zepchnie obraz do GHCR, a następnie wdroży Deployment (Sync Wave 0), który pobierze ten obraz."
echo "================================================================"
