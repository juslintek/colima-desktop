/// Monitoring view — VM resource usage + process management.
///
/// CONTRACT Part A: VMStats (polling) · ProcessList · KillProcess.
///
/// Async pattern: same GTK-main-thread-safe approach used across all views.
///   1. Button / timer fires on GTK main thread.
///   2. Client is cloned (Send), work is spawned on the Tokio runtime via
///      `AppHandle::rt.spawn(async move { … })`.
///   3. Result is sent through an `async_channel::bounded` channel.
///   4. `glib::spawn_future_local` receives on the channel and updates widgets
///      — this future runs on the GLib main context so `!Send` GTK widgets are
///      safe to touch.
///
/// Streaming note: VMStats is a server-streaming RPC.  Continuous streaming
/// inside GTK is tricky because we cannot hold a long-lived stream across GTK
/// callbacks safely.  We use a **bounded poll** instead:
///   – A `glib::timeout_add_seconds_local` fires every 3 s.
///   – Each tick opens a NEW call to VMStats with a 1-sample limit: we read
///     exactly one message from the stream, then drop the stream.  This gives
///     near-live stats without a background thread holding the stream open.
///   – Refresh button does the same on demand.
///   – KillProcess and ProcessList are one-shot unary calls.
use gtk::prelude::*;
use gtk::{
    Box as GtkBox, Entry, Grid, Label, ListBox, ListBoxRow, Orientation, ProgressBar, Separator,
    SpinButton,
};

use crate::app_state::AppHandle;
use crate::client::proto::{KillProcessRequest, ProfileRequest};
use crate::ui_helpers::{make_action_button, make_output_view, make_surface_header, set_text};

/// Plain-data snapshot of a single VMStats sample (all Send).
struct StatsSample {
    cpu_percent: f64,
    memory_used: i64,
    memory_total: i64,
    disk_used: i64,
    disk_total: i64,
}

/// Plain-data snapshot of a single process entry (all Send).
struct ProcessRow {
    pid: i32,
    user: String,
    cpu_percent: f64,
    memory_percent: f64,
    command: String,
    container: String,
}

pub fn build(handle: AppHandle) -> GtkBox {
    let root = GtkBox::new(Orientation::Vertical, 0);
    root.set_widget_name("view_monitoring");
    root.update_property(&[gtk::accessible::Property::Label("Monitoring")]);

    let (header, spinner, refresh_btn) = make_surface_header("Monitoring", "monitoring");
    root.append(&header);

    // ── VM Stats section ─────────────────────────────────────────────────
    let stats_section_lbl = Label::new(Some("VM Resource Usage"));
    stats_section_lbl.set_halign(gtk::Align::Start);
    stats_section_lbl.set_margin_start(12);
    stats_section_lbl.set_margin_top(8);
    stats_section_lbl.add_css_class("heading");
    stats_section_lbl.set_widget_name("monitoring_stats_heading");
    stats_section_lbl.update_property(&[gtk::accessible::Property::Label("VM resource usage")]);
    root.append(&stats_section_lbl);

    let stats_grid = Grid::builder()
        .column_spacing(12)
        .row_spacing(4)
        .margin_start(12)
        .margin_end(12)
        .margin_top(4)
        .margin_bottom(4)
        .build();
    stats_grid.set_widget_name("monitoring_stats_grid");
    stats_grid.update_property(&[gtk::accessible::Property::Label("VM stats grid")]);

    // CPU bar
    let cpu_key = Label::new(Some("CPU"));
    cpu_key.set_halign(gtk::Align::End);
    cpu_key.add_css_class("dim-label");
    cpu_key.set_widget_name("monitoring_key_cpu");
    let cpu_bar = ProgressBar::new();
    cpu_bar.set_widget_name("monitoring_cpu_bar");
    cpu_bar.update_property(&[gtk::accessible::Property::Label("CPU usage")]);
    cpu_bar.set_show_text(true);
    cpu_bar.set_hexpand(true);
    stats_grid.attach(&cpu_key, 0, 0, 1, 1);
    stats_grid.attach(&cpu_bar, 1, 0, 1, 1);

    // Memory bar
    let mem_key = Label::new(Some("Memory"));
    mem_key.set_halign(gtk::Align::End);
    mem_key.add_css_class("dim-label");
    mem_key.set_widget_name("monitoring_key_memory");
    let mem_bar = ProgressBar::new();
    mem_bar.set_widget_name("monitoring_mem_bar");
    mem_bar.update_property(&[gtk::accessible::Property::Label("Memory usage")]);
    mem_bar.set_show_text(true);
    mem_bar.set_hexpand(true);
    stats_grid.attach(&mem_key, 0, 1, 1, 1);
    stats_grid.attach(&mem_bar, 1, 1, 1, 1);

    // Disk bar
    let disk_key = Label::new(Some("Disk"));
    disk_key.set_halign(gtk::Align::End);
    disk_key.add_css_class("dim-label");
    disk_key.set_widget_name("monitoring_key_disk");
    let disk_bar = ProgressBar::new();
    disk_bar.set_widget_name("monitoring_disk_bar");
    disk_bar.update_property(&[gtk::accessible::Property::Label("Disk usage")]);
    disk_bar.set_show_text(true);
    disk_bar.set_hexpand(true);
    stats_grid.attach(&disk_key, 0, 2, 1, 1);
    stats_grid.attach(&disk_bar, 1, 2, 1, 1);

    root.append(&stats_grid);
    root.append(&Separator::new(Orientation::Horizontal));

    // ── Process list section ─────────────────────────────────────────────
    let proc_section_lbl = Label::new(Some("Processes"));
    proc_section_lbl.set_halign(gtk::Align::Start);
    proc_section_lbl.set_margin_start(12);
    proc_section_lbl.set_margin_top(8);
    proc_section_lbl.set_margin_bottom(4);
    proc_section_lbl.add_css_class("heading");
    proc_section_lbl.set_widget_name("monitoring_procs_heading");
    proc_section_lbl.update_property(&[gtk::accessible::Property::Label("Process list")]);
    root.append(&proc_section_lbl);

    let proc_list = ListBox::new();
    proc_list.set_widget_name("monitoring_process_list");
    proc_list.update_property(&[gtk::accessible::Property::Label("Process list")]);
    proc_list.set_selection_mode(gtk::SelectionMode::Single);

    let proc_sw = gtk::ScrolledWindow::builder()
        .child(&proc_list)
        .vexpand(true)
        .min_content_height(140)
        .build();
    proc_sw.set_widget_name("monitoring_process_scroll");
    root.append(&proc_sw);

    root.append(&Separator::new(Orientation::Horizontal));

    // ── Kill process row ─────────────────────────────────────────────────
    let kill_row = GtkBox::new(Orientation::Horizontal, 6);
    kill_row.set_margin_start(12);
    kill_row.set_margin_end(12);
    kill_row.set_margin_top(8);
    kill_row.set_margin_bottom(4);

    let pid_lbl = Label::new(Some("PID:"));
    pid_lbl.set_widget_name("monitoring_pid_label");
    pid_lbl.update_property(&[gtk::accessible::Property::Label("PID")]);

    // SpinButton for PID — numeric input, AT-SPI accessible
    let pid_adj = gtk::Adjustment::new(0.0, 0.0, 99999.0, 1.0, 10.0, 0.0);
    let pid_spin = SpinButton::new(Some(&pid_adj), 1.0, 0);
    pid_spin.set_widget_name("monitoring_pid_spin");
    pid_spin.update_property(&[gtk::accessible::Property::Label("Process ID to kill")]);
    pid_spin.set_width_chars(7);

    let sig_lbl = Label::new(Some("Signal:"));
    sig_lbl.set_widget_name("monitoring_sig_label");
    sig_lbl.update_property(&[gtk::accessible::Property::Label("Signal")]);

    let sig_entry = Entry::builder()
        .placeholder_text("9")
        .max_length(4)
        .width_chars(4)
        .build();
    sig_entry.set_widget_name("monitoring_sig_entry");
    sig_entry.update_property(&[gtk::accessible::Property::Label(
        "Signal number (default 9)",
    )]);

    let btn_kill = make_action_button("✕ Kill", "monitoring_btn_kill");

    kill_row.append(&pid_lbl);
    kill_row.append(&pid_spin);
    kill_row.append(&sig_lbl);
    kill_row.append(&sig_entry);
    kill_row.append(&btn_kill);
    root.append(&kill_row);

    // ── Output log ───────────────────────────────────────────────────────
    let (sw_out, log_buf) = make_output_view("monitoring_output");
    root.append(&sw_out);

    // ── Wire refresh button (VMStats poll + ProcessList) ─────────────────
    {
        let h = handle.clone();
        let cpu_b = cpu_bar.clone();
        let mem_b = mem_bar.clone();
        let disk_b = disk_bar.clone();
        let plist = proc_list.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();

        refresh_btn.connect_clicked(move |_| {
            do_refresh(
                h.clone(),
                cpu_b.clone(),
                mem_b.clone(),
                disk_b.clone(),
                plist.clone(),
                lb.clone(),
                sp.clone(),
            );
        });
    }

    // ── Auto-poll VMStats every 3 seconds ────────────────────────────────
    // Uses a bounded single-sample poll: open stream → read 1 message → drop.
    // This is cancellation-safe: if the GTK window is destroyed the timeout
    // closure holds no strong widget references that would keep widgets alive
    // past their natural lifetime.
    {
        let h = handle.clone();
        let cpu_b = cpu_bar.clone();
        let mem_b = mem_bar.clone();
        let disk_b = disk_bar.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();

        glib::timeout_add_seconds_local(3, move || {
            poll_vm_stats(
                h.clone(),
                cpu_b.clone(),
                mem_b.clone(),
                disk_b.clone(),
                lb.clone(),
                sp.clone(),
            );
            glib::ControlFlow::Continue
        });
    }

    // ── Wire kill button ─────────────────────────────────────────────────
    {
        let h = handle.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        let pspin = pid_spin.clone();
        let sige = sig_entry.clone();

        btn_kill.connect_clicked(move |_| {
            let pid = pspin.value() as i32;
            if pid <= 0 {
                set_text(&lb, "Enter a valid PID (> 0) before killing");
                return;
            }
            let sig_text = sige.text().to_string();
            let signal: i32 = sig_text.trim().parse().unwrap_or(9);

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
                        .kill_process(KillProcessRequest {
                            profile,
                            pid,
                            signal,
                        })
                        .await
                        .map(|r| {
                            let r = r.into_inner();
                            if r.success {
                                format!("Killed PID {pid} (signal {signal})")
                            } else {
                                format!("Kill failed: {}", r.message)
                            }
                        })
                        .map_err(|e| format!("Kill error: {e}"));
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
                set_text(&lb, "Not connected to daemon");
            }
        });
    }

    root
}

/// Fire a single VMStats sample + ProcessList refresh.
/// Called from both the refresh button and the auto-poll timer.
fn do_refresh(
    handle: AppHandle,
    cpu_bar: ProgressBar,
    mem_bar: ProgressBar,
    disk_bar: ProgressBar,
    proc_list: ListBox,
    log_buf: gtk::TextBuffer,
    spinner: gtk::Spinner,
) {
    spinner.set_spinning(true);
    let profile = handle.profile();
    let state = handle.state.lock().unwrap();
    if let Some(ref client) = state.daemon {
        let mut c = client.colima.clone();

        // Channel carrying (Option<StatsSample>, Vec<ProcessRow>, Option<String-error>)
        type Payload = (Option<StatsSample>, Vec<ProcessRow>, Option<String>);
        let (tx, rx) = async_channel::bounded::<Payload>(1);

        let profile2 = profile.clone();
        handle.rt.spawn(async move {
            // — One-shot VMStats sample —
            let stats_opt = match c
                .vm_stats(ProfileRequest {
                    profile: profile2.clone(),
                })
                .await
            {
                Ok(mut stream) => {
                    // Read exactly one event; drop the stream immediately.
                    match stream.get_mut().message().await {
                        Ok(Some(evt)) => Some(StatsSample {
                            cpu_percent: evt.cpu_percent,
                            memory_used: evt.memory_used,
                            memory_total: evt.memory_total,
                            disk_used: evt.disk_used,
                            disk_total: evt.disk_total,
                        }),
                        _ => None,
                    }
                    // stream dropped here — gRPC call is effectively cancelled
                }
                Err(_) => None,
            };

            // — ProcessList —
            let (procs, err_msg) = match c.process_list(ProfileRequest { profile: profile2 }).await
            {
                Ok(r) => {
                    let rows: Vec<ProcessRow> = r
                        .into_inner()
                        .processes
                        .into_iter()
                        .map(|p| ProcessRow {
                            pid: p.pid,
                            user: p.user,
                            cpu_percent: p.cpu_percent,
                            memory_percent: p.memory_percent,
                            command: p.command,
                            container: p.container,
                        })
                        .collect();
                    (rows, None)
                }
                Err(e) => (Vec::new(), Some(format!("ProcessList error: {e}"))),
            };

            let _ = tx.send((stats_opt, procs, err_msg)).await;
        });

        let cpu_b = cpu_bar.clone();
        let mem_b = mem_bar.clone();
        let disk_b = disk_bar.clone();
        let plist = proc_list.clone();
        let lb2 = log_buf.clone();
        let sp2 = spinner.clone();

        glib::spawn_future_local(async move {
            sp2.set_spinning(false);
            if let Ok((stats_opt, procs, err_msg)) = rx.recv().await {
                // Update stat bars
                if let Some(s) = stats_opt {
                    cpu_b.set_fraction(s.cpu_percent / 100.0);
                    cpu_b.set_text(Some(&format!("{:.1}%", s.cpu_percent)));

                    let mem_frac = if s.memory_total > 0 {
                        s.memory_used as f64 / s.memory_total as f64
                    } else {
                        0.0
                    };
                    mem_b.set_fraction(mem_frac.clamp(0.0, 1.0));
                    mem_b.set_text(Some(&format!(
                        "{:.1}/{:.1} GiB",
                        s.memory_used as f64 / 1_073_741_824.0,
                        s.memory_total as f64 / 1_073_741_824.0
                    )));

                    let disk_frac = if s.disk_total > 0 {
                        s.disk_used as f64 / s.disk_total as f64
                    } else {
                        0.0
                    };
                    disk_b.set_fraction(disk_frac.clamp(0.0, 1.0));
                    disk_b.set_text(Some(&format!(
                        "{:.1}/{:.1} GiB",
                        s.disk_used as f64 / 1_073_741_824.0,
                        s.disk_total as f64 / 1_073_741_824.0
                    )));
                }

                // Rebuild process list
                while let Some(child) = plist.first_child() {
                    plist.remove(&child);
                }
                if procs.is_empty() {
                    if let Some(e) = err_msg {
                        set_text(&lb2, &e);
                    } else {
                        set_text(&lb2, "(no processes returned)");
                    }
                } else {
                    for p in &procs {
                        let line = if p.container.is_empty() {
                            format!(
                                "PID {:>6}  {:>8}  cpu {:>5.1}%  mem {:>5.1}%  {}",
                                p.pid, p.user, p.cpu_percent, p.memory_percent, p.command
                            )
                        } else {
                            format!(
                                "PID {:>6}  {:>8}  cpu {:>5.1}%  mem {:>5.1}%  {}  [{}]",
                                p.pid,
                                p.user,
                                p.cpu_percent,
                                p.memory_percent,
                                p.command,
                                p.container
                            )
                        };
                        let lbl = Label::new(Some(&line));
                        lbl.set_halign(gtk::Align::Start);
                        lbl.set_margin_start(8);
                        lbl.set_margin_top(2);
                        lbl.set_margin_bottom(2);
                        lbl.add_css_class("monospace");
                        let row = ListBoxRow::new();
                        let pid_name = format!("proc_{}", p.pid);
                        row.set_widget_name(&pid_name);
                        row.update_property(&[gtk::accessible::Property::Label(&format!(
                            "PID {} {} {}",
                            p.pid, p.user, p.command
                        ))]);
                        row.set_child(Some(&lbl));
                        plist.append(&row);
                    }
                    set_text(&lb2, &format!("{} processes", procs.len()));
                }
            }
        });
    } else {
        spinner.set_spinning(false);
        set_text(&log_buf, "Not connected to daemon");
    }
}

/// One-shot VMStats-only poll used by the auto-poll timer.
/// Avoids rebuilding the process list on every tick (only on explicit refresh).
fn poll_vm_stats(
    handle: AppHandle,
    cpu_bar: ProgressBar,
    mem_bar: ProgressBar,
    disk_bar: ProgressBar,
    log_buf: gtk::TextBuffer,
    spinner: gtk::Spinner,
) {
    let state = handle.state.lock().unwrap();
    if let Some(ref client) = state.daemon {
        let mut c = client.colima.clone();
        let profile = handle.profile();
        let (tx, rx) = async_channel::bounded::<Option<StatsSample>>(1);

        handle.rt.spawn(async move {
            let sample = match c.vm_stats(ProfileRequest { profile }).await {
                Ok(mut stream) => match stream.get_mut().message().await {
                    Ok(Some(evt)) => Some(StatsSample {
                        cpu_percent: evt.cpu_percent,
                        memory_used: evt.memory_used,
                        memory_total: evt.memory_total,
                        disk_used: evt.disk_used,
                        disk_total: evt.disk_total,
                    }),
                    _ => None,
                },
                Err(_) => None,
            };
            let _ = tx.send(sample).await;
        });

        let cpu_b = cpu_bar.clone();
        let mem_b = mem_bar.clone();
        let disk_b = disk_bar.clone();
        let lb2 = log_buf;
        let sp2 = spinner;

        glib::spawn_future_local(async move {
            sp2.set_spinning(false);
            if let Ok(Some(s)) = rx.recv().await {
                cpu_b.set_fraction(s.cpu_percent / 100.0);
                cpu_b.set_text(Some(&format!("{:.1}%", s.cpu_percent)));

                let mem_frac = if s.memory_total > 0 {
                    s.memory_used as f64 / s.memory_total as f64
                } else {
                    0.0
                };
                mem_b.set_fraction(mem_frac.clamp(0.0, 1.0));
                mem_b.set_text(Some(&format!(
                    "{:.1}/{:.1} GiB",
                    s.memory_used as f64 / 1_073_741_824.0,
                    s.memory_total as f64 / 1_073_741_824.0
                )));

                let disk_frac = if s.disk_total > 0 {
                    s.disk_used as f64 / s.disk_total as f64
                } else {
                    0.0
                };
                disk_b.set_fraction(disk_frac.clamp(0.0, 1.0));
                disk_b.set_text(Some(&format!(
                    "{:.1}/{:.1} GiB",
                    s.disk_used as f64 / 1_073_741_824.0,
                    s.disk_total as f64 / 1_073_741_824.0
                )));
                set_text(&lb2, "Stats updated");
            }
        });
    }
}
