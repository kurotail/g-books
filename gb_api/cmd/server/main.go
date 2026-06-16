package main

import (
	"context"
	"errors"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"gb-api/internal/handler"
	"gb-api/internal/logger"
	"gb-api/internal/repo"
	"gb-api/internal/service"
)

func routes() (http.Handler, *handler.StateHandler) {
	authHandler := handler.NewAuthHandler(service.NewAuthSvc(repo.InitUserRepo(), repo.InitRefreshTokenRepo()))
	itemHandler := handler.NewItemHandler(service.NewItemSvc(repo.InitItemRepo(), repo.InitUserRepo(), repo.InitGroupRepo(), repo.InitBuildingRepo()))
	questionHandler := handler.NewQuestionHandler(service.NewQuestionSvc(repo.InitQuestionRepo(), repo.InitUserRepo(), repo.InitGroupRepo(), repo.InitBuildingRepo(), repo.InitItemRepo(), repo.InitSTTRepo()))
	stateHandler := handler.NewStateHandler(service.NewStateSvc(repo.InitUserRepo()))
	groupHandler := handler.NewGroupHandler(service.NewGroupSvc(repo.InitGroupRepo(), repo.InitUserRepo()))
	buildingHandler := handler.NewBuildingHandler(service.NewBuildingSvc(repo.InitBuildingRepo(), repo.InitUserRepo()))

	mux := http.NewServeMux()

	mux.HandleFunc("POST /api/login", authHandler.Login)
	mux.HandleFunc("POST /api/register", authHandler.Register)
	mux.HandleFunc("POST /api/users/delete", authHandler.DeleteUser)
	mux.HandleFunc("POST /api/refresh", authHandler.Refresh)
	mux.HandleFunc("GET /api/users", authHandler.QueryUser)

	mux.HandleFunc("POST /api/item", itemHandler.QueryItems)
	mux.HandleFunc("POST /api/item/inv2slot", itemHandler.TranInv2Slot)
	mux.HandleFunc("POST /api/item/slot2inv", itemHandler.TranSlot2Inv)

	mux.HandleFunc("POST /api/group/set", groupHandler.SetGroup)
	mux.HandleFunc("POST /api/group/name", groupHandler.SetName)
	mux.HandleFunc("POST /api/group/building", groupHandler.SetBuilding)
	mux.HandleFunc("GET /api/group", groupHandler.QueryGroup)

	mux.HandleFunc("POST /api/building", buildingHandler.Create)
	mux.HandleFunc("GET /api/building", buildingHandler.List)
	mux.HandleFunc("GET /api/building/{id}", buildingHandler.Get)
	mux.HandleFunc("PUT /api/building/{id}", buildingHandler.Update)

	mux.HandleFunc("POST /api/question/generate", questionHandler.GenerateItem)
	mux.HandleFunc("POST /api/question/target", questionHandler.GenerateTarget)
	mux.HandleFunc("POST /api/question/answer", questionHandler.Answer)
	mux.HandleFunc("POST /api/question/upload", questionHandler.Upload)
	mux.HandleFunc("GET /api/question/search", questionHandler.Search)
	mux.HandleFunc("GET /api/question/{id}", questionHandler.Get)
	mux.HandleFunc("PUT /api/question/{id}", questionHandler.Update)
	mux.HandleFunc("DELETE /api/question/{id}", questionHandler.Delete)

	mux.HandleFunc("GET /api/state", stateHandler.GetState)
	mux.HandleFunc("POST /api/state", stateHandler.SetState)
	mux.HandleFunc("GET /api/state/ws", stateHandler.StateSocket)

	return logger.RequestLogger(mux), stateHandler
}

func main() {
	mux, stateHandler := routes()
	server := &http.Server{
		Addr:    ":8080",
		Handler: mux,
	}

	go func() {
		logger.L.Info("server started, port " + strings.TrimPrefix(server.Addr, ":"))
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.L.Error("server failed to start", "err", err)
			os.Exit(1)
		}
	}()

	// Block until an interrupt or terminate signal is received.
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	logger.L.Info("shutting down server...")
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := stateHandler.Shutdown(ctx); err != nil {
		logger.L.Warn("websocket forced to close", "err", err)
	}

	if err := server.Shutdown(ctx); err != nil {
		logger.L.Error("server forced to shutdown", "err", err)
		os.Exit(1)
	}

	logger.L.Info("server exited")
}
