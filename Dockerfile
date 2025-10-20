FROM golang:1.21-alpine AS builder
WORKDIR /app

# Krok 1: Kopiowanie plików definicji modułów. Umożliwia buforowanie
# zależności, jeśli go.mod/go.sum się nie zmieniły.
COPY go.mod go.sum ./

# Krok 2: Pobranie wszystkich zależności. 
# Zamiast go mod tidy, uzywamy tylko go mod download, 
# ufając, że skopiowany go.sum jest juz poprawny.
RUN go mod download

# Krok 3: Kopiowanie plików źródłowych i kompilacja
# Kopiujemy kod źródłowy po modyfikacjach modułów.
COPY src/*.go ./
RUN go build -o /davtrogr-website ./main.go

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /davtrogr-website .

EXPOSE 8080
CMD ["./davtrogr-website"]