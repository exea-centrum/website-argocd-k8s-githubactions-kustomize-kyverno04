FROM golang:1.21-alpine AS builder
WORKDIR /app

# Krok 1: Kopiowanie plików definicji modułów. Umożliwia buforowanie
# zależności, jeśli go.mod/go.sum się nie zmieniły.
COPY go.mod go.sum ./

# Krok 2: Pobranie i weryfikacja wszystkich zależności.
# Najpierw pobierz, aby upewnić się, że moduły są fizycznie obecne.
RUN go mod download
# Następnie uporządkuj go.sum.
RUN go mod tidy

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