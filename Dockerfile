FROM golang:1.21-alpine AS builder
WORKDIR /app

# Kopiowanie plików definicji modułów: go.mod i go.sum. 
# MUSZĄ być skopiowane razem, aby zapewnić spójność zależności.
COPY go.mod go.sum ./

# Pobrane zależności i ich weryfikacja/aktualizacja.
# 'go mod tidy' pobiera moduły i aktualizuje go.sum.
RUN go mod tidy

# Kopiowanie plików źródłowych i kompilacja
COPY src/*.go ./
RUN go build -o /davtrogr-website ./main.go

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /davtrogr-website .

EXPOSE 8080
CMD ["./davtrogr-website"]
