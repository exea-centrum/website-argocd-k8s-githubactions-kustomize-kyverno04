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
