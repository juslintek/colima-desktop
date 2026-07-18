// Package ui — tab definitions matching the frozen CONTRACT surfaces.
package ui

// Tab indices — keep in sync with Tabs slice below.
const (
	TabDashboard  = 0
	TabContainers = 1
	TabImages     = 2
	TabVolumes    = 3
	TabNetworks   = 4
	TabKubernetes = 5
	TabConfig     = 6
	TabRuntime    = 7
	TabAI         = 8
	TabProfiles   = 9
	TabMachines   = 10
	TabMonitoring = 11
)

// Tabs is the ordered list of surface names shown in the header bar.
// Mirrors CONTRACT Part A+B: Dashboard · Containers · Images · Volumes · Networks ·
// Kubernetes · Configuration · Runtime · AI Workloads · Profiles · Machines · Monitoring
var Tabs = []string{
	"Dashboard",
	"Containers",
	"Images",
	"Volumes",
	"Networks",
	"Kubernetes",
	"Configuration",
	"Runtime",
	"AI Workloads",
	"Profiles",
	"Machines",
	"Monitoring",
}
