package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"

	"github.com/jkhelil/pac-demo/internal/version"
)

// Default greeting word when GREETING_PREFIX env is not set. Change this for demo PRs (e.g. "Hi", "Hey", "Welcome").
const defaultGreetingPrefix = "Hello"

func Healthz(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ok"))
}

func Version(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{
		"version": version.Version,
	})
}

func Greet(w http.ResponseWriter, r *http.Request) {
	name := r.URL.Query().Get("name")
	if name == "" {
		name = "world"
	}
	prefix := os.Getenv("GREETING_PREFIX")
	if prefix == "" {
		prefix = defaultGreetingPrefix
	}
	msg := fmt.Sprintf("%s, %s!", prefix, name)
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{
		"message": msg,
	})
}

type sumRequest struct {
	Numbers []float64 `json:"numbers"`
}

func CalcSum(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req sumRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}
	var sum float64
	for _, n := range req.Numbers {
		sum += n
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"sum": sum,
	})
}
