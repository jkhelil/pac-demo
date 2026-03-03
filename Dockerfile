FROM --platform=$TARGETOS/$TARGETARCH golang:1.22 as build
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=$(go env GOARCH) go build -o /out/pac-demo ./cmd/pac-demo

FROM gcr.io/distroless/static:nonroot
USER nonroot:nonroot
COPY --from=build /out/pac-demo /pac-demo
EXPOSE 8080
ENTRYPOINT ["/pac-demo"]

