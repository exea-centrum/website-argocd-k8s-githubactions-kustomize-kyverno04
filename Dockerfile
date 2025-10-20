FROM golang:1.21-alpine AS builder
WORKDIR /app
# W tej linii usunęliśmy komentarz, który mógł powodować błąd parsowania ścieżki
COPY go.mod ./ 
RUN go mod download
COPY src/*.go ./
RUN go build -o /davtrogr-website ./main.go

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /davtrogr-website .

EXPOSE 8080
CMD ["./davtrogr-website"]