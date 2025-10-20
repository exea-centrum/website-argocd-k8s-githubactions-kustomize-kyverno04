FROM golang:1.21-alpine AS builder
WORKDIR /app

# Krok 1: Kopiowanie wszystkich plików projektu (moduły i kod źródłowy) 
# przed manipulacją modułami. To zapewnia, że 'go mod tidy' widzi wszystkie zależności
# i poprawnie aktualizuje go.sum, przygotowując wszystko do kompilacji.
COPY go.mod go.sum ./
COPY src/*.go ./

# Krok 2: Pobranie i weryfikacja wszystkich zależności.
# 'go mod tidy' zapewni spójność go.sum, a także pobierze wymagane pakiety.
RUN go mod tidy

# Krok 3: Kompilacja binarki
RUN go build -o /davtrogr-website ./main.go

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /davtrogr-website .

EXPOSE 8080
CMD ["./davtrogr-website"]