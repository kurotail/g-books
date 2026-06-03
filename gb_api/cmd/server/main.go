package main

import (
	"log"
	"net/http"

	"gb-api/internal/handler"
)


func main() {
	// 使用 Go 1.22+ 內建的新路由格式
	mux := http.NewServeMux()

	mux.HandleFunc("POST /api/login", handler.LoginHandler)
	mux.HandleFunc("POST /api/refresh", handler.RefreshHandler)
	mux.HandleFunc("GET /api/dashboard", handler.QueryHandler)

	log.Println("伺服器已啟動，監聽埠號 :8080...")
	if err := http.ListenAndServe(":8080", mux); err != nil {
		log.Fatalf("伺服器啟動失敗: %v", err)
	}
}
