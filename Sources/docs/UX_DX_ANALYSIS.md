# UX/DX Analysis: Kubernetes, AI Workloads, Monitoring, Runtime Controls, Community

## Kubernetes — Current Problems

1. **Static data** — "12 pods", "1 node" are hardcoded text, not interactive. A real k8s view should show actual resource lists.
2. **"Quick Actions" are just toast buttons** — Get Pods/Services/All should show actual output in a table or sheet, not a toast.
3. **No namespace awareness** — k8s is namespace-scoped, there's no namespace selector.
4. **No resource detail** — Can't click a pod to see its status, logs, or events.
5. **No visual hierarchy** — Everything is flat GroupBoxes. Pods, Services, Deployments are fundamentally different resource types.
6. **Missing workload management** — Can't delete a pod, scale a deployment, or view events.

**Fix:** Tabbed resource browser (Pods/Services/Deployments/Nodes) with mock resource lists, namespace picker, per-resource actions (logs, describe, delete), events timeline.

## AI Workloads — Current Problems

1. **No model library** — Just a text field. Users don't know what models are available.
2. **Run/Serve are toasts** — Should show actual model status (downloading, running, serving).
3. **No model management** — Can't see downloaded models, their sizes, or delete them.
4. **Registry info is just text** — Should be browsable with model cards.
5. **Resource recommendations are disconnected** — Should auto-warn if current VM doesn't have enough RAM for selected model.
6. **No serving status** — When a model is being served, should show the URL, port, and a stop button.

**Fix:** Model library with browsable cards, download progress, running model status panel, serve URL display, resource validation against current VM config.

## Monitoring — Current Problems

1. **All data is static** — Progress bars are hardcoded (0.35, 0.62, 0.45). Should reflect mock state.
2. **Kill Process has no target** — Button exists but doesn't know which process to kill. Need selection.
3. **Container stats don't match actual containers** — Hardcoded "web-server", "postgres-db" instead of reading from appState.containers.
4. **No time dimension** — Real monitoring shows trends. At minimum, show "last updated" timestamps.
5. **Memory Governor is passive** — Shows tier but no explanation of what each tier means or what's being throttled.
6. **Process list isn't selectable** — Can't click a process to kill it.

**Fix:** Dynamic stats from appState.containers, selectable process list with kill confirmation, governor explanation panel, live-updating timestamps, summary cards that reflect actual container states.

## Runtime Controls — Current Problems

1. **nerdctl/incus are just text fields** — No guidance on what commands are available. Users need to already know the CLI.
2. **Docker Context section is trivial** — Just shows current context with a switch button.
3. **Runtime Switching is dangerous with no info** — Should explain what happens (VM restart, data implications).
4. **Data Persistence section is just text** — Should be interactive, showing actual data sizes per runtime.
5. **No runtime status** — Doesn't show which runtime is currently active or its version.
6. **No socket info** — Docker socket path is critical for debugging, not shown.

**Fix:** Current runtime status card with version/socket, command palette with categorized common commands and autocomplete, runtime comparison table, switching wizard with data impact warning, socket path with copy button.

## Community — Current Problems

1. **Links are just toast buttons** — Should actually open URLs in browser.
2. **Issue wizard is clunky** — 3 steps for what should be 1 form. Step 1 (pick repo) is unnecessary friction.
3. **No system info auto-collection** — Real issue reporters need colima version, macOS version, VM type, runtime. Should auto-fill.
4. **FAQ is a flat list** — No categories, no search, no expand/collapse. Hard to scan.
5. **No discussions feed** — Was supposed to show recent GitHub discussions, just has a link.
6. **Submit doesn't open GitHub** — Should construct a pre-filled GitHub issue URL and open browser.

**Fix:** Real URL opening, single-form issue reporter with auto-collected system info and GitHub URL construction, categorized searchable FAQ with expand/collapse, mock discussions feed with titles/dates/reactions.
