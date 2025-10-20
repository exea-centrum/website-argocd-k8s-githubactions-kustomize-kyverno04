FROM golang:1.21-alpine AS builder

WORKDIR /app

# Skopiuj definicję modułów i pobierz zależności
COPY go.mod ./
RUN go mod tidy

# Skopiuj źródła
COPY src/*.go ./

# Upewnij się, że zależności są zaciągnięte (wygeneruje go.sum)
RUN go mod download

# Buduj binarkę
RUN go build -o app

# Faza końcowa - minimalny obraz
FROM alpine:latest

WORKDIR /root/
COPY --from=builder /app/app .

EXPOSE 8080
CMD ["./app"]
