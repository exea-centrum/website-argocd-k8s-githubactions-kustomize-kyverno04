# website-argocd-k8s-githubactions-kustomize-kyverno04
website-argocd-k8s-githubactions-kustomize-kyverno04
kompletne „starter” repo + manifesty + CI/CD + ArgoCD Application + przykładową aplikację w Go, tak żebyś mógł od razu wrzucić to do GitHub (repo: exea-centrum/website-argocd-k8s-githubactions-kustomize-kyverno03) i ArgoCD (na Twoim microk8s). Dostosowałem wszystko do Twoich wymagań:
obraz budowany przez GitHub Actions i pushowany do GHCR (ghcr.io/<GH_OWNER>/<IMAGE>),


ArgoCD ma wskazywać na repo + ścieżkę Kustomize ./manifests/production,


namespace aplikacji: davtro,


Kustomize image id: website-argocd-k8s-githubactions-kustomize-kyverno03 (użyty w przykładach),


użyte technologie: Go (serwis www), Postgres (DB), Kustomize, Kyverno (przykładowa polityka), ArgoCD (Application manifest), GitHub Actions (build+push+kustomize image update), Terraform (przykładowy terraform main do tworzenia namespace i opcjonalnego ArgoCD app registration),


monitoring: przykładowe manifesty/ wskazówki wdrożenia Prometheus / Grafana / Loki / Tempo (starter manifests + ServiceMonitors / Grafana datasource ConfigMap).


Poniżej znajdziesz strukturę repo i najważniejsze pliki — full copy/paste, gotowe do wrzucenia. Robię to po polsku i trzymam się konkretnych plików, żebyś mógł wkleić je do repo.

Struktura repo (proponowana)
website-argocd-k8s-githubactions-kustomize-kyverno03/
├── README.md
├── src/
│   ├── go.mod
│   └── main.go
├── Dockerfile
├── .github/
│   └── workflows/
│       └── ci.yml
├── manifests/
│   ├── base/
│   │   ├── kustomization.yaml
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── ingress.yaml
│   │   ├── configmap-sitecontent.yaml
│   │   ├── postgres-deployment.yaml
│   │   └── postgres-pvc.yaml
│   └── production/
│       └── kustomization.yaml
├── argocd/
│   └── application.yaml
├── kyverno/
│   └── disallow-latest-tag.yaml
└── terraform/
    ├── main.tf
    └── variables.tf


1) Aplikacja Go (pobiera zawartość z Twojej strony Google Sites i serwuje prostą stronę)
Plik: src/main.go
package main

import (
	"context"
	"fmt"
	"html/template"
	"io"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/PuerkitoBio/goquery"
)

var tpl = template.Must(template.New("index").Parse(`
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Dawid Trojanowski — mirror</title>
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <style>
    body{font-family:Inter, system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial;max-width:900px;margin:2rem auto;padding:1rem;}
    header{border-bottom:1px solid #eee;padding-bottom:1rem;margin-bottom:1rem;}
    h1{font-size:1.6rem}
    .content{white-space:pre-wrap;}
    footer{margin-top:3rem;color:#666;font-size:0.9rem}
  </style>
</head>
<body>
  <header>
    <h1>Dawid Trojanowski — mirror</h1>
    <p>Źródło: <a href="{{.SourceURL}}" target="_blank">{{.SourceURL}}</a></p>
  </header>
  <main class="content">{{.Content}}</main>

  <footer>
    <p>Funkcja aktualizacji: <strong>{{.LastFetch}}</strong></p>
  </footer>
</body>
</html>
`))

type Page struct {
	SourceURL string
	Content   string
	LastFetch string
}

func fetchSite(ctx context.Context, url string) (string, error) {
	// proste pobranie i wyciągnięcie tekstu głównego kontentu
	req, _ := http.NewRequestWithContext(ctx, "GET", url, nil)
	req.Header.Set("User-Agent", "davtro-mirror/1.0")
	client := &http.Client{Timeout: 15 * time.Second}
	res, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer res.Body.Close()
	if res.StatusCode != 200 {
		bodyBytes, _ := io.ReadAll(io.LimitReader(res.Body, 2048))
		return "", fmt.Errorf("status %d: %s", res.StatusCode, string(bodyBytes))
	}

	doc, err := goquery.NewDocumentFromReader(res.Body)
	if err != nil {
		return "", err
	}

	// heurystyka: w Google Sites główny content często w elementach <main> lub .sites-viewport
	var text string
	if sel := doc.Find("main"); sel.Length() > 0 {
		text = sel.Text()
	} else if sel := doc.Find(".sites-viewport"); sel.Length() > 0 {
		text = sel.Text()
	} else {
		// fallback: całe body
		text = doc.Find("body").Text()
	}
	return text, nil
}

func handler(w http.ResponseWriter, r *http.Request) {
	source := os.Getenv("SOURCE_URL")
	if source == "" {
		source = "https://sites.google.com/view/dawidtrojanowski/dawid?authuser=0"
	}
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()
	content, err := fetchSite(ctx, source)
	last := time.Now().Format(time.RFC3339)
	if err != nil {
		log.Printf("fetch error: %v", err)
		content = fmt.Sprintf("Błąd pobierania strony źródłowej: %v", err)
	}
	page := Page{SourceURL: source, Content: content, LastFetch: last}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := tpl.Execute(w, page); err != nil {
		log.Printf("template execute: %v", err)
	}
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	http.HandleFunc("/", handler)
	log.Printf("Starting server on :%s", port)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}

Plik: src/go.mod
module davtro.site

go 1.21

require (
    github.com/PuerkitoBio/goquery v1.8.0
)

Uwaga: w production możesz chcieć dodać caching (Redis/PG), rate limit, error handling, i auth.

2) Dockerfile
Plik: Dockerfile
# build
FROM golang:1.21-alpine AS builder
RUN apk add --no-cache git build-base
WORKDIR /src
COPY src/go.mod src/go.sum ./
RUN go mod download
COPY src/ .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /app ./main.go

# final
FROM busybox:1.36
COPY --from=builder /app /app
EXPOSE 8080
ENV PORT=8080
ENTRYPOINT ["/app"]


3) GitHub Actions — build + push do GHCR i opcjonalnie commit aktualizacji kustomize image (tag)
Plik: .github/workflows/ci.yml
name: CI - Build & Push to GHCR

on:
  push:
    branches: [ main, master ]
  workflow_dispatch:

env:
  IMAGE_NAME: ghcr.io/${{ github.repository_owner }}/${{ env.KUSTOMIZE_IMAGE_ID }}
  KUSTOMIZE_IMAGE_ID: website-argocd-k8s-githubactions-kustomize-kyverno03
  KUSTOMIZE_PATH: ./manifests/production

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v2

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2

      - name: Login to GHCR
        uses: docker/login-action@v2
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GHCR_PAT }}

      - name: Build and push
        uses: docker/build-push-action@v4
        with:
          context: .
          file: ./Dockerfile
          push: true
          tags: |
            ghcr.io/${{ github.repository_owner }}/website-argocd-k8s-githubactions-kustomize-kyverno03:latest
            ghcr.io/${{ github.repository_owner }}/website-argocd-k8s-githubactions-kustomize-kyverno03:${{ github.sha }}

      - name: Optionally update kustomize image (commit)
        if: github.ref == 'refs/heads/main'
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "actions@github.com"
          yq eval -i '.images[0].newTag = "'${{ github.sha }}'"' ${KUSTOMIZE_PATH}/kustomization.yaml || true
          git add ${KUSTOMIZE_PATH}/kustomization.yaml || true
          git commit -m "chore: update image tag to ${{ github.sha }}" || echo "no changes"
          git push origin HEAD:main || echo "push failed"
        env:
          KUSTOMIZE_PATH: ./manifests/production

Sekrety GitHub repo: ustaw GHCR_PAT (personal access token z write:packages, delete:packages), oraz opcjonalnie TF_API_TOKEN do terraform cloud.

4) Kustomize — base i production
Plik: manifests/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml
  - ingress.yaml
  - configmap-sitecontent.yaml
  - postgres-deployment.yaml
  - postgres-pvc.yaml

images:
  - name: website-argocd-k8s-githubactions-kustomize-kyverno03
    newName: ghcr.io/REPLACE_OWNER/website-argocd-k8s-githubactions-kustomize-kyverno03
    newTag: latest

Plik: manifests/base/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: davtro-website
  labels:
    app: davtro-website
spec:
  replicas: 1
  selector:
    matchLabels:
      app: davtro-website
  template:
    metadata:
      labels:
        app: davtro-website
    spec:
      containers:
        - name: davtro-website
          image: ghcr.io/REPLACE_OWNER/website-argocd-k8s-githubactions-kustomize-kyverno03:latest
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 8080
          env:
            - name: SOURCE_URL
              value: "https://sites.google.com/view/dawidtrojanowski/dawid?authuser=0"
            - name: PORT
              value: "8080"
          readinessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 15
            periodSeconds: 20

Plik: manifests/base/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: davtro-website
spec:
  type: ClusterIP
  selector:
    app: davtro-website
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
      name: http

Plik: manifests/base/ingress.yaml (przykład dla nginx ingress / microk8s traefik — dopasuj)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: davtro-website
  annotations:
    kubernetes.io/ingress.class: "nginx"
spec:
  rules:
    - host: davtro.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: davtro-website
                port:
                  number: 80

Plik: manifests/base/configmap-sitecontent.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: davtro-site-config
data:
  SOURCE_URL: "https://sites.google.com/view/dawidtrojanowski/dawid?authuser=0"

Plik: manifests/base/postgres-deployment.yaml (prostyy PG)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: davtro-postgres
  labels:
    app: davtro-postgres
spec:
  replicas: 1
  selector:
    matchLabels:
      app: davtro-postgres
  template:
    metadata:
      labels:
        app: davtro-postgres
    spec:
      containers:
        - name: postgres
          image: postgres:15
          env:
            - name: POSTGRES_DB
              value: davtro
            - name: POSTGRES_USER
              value: davtro
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: davtro-postgres-secret
                  key: password
          ports:
            - containerPort: 5432
          volumeMounts:
            - mountPath: /var/lib/postgresql/data
              name: postgres-data
      volumes:
        - name: postgres-data
          persistentVolumeClaim:
            claimName: davtro-postgres-pvc

Plik: manifests/base/postgres-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: davtro-postgres-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi

Plik: manifests/production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../base

namespace: davtro

images:
  - name: website-argocd-k8s-githubactions-kustomize-kyverno03
    newName: ghcr.io/REPLACE_OWNER/website-argocd-k8s-githubactions-kustomize-kyverno03
    newTag: latest

Ważne: zamień REPLACE_OWNER na właściciela GHCR (np. exea-centrum albo Twój GH user/org).

5) ArgoCD Application manifest
Plik: argocd/application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: davtro-website-app
  namespace: argocd
spec:
  destination:
    namespace: davtro
    server: https://kubernetes.default.svc
  project: default
  source:
    repoURL: 'https://github.com/exea-centrum/website-argocd-k8s-githubactions-kustomize-kyverno03.git'
    targetRevision: main
    path: ./manifests/production
    plugin: {}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true

Po wdrożeniu powyższego Application ArgoCD pobierze zasoby z ./manifests/production i utworzy namespace davtro + resources.

6) Kyverno policy (przykład — blokuj obrazy z tagiem latest)
Plik: kyverno/disallow-latest-tag.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-latest-image-tag
spec:
  validationFailureAction: enforce
  rules:
  - name: check-no-latest
    match:
      resources:
        kinds:
        - Pod
        - Deployment
        - DaemonSet
        - StatefulSet
    validate:
      message: "Using image tag 'latest' is disallowed. Use a specific digest or tag."
      pattern:
        spec:
          containers:
          - image: "!*:latest"


7) Monitoring — wskazówki + przykładowe ServiceMonitor / Grafana datasource
Pełny zestaw Prometheus/Grafana/Loki/Tempo to duże helm charts. Poniżej krótkie pliki startowe i wskazówki, które możesz wkleić do repo i deployować w namespace observability lub monitoring.
A) Prometheus (szybki sposób)
Zalecam użyć kube-prometheus-stack (Helm chart od prometheus-community). Na microk8s możesz zainstalować helm i uruchomić:
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack -n monitoring --create-namespace

B) Loki + Tempo + Grafana
Grafana chart ma opcję instalacji loki datasource lub zainstaluj:
helm install loki grafana/loki-stack -n monitoring
helm install tempo grafana/tempo -n monitoring
helm upgrade --install grafana grafana/grafana -n monitoring

C) ServiceMonitor dla aplikacji (przykład)
Plik: manifests/base/servicemonitor-app.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: davtro-website-sm
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app: davtro-website
  namespaceSelector:
    matchNames:
      - davtro
  endpoints:
    - port: http
      interval: 30s
      path: /

D) Grafana datasource (ConfigMap) — przykład
Plik: manifests/base/grafana-datasource.yaml
apiVersion: 1
kind: ConfigMap
metadata:
  name: grafana-datasources
  labels:
    grafana_datasource: "1"
data:
  prometheus.yaml: |
    apiVersion: 1
    deleteDatasources:
    - name: Prometheus
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus-operated.monitoring.svc.cluster.local:9090
      access: proxy
      isDefault: true

Te pliki wklej do manifests/base jeśli masz zainstalowany Prometheus Operator — w przeciwnym razie użyj Helm do szybszej instalacji.

8) Terraform — przykład do utworzenia namespace + opcjonalnego ArgoCD Application (Terraform Cloud workspace)
Plik: terraform/main.tf
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.19"
    }
  }
  backend "remote" {
    hostname = "app.terraform.io"
    organization = "davtro"
    workspaces {
      name = "github-actions-terraform"
    }
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

resource "kubernetes_namespace" "davtro" {
  metadata {
    name = "davtro"
  }
}

# Opcjonalnie: utworzenie ArgoCD Application (jeśli argocd CRD jest dostępny w clusterze)
resource "kubernetes_manifest" "argocd_app" {
  manifest = yamldecode(file("${path.module}/../argocd/application.yaml"))
  depends_on = [kubernetes_namespace.davtro]
}

Plik: terraform/variables.tf
variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/config"
}

Ustaw w Terraform Cloud workspace odpowiedni token i kubeconfig (lub użyj GitHub Actions z TF_API_TOKEN + runner z dostępem do clustra).

9) README.md — instrukcje szybkiego uruchomienia
Plik: README.md (skrót)
# Davtro Website — ArgoCD + GHCR + Kustomize starter

## Co robi repo
- Aplikacja Go pobiera treść z: https://sites.google.com/view/dawidtrojanowski/dawid?authuser=0 i serwuje prostą stronę
- Build & push do GHCR przez GitHub Actions
- Kustomize manifesty w `manifests/production`
- ArgoCD Application w `argocd/application.yaml` (namespace `davtro`)
- Kyverno policy przykładowa
- Monitoring: ServiceMonitor + grafana datasource (instrukcje użycia Helm)

## Kroki
1. Skonfiguruj repo w GitHub: `exea-centrum/website-argocd-k8s-githubactions-kustomize-kyverno03`
2. Ustaw secret `GHCR_PAT` w repo (personal token z `write:packages`)
3. Zamień `REPLACE_OWNER` w `manifests/*/kustomization.yaml` na `exea-centrum` lub swój właściciel GHCR
4. Push kodu (branch main)
5. GH Actions zbuduje i opublikuje image do GHCR
6. W ArgoCD: zaaplikuj `argocd/application.yaml` (możesz użyć `kubectl apply -f argocd/application.yaml -n argocd`)
7. ArgoCD zdeployuje zasoby do namespace `davtro`
8. Zainstaluj monitoring przez Helm:
   - `helm install monitoring prometheus-community/kube-prometheus-stack -n monitoring --create-namespace`
   - `helm repo add grafana https://grafana.github.io/helm-charts && helm repo update`
   - `helm install loki grafana/loki-stack -n monitoring`


10) Dodatkowe wskazówki / uwagi operacyjne
Zamień REPLACE_OWNER w kustomization.yaml na właściwy owner GHCR (exea-centrum lub Twój account).


Secrets:


Utwórz davtro-postgres-secret z kluczem password, jeśli deployujesz Postgresa.


Ingress: dopasuj ingress.class do Twojego microk8s (microk8s zwykle używa traefik lub zainstalowanego nginx).


ArgoCD: masz już zainstalowane ArgoCD na microk8s — po zaaplikowaniu argocd/application.yaml ArgoCD zacznie synchronizować.


GHCR rate limits: upewnij się, że GHCR token ma odpowiednie scope.


Monitoring: rekomenduję użycie Helm charts, bo ręczne manifesty Prometheus/Grafana/Loki/Tempo są duże i łatwiej je utrzymywać przez Helm.
