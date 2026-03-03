APP_NAME := pac-demo
IMG ?= ghcr.io/jkhelil/$(APP_NAME):dev

.PHONY: all build test run docker-build docker-run fmt

all: test build

build:
	GO111MODULE=on go build -o bin/$(APP_NAME) ./cmd/$(APP_NAME)

test:
	go test ./...

fmt:
	go fmt ./...

docker-build:
	docker build -t $(IMG) .

docker-run:
	docker run --rm -p 8080:8080 $(IMG)

