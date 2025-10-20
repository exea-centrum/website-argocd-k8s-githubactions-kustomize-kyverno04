# -----------------------
#  Stage 1: Builder
# -----------------------
FROM golang:1.21-alpine AS builder

WORKDIR /app

# Skopiuj tylko plik go.mod (lub utwórz, jeśli nie istnieje)
COPY go.mod* . || true

# Zainicjalizuj moduł, jeśli nie istnieje
RUN if [ ! -f go.mod ]; then go mod init app; fi

# Pobierz zależności Prometheusa
RUN go get github.com/prometheus/client_golang/prometheus \
    && go get github.com/prometheus/client_golang/prometheus/promhttp \
    && go mod tidy

# Skopiuj kod źródłowy
COPY src/*.go ./

# Zbuduj binarkę
RUN go build -o app .

# -----------------------
#  Stage 2: Final Image
# -----------------------
FROM alpine:latest

WORKDIR /root/
COPY --from=builder /app/app .

EXPOSE 8080
CMD ["./app"]
