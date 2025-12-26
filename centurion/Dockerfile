# Multi-stage Dockerfile for building the centurion binary
# Builder stage
FROM golang:1.25.5 AS builder

WORKDIR /src

# Cache module downloads
COPY go.mod go.sum ./
RUN go mod download

# Copy sources and build
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags "-s -w" -o /centurion .

# Final minimal image
FROM scratch
COPY --from=builder /centurion /centurion
ENTRYPOINT ["/centurion"]
