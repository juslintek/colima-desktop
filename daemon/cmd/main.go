package main

import (
	"flag"
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"

	"github.com/colima-ui/daemon/internal/server"
	"google.golang.org/grpc"
)

const defaultSocket = "/tmp/colima-ui.sock"

func main() {
	socketPath := flag.String("socket", defaultSocket, "Unix socket path")
	flag.Parse()

	os.Remove(*socketPath)

	lis, err := net.Listen("unix", *socketPath)
	if err != nil {
		log.Fatalf("failed to listen: %v", err)
	}
	defer os.Remove(*socketPath)

	grpcServer := grpc.NewServer()
	server.Register(grpcServer)

	go func() {
		sig := make(chan os.Signal, 1)
		signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
		<-sig
		log.Println("shutting down...")
		grpcServer.GracefulStop()
	}()

	log.Printf("colima-ui daemon listening on %s", *socketPath)
	if err := grpcServer.Serve(lis); err != nil {
		log.Fatalf("failed to serve: %v", err)
	}
}
