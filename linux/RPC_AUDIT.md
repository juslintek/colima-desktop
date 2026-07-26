# Linux (GTK4) frozen-v1 RPC audit

Audited 2026-07-21 against `linux/proto/colima_ui.proto` and the full `linux/src/**` tree:
**65/65 RPCs are invoked from a concrete GTK callback through a generated tonic client method**
(31 `ColimaService` + 34 `DockerService`). Every row below was checked against source — no
estimates. This is source-level evidence; native GTK4 compilation and live AT-SPI proof run on the
authoritative `linux-gtk4` CI job, not on the macOS audit host.

## How the Linux frontend calls the daemon

- **Generated client:** `linux/src/client.rs` exposes `DaemonClient { colima: ColimaServiceClient<Channel>, docker: DockerServiceClient<Channel> }` built from `tonic::include_proto!("colimaui")`. tonic generates snake_case async methods from the proto RPC names (`Start` → `colima.start`, `ListContainers` → `docker.list_containers`, etc.). The table's "tonic client method" column names the exact generated method invoked in source.
- **GLib main context (Requirement 6.5):** every callback follows one pattern — the GTK signal (`connect_clicked` / `connect_row_selected` / `glib::timeout_add_seconds_local`) fires on the GLib main thread; it snapshots plain `Send` data (`h.profile()`, `h.docker_target()`) and clones the tonic client (`client.colima.clone()` / `client.docker` — a `tonic` `Channel` is cheaply cloneable and `Send`); async work runs on the Tokio runtime via `handle.rt.spawn(async move { … })`; results are sent back as **plain `Send` data** over `async_channel`; the receiver runs in `glib::spawn_future_local(async move { … })`, which executes on the GLib main context, and **only there** are the `!Send` GTK widgets mutated. No GTK widget is ever touched off the main context.
- **Profile / provider scope (v1.1):**
  - **ColimaService** RPCs are scoped by the active profile via `h.profile()`, packed into `ProfileRequest { profile }` (or the RPC's specific request that carries a `profile`/`name`). Per the approved v1.1 additive correction, `Update` takes `ProfileRequest` and `Prune` takes `PruneRequest { all, profile }` — both profile-scoped, not global.
  - **DockerService** RPCs snapshot the full provider target once via `h.docker_target()` → `DockerTarget { profile, host, wsl2 }` (`linux/src/app_state.rs`), then build the request through the target's builders (`scope`, `id_request`, `name_request`, `container_action`, `create_container`, `rename_request`, `tag_request`, `search_request`, `network_request`). Every Docker request — including `RenameRequest`/`TagRequest`/`SearchRequest`/`NetworkContainerRequest` — carries `profile` + `host` + `wsl2` (v1.1 scope fields present in `linux/proto/colima_ui.proto`; propagation asserted by the `request_builders_propagate_the_complete_provider_scope` unit test). The active profile is switched atomically from the Profiles surface (`h.select_profile`).
- **Destructive confirmation (Requirement 6.6, Property 13):** destructive callbacks route through `confirm_destructive` (`linux/src/ui_helpers.rs`) — a modal `OkCancel` dialog that invokes the RPC-issuing closure **only** on `ResponseType::Ok`; Cancel/dismiss issues no RPC.
- **Cancellation + bounded output (Requirement 6.3, Property 14):** streaming callbacks store a `tokio::task::AbortHandle` in an `Rc<RefCell<Option<…>>>` and expose an explicit Cancel button; text sinks drain to a bounded length (`log.drain(..50_000)` once past `100_000` chars); `VMStats` uses a bounded single-sample poll (open stream → read one message → drop).

---

## ColimaService (31/31)

Active profile comes from `h.profile()`. Streaming RPCs read `ProgressEvent`s in the Tokio task and
marshal text to the UI over `async_channel`.

| # | RPC | tonic client method | GTK callback (widget id · signal) | Source | Request / scope · behavior |
|---|-----|---------------------|-----------------------------------|--------|----------------------------|
| 1 | Start | `colima.start` | `dashboard_btn_start` · clicked | dashboard.rs | `StartRequest{profile, config:None}` · server-stream; log bounded |
| 2 | Stop | `colima.stop` | `dashboard_btn_stop` · clicked | dashboard.rs | `StopRequest{profile, force:false}` · `StatusResponse` |
| 3 | Restart | `colima.restart` | `dashboard_btn_restart` · clicked | dashboard.rs | `RestartRequest{profile}` · server-stream |
| 4 | Delete | `colima.delete` | `dashboard_btn_delete` · clicked | dashboard.rs | `DeleteRequest{profile}` · **confirm_destructive** |
| 5 | Status | `colima.status` | `dashboard_btn_refresh` · clicked | dashboard.rs | `StatusRequest{profile, extended:true}` |
| 6 | Version | `colima.version` | `dashboard_btn_refresh` · clicked | dashboard.rs | `Empty` · fetched alongside Status |
| 7 | Update | `colima.update` | `dashboard_btn_update` · clicked | dashboard.rs | `ProfileRequest{profile}` (v1.1) · **confirm_destructive** |
| 8 | Prune | `colima.prune` | `dashboard_btn_prune` · clicked | dashboard.rs | `PruneRequest{all:false, profile}` (v1.1) · **confirm_destructive** |
| 9 | SSHConfig | `colima.ssh_config` | `profiles_btn_ssh` · clicked | profiles.rs | `ProfileRequest{profile=selected}` |
| 10 | ListProfiles | `colima.list_profiles` | `profiles_btn_refresh` · clicked | profiles.rs | `Empty` · populates list |
| 11 | ListMachines | `colima.list_machines` | `machines_btn_refresh` · clicked | machines.rs | `Empty` · Lima machine list |
| 12 | CreateProfile | `colima.create_profile` | `profiles_btn_create` · clicked | profiles.rs | `CreateProfileRequest{name, config:None}` |
| 13 | DeleteProfile | `colima.delete_profile` | `profiles_btn_delete` · clicked | profiles.rs | `DeleteProfileRequest{name=selected}` · **confirm_destructive** |
| 14 | CloneProfile | `colima.clone_profile` | `profiles_btn_clone` · clicked | profiles.rs | `CloneProfileRequest{source=selected, destination}` |
| 15 | GetConfig | `colima.get_config` | `config_btn_load` · clicked | configuration.rs | `ProfileRequest{profile}` · fills fields |
| 16 | SetConfig | `colima.set_config` | `config_btn_save` · clicked | configuration.rs | `SetConfigRequest{profile, config}` |
| 17 | GetTemplate | `colima.get_template` | `config_btn_load_tpl` · clicked | configuration.rs | `Empty` · loads template into editor |
| 18 | SetTemplate | `colima.set_template` | `config_btn_save_tpl` · clicked | configuration.rs | `ColimaConfig{…}` from editor fields |
| 19 | KubernetesStart | `colima.kubernetes_start` | `kubernetes_btn_start` · clicked | kubernetes.rs | `ProfileRequest{profile}` (wire_k8s! macro) |
| 20 | KubernetesStop | `colima.kubernetes_stop` | `kubernetes_btn_stop` · clicked | kubernetes.rs | `ProfileRequest{profile}` (wire_k8s! macro) |
| 21 | KubernetesReset | `colima.kubernetes_reset` | `kubernetes_btn_reset` · clicked | kubernetes.rs | `ProfileRequest{profile}` · **confirm_destructive** |
| 22 | KubernetesExec | `colima.kubernetes_exec` | `kubernetes_btn_exec` · clicked | kubernetes.rs | `KubeExecRequest{profile, command}` · non-zero exit surfaced |
| 23 | ModelSetup | `colima.model_setup` | `ai_btn_setup` · clicked | ai_workloads.rs | `ModelRequest{profile, runner}` · server-stream |
| 24 | ModelRun | `colima.model_run` | `ai_btn_run` · clicked | ai_workloads.rs | `ModelRunRequest{profile, model, runner, prompt}` · server-stream |
| 25 | ModelServe | `colima.model_serve` | `ai_btn_serve` · clicked | ai_workloads.rs | `ModelServeRequest{profile, model, runner, port}` |
| 26 | ModelStop | `colima.model_stop` | `ai_btn_stop` · clicked | ai_workloads.rs | `ProfileRequest{profile}` |
| 27 | SwitchRuntime | `colima.switch_runtime` | `runtime_btn_switch` · clicked | runtime.rs | `SwitchRuntimeRequest{profile, runtime}` · **confirm_destructive** |
| 28 | UpdateRuntime | `colima.update_runtime` | `runtime_btn_update` · clicked | runtime.rs | `ProfileRequest{profile}` |
| 29 | VMStats | `colima.vm_stats` | `monitoring_btn_refresh` · clicked **and** 3 s `timeout_add_seconds_local` poll | monitoring.rs | `ProfileRequest{profile}` · server-stream read as bounded single-sample poll (read 1 → drop) |
| 30 | ProcessList | `colima.process_list` | `monitoring_btn_refresh` · clicked (`do_refresh`) | monitoring.rs | `ProfileRequest{profile}` |
| 31 | KillProcess | `colima.kill_process` | `monitoring_btn_kill` · clicked | monitoring.rs | `KillProcessRequest{profile, pid, signal}` · **confirm_destructive** |

## DockerService (34/34)

Every request is built from one immutable `h.docker_target()` snapshot (`DockerTarget{profile, host,
wsl2}`) via the `app_state.rs` request builders, so `profile` + `host` + `wsl2` (v1.1 scope) travel
with each call. `JsonResponse.error` / unsuccessful `StatusResponse` are converted to visible errors
in the output view before any success is shown.

| # | RPC | tonic client method | GTK callback (widget id · signal) | Source | Request builder / scope · behavior |
|---|-----|---------------------|-----------------------------------|--------|-------------------------------------|
| 1 | ListContainers | `docker.list_containers` | `containers_btn_refresh` · clicked | containers.rs | `target.scope(all:true)` |
| 2 | ContainerAction | `docker.container_action` | `containers_btn_{start,stop,kill,restart,pause,resume,remove}` · clicked (wire_action!) | containers.rs | `target.container_action(id, action)` · **kill/remove confirm_destructive** |
| 3 | CreateContainer | `docker.create_container` | `containers_btn_create` · clicked | containers.rs | `target.create_container(name, image)` |
| 4 | RenameContainer | `docker.rename_container` | `containers_btn_rename` · clicked | containers.rs | `target.rename_request(id, new_name)` (host/wsl2 v1.1) |
| 5 | ContainerLogs | `docker.container_logs` | `containers_btn_logs` · clicked | containers.rs | `target.id_request(id)` |
| 6 | InspectContainer | `docker.inspect_container` | `containers_btn_inspect` · clicked | containers.rs | `target.id_request(id)` |
| 7 | ContainerTop | `docker.container_top` | `containers_btn_top` · clicked (wire_query!) | containers.rs | `target.id_request(id)` |
| 8 | ContainerStats | `docker.container_stats` | `containers_btn_stats` · clicked (wire_query!) | containers.rs | `target.id_request(id)` |
| 9 | ContainerChanges | `docker.container_changes` | `containers_btn_changes` · clicked (wire_query!) | containers.rs | `target.id_request(id)` |
| 10 | PruneContainers | `docker.prune_containers` | `containers_btn_prune` · clicked | containers.rs | `target.scope(false)` · **confirm_destructive** |
| 11 | ListImages | `docker.list_images` | `images_btn_refresh` · clicked | images.rs | `target.scope(false)` |
| 12 | PullImage | `docker.pull_image` | `images_btn_pull` · clicked | images.rs | `target.name_request(name)` · server-stream; AbortHandle + `images_btn_cancel_transfer` |
| 13 | RemoveImage | `docker.remove_image` | `images_btn_remove` · clicked | images.rs | `target.id_request(id)` · **confirm_destructive** |
| 14 | InspectImage | `docker.inspect_image` | `images_btn_inspect` · clicked | images.rs | `target.name_request(name)` |
| 15 | ImageHistory | `docker.image_history` | `images_btn_history` · clicked | images.rs | `target.name_request(name)` |
| 16 | TagImage | `docker.tag_image` | `images_btn_tag` · clicked | images.rs | `target.tag_request(name, repo, tag)` (host/wsl2 v1.1) |
| 17 | PushImage | `docker.push_image` | `images_btn_push` · clicked | images.rs | `target.name_request(name)` · server-stream; AbortHandle + `images_btn_cancel_transfer` |
| 18 | SearchImages | `docker.search_images` | `images_btn_search` · clicked | images.rs | `target.search_request(term)` (host/wsl2 v1.1) |
| 19 | PruneImages | `docker.prune_images` | `images_btn_prune` · clicked | images.rs | `target.scope(false)` · **confirm_destructive** |
| 20 | ListVolumes | `docker.list_volumes` | `volumes_btn_refresh` · clicked | volumes.rs | `target.scope(false)` |
| 21 | CreateVolume | `docker.create_volume` | `volumes_btn_create` · clicked | volumes.rs | `target.name_request(name)` |
| 22 | RemoveVolume | `docker.remove_volume` | `volumes_btn_remove` · clicked | volumes.rs | `target.name_request(name)` · **confirm_destructive** |
| 23 | InspectVolume | `docker.inspect_volume` | `volumes_btn_inspect` · clicked | volumes.rs | `target.name_request(name)` |
| 24 | PruneVolumes | `docker.prune_volumes` | `volumes_btn_prune` · clicked | volumes.rs | `target.scope(false)` · **confirm_destructive** |
| 25 | ListNetworks | `docker.list_networks` | `networks_btn_refresh` · clicked | networks.rs | `target.scope(false)` |
| 26 | CreateNetwork | `docker.create_network` | `networks_btn_create` · clicked | networks.rs | `target.name_request(name)` |
| 27 | RemoveNetwork | `docker.remove_network` | `networks_btn_remove` · clicked | networks.rs | `target.id_request(id)` · **confirm_destructive** |
| 28 | InspectNetwork | `docker.inspect_network` | `networks_btn_inspect` · clicked | networks.rs | `target.id_request(id)` |
| 29 | ConnectNetwork | `docker.connect_network` | `networks_btn_connect` · clicked | networks.rs | `target.network_request(net_id, container_id)` (host/wsl2 v1.1) |
| 30 | DisconnectNetwork | `docker.disconnect_network` | `networks_btn_disconnect` · clicked | networks.rs | `target.network_request(net_id, container_id)` (host/wsl2 v1.1) · **confirm_destructive** |
| 31 | PruneNetworks | `docker.prune_networks` | `networks_btn_prune` · clicked | networks.rs | `target.scope(false)` · **confirm_destructive** |
| 32 | StreamEvents | `docker.stream_events` | `dashboard_btn_events` · clicked | dashboard.rs | `target.scope(false)` · server-stream; AbortHandle + `dashboard_btn_cancel_events`; output bounded 100k |
| 33 | StreamLogs | `docker.stream_logs` | `containers_btn_stream_logs` · clicked (wire_stream!) | containers.rs | `target.id_request(id)` · server-stream; AbortHandle + `containers_btn_cancel_stream`; bounded 100k |
| 34 | StreamStats | `docker.stream_stats` | `containers_btn_stream_stats` · clicked (wire_stream!) | containers.rs | `target.id_request(id)` · server-stream; AbortHandle + `containers_btn_cancel_stream`; bounded 100k |

---

## Result

- **65/65 mapped. Zero gaps.** Every one of the 31 `ColimaService` + 34 `DockerService` RPCs is
  invoked from a concrete GTK callback through its generated tonic client method, verified row-by-row
  against `linux/src/**` (no estimates). This confirms the `2026-07-18T20:43Z` ledger claim by direct
  source check.
- **Provider/profile scope (v1.1) present on every call:** ColimaService via `h.profile()` /
  `ProfileRequest` (incl. `Update`→`ProfileRequest` and `Prune`→`PruneRequest{all,profile}`);
  DockerService via a single `h.docker_target()` snapshot carrying `profile`+`host`+`wsl2` — including
  `Rename`/`Tag`/`Search`/`Connect`/`Disconnect`, which gained `host`/`wsl2` in v1.1.
- **GLib main context invariant holds on all 65** (Tokio `rt.spawn` → `async_channel` →
  `glib::spawn_future_local`; GTK widgets mutated only on the main context).
- **Destructive confirmation** gates 16 callbacks (every destructive action; Requirement 6.6,
  Property 13): VM Delete/Update/Prune; container kill/remove + PruneContainers;
  RemoveImage/PruneImages; RemoveVolume/PruneVolumes; RemoveNetwork/DisconnectNetwork/PruneNetworks;
  KubernetesReset; SwitchRuntime; DeleteProfile; KillProcess. No destructive RPC fires directly from
  a button click — each routes through `confirm_destructive` (modal OkCancel; RPC issued only on Ok).
- **Cancellable, bounded streams:** PullImage, PushImage, StreamEvents, StreamLogs, StreamStats each
  have an explicit Cancel button + `AbortHandle`; VMStats is a bounded single-sample poll.

## Honest limitations (not hidden)

- **Create-time config is minimal:** `Start` sends `StartRequest{config:None}` and `CreateProfile`
  sends `CreateProfileRequest{config:None}` — the RPC is wired and profile-scoped, but the GTK
  surfaces do not yet compose a full `ColimaConfig` at create time (config editing is done separately
  via `SetConfig`/`SetTemplate`). This is a functional-depth note, not a wiring gap.
- **`ModelServe`** does not require a non-empty model name in the callback (`ai_btn_serve` sends
  whatever is typed); the daemon enforces validity.
- **Evidence level:** this is source-audit evidence. GTK4 cannot compile on the macOS audit host, so
  the authoritative build + unit/clippy/fmt gate is the `linux-gtk4` CI job (green per the program
  ledger). Live AT-SPI runtime capture on a macOS-only host is `environment-blocked` (Assumption A2)
  and is tracked separately under `exploration/linux/**`; Linux parity is therefore evidenced at
  `CI-without-daemon`, not local live-backend.

## Verification boundary

- Source of truth: `linux/proto/colima_ui.proto` (65 RPCs, v1.1 additive scope fields present).
- Audited files: `linux/src/client.rs`, `linux/src/app_state.rs`, `linux/src/ui_helpers.rs`,
  `linux/src/main.rs`, and all 12 surface views under `linux/src/views/` (dashboard, containers,
  images, volumes, networks, machines, kubernetes, configuration, runtime, ai_workloads, profiles,
  monitoring) + onboarding.
- Not runnable here: native GTK4 compilation and AT-SPI live capture require a Linux host with a
  desktop session; both are exercised by the `linux-gtk4` CI job and the Linux explorer lane.
