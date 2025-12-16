# --- Build Stage ---
FROM golang:1.24-alpine AS builder

WORKDIR /app

# Copy go.mod and go.sum to leverage Docker cache
COPY go.mod go.sum ./
# Download all dependencies. Dependencies will be cached if the go.mod and go.sum files are not changed
RUN go mod download

# Copy the source code required for the build
COPY main.go .

# Build the application
# -o /app/go-autoscale: output path for the executable
# CGO_ENABLED=0: build a statically linked binary
# -ldflags="-s -w": strip debugging information
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -ldflags="-s -w" -o /app/go-autoscale .

# --- Final Stage ---
FROM alpine:latest

# Install docker-cli and docker-compose for the autoscaler to use
RUN apk --no-cache add docker-cli docker-compose

# Set the working directory
WORKDIR /app

# Copy the pre-built binary from the build stage
COPY --from=builder /app/go-autoscale .

# The command to run the autoscaler.
# The actual parameters will be provided from docker-compose.yml
ENTRYPOINT ["/app/go-autoscale"]
