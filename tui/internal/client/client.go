// Package client wraps the colima-desktop daemon gRPC services for the TUI.
package client

import (
	"context"
	"time"

	pb "github.com/colima-desktop/daemon/proto"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

// Client connects to the local daemon over its unix socket and exposes the
// ColimaService + DockerService contracts.
type Client struct {
	conn   *grpc.ClientConn
	Colima pb.ColimaServiceClient
	Docker pb.DockerServiceClient
}

// Dial connects to the daemon at the given unix socket path.
func Dial(socket string) (*Client, error) {
	conn, err := grpc.NewClient(
		"unix://"+socket,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)
	if err != nil {
		return nil, err
	}
	return &Client{
		conn:   conn,
		Colima: pb.NewColimaServiceClient(conn),
		Docker: pb.NewDockerServiceClient(conn),
	}, nil
}

// Close releases the gRPC connection.
func (c *Client) Close() error { return c.conn.Close() }

func ctx() (context.Context, context.CancelFunc) {
	return context.WithTimeout(context.Background(), 15*time.Second)
}

// ─── ColimaService methods ───────────────────────────────────────────────────

// Status returns the current VM status for the profile.
func (c *Client) Status(profile string) (*pb.VMStatus, error) {
	cx, cancel := ctx()
	defer cancel()
	return c.Colima.Status(cx, &pb.StatusRequest{Profile: profile})
}

// Profiles lists all colima profiles.
func (c *Client) Profiles() (*pb.ProfileList, error) {
	cx, cancel := ctx()
	defer cancel()
	return c.Colima.ListProfiles(cx, &pb.Empty{})
}

// Machines lists Lima VMs.
func (c *Client) Machines() (*pb.MachineList, error) {
	cx, cancel := ctx()
	defer cancel()
	return c.Colima.ListMachines(cx, &pb.Empty{})
}

// GetConfig fetches the colima configuration for a profile.
func (c *Client) GetConfig(profile string) (*pb.ColimaConfig, error) {
	cx, cancel := ctx()
	defer cancel()
	return c.Colima.GetConfig(cx, &pb.ProfileRequest{Profile: profile})
}

// KubernetesStatus returns the VM status (which includes the kubernetes field)
// for the given profile — used to display Kubernetes state.
func (c *Client) KubernetesStatus(profile string) (*pb.VMStatus, error) {
	cx, cancel := ctx()
	defer cancel()
	return c.Colima.Status(cx, &pb.StatusRequest{Profile: profile})
}

// ─── DockerService methods ───────────────────────────────────────────────────

// Containers returns raw Docker JSON for the profile.
func (c *Client) Containers(profile string) (string, error) {
	cx, cancel := ctx()
	defer cancel()
	r, err := c.Docker.ListContainers(cx, &pb.DockerScope{Profile: profile, All: true})
	if err != nil {
		return "", err
	}
	if r.Error != "" {
		return "", &apiError{r.Error}
	}
	return r.Json, nil
}

// Images returns raw Docker JSON for the profile.
func (c *Client) Images(profile string) (string, error) {
	cx, cancel := ctx()
	defer cancel()
	r, err := c.Docker.ListImages(cx, &pb.DockerScope{Profile: profile})
	if err != nil {
		return "", err
	}
	if r.Error != "" {
		return "", &apiError{r.Error}
	}
	return r.Json, nil
}

// Volumes returns raw Docker JSON for volumes in the profile.
func (c *Client) Volumes(profile string) (string, error) {
	cx, cancel := ctx()
	defer cancel()
	r, err := c.Docker.ListVolumes(cx, &pb.DockerScope{Profile: profile})
	if err != nil {
		return "", err
	}
	if r.Error != "" {
		return "", &apiError{r.Error}
	}
	return r.Json, nil
}

// Networks returns raw Docker JSON for networks in the profile.
func (c *Client) Networks(profile string) (string, error) {
	cx, cancel := ctx()
	defer cancel()
	r, err := c.Docker.ListNetworks(cx, &pb.DockerScope{Profile: profile})
	if err != nil {
		return "", err
	}
	if r.Error != "" {
		return "", &apiError{r.Error}
	}
	return r.Json, nil
}

type apiError struct{ msg string }

func (e *apiError) Error() string { return e.msg }
