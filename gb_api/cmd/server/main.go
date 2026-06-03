package main

import (
	"log"
	"net/http"

	"gb-api/internal/handler"
	"gb-api/internal/repo"
	"gb-api/internal/service"
)


func main() {
	authRepo := repo.InitAuthRepo()
	authSvc := service.NewAuthSvc(authRepo)
	authHandler := handler.NewAuthHandler(authSvc)

	itemRepo := repo.InitItemRepo()
	itemSvc := service.NewItemSvc(itemRepo)
	itemHandler := handler.NewItemHandler(itemSvc)

	mux := http.NewServeMux()

	mux.HandleFunc("POST /api/login", authHandler.Login)
	mux.HandleFunc("POST /api/refresh", authHandler.Refresh)
	mux.HandleFunc("GET /api/dashboard", handler.QueryDashboard)

	mux.HandleFunc("POST /api/item/inv", itemHandler.QueryInv)
	mux.HandleFunc("POST /api/item/slot", itemHandler.QuerySlot)
	mux.HandleFunc("POST /api/item/increase", itemHandler.IncreaseInvItem)
	mux.HandleFunc("DELETE /api/item/slot", itemHandler.DeleteSlotItem)
	mux.HandleFunc("POST /api/item/inv2slot", itemHandler.TranInv2Slot)
	mux.HandleFunc("POST /api/item/slot2inv", itemHandler.TranSlot2Inv)

	log.Println("伺服器已啟動，監聽埠號 :8080...")
	if err := http.ListenAndServe(":8080", mux); err != nil {
		log.Fatalf("伺服器啟動失敗: %v", err)
	}
}
