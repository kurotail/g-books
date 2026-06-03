package main

import (
	"log"
	"net/http"

	"gb-api/internal/handler"
	"gb-api/internal/repo"
	"gb-api/internal/service"
)


func main() {
	r := repo.InitAuthRepo()
	s := service.NewAuthSvc(r)
	h := handler.NewAuthHandler(s)
	mux := http.NewServeMux()

	mux.HandleFunc("POST /api/login", h.Login)
	mux.HandleFunc("POST /api/refresh", h.Refresh)
	mux.HandleFunc("GET /api/dashboard", handler.QueryDashboard)

	log.Println("伺服器已啟動，監聽埠號 :8080...")
	if err := http.ListenAndServe(":8080", mux); err != nil {
		log.Fatalf("伺服器啟動失敗: %v", err)
	}
}
