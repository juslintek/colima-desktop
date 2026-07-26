// Package action contains the typed requests shared by the TUI model and its
// daemon client. Keeping this small boundary makes the Bubble Tea state
// machine deterministic in tests while the live client still maps every
// request to the shared protobuf contract.
package action

import (
	"context"

	pb "github.com/colima-desktop/daemon/proto"
)

// Kind identifies one user-visible operation.
type Kind string

const (
	VMStart           Kind = "vm.start"
	VMStop            Kind = "vm.stop"
	VMRestart         Kind = "vm.restart"
	VMDelete          Kind = "vm.delete"
	VMUpdate          Kind = "vm.update"
	VMPrune           Kind = "vm.prune"
	VMSSHConfig       Kind = "vm.ssh-config"
	ContainerDo       Kind = "container.action"
	ContainerNew      Kind = "container.create"
	ContainerName     Kind = "container.rename"
	ContainerLogs     Kind = "container.logs"
	ContainerInfo     Kind = "container.inspect"
	ContainerTop      Kind = "container.top"
	ContainerStat     Kind = "container.stats"
	ContainerDiff     Kind = "container.changes"
	ContainerPrune    Kind = "container.prune"
	ImagePull         Kind = "image.pull"
	ImagePush         Kind = "image.push"
	ImageRemove       Kind = "image.remove"
	ImageTag          Kind = "image.tag"
	ImageSearch       Kind = "image.search"
	ImageHistory      Kind = "image.history"
	ImageInspect      Kind = "image.inspect"
	ImagePrune        Kind = "image.prune"
	VolumeCreate      Kind = "volume.create"
	VolumeRemove      Kind = "volume.remove"
	VolumeInspect     Kind = "volume.inspect"
	VolumePrune       Kind = "volume.prune"
	NetworkCreate     Kind = "network.create"
	NetworkRemove     Kind = "network.remove"
	NetworkInspect    Kind = "network.inspect"
	NetworkConnect    Kind = "network.connect"
	NetworkDisconnect Kind = "network.disconnect"
	NetworkPrune      Kind = "network.prune"
	KubeStart         Kind = "kubernetes.start"
	KubeStop          Kind = "kubernetes.stop"
	KubeReset         Kind = "kubernetes.reset"
	KubeExec          Kind = "kubernetes.exec"
	ProfileCreate     Kind = "profile.create"
	ProfileDelete     Kind = "profile.delete"
	ProfileClone      Kind = "profile.clone"
	ConfigSet         Kind = "config.set"
	TemplateSet       Kind = "template.set"
	RuntimeSwitch     Kind = "runtime.switch"
	RuntimeUpdate     Kind = "runtime.update"
	ModelSetup        Kind = "model.setup"
	ModelRun          Kind = "model.run"
	ModelServe        Kind = "model.serve"
	ModelStop         Kind = "model.stop"
	ProcessKill       Kind = "process.kill"
)

// Request carries only values represented by the protobuf schema.
// Fields that are not meaningful to a Kind are left at their zero value.
type Request struct {
	Kind        Kind
	Profile     string
	Host        string
	WSL2        bool
	ID          string
	Name        string
	NewName     string
	Action      string
	Source      string
	Target      string
	Repository  string
	Tag         string
	Term        string
	ContainerID string
	Command     string
	Runtime     string
	Runner      string
	Model       string
	Prompt      string
	Port        int32
	PID         int32
	Signal      int32
	Force       bool
	Data        bool
	All         bool
	Config      *pb.ColimaConfig
}

// Result is the daemon-confirmed output of a unary RPC.
type Result struct {
	Text string
}

// ProgressStream is implemented by generated gRPC streaming clients and test
// fakes. Recv must unblock when the context passed to OpenProgress is canceled.
type ProgressStream interface {
	Recv() (*pb.ProgressEvent, error)
}

// Runner is the action portion of the TUI data source.
type Runner interface {
	RunAction(context.Context, Request) (Result, error)
	OpenProgress(context.Context, Request) (ProgressStream, error)
}
