/// Runtime view — SwitchRuntime, UpdateRuntime.
///
/// CONTRACT Part A: SwitchRuntime · UpdateRuntime.
use gtk::prelude::*;
use gtk::{Box as GtkBox, ComboBoxText, Label, Orientation, Separator};

use crate::app_state::AppHandle;
use crate::client::proto::{ProfileRequest, SwitchRuntimeRequest};
use crate::ui_helpers::{make_action_button, make_output_view, make_surface_header, set_text};

pub fn build(handle: AppHandle) -> GtkBox {
    let root = GtkBox::new(Orientation::Vertical, 0);
    root.set_widget_name("view_runtime");
    root.update_property(&[gtk::accessible::Property::Label("Runtime Controls")]);

    let (header, spinner, _) = make_surface_header("Runtime Controls", "runtime");
    root.append(&header);

    let row = GtkBox::new(Orientation::Horizontal, 8);
    row.set_margin_start(12);
    row.set_margin_end(12);
    row.set_margin_top(12);
    row.set_margin_bottom(12);

    let lbl = Label::new(Some("Runtime:"));
    lbl.set_widget_name("runtime_label");
    lbl.add_css_class("dim-label");

    let combo = ComboBoxText::new();
    combo.set_widget_name("runtime_combo");
    combo.update_property(&[gtk::accessible::Property::Label("Select runtime")]);
    for rt in &["docker", "containerd", "incus"] {
        combo.append_text(rt);
    }
    combo.set_active(Some(0));

    let btn_switch = make_action_button("⟳ Switch", "runtime_btn_switch");
    let btn_update = make_action_button("⬆ Update", "runtime_btn_update");

    row.append(&lbl);
    row.append(&combo);
    row.append(&btn_switch);
    row.append(&btn_update);
    root.append(&row);

    root.append(&Separator::new(Orientation::Horizontal));

    let (sw_out, log_buf) = make_output_view("runtime_output");
    root.append(&sw_out);

    // Switch Runtime
    {
        let h = handle.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        let cb = combo.clone();
        btn_switch.connect_clicked(move |_| {
            let runtime = cb.active_text().map(|s| s.to_string()).unwrap_or_default();
            if runtime.is_empty() {
                set_text(&lb, "Select a runtime first");
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
                        .switch_runtime(SwitchRuntimeRequest { profile, runtime })
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
    }

    // Update Runtime
    {
        let h = handle.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        btn_update.connect_clicked(move |_| {
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
                        .update_runtime(ProfileRequest { profile })
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
    }

    root
}
