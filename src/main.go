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

const (
	DB_HOST = "postgres-service"
	DB_PORT = "5432"
	DB_USER = "appuser"
	DB_NAME = "davtrogrdb"
)

var (
	httpRequestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{Name: "http_requests_total", Help: "Liczba zapytań HTTP."},
		[]string{"path", "method", "code"},
	)
	httpRequestDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{Name: "http_request_duration_seconds", Help: "Czas trwania zapytań HTTP."},
		[]string{"path", "method"},
	)
)

func init() {
	prometheus.MustRegister(httpRequestsTotal)
	prometheus.MustRegister(httpRequestDuration)
}

func main() {
	log.SetFlags(log.Ldate | log.Ltime | log.Lshortfile)
	dbPassword := os.Getenv("DB_PASSWORD")
	log.Printf("DB host=%s, user=%s, password_set=%t", DB_HOST, DB_USER, dbPassword != "")

	http.HandleFunc("/", loggingMiddleware(homeHandler))
	http.HandleFunc("/healthz", healthzHandler)
	http.Handle("/metrics", promhttp.Handler())

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Printf("Serwer działa na porcie :%s", port)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}

func homeHandler(w http.ResponseWriter, r *http.Request) {
	page := `
	<h2>O Mnie</h2>
	<p>Jestem entuzjastą DevOps, specjalizującym się w CI/CD, Kubernetes, GitOps i ArgoCD.</p>
	<h2>Stack</h2>
	<ul><li>GoLang</li><li>MicroK8s</li><li>ArgoCD</li><li>GitHub Actions</li></ul>
	`
	html := fmt.Sprintf(`
	<html><head><title>dawtrogr Website</title></head>
	<body style="font-family:Arial;background:#f7f7f7;padding:40px;">
	<div style="max-width:800px;margin:auto;background:#fff;padding:20px;border-radius:10px;">
	<h1>davtrogr Website (GitOps)</h1>%s
	<p><b>Status:</b> OK</p></div></body></html>`, page)
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(html))
}

type responseWriterWrapper struct {
	http.ResponseWriter
	statusCode int
}
func (lrw *responseWriterWrapper) WriteHeader(code int) {
	lrw.statusCode = code
	lrw.ResponseWriter.WriteHeader(code)
}

func loggingMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		lrw := &responseWriterWrapper{ResponseWriter: w, statusCode: 200}
		start := time.Now()
		next(lrw, r)
		dur := time.Since(start).Seconds()
		httpRequestsTotal.WithLabelValues(r.URL.Path, r.Method, fmt.Sprint(lrw.statusCode)).Inc()
		httpRequestDuration.WithLabelValues(r.URL.Path, r.Method).Observe(dur)
		log.Printf("%s %s -> %d (%.3fs)", r.Method, r.URL.Path, lrw.statusCode, dur)
	}
}

func healthzHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("ok"))
}
