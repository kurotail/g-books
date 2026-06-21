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

	"gb-api/internal/config"
	"gb-api/internal/handler"
	"gb-api/internal/logger"
	"gb-api/internal/repo"
	"gb-api/internal/service"
)

func routes() (http.Handler, *handler.StateHandler) {
	authHandler := handler.NewAuthHandler(service.NewAuthSvc(repo.InitUserRepo(), repo.InitRefreshTokenRepo()))
	itemHandler := handler.NewItemHandler(service.NewItemSvc(repo.InitItemRepo(), repo.InitInventoryRepo(), repo.InitUserRepo(), repo.InitBuildingRepo()))
	questionHandler := handler.NewQuestionHandler(service.NewQuestionSvc(repo.InitQuestionRepo(), repo.InitUserRepo(), repo.InitBuildingRepo(), repo.InitItemRepo(), repo.InitInventoryRepo(), repo.InitSTTRepo()))
	stateHandler := handler.NewStateHandler(service.NewStateSvc(repo.InitUserRepo()))
	buildingHandler := handler.NewBuildingHandler(service.NewBuildingSvc(repo.InitBuildingRepo(), repo.InitUserRepo()))
	studentHandler := handler.NewStudentHandler(service.NewStudentSvc(repo.InitStudentRepo(), repo.InitUserRepo()))
	mediaHandler := handler.NewMediaHandler(service.NewMediaSvc(config.UploadDir, config.MaxImageMB, config.MaxAudioMB))
	sttHandler := handler.NewSTTHandler(service.NewSTTSvc(repo.InitSTTRepo(), repo.InitUserRepo()))

	mux := http.NewServeMux()

	mux.HandleFunc("POST /api/login", authHandler.Login)
	mux.HandleFunc("POST /api/register", authHandler.Register)
	mux.HandleFunc("POST /api/refresh", authHandler.Refresh)
	mux.HandleFunc("GET /api/users", authHandler.QueryUser)
	mux.HandleFunc("GET /api/users/{username}", authHandler.GetUser)
	mux.HandleFunc("POST /api/users/pfp", authHandler.SetProfilePic)
	mux.HandleFunc("POST /api/users/building", authHandler.SetBuilding)
	mux.HandleFunc("POST /api/users/students", studentHandler.SetStudents)
	mux.HandleFunc("POST /api/users/display_name", authHandler.SetDisplayName)
	mux.HandleFunc("POST /api/users/password", authHandler.SetPassword)
	mux.HandleFunc("DELETE /api/users/{id}", authHandler.DeleteUser)

	mux.HandleFunc("POST /api/item", itemHandler.QueryItems)
	mux.HandleFunc("POST /api/item/inv2slot", itemHandler.TranInv2Slot)
	mux.HandleFunc("POST /api/item/slot2inv", itemHandler.TranSlot2Inv)

	mux.HandleFunc("POST /api/building", buildingHandler.Create)
	mux.HandleFunc("GET /api/building", buildingHandler.List)
	mux.HandleFunc("GET /api/building/{id}", buildingHandler.Get)
	mux.HandleFunc("PUT /api/building/{id}", buildingHandler.Update)

	mux.HandleFunc("POST /api/student", studentHandler.Create)
	mux.HandleFunc("GET /api/student", studentHandler.List)
	mux.HandleFunc("GET /api/student/{id}", studentHandler.Get)
	mux.HandleFunc("PUT /api/student/{id}", studentHandler.Update)
	mux.HandleFunc("DELETE /api/student/{id}", studentHandler.Delete)

	mux.HandleFunc("POST /api/question/generate", questionHandler.GenerateItem)
	mux.HandleFunc("POST /api/question/target", questionHandler.GenerateTarget)
	mux.HandleFunc("POST /api/question/answer", questionHandler.Answer)
	mux.HandleFunc("POST /api/question/upload", questionHandler.Upload)
	mux.HandleFunc("GET /api/question/search", questionHandler.Search)
	mux.HandleFunc("GET /api/question/{id}", questionHandler.Get)
	mux.HandleFunc("PUT /api/question/{id}", questionHandler.Update)
	mux.HandleFunc("DELETE /api/question/{id}", questionHandler.Delete)

	mux.HandleFunc("POST /api/image", mediaHandler.UploadImage)
	mux.HandleFunc("POST /api/audio", mediaHandler.UploadAudio)
	mux.HandleFunc("POST /api/stt", sttHandler.Transcribe)

	mux.HandleFunc("GET /api/state", stateHandler.GetState)
	mux.HandleFunc("POST /api/state", stateHandler.SetState)
	mux.HandleFunc("GET /api/state/ws", stateHandler.StateSocket)

	return logger.RequestLogger(mux), stateHandler
}

func main() {
	// Connect to Postgres, apply the schema, and seed the admin account.
	initCtx, cancelInit := context.WithTimeout(context.Background(), 60*time.Second)
	err := repo.Init(initCtx, config.DatabaseURL, config.AdminUsername, config.AdminPassword)
	cancelInit()
	if err != nil {
		logger.L.Error(err.Error())
		logger.L.Error("failed to initialize database")
		os.Exit(1)
	}
	defer repo.Close()

	mux, stateHandler := routes()
	server := &http.Server{
		Addr:    ":8080",
		Handler: mux,
	}

	// Poll the scheduled state end time and auto-revert to NORMAL; stops on shutdown.
	rootCtx, stopScheduler := context.WithCancel(context.Background())
	defer stopScheduler()
	service.StartStateScheduler(rootCtx, time.Second)

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
