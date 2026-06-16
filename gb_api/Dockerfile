# syntax=docker/dockerfile:1

# --- Build stage ---
FROM golang:1.26.4-alpine3.23 AS build
WORKDIR /src

# Cache dependencies
COPY go.mod go.sum ./
RUN go mod download

# Build the server
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/server ./cmd/server

# Staged empty uploads dir, copied into the runtime image so the named volume
# mounted there inherits nonroot ownership and is writable by the server.
RUN mkdir -p /out/uploads

# --- Runtime stage ---
FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app
COPY --from=build /out/server /app/server

# 65532 is the distroless "nonroot" uid/gid.
COPY --from=build --chown=65532:65532 /out/uploads /srv/uploads

EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/app/server"]
