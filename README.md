# 🚀 Davtro Website - ArgoCD + K8s + GitHub Actions

## 📋 Opis projektu zakładam żę masz k8s i w nim ArgoCD jak coś to masz w inych moich repo gotowce z jak w 3 ruchach zainstalować k8s i ArgoCD

Kompletne rozwiązanie strony internetowej z pełnym stackiem technologicznym:

- **Frontend**: Go + HTML/CSS
- **Backend**: Go + PostgreSQL
- **CI/CD**: GitHub Actions + GHCR
- **Deployment**: ArgoCD + Kustomize
- **Orchestration**: Kubernetes (MicroK8s)

## 🏗️ Architektura

```
GitHub Repository → GitHub Actions → GHCR.io → ArgoCD → MicroK8s → Website
```

## 🚀 Szybki start

### 1. Inicjalizacja

```bash
git clone https://github.com/exea-centrum/website-argocd-k8s-githubactions-kustomize-kyverno04.git
cd website-argocd-k8s-githubactions-kustomize-kyverno03
```

### 2. Deploy ArgoCD Application

```bash
kubectl apply -f argocd/application.yaml


albo add new w ArgoCD w UI edit yaml i wklej i ciesz się że argocd pobrał i wszystko ci ogarneło:


apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: website
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/exea-centrum/website-argocd-k8s-githubactions-kustomize-kyverno04.git
    targetRevision: main
    path: manifests/production
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
# to opcjonalnie     - CreateNamespace=true


```

## 📊 Endpoints

- 🌐 **Website**: http://website-argocd-k8s-githubactions-kustomize-kyverno04.local
- 📡 **API**: /api/data

- 🎯 **ArgoCD**: http://argocd.local

## 🔧 Konfiguracja

### Zmienne środowiskowe

```
DB_HOST=postgres-service
DB_PORT=5432
DB_USER=davtro
DB_PASSWORD=password123
DB_NAME=davtro_db
PORT=8080
```

## 📈 Monitoring

- Prometheus metrics dostępne pod /metrics
- ServiceMonitor dla Prometheus
- Health checks i readiness probes
- Resource limits i requests

## 🛡️ Bezpieczeństwo

- Kyverno policies dla compliance
- Resource limits
- Readiness/liveness probes
- TLS via cert-manager
