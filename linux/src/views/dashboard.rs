/// Dashboard view — VM status overview + quick actions.
///
/// Surfaces: Status · Version · Start/Stop/Restart · VMStats (streaming) · Prune.
/// All interactive widgets carry AT-SPI accessible names.
use gtk::prelude::*;
use gtk::{Box as GtkBox, Button, Grid, Label, Orientation, ProgressBar, Separator};

use crate::app_state::AppHandle;
use crate::client::proto::{
    Empty, ProfileRequest, PruneRequest, RestartRequest, StartRequest, StopRequest,
};
use crate::ui_helpers::{make_action_button, make_output_view, make_surface_header, set_text};

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
    let btn_prune = make_action_button("🗑 Prune", "dashboard_btn_prune");
    actions.append(&btn_start);
    actions.append(&btn_stop);
    actions.append(&btn_restart);
    actions.append(&btn_prune);
    root.append(&actions);

    // Output log area
    let (sw, log_buf) = make_output_view("dashboard_output");
    root.append(&sw);

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
        btn_prune.connect_clicked(move |_| {
            sp.set_spinning(true);
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.colima.clone();
                let lb2 = lb.clone();
                let sp2 = sp.clone();
                let (tx, rx) = async_channel::bounded::<Result<String, String>>(1);
                h.rt.spawn(async move {
                    let result = c
                        .prune(PruneRequest { all: false })
                        .await
                        .map(|r| r.into_inner().message)
                        .map_err(|e| format!("Prune error: {e}"));
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

    root
}
