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
