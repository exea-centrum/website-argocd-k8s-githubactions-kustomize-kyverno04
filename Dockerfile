FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY go.mod ./ 
# Dodano go.sum do kopiowania, aby zapewnić spójność z main.go, 
# a także zmieniono RUN go mod download na go mod tidy
# UWAGA: W poprzednim kroku usunąłeś go.sum z COPY, 
# więc kompilator potrzebuje, by go.mod i go.sum były spójne.
# Zostawmy na razie tylko go.mod i wymuśmy jego wygenerowanie za pomocą go mod tidy
COPY go.sum ./
RUN go mod tidy
COPY src/*.go ./
RUN go build -o /davtrogr-website ./main.go

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /davtrogr-website .

EXPOSE 8080
CMD ["./davtrogr-website"]