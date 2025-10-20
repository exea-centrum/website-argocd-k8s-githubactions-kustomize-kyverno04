# ============================
# Stage 1: Build Go app
# ============================
FROM golang:1.21-alpine AS builder

WORKDIR /app

# Skopiuj kod źródłowy
COPY src/*.go ./

# Jeśli brak go.mod, utwórz go dynamicznie
RUN if [ ! -f go.mod ]; then go mod init example.com/app; fi

# Dodaj zależności Prometheusa i zapisz go.sum
RUN go get github.com/prometheus/client_golang/prometheus \
    && go get github.com/prometheus/client_golang/prometheus/promhttp \
    && go mod tidy

# Zbuduj binarkę
RUN go build -o app main.go

# ============================
# Stage 2: Minimalny obraz
# ============================
FROM alpine:latest

WORKDIR /root/
COPY --from=builder /app/app .



EXPOSE 8080
CMD ["./app"]
