package main

import (
	"log"
	"net/http"
	"os"
	"time"

	"github.com/jkhelil/pac-demo/internal/handlers"
)

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", handlers.Healthz)
	mux.HandleFunc("/version", handlers.Version)
	mux.HandleFunc("/greet", handlers.Greet)
	mux.HandleFunc("/calc/sum", handlers.CalcSum)

	addr := ":8080"
	srv := &http.Server{
		Addr:              addr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		IdleTimeout:       30 * time.Second,
	}

	log.Printf("pac-demo listening on %s", addr)
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Printf("server error: %v", err)
		os.Exit(1)
	}
}

