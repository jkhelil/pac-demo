package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
)

func TestHealthz(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	rr := httptest.NewRecorder()
	Healthz(rr, req)
	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rr.Code)
	}
}

func TestGreet_Defaults(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/greet", nil)
	rr := httptest.NewRecorder()
	os.Unsetenv("GREETING_PREFIX")
	Greet(rr, req)
	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rr.Code)
	}
	var res map[string]string
	_ = json.Unmarshal(rr.Body.Bytes(), &res)
	if res["message"] != "Hello, world!" {
		t.Fatalf("unexpected message: %q", res["message"])
	}
}

func TestGreet_WithParamsAndEnv(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/greet?name=KubeCon", nil)
	rr := httptest.NewRecorder()
	os.Setenv("GREETING_PREFIX", "Welcome")
	defer os.Unsetenv("GREETING_PREFIX")
	Greet(rr, req)
	var res map[string]string
	_ = json.Unmarshal(rr.Body.Bytes(), &res)
	if res["message"] != "Welcome, KubeCon!" {
		t.Fatalf("unexpected message: %q", res["message"])
	}
}

func TestCalcSum_MethodGuard(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/calc/sum", nil)
	rr := httptest.NewRecorder()
	CalcSum(rr, req)
	if rr.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", rr.Code)
	}
}

func TestCalcSum_Valid(t *testing.T) {
	body := []byte(`{"numbers":[1,2.5,3.5]}`)
	req := httptest.NewRequest(http.MethodPost, "/calc/sum", bytes.NewReader(body))
	rr := httptest.NewRecorder()
	CalcSum(rr, req)
	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rr.Code)
	}
	var res map[string]any
	_ = json.Unmarshal(rr.Body.Bytes(), &res)
	if res["sum"] != 7.0 {
		t.Fatalf("unexpected sum: %v", res["sum"])
	}
}

