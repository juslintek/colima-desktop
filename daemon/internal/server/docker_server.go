package server

import (
	"bufio"
	"context"

	"github.com/colima-desktop/daemon/internal/docker"
	pb "github.com/colima-desktop/daemon/proto"
)

// DockerServer implements the generated pb.DockerServiceServer by delegating to
// the docker.Client for the requested target (local / remote-SSH / WSL2).
type DockerServer struct {
	pb.UnimplementedDockerServiceServer
}

func NewDocker() *DockerServer { return &DockerServer{} }

func clientFor(profile, host string, wsl2 bool) (*docker.Client, error) {
	return docker.New(docker.Target{Profile: profile, Host: host, WSL2: wsl2})
}

func jsonResp(s string, err error) (*pb.JsonResponse, error) {
	if err != nil {
		return &pb.JsonResponse{Error: err.Error()}, nil
	}
	return &pb.JsonResponse{Json: s}, nil
}

func ok(msg string, err error) (*pb.StatusResponse, error) {
	if err != nil {
		return &pb.StatusResponse{Success: false, Error: err.Error()}, nil
	}
	return &pb.StatusResponse{Success: true, Message: msg}, nil
}

// --- Containers ---

func (s *DockerServer) ListContainers(_ context.Context, r *pb.DockerScope) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil {
		return &pb.JsonResponse{Error: err.Error()}, nil
	}
	return jsonResp(c.ListContainers(r.All))
}
func (s *DockerServer) ContainerAction(_ context.Context, r *pb.ContainerActionRequest) (*pb.StatusResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil {
		return ok("", err)
	}
	return ok(r.Action, c.ContainerAction(r.Id, r.Action))
}
func (s *DockerServer) CreateContainer(_ context.Context, r *pb.CreateContainerRequest) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil {
		return &pb.JsonResponse{Error: err.Error()}, nil
	}
	return jsonResp(c.CreateContainer(r.Name, r.Image))
}
func (s *DockerServer) RenameContainer(_ context.Context, r *pb.RenameRequest) (*pb.StatusResponse, error) {
	c, err := clientFor(r.Profile, "", false)
	if err != nil {
		return ok("", err)
	}
	return ok("renamed", c.RenameContainer(r.Id, r.NewName))
}
func (s *DockerServer) ContainerLogs(_ context.Context, r *pb.IdRequest) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil { return &pb.JsonResponse{Error: err.Error()}, nil }
	return jsonResp(c.ContainerLogs(r.Id))
}
func (s *DockerServer) InspectContainer(_ context.Context, r *pb.IdRequest) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil { return &pb.JsonResponse{Error: err.Error()}, nil }
	return jsonResp(c.InspectContainer(r.Id))
}
func (s *DockerServer) ContainerTop(_ context.Context, r *pb.IdRequest) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil { return &pb.JsonResponse{Error: err.Error()}, nil }
	return jsonResp(c.ContainerTop(r.Id))
}
func (s *DockerServer) ContainerStats(_ context.Context, r *pb.IdRequest) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil { return &pb.JsonResponse{Error: err.Error()}, nil }
	return jsonResp(c.ContainerStats(r.Id))
}
func (s *DockerServer) ContainerChanges(_ context.Context, r *pb.IdRequest) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil { return &pb.JsonResponse{Error: err.Error()}, nil }
	return jsonResp(c.ContainerChanges(r.Id))
}
func (s *DockerServer) PruneContainers(_ context.Context, r *pb.DockerScope) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil { return &pb.JsonResponse{Error: err.Error()}, nil }
	return jsonResp(c.PruneContainers())
}

// --- Images ---

func (s *DockerServer) ListImages(_ context.Context, r *pb.DockerScope) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil { return &pb.JsonResponse{Error: err.Error()}, nil }
	return jsonResp(c.ListImages())
}
func (s *DockerServer) RemoveImage(_ context.Context, r *pb.IdRequest) (*pb.StatusResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil { return ok("", err) }
	return ok("removed", c.RemoveImage(r.Id))
}
func (s *DockerServer) InspectImage(_ context.Context, r *pb.NameRequest) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil { return &pb.JsonResponse{Error: err.Error()}, nil }
	return jsonResp(c.InspectImage(r.Name))
}
func (s *DockerServer) ImageHistory(_ context.Context, r *pb.NameRequest) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil { return &pb.JsonResponse{Error: err.Error()}, nil }
	return jsonResp(c.ImageHistory(r.Name))
}
func (s *DockerServer) TagImage(_ context.Context, r *pb.TagRequest) (*pb.StatusResponse, error) {
	c, err := clientFor(r.Profile, "", false)
	if err != nil { return ok("", err) }
	return ok("tagged", c.TagImage(r.Name, r.Repo, r.Tag))
}
func (s *DockerServer) SearchImages(_ context.Context, r *pb.SearchRequest) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, "", false)
	if err != nil { return &pb.JsonResponse{Error: err.Error()}, nil }
	return jsonResp(c.SearchImages(r.Term))
}
func (s *DockerServer) PruneImages(_ context.Context, r *pb.DockerScope) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil { return &pb.JsonResponse{Error: err.Error()}, nil }
	return jsonResp(c.PruneImages())
}

// --- Volumes ---

func (s *DockerServer) ListVolumes(_ context.Context, r *pb.DockerScope) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil { return &pb.JsonResponse{Error: err.Error()}, nil }
	return jsonResp(c.ListVolumes())
}
func (s *DockerServer) CreateVolume(_ context.Context, r *pb.NameRequest) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil { return &pb.JsonResponse{Error: err.Error()}, nil }
	return jsonResp(c.CreateVolume(r.Name))
}
func (s *DockerServer) RemoveVolume(_ context.Context, r *pb.NameRequest) (*pb.StatusResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil { return ok("", err) }
	return ok("removed", c.RemoveVolume(r.Name))
}
func (s *DockerServer) InspectVolume(_ context.Context, r *pb.NameRequest) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil { return &pb.JsonResponse{Error: err.Error()}, nil }
	return jsonResp(c.InspectVolume(r.Name))
}
func (s *DockerServer) PruneVolumes(_ context.Context, r *pb.DockerScope) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil { return &pb.JsonResponse{Error: err.Error()}, nil }
	return jsonResp(c.PruneVolumes())
}

// --- Networks ---

func (s *DockerServer) ListNetworks(_ context.Context, r *pb.DockerScope) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil { return &pb.JsonResponse{Error: err.Error()}, nil }
	return jsonResp(c.ListNetworks())
}
func (s *DockerServer) CreateNetwork(_ context.Context, r *pb.NameRequest) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil { return &pb.JsonResponse{Error: err.Error()}, nil }
	return jsonResp(c.CreateNetwork(r.Name))
}
func (s *DockerServer) RemoveNetwork(_ context.Context, r *pb.IdRequest) (*pb.StatusResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil { return ok("", err) }
	return ok("removed", c.RemoveNetwork(r.Id))
}
func (s *DockerServer) InspectNetwork(_ context.Context, r *pb.IdRequest) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil { return &pb.JsonResponse{Error: err.Error()}, nil }
	return jsonResp(c.InspectNetwork(r.Id))
}
func (s *DockerServer) ConnectNetwork(_ context.Context, r *pb.NetworkContainerRequest) (*pb.StatusResponse, error) {
	c, err := clientFor(r.Profile, "", false)
	if err != nil { return ok("", err) }
	return ok("connected", c.ConnectNetwork(r.NetworkId, r.ContainerId))
}
func (s *DockerServer) DisconnectNetwork(_ context.Context, r *pb.NetworkContainerRequest) (*pb.StatusResponse, error) {
	c, err := clientFor(r.Profile, "", false)
	if err != nil { return ok("", err) }
	return ok("disconnected", c.DisconnectNetwork(r.NetworkId, r.ContainerId))
}
func (s *DockerServer) PruneNetworks(_ context.Context, r *pb.DockerScope) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil { return &pb.JsonResponse{Error: err.Error()}, nil }
	return jsonResp(c.PruneNetworks())
}

// --- Streams ---

func streamLines(path string, profile, host string, wsl2 bool, send func(*pb.JsonResponse) error) error {
	c, err := clientFor(profile, host, wsl2)
	if err != nil {
		return send(&pb.JsonResponse{Error: err.Error()})
	}
	body, err := c.StreamPath(path)
	if err != nil {
		return send(&pb.JsonResponse{Error: err.Error()})
	}
	defer body.Close()
	sc := bufio.NewScanner(body)
	sc.Buffer(make([]byte, 0, 1024*1024), 4*1024*1024)
	for sc.Scan() {
		if err := send(&pb.JsonResponse{Json: sc.Text()}); err != nil {
			return err
		}
	}
	return sc.Err()
}

func (s *DockerServer) StreamEvents(r *pb.DockerScope, stream pb.DockerService_StreamEventsServer) error {
	return streamLines("/events", r.Profile, r.Host, r.Wsl2, stream.Send)
}
func (s *DockerServer) StreamLogs(r *pb.IdRequest, stream pb.DockerService_StreamLogsServer) error {
	return streamLines("/containers/"+r.Id+"/logs?follow=1&stdout=1&stderr=1&tail=100", r.Profile, r.Host, r.Wsl2, stream.Send)
}
func (s *DockerServer) StreamStats(r *pb.IdRequest, stream pb.DockerService_StreamStatsServer) error {
	return streamLines("/containers/"+r.Id+"/stats?stream=1", r.Profile, r.Host, r.Wsl2, stream.Send)
}
