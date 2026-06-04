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

	questionRepo := repo.InitQuestionRepo()
	questionSvc := service.NewQuestionSvc(questionRepo)
	questionHandler := handler.NewQuestionHandler(questionSvc)

	groupRepo := repo.InitGroupRepo()
	groupSvc := service.NewGroupSvc(groupRepo)
	groupHandler := handler.NewGroupHandler(groupSvc)

	mux := http.NewServeMux()

	mux.HandleFunc("POST /api/login", authHandler.Login)
	mux.HandleFunc("POST /api/register", authHandler.Register)
	mux.HandleFunc("POST /api/refresh", authHandler.Refresh)
	mux.HandleFunc("GET /api/users", authHandler.QueryUser)

	mux.HandleFunc("POST /api/item/inv", itemHandler.QueryInv)
	mux.HandleFunc("POST /api/item/slot", itemHandler.QuerySlot)
	mux.HandleFunc("POST /api/item/inv2slot", itemHandler.TranInv2Slot)
	mux.HandleFunc("POST /api/item/slot2inv", itemHandler.TranSlot2Inv)

	mux.HandleFunc("POST /api/group/set", groupHandler.SetGroup)
	mux.HandleFunc("GET /api/group", groupHandler.QueryGroup)
	mux.HandleFunc("POST /api/group/members", groupHandler.QueryMember)

	mux.HandleFunc("POST /api/question/generate", questionHandler.Generate)
	mux.HandleFunc("POST /api/question/answer", questionHandler.Answer)

	mux.HandleFunc("GET /api/state", questionHandler.GetState)
	mux.HandleFunc("POST /api/state", questionHandler.SetState)

	log.Println("伺服器已啟動，監聽埠號 :8080...")
	if err := http.ListenAndServe(":8080", mux); err != nil {
		log.Fatalf("伺服器啟動失敗: %v", err)
	}
}
