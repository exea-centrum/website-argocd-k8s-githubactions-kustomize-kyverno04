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
