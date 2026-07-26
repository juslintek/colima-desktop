/// Dashboard view — VM status overview + quick actions.
///
/// Surfaces: Status · Version · Start/Stop/Restart · VMStats (streaming) · Prune.
/// All interactive widgets carry AT-SPI accessible names.
use gtk::prelude::*;
use gtk::{Box as GtkBox, Grid, Label, Orientation, ProgressBar, Separator};

use crate::app_state::AppHandle;
use crate::client::proto::{
    DeleteRequest, Empty, ProfileRequest, PruneRequest, RestartRequest, StartRequest, StopRequest,
};
use crate::ui_helpers::{
    confirm_destructive, make_action_button, make_output_view, make_surface_header, set_text,
};

pub fn build(handle: AppHandle) -> GtkBox {
    let root = GtkBox::new(Orientation::Vertical, 0);
    root.set_widget_name("view_dashboard");
    root.update_property(&[gtk::accessible::Property::Label("Dashboard")]);

    let (header, spinner, refresh_btn) = make_surface_header("Dashboard", "dashboard");
    root.append(&header);

    // Status grid
    let grid = Grid::builder()
        .column_spacing(12)
        .row_spacing(6)
        .margin_start(12)
        .margin_end(12)
        .margin_top(4)
        .build();

    macro_rules! grid_row {
        ($row:expr, $key:expr, $id:expr) => {{
            let key_lbl = Label::new(Some($key));
            key_lbl.set_halign(gtk::Align::End);
            key_lbl.set_widget_name(&format!("dashboard_key_{}", $id));
            key_lbl.add_css_class("dim-label");
            let val_lbl = Label::new(Some("—"));
            val_lbl.set_halign(gtk::Align::Start);
            val_lbl.set_widget_name(&format!("dashboard_val_{}", $id));
            val_lbl.update_property(&[gtk::accessible::Property::Label($key)]);
            grid.attach(&key_lbl, 0, $row, 1, 1);
            grid.attach(&val_lbl, 1, $row, 1, 1);
            val_lbl
        }};
    }

    let val_status = grid_row!(0, "Status", "status");
    let val_runtime = grid_row!(1, "Runtime", "runtime");
    let val_arch = grid_row!(2, "Architecture", "arch");
    let val_cpu = grid_row!(3, "CPUs", "cpu");
    let val_mem = grid_row!(4, "Memory", "memory");
    let val_disk = grid_row!(5, "Disk", "disk");
    let val_ip = grid_row!(6, "IP Address", "ip");
    let val_k8s = grid_row!(7, "Kubernetes", "k8s");
    let val_version = grid_row!(8, "Version", "version");
    root.append(&grid);

    root.append(&Separator::new(Orientation::Horizontal));

    // CPU/memory progress bars
    let stats_box = GtkBox::new(Orientation::Vertical, 4);
    stats_box.set_margin_start(12);
    stats_box.set_margin_end(12);
    stats_box.set_margin_top(8);

    let cpu_lbl = Label::new(Some("CPU"));
    cpu_lbl.set_halign(gtk::Align::Start);
    cpu_lbl.set_widget_name("dashboard_cpu_label");
    let cpu_bar = ProgressBar::new();
    cpu_bar.set_widget_name("dashboard_cpu_bar");
    cpu_bar.update_property(&[gtk::accessible::Property::Label("CPU usage")]);
    cpu_bar.set_show_text(true);

    let mem_lbl = Label::new(Some("Memory"));
    mem_lbl.set_halign(gtk::Align::Start);
    mem_lbl.set_widget_name("dashboard_mem_label");
    let mem_bar = ProgressBar::new();
    mem_bar.set_widget_name("dashboard_mem_bar");
    mem_bar.update_property(&[gtk::accessible::Property::Label("Memory usage")]);
    mem_bar.set_show_text(true);

    stats_box.append(&cpu_lbl);
    stats_box.append(&cpu_bar);
    stats_box.append(&mem_lbl);
    stats_box.append(&mem_bar);
    root.append(&stats_box);

    root.append(&Separator::new(Orientation::Horizontal));

    // Action buttons row
    let actions = GtkBox::new(Orientation::Horizontal, 8);
    actions.set_margin_start(12);
    actions.set_margin_end(12);
    actions.set_margin_top(8);
    actions.set_margin_bottom(8);

    let btn_start = make_action_button("▶ Start", "dashboard_btn_start");
    let btn_stop = make_action_button("■ Stop", "dashboard_btn_stop");
    let btn_restart = make_action_button("↺ Restart", "dashboard_btn_restart");
    let btn_delete = make_action_button("🗑 Delete VM", "dashboard_btn_delete");
    let btn_update = make_action_button("⬆ Update CLI", "dashboard_btn_update");
    let btn_prune = make_action_button("🗑 Prune", "dashboard_btn_prune");
    let btn_events = make_action_button("Events", "dashboard_btn_events");
    let btn_cancel_events = make_action_button("Cancel Events", "dashboard_btn_cancel_events");
    actions.append(&btn_start);
    actions.append(&btn_stop);
    actions.append(&btn_restart);
    actions.append(&btn_delete);
    actions.append(&btn_update);
    actions.append(&btn_prune);
    actions.append(&btn_events);
    actions.append(&btn_cancel_events);
    root.append(&actions);

    // Output log area
    let (sw, log_buf) = make_output_view("dashboard_output");
    root.append(&sw);
    let event_abort = std::rc::Rc::new(std::cell::RefCell::new(None::<tokio::task::AbortHandle>));

    // ── Wire up buttons ──────────────────────────────────────────────────────

    // Result type for the status+version refresh: carry only plain Send data.
    enum StatusResult {
        Ok {
            running: bool,
            runtime: String,
            arch: String,
            cpu: i32,
            memory: i64,
            disk: i64,
            ip_address: String,
            kubernetes: bool,
            version: String,
        },
        Err(String),
    }

    // Refresh / Status
    {
        let h = handle.clone();
        let vs = val_status.clone();
        let vr = val_runtime.clone();
        let va = val_arch.clone();
        let vc = val_cpu.clone();
        let vm = val_mem.clone();
        let vd = val_disk.clone();
        let vi = val_ip.clone();
        let vk = val_k8s.clone();
        let vv = val_version.clone();
        let sp = spinner.clone();
        let lb = log_buf.clone();
        refresh_btn.connect_clicked(move |_| {
            sp.set_spinning(true);
            let profile = h.profile();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.colima.clone();
                let sp2 = sp.clone();
                let lb2 = lb.clone();
                let vs2 = vs.clone();
                let vr2 = vr.clone();
                let va2 = va.clone();
                let vc2 = vc.clone();
                let vm2 = vm.clone();
                let vd2 = vd.clone();
                let vi2 = vi.clone();
                let vk2 = vk.clone();
                let vv2 = vv.clone();
                let (tx, rx) = async_channel::bounded::<StatusResult>(1);
                h.rt.spawn(async move {
                    let status_res = c
                        .status(crate::client::proto::StatusRequest {
                            profile: profile.clone(),
                            extended: true,
                        })
                        .await;
                    let version_res = c.version(Empty {}).await;
                    let result = match status_res {
                        Ok(r) => {
                            let s = r.into_inner();
                            let version = version_res
                                .map(|v| v.into_inner().version)
                                .unwrap_or_default();
                            StatusResult::Ok {
                                running: s.running,
                                runtime: s.runtime,
                                arch: s.arch,
                                cpu: s.cpu,
                                memory: s.memory,
                                disk: s.disk,
                                ip_address: s.ip_address,
                                kubernetes: s.kubernetes,
                                version,
                            }
                        }
                        Err(e) => StatusResult::Err(format!("Status error: {e}")),
                    };
                    let _ = tx.send(result).await;
                });
                glib::spawn_future_local(async move {
                    sp2.set_spinning(false);
                    if let Ok(result) = rx.recv().await {
                        match result {
                            StatusResult::Ok {
                                running,
                                runtime,
                                arch,
                                cpu,
                                memory,
                                disk,
                                ip_address,
                                kubernetes,
                                version,
                            } => {
                                vs2.set_label(if running { "Running ✓" } else { "Stopped" });
                                vr2.set_label(&runtime);
                                va2.set_label(&arch);
                                vc2.set_label(&cpu.to_string());
                                vm2.set_label(&format!(
                                    "{:.1} GiB",
                                    memory as f64 / 1_073_741_824.0
                                ));
                                vd2.set_label(&format!("{:.1} GiB", disk as f64 / 1_073_741_824.0));
                                vi2.set_label(if ip_address.is_empty() {
                                    "—"
                                } else {
                                    &ip_address
                                });
                                vk2.set_label(if kubernetes { "Enabled" } else { "Disabled" });
                                if !version.is_empty() {
                                    vv2.set_label(&version);
                                }
                            }
                            StatusResult::Err(e) => set_text(&lb2, &e),
                        }
                    }
                });
            } else {
                sp.set_spinning(false);
                set_text(&lb, "Not connected to daemon");
            }
        });
    }

    // Start
    {
        let h = handle.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        btn_start.connect_clicked(move |_| {
            sp.set_spinning(true);
            let profile = h.profile();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.colima.clone();
                let lb2 = lb.clone();
                let sp2 = sp.clone();
                let (tx, rx) = async_channel::bounded::<Result<String, String>>(1);
                h.rt.spawn(async move {
                    let result = match c
                        .start(StartRequest {
                            profile,
                            config: None,
                        })
                        .await
                    {
                        Ok(mut stream) => {
                            let mut log = String::new();
                            while let Ok(Some(evt)) = stream.get_mut().message().await {
                                log.push_str(&format!("[{}] {}\n", evt.stage, evt.message));
                            }
                            Ok(log)
                        }
                        Err(e) => Err(format!("Start error: {e}")),
                    };
                    let _ = tx.send(result).await;
                });
                glib::spawn_future_local(async move {
                    sp2.set_spinning(false);
                    if let Ok(result) = rx.recv().await {
                        match result {
                            Ok(log) => set_text(&lb2, &log),
                            Err(e) => set_text(&lb2, &e),
                        }
                    }
                });
            } else {
                sp.set_spinning(false);
                set_text(&lb, "Not connected to daemon");
            }
        });
    }

    // Stop
    {
        let h = handle.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        btn_stop.connect_clicked(move |_| {
            sp.set_spinning(true);
            let profile = h.profile();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.colima.clone();
                let lb2 = lb.clone();
                let sp2 = sp.clone();
                let (tx, rx) = async_channel::bounded::<Result<String, String>>(1);
                h.rt.spawn(async move {
                    let result = c
                        .stop(StopRequest {
                            profile,
                            force: false,
                        })
                        .await
                        .map(|r| r.into_inner().message)
                        .map_err(|e| format!("Stop error: {e}"));
                    let _ = tx.send(result).await;
                });
                glib::spawn_future_local(async move {
                    sp2.set_spinning(false);
                    if let Ok(result) = rx.recv().await {
                        match result {
                            Ok(msg) => set_text(&lb2, &msg),
                            Err(e) => set_text(&lb2, &e),
                        }
                    }
                });
            } else {
                sp.set_spinning(false);
                set_text(&lb, "Not connected");
            }
        });
    }

    // Restart
    {
        let h = handle.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        btn_restart.connect_clicked(move |_| {
            sp.set_spinning(true);
            let profile = h.profile();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.colima.clone();
                let lb2 = lb.clone();
                let sp2 = sp.clone();
                let (tx, rx) = async_channel::bounded::<Result<String, String>>(1);
                h.rt.spawn(async move {
                    let result = match c.restart(RestartRequest { profile }).await {
                        Ok(mut stream) => {
                            let mut log = String::new();
                            while let Ok(Some(evt)) = stream.get_mut().message().await {
                                log.push_str(&format!("[{}] {}\n", evt.stage, evt.message));
                            }
                            Ok(log)
                        }
                        Err(e) => Err(format!("Restart error: {e}")),
                    };
                    let _ = tx.send(result).await;
                });
                glib::spawn_future_local(async move {
                    sp2.set_spinning(false);
                    if let Ok(result) = rx.recv().await {
                        match result {
                            Ok(log) => set_text(&lb2, &log),
                            Err(e) => set_text(&lb2, &e),
                        }
                    }
                });
            } else {
                sp.set_spinning(false);
                set_text(&lb, "Not connected");
            }
        });
    }

    // Prune
    {
        let h = handle.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        btn_prune.connect_clicked(move |source| {
            let profile = h.profile();
            let h2 = h.clone();
            let lb2 = lb.clone();
            let sp2 = sp.clone();
            confirm_destructive(
                source,
                "Prune unused virtual machines?",
                &format!("Remove unused Colima resources for profile '{profile}'?"),
                move || {
                    run_colima_status_call(h2, sp2, lb2, move |mut client| async move {
                        client
                            .prune(PruneRequest {
                                all: false,
                                profile,
                            })
                            .await
                            .map(|response| response.into_inner().message)
                            .map_err(|error| format!("Prune error: {error}"))
                    })
                },
            );
        });
    }

    // Delete the selected VM, preserving profile data by default.
    {
        let h = handle.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        btn_delete.connect_clicked(move |source| {
            let profile = h.profile();
            let h2 = h.clone();
            let lb2 = lb.clone();
            let sp2 = sp.clone();
            confirm_destructive(
                source,
                "Delete virtual machine?",
                &format!("Delete the VM for profile '{profile}'? Profile data is retained."),
                move || run_vm_delete(h2, sp2, lb2, profile),
            );
        });
    }

    // Update is explicitly profile-scoped by the canonical contract.
    {
        let h = handle.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        btn_update.connect_clicked(move |source| {
            let profile = h.profile();
            let h2 = h.clone();
            let lb2 = lb.clone();
            let sp2 = sp.clone();
            confirm_destructive(
                source,
                "Update Colima CLI?",
                &format!("Update the runtime for profile '{profile}'?"),
                move || run_profile_update(h2, sp2, lb2, profile),
            );
        });
    }

    // Docker event stream, bounded in the UI and explicitly cancellable.
    {
        let h = handle.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        let running = event_abort.clone();
        btn_events.connect_clicked(move |_| {
            if let Some(abort) = running.borrow_mut().take() {
                abort.abort();
            }
            if let Some(abort) = start_event_stream(h.clone(), sp.clone(), lb.clone()) {
                *running.borrow_mut() = Some(abort);
            } else {
                set_text(&lb, "Not connected");
            }
        });
    }
    {
        let running = event_abort.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        btn_cancel_events.connect_clicked(move |_| {
            if let Some(abort) = running.borrow_mut().take() {
                abort.abort();
                set_text(&lb, "Event stream cancelled");
            }
            sp.set_spinning(false);
        });
    }

    root
}

fn run_vm_delete(
    handle: AppHandle,
    spinner: gtk::Spinner,
    output: gtk::TextBuffer,
    profile: String,
) {
    run_colima_status_call(handle, spinner, output, move |mut client| async move {
        client
            .delete(DeleteRequest {
                profile,
                force: false,
                data: false,
            })
            .await
            .map(|response| response.into_inner().message)
            .map_err(|error| format!("Delete error: {error}"))
    });
}

fn run_profile_update(
    handle: AppHandle,
    spinner: gtk::Spinner,
    output: gtk::TextBuffer,
    profile: String,
) {
    run_colima_status_call(handle, spinner, output, move |mut client| async move {
        client
            .update(ProfileRequest { profile })
            .await
            .map(|response| response.into_inner().message)
            .map_err(|error| format!("Update error: {error}"))
    });
}

fn run_colima_status_call<F, Fut>(
    handle: AppHandle,
    spinner: gtk::Spinner,
    output: gtk::TextBuffer,
    call: F,
) where
    F: FnOnce(
            crate::client::proto::colima_service_client::ColimaServiceClient<
                tonic::transport::Channel,
            >,
        ) -> Fut
        + Send
        + 'static,
    Fut: std::future::Future<Output = Result<String, String>> + Send + 'static,
{
    let client = handle.state.lock().unwrap().daemon.clone();
    let Some(client) = client else {
        set_text(&output, "Not connected");
        return;
    };
    spinner.set_spinning(true);
    let (tx, rx) = async_channel::bounded(1);
    handle.rt.spawn(async move {
        let _ = tx.send(call(client.colima).await).await;
    });
    glib::spawn_future_local(async move {
        if let Ok(result) = rx.recv().await {
            set_text(&output, &result.unwrap_or_else(|error| error));
        }
        spinner.set_spinning(false);
    });
}

fn start_event_stream(
    handle: AppHandle,
    spinner: gtk::Spinner,
    output: gtk::TextBuffer,
) -> Option<tokio::task::AbortHandle> {
    let target = handle.docker_target();
    let client = handle.state.lock().unwrap().daemon.clone()?;
    spinner.set_spinning(true);
    let mut client = client.docker;
    let (tx, rx) = async_channel::unbounded::<Result<String, String>>();
    let task = handle.rt.spawn(async move {
        match client.stream_events(target.scope(false)).await {
            Ok(mut stream) => loop {
                match stream.get_mut().message().await {
                    Ok(Some(event)) if event.error.is_empty() => {
                        if tx.send(Ok(event.json)).await.is_err() {
                            break;
                        }
                    }
                    Ok(Some(event)) => {
                        let _ = tx.send(Err(event.error)).await;
                        break;
                    }
                    Ok(None) => break,
                    Err(error) => {
                        let _ = tx.send(Err(format!("Event stream error: {error}"))).await;
                        break;
                    }
                }
            },
            Err(error) => {
                let _ = tx
                    .send(Err(format!("Event stream start error: {error}")))
                    .await;
            }
        }
    });
    let abort = task.abort_handle();
    glib::spawn_future_local(async move {
        let mut log = String::new();
        while let Ok(item) = rx.recv().await {
            let stop = item.is_err();
            log.push_str(&item.unwrap_or_else(|error| error));
            log.push('\n');
            if log.len() > 100_000 {
                log.drain(..50_000);
            }
            set_text(&output, &log);
            if stop {
                break;
            }
        }
        spinner.set_spinning(false);
    });
    Some(abort)
}
