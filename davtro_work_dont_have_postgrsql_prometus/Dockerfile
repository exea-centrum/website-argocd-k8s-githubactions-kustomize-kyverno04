FROM golang:1.21-alpine AS builder

WORKDIR /app

# Skopiuj definicje modułów i spróbuj pobrać zależności
COPY go.mod ./
RUN go mod tidy || true
RUN go mod download || true

# Skopiuj kod źródłowy
COPY src/*.go ./

# Jeszcze raz uruchom tidy (teraz z pełnym kodem, by wygenerować brakujące wpisy)
RUN go mod tidy && go mod download

# Zbuduj binarkę
RUN go build -o app

# Druga faza – minimalny obraz
FROM alpine:latest
WORKDIR /root/
COPY --from=builder /app/app .
EXPOSE 8080
CMD ["./app"]
