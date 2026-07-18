/// Kubernetes view — Start, Stop, Reset, Exec.
///
/// CONTRACT Part A: KubernetesStart · KubernetesStop · KubernetesReset · KubernetesExec.
use gtk::prelude::*;
use gtk::{Box as GtkBox, Entry, Orientation, Separator};

use crate::app_state::AppHandle;
use crate::client::proto::{KubeExecRequest, ProfileRequest};
use crate::ui_helpers::{make_action_button, make_output_view, make_surface_header, set_text};

pub fn build(handle: AppHandle) -> GtkBox {
    let root = GtkBox::new(Orientation::Vertical, 0);
    root.set_widget_name("view_kubernetes");
    root.update_property(&[gtk::accessible::Property::Label("Kubernetes")]);

    let (header, spinner, _refresh_btn) = make_surface_header("Kubernetes", "kubernetes");
    root.append(&header);

    let actions = GtkBox::new(Orientation::Horizontal, 4);
    actions.set_margin_start(12);
    actions.set_margin_end(12);
    actions.set_margin_top(8);
    actions.set_margin_bottom(8);

    macro_rules! abtn {
        ($l:expr, $n:expr) => {{
            let b = make_action_button($l, $n);
            actions.append(&b);
            b
        }};
    }
    let btn_start = abtn!("▶ Start K8s", "kubernetes_btn_start");
    let btn_stop = abtn!("■ Stop K8s", "kubernetes_btn_stop");
    let btn_reset = abtn!("↺ Reset K8s", "kubernetes_btn_reset");
    root.append(&actions);

    root.append(&Separator::new(Orientation::Horizontal));

    // kubectl exec row
    let exec_row = GtkBox::new(Orientation::Horizontal, 4);
    exec_row.set_margin_start(12);
    exec_row.set_margin_end(12);
    exec_row.set_margin_top(8);
    exec_row.set_margin_bottom(8);

    let entry_cmd = Entry::builder()
        .placeholder_text("kubectl command (e.g. get pods)")
        .hexpand(true)
        .build();
    entry_cmd.set_widget_name("kubernetes_entry_command");
    entry_cmd.update_property(&[gtk::accessible::Property::Label("kubectl command")]);
    let btn_exec = make_action_button("▶ Exec", "kubernetes_btn_exec");
    exec_row.append(&entry_cmd);
    exec_row.append(&btn_exec);
    root.append(&exec_row);

    let (sw_out, log_buf) = make_output_view("kubernetes_output");
    root.append(&sw_out);

    macro_rules! wire_k8s {
        ($btn:expr, $rpc:ident) => {{
            let h = handle.clone();
            let lb = log_buf.clone();
            let sp = spinner.clone();
            $btn.connect_clicked(move |_| {
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
                            .$rpc(ProfileRequest { profile })
                            .await
                            .map(|r| r.into_inner().message)
                            .map_err(|e| format!("Error: {e}"));
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
        }};
    }

    wire_k8s!(btn_start, kubernetes_start);
    wire_k8s!(btn_stop, kubernetes_stop);
    wire_k8s!(btn_reset, kubernetes_reset);

    // Exec
    {
        let h = handle.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        let ec = entry_cmd.clone();
        btn_exec.connect_clicked(move |_| {
            let command = ec.text().to_string();
            if command.is_empty() {
                set_text(&lb, "Enter a kubectl command first");
                return;
            }
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
                        .kubernetes_exec(KubeExecRequest { profile, command })
                        .await
                        .map(|r| {
                            let resp = r.into_inner();
                            if resp.error.is_empty() {
                                resp.output
                            } else {
                                format!("{}\n{}", resp.output, resp.error)
                            }
                        })
                        .map_err(|e| format!("Error: {e}"));
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
