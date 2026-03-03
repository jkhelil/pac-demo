# Use default platform when TARGETPLATFORM not provided by builder (e.g. buildah)
FROM golang:1.25 AS build
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /out/pac-demo ./cmd/pac-demo

FROM gcr.io/distroless/static:nonroot
USER nonroot:nonroot
COPY --from=build /out/pac-demo /pac-demo
EXPOSE 8080
ENTRYPOINT ["/pac-demo"]

