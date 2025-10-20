package main

import (
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	_ "github.com/lib/pq"
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
	// 🔧 Zmienne środowiskowe do połączenia z PostgreSQL
	dbHost := os.Getenv("DATABASE_HOST")
	dbPort := os.Getenv("DATABASE_PORT")
	dbUser := os.Getenv("DATABASE_USER")
	dbPassword := os.Getenv("DATABASE_PASSWORD")
	dbName := os.Getenv("DATABASE_NAME")

	connStr := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		dbHost, dbPort, dbUser, dbPassword, dbName)

	db, err := sql.Open("postgres", connStr)
	if err != nil {
		log.Fatalf("❌ Błąd połączenia z bazą: %v", err)
	}
	defer db.Close()

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		httpRequests.WithLabelValues(r.URL.Path, r.Method).Inc()

		var dbTime string
		err := db.QueryRow("SELECT NOW()").Scan(&dbTime)
		if err != nil {
			dbTime = "brak połączenia z bazą"
		}

		t := time.Now().Format("2006-01-02 15:04:05")
		fmt.Fprintf(w,
			"<h1>davtrogr Website</h1>"+
				"<p>Serwer działa lokalnie: %s</p>"+
				"<p>Czas z bazy danych: %s</p>",
			t, dbTime)
	})

	http.Handle("/metrics", promhttp.Handler())

	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("ok"))
	})

	log.Println("🌍 Start serwera na :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
