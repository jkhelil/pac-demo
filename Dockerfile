# TARGETPLATFORM is set by docker buildx; default for plain docker build
ARG TARGETPLATFORM=linux/amd64

FROM --platform=$TARGETPLATFORM golang:1.22 AS build
ARG TARGETOS=linux
ARG TARGETARCH=amd64
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -o /out/pac-demo ./cmd/pac-demo

FROM --platform=$TARGETPLATFORM gcr.io/distroless/static:nonroot
USER nonroot:nonroot
COPY --from=build /out/pac-demo /pac-demo
EXPOSE 8080
ENTRYPOINT ["/pac-demo"]

