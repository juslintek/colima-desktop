package server

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"strings"

	"github.com/colima-desktop/daemon/internal/docker"
	pb "github.com/colima-desktop/daemon/proto"
)

// DockerServer implements the generated pb.DockerServiceServer by delegating to
// the docker.Client for the requested target (local / remote-SSH / WSL2).
type DockerServer struct {
	pb.UnimplementedDockerServiceServer
	imageClientFactory imageClientFactory
}

type imageClient interface {
	PullImage(context.Context, string) (io.ReadCloser, error)
	PushImage(context.Context, string) (io.ReadCloser, error)
	CloseIdleConnections()
}

type imageClientFactory func(docker.Target) (imageClient, error)

func NewDocker() *DockerServer {
	return &DockerServer{
		imageClientFactory: func(target docker.Target) (imageClient, error) {
			return docker.New(target)
		},
	}
}

func clientFor(profile, host string, wsl2 bool) (*docker.Client, error) {
	return docker.New(docker.Target{Profile: profile, Host: host, WSL2: wsl2})
}

// mutatingClientFor builds a docker client for a mutating request, first
// rejecting requests that omit the profile/provider scope required for safe
// targeting (Requirement 3.5; design Property 11). Without a profile (and
// outside WSL2) the client would fall back to the default profile's docker.sock
// and silently mutate whatever engine answers there. Read-only handlers use
// clientFor directly and keep the documented default-profile fallback.
func mutatingClientFor(profile, host string, wsl2 bool) (*docker.Client, error) {
	if err := requireDockerScope(profile, wsl2); err != nil {
		return nil, err
	}
	return clientFor(profile, host, wsl2)
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
	c, err := mutatingClientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil {
		return ok("", err)
	}
	return ok(r.Action, c.ContainerAction(r.Id, r.Action))
}
func (s *DockerServer) CreateContainer(_ context.Context, r *pb.CreateContainerRequest) (*pb.JsonResponse, error) {
	c, err := mutatingClientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil {
		return &pb.JsonResponse{Error: err.Error()}, nil
	}
	return jsonResp(c.CreateContainer(r.Name, r.Image))
}
func (s *DockerServer) RenameContainer(_ context.Context, r *pb.RenameRequest) (*pb.StatusResponse, error) {
	c, err := mutatingClientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil {
		return ok("", err)
	}
	return ok("renamed", c.RenameContainer(r.Id, r.NewName))
}
func (s *DockerServer) ContainerLogs(_ context.Context, r *pb.IdRequest) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil {
		return &pb.JsonResponse{Error: err.Error()}, nil
	}
	return jsonResp(c.ContainerLogs(r.Id))
}
func (s *DockerServer) InspectContainer(_ context.Context, r *pb.IdRequest) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil {
		return &pb.JsonResponse{Error: err.Error()}, nil
	}
	return jsonResp(c.InspectContainer(r.Id))
}
func (s *DockerServer) ContainerTop(_ context.Context, r *pb.IdRequest) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil {
		return &pb.JsonResponse{Error: err.Error()}, nil
	}
	return jsonResp(c.ContainerTop(r.Id))
}
func (s *DockerServer) ContainerStats(_ context.Context, r *pb.IdRequest) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil {
		return &pb.JsonResponse{Error: err.Error()}, nil
	}
	return jsonResp(c.ContainerStats(r.Id))
}
func (s *DockerServer) ContainerChanges(_ context.Context, r *pb.IdRequest) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil {
		return &pb.JsonResponse{Error: err.Error()}, nil
	}
	return jsonResp(c.ContainerChanges(r.Id))
}
func (s *DockerServer) PruneContainers(_ context.Context, r *pb.DockerScope) (*pb.JsonResponse, error) {
	c, err := mutatingClientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil {
		return &pb.JsonResponse{Error: err.Error()}, nil
	}
	return jsonResp(c.PruneContainers())
}

// --- Images ---

func (s *DockerServer) ListImages(_ context.Context, r *pb.DockerScope) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil {
		return &pb.JsonResponse{Error: err.Error()}, nil
	}
	return jsonResp(c.ListImages())
}
func (s *DockerServer) RemoveImage(_ context.Context, r *pb.IdRequest) (*pb.StatusResponse, error) {
	c, err := mutatingClientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil {
		return ok("", err)
	}
	return ok("removed", c.RemoveImage(r.Id))
}
func (s *DockerServer) InspectImage(_ context.Context, r *pb.NameRequest) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil {
		return &pb.JsonResponse{Error: err.Error()}, nil
	}
	return jsonResp(c.InspectImage(r.Name))
}
func (s *DockerServer) ImageHistory(_ context.Context, r *pb.NameRequest) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil {
		return &pb.JsonResponse{Error: err.Error()}, nil
	}
	return jsonResp(c.ImageHistory(r.Name))
}
func (s *DockerServer) TagImage(_ context.Context, r *pb.TagRequest) (*pb.StatusResponse, error) {
	c, err := mutatingClientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil {
		return ok("", err)
	}
	return ok("tagged", c.TagImage(r.Name, r.Repo, r.Tag))
}
func (s *DockerServer) SearchImages(_ context.Context, r *pb.SearchRequest) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil {
		return &pb.JsonResponse{Error: err.Error()}, nil
	}
	return jsonResp(c.SearchImages(r.Term))
}
func (s *DockerServer) PruneImages(_ context.Context, r *pb.DockerScope) (*pb.JsonResponse, error) {
	c, err := mutatingClientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil {
		return &pb.JsonResponse{Error: err.Error()}, nil
	}
	return jsonResp(c.PruneImages())
}

type dockerProgress struct {
	Status         string          `json:"status"`
	ID             string          `json:"id"`
	Progress       string          `json:"progress"`
	ProgressDetail progressDetail  `json:"progressDetail"`
	Error          string          `json:"error"`
	ErrorDetail    dockerError     `json:"errorDetail"`
	Aux            json.RawMessage `json:"aux"`
}

type progressDetail struct {
	Current int64 `json:"current"`
	Total   int64 `json:"total"`
}

type dockerError struct {
	Message string `json:"message"`
}

func (s *DockerServer) newImageClient(target docker.Target) (imageClient, error) {
	if s.imageClientFactory != nil {
		return s.imageClientFactory(target)
	}
	// Preserve a useful zero value for tests and alternate embedders while the
	// public constructor remains the normal production path.
	return docker.New(target)
}

func imageProgressValue(detail progressDetail) float32 {
	if detail.Total <= 0 {
		return 0
	}
	progress := float64(detail.Current) / float64(detail.Total)
	if progress < 0 {
		return 0
	}
	if progress > 1 {
		return 1
	}
	return float32(progress)
}

func imageProgressMessage(progress dockerProgress) string {
	parts := make([]string, 0, 3)
	if progress.ID != "" {
		parts = append(parts, progress.ID+":")
	}
	if progress.Status != "" {
		parts = append(parts, progress.Status)
	}
	if progress.Progress != "" {
		parts = append(parts, progress.Progress)
	}
	if len(parts) == 0 && len(progress.Aux) > 0 && string(progress.Aux) != "null" {
		parts = append(parts, string(progress.Aux))
	}
	return strings.Join(parts, " ")
}

func sendImageError(stage string, err error, send func(*pb.ProgressEvent) error) error {
	return send(&pb.ProgressEvent{
		Stage:   stage,
		Message: err.Error(),
		Done:    true,
		Error:   err.Error(),
	})
}

func streamImageProgress(
	ctx context.Context,
	stage string,
	name string,
	body io.Reader,
	send func(*pb.ProgressEvent) error,
) error {
	if err := send(&pb.ProgressEvent{Stage: stage, Message: fmt.Sprintf("%s %s", stage, name)}); err != nil {
		return err
	}

	decoder := json.NewDecoder(body)
	for {
		var progress dockerProgress
		err := decoder.Decode(&progress)
		if err == io.EOF {
			break
		}
		if err != nil {
			if ctxErr := ctx.Err(); ctxErr != nil {
				return ctxErr
			}
			return sendImageError(stage, fmt.Errorf("decode docker %s progress: %w", stage, err), send)
		}
		if ctxErr := ctx.Err(); ctxErr != nil {
			return ctxErr
		}

		dockerErr := progress.ErrorDetail.Message
		if dockerErr == "" {
			dockerErr = progress.Error
		}
		if dockerErr != "" {
			return sendImageError(stage, fmt.Errorf("docker %s failed: %s", stage, dockerErr), send)
		}

		if err := send(&pb.ProgressEvent{
			Stage:    stage,
			Message:  imageProgressMessage(progress),
			Progress: imageProgressValue(progress.ProgressDetail),
		}); err != nil {
			return err
		}
	}

	if ctxErr := ctx.Err(); ctxErr != nil {
		return ctxErr
	}
	return send(&pb.ProgressEvent{
		Stage:    stage,
		Message:  fmt.Sprintf("%s complete", stage),
		Progress: 1,
		Done:     true,
	})
}

func (s *DockerServer) PullImage(r *pb.NameRequest, stream pb.DockerService_PullImageServer) error {
	const stage = "image-pull"
	if err := requireDockerScope(r.Profile, r.Wsl2); err != nil {
		return sendImageError(stage, err, stream.Send)
	}
	client, err := s.newImageClient(docker.Target{Profile: r.Profile, Host: r.Host, WSL2: r.Wsl2})
	if err != nil {
		return sendImageError(stage, fmt.Errorf("create docker provider: %w", err), stream.Send)
	}
	defer client.CloseIdleConnections()

	body, err := client.PullImage(stream.Context(), r.Name)
	if err != nil {
		if ctxErr := stream.Context().Err(); ctxErr != nil {
			return ctxErr
		}
		return sendImageError(stage, err, stream.Send)
	}
	defer body.Close()
	return streamImageProgress(stream.Context(), stage, r.Name, body, stream.Send)
}

func (s *DockerServer) PushImage(r *pb.NameRequest, stream pb.DockerService_PushImageServer) error {
	const stage = "image-push"
	if err := requireDockerScope(r.Profile, r.Wsl2); err != nil {
		return sendImageError(stage, err, stream.Send)
	}
	client, err := s.newImageClient(docker.Target{Profile: r.Profile, Host: r.Host, WSL2: r.Wsl2})
	if err != nil {
		return sendImageError(stage, fmt.Errorf("create docker provider: %w", err), stream.Send)
	}
	defer client.CloseIdleConnections()

	body, err := client.PushImage(stream.Context(), r.Name)
	if err != nil {
		if ctxErr := stream.Context().Err(); ctxErr != nil {
			return ctxErr
		}
		return sendImageError(stage, err, stream.Send)
	}
	defer body.Close()
	return streamImageProgress(stream.Context(), stage, r.Name, body, stream.Send)
}

// --- Volumes ---

func (s *DockerServer) ListVolumes(_ context.Context, r *pb.DockerScope) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil {
		return &pb.JsonResponse{Error: err.Error()}, nil
	}
	return jsonResp(c.ListVolumes())
}
func (s *DockerServer) CreateVolume(_ context.Context, r *pb.NameRequest) (*pb.JsonResponse, error) {
	c, err := mutatingClientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil {
		return &pb.JsonResponse{Error: err.Error()}, nil
	}
	return jsonResp(c.CreateVolume(r.Name))
}
func (s *DockerServer) RemoveVolume(_ context.Context, r *pb.NameRequest) (*pb.StatusResponse, error) {
	c, err := mutatingClientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil {
		return ok("", err)
	}
	return ok("removed", c.RemoveVolume(r.Name))
}
func (s *DockerServer) InspectVolume(_ context.Context, r *pb.NameRequest) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil {
		return &pb.JsonResponse{Error: err.Error()}, nil
	}
	return jsonResp(c.InspectVolume(r.Name))
}
func (s *DockerServer) PruneVolumes(_ context.Context, r *pb.DockerScope) (*pb.JsonResponse, error) {
	c, err := mutatingClientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil {
		return &pb.JsonResponse{Error: err.Error()}, nil
	}
	return jsonResp(c.PruneVolumes())
}

// --- Networks ---

func (s *DockerServer) ListNetworks(_ context.Context, r *pb.DockerScope) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil {
		return &pb.JsonResponse{Error: err.Error()}, nil
	}
	return jsonResp(c.ListNetworks())
}
func (s *DockerServer) CreateNetwork(_ context.Context, r *pb.NameRequest) (*pb.JsonResponse, error) {
	c, err := mutatingClientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil {
		return &pb.JsonResponse{Error: err.Error()}, nil
	}
	return jsonResp(c.CreateNetwork(r.Name))
}
func (s *DockerServer) RemoveNetwork(_ context.Context, r *pb.IdRequest) (*pb.StatusResponse, error) {
	c, err := mutatingClientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil {
		return ok("", err)
	}
	return ok("removed", c.RemoveNetwork(r.Id))
}
func (s *DockerServer) InspectNetwork(_ context.Context, r *pb.IdRequest) (*pb.JsonResponse, error) {
	c, err := clientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil {
		return &pb.JsonResponse{Error: err.Error()}, nil
	}
	return jsonResp(c.InspectNetwork(r.Id))
}
func (s *DockerServer) ConnectNetwork(_ context.Context, r *pb.NetworkContainerRequest) (*pb.StatusResponse, error) {
	c, err := mutatingClientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil {
		return ok("", err)
	}
	return ok("connected", c.ConnectNetwork(r.NetworkId, r.ContainerId))
}
func (s *DockerServer) DisconnectNetwork(_ context.Context, r *pb.NetworkContainerRequest) (*pb.StatusResponse, error) {
	c, err := mutatingClientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil {
		return ok("", err)
	}
	return ok("disconnected", c.DisconnectNetwork(r.NetworkId, r.ContainerId))
}
func (s *DockerServer) PruneNetworks(_ context.Context, r *pb.DockerScope) (*pb.JsonResponse, error) {
	c, err := mutatingClientFor(r.Profile, r.Host, r.Wsl2)
	if err != nil {
		return &pb.JsonResponse{Error: err.Error()}, nil
	}
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
