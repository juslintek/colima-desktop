/// Volumes view — list, create, remove, inspect, prune.
///
/// CONTRACT Part B: ListVolumes · CreateVolume · RemoveVolume · InspectVolume · PruneVolumes.
use gtk::prelude::*;
use gtk::{Box as GtkBox, Entry, Label, ListBox, ListBoxRow, Orientation, Separator};

use crate::app_state::AppHandle;
use crate::ui_helpers::{
    confirm_destructive, make_action_button, make_output_view, make_surface_header, set_text,
    status_message,
};

struct VolumeInfo {
    name: String,
    driver: String,
}

pub fn build(handle: AppHandle) -> GtkBox {
    let root = GtkBox::new(Orientation::Vertical, 0);
    root.set_widget_name("view_volumes");
    root.update_property(&[gtk::accessible::Property::Label("Volumes")]);

    let (header, spinner, refresh_btn) = make_surface_header("Volumes", "volumes");
    root.append(&header);

    let list_box = ListBox::new();
    list_box.set_widget_name("volumes_list");
    list_box.update_property(&[gtk::accessible::Property::Label("Volume list")]);
    list_box.set_selection_mode(gtk::SelectionMode::Single);
    let sw_list = gtk::ScrolledWindow::builder()
        .child(&list_box)
        .vexpand(true)
        .build();
    root.append(&sw_list);

    root.append(&Separator::new(Orientation::Horizontal));

    let actions = GtkBox::new(Orientation::Horizontal, 4);
    actions.set_margin_start(12);
    actions.set_margin_end(12);
    actions.set_margin_top(6);
    actions.set_margin_bottom(6);

    macro_rules! abtn {
        ($l:expr, $n:expr) => {{
            let b = make_action_button($l, $n);
            actions.append(&b);
            b
        }};
    }
    let btn_remove = abtn!("🗑 Remove", "volumes_btn_remove");
    let btn_inspect = abtn!("🔍 Inspect", "volumes_btn_inspect");
    let btn_prune = abtn!("🧹 Prune", "volumes_btn_prune");
    root.append(&actions);

    let create_row = GtkBox::new(Orientation::Horizontal, 4);
    create_row.set_margin_start(12);
    create_row.set_margin_end(12);
    create_row.set_margin_bottom(6);
    let entry_name = Entry::builder()
        .placeholder_text("Volume name")
        .hexpand(true)
        .build();
    entry_name.set_widget_name("volumes_entry_name");
    entry_name.update_property(&[gtk::accessible::Property::Label("Volume name")]);
    let btn_create = make_action_button("+ Create", "volumes_btn_create");
    create_row.append(&entry_name);
    create_row.append(&btn_create);
    root.append(&create_row);

    let (sw_out, log_buf) = make_output_view("volumes_output");
    root.append(&sw_out);

    let selected = std::rc::Rc::new(std::cell::RefCell::new(String::new()));
    {
        let sel = selected.clone();
        list_box.connect_row_selected(move |_, row| {
            if let Some(r) = row {
                *sel.borrow_mut() = r.widget_name().to_string();
            }
        });
    }

    // Refresh
    {
        let h = handle.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        let list = list_box.clone();
        refresh_btn.connect_clicked(move |_| {
            sp.set_spinning(true);
            let target = h.docker_target();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.docker.clone();
                let lb2 = lb.clone();
                let sp2 = sp.clone();
                let list2 = list.clone();
                let (tx, rx) = async_channel::bounded::<Result<Vec<VolumeInfo>, String>>(1);
                h.rt.spawn(async move {
                    let result = c
                        .list_volumes(target.scope(false))
                        .await
                        .map_err(|e| format!("Error: {e}"))
                        .and_then(|r| {
                            let j = r.into_inner();
                            serde_json::from_str::<serde_json::Value>(&j.json)
                                .map_err(|e| format!("JSON parse error: {e}"))
                                .map(|v| {
                                    let items = v["Volumes"]
                                        .as_array()
                                        .or_else(|| v.as_array())
                                        .cloned()
                                        .unwrap_or_default();
                                    items
                                        .iter()
                                        .map(|item| VolumeInfo {
                                            name: item["Name"].as_str().unwrap_or("").to_owned(),
                                            driver: item["Driver"]
                                                .as_str()
                                                .unwrap_or("")
                                                .to_owned(),
                                        })
                                        .collect()
                                })
                        });
                    let _ = tx.send(result).await;
                });
                glib::spawn_future_local(async move {
                    sp2.set_spinning(false);
                    while let Some(child) = list2.first_child() {
                        list2.remove(&child);
                    }
                    if let Ok(result) = rx.recv().await {
                        match result {
                            Ok(volumes) => {
                                for v in volumes {
                                    let lbl =
                                        Label::new(Some(&format!("{}  ({})", v.name, v.driver)));
                                    lbl.set_halign(gtk::Align::Start);
                                    lbl.set_margin_start(8);
                                    lbl.set_margin_top(4);
                                    lbl.set_margin_bottom(4);
                                    let row = ListBoxRow::new();
                                    row.set_widget_name(&v.name);
                                    row.update_property(&[gtk::accessible::Property::Label(
                                        &v.name,
                                    )]);
                                    row.set_child(Some(&lbl));
                                    list2.append(&row);
                                }
                            }
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

    // Remove
    {
        let h = handle.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        let sel = selected.clone();
        btn_remove.connect_clicked(move |source| {
            let name = sel.borrow().clone();
            if name.is_empty() {
                set_text(&lb, "Select a volume first");
                return;
            }
            let h2 = h.clone();
            let lb2 = lb.clone();
            let sp2 = sp.clone();
            confirm_destructive(
                source,
                "Remove volume?",
                &format!("Remove volume '{name}'?"),
                move || run_remove_volume(h2, sp2, lb2, name),
            );
        });
    }

    // Inspect
    {
        let h = handle.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        let sel = selected.clone();
        btn_inspect.connect_clicked(move |_| {
            let name = sel.borrow().clone();
            if name.is_empty() {
                set_text(&lb, "Select a volume first");
                return;
            }
            sp.set_spinning(true);
            let target = h.docker_target();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.docker.clone();
                let lb2 = lb.clone();
                let sp2 = sp.clone();
                let (tx, rx) = async_channel::bounded::<Result<String, String>>(1);
                h.rt.spawn(async move {
                    let result = c
                        .inspect_volume(target.name_request(name))
                        .await
                        .map(|r| {
                            let j = r.into_inner();
                            serde_json::from_str::<serde_json::Value>(&j.json)
                                .map(|v| serde_json::to_string_pretty(&v).unwrap_or(j.json.clone()))
                                .unwrap_or(j.json)
                        })
                        .map_err(|e| format!("Error: {e}"));
                    let _ = tx.send(result).await;
                });
                glib::spawn_future_local(async move {
                    sp2.set_spinning(false);
                    if let Ok(result) = rx.recv().await {
                        match result {
                            Ok(text) => set_text(&lb2, &text),
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
            let h2 = h.clone();
            let lb2 = lb.clone();
            let sp2 = sp.clone();
            confirm_destructive(
                source,
                "Prune unused volumes?",
                "Remove every unused volume in the selected provider/profile?",
                move || run_prune_volumes(h2, sp2, lb2),
            );
        });
    }

    // Create
    {
        let h = handle.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        let en = entry_name.clone();
        btn_create.connect_clicked(move |_| {
            let name = en.text().to_string();
            if name.is_empty() {
                set_text(&lb, "Enter a volume name first");
                return;
            }
            sp.set_spinning(true);
            let target = h.docker_target();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.docker.clone();
                let lb2 = lb.clone();
                let sp2 = sp.clone();
                let (tx, rx) = async_channel::bounded::<Result<String, String>>(1);
                h.rt.spawn(async move {
                    let result = c
                        .create_volume(target.name_request(name))
                        .await
                        .map(|r| {
                            let j = r.into_inner();
                            if j.error.is_empty() {
                                j.json
                            } else {
                                j.error
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

fn run_remove_volume(
    handle: AppHandle,
    spinner: gtk::Spinner,
    output: gtk::TextBuffer,
    name: String,
) {
    let target = handle.docker_target();
    let client = handle.state.lock().unwrap().daemon.clone();
    let Some(client) = client else {
        set_text(&output, "Not connected");
        return;
    };
    spinner.set_spinning(true);
    let mut client = client.docker;
    let (tx, rx) = async_channel::bounded(1);
    handle.rt.spawn(async move {
        let result = client
            .remove_volume(target.name_request(name))
            .await
            .map_err(|error| format!("Remove volume error: {error}"))
            .and_then(|response| status_message(response.into_inner()));
        let _ = tx.send(result).await;
    });
    glib::spawn_future_local(async move {
        if let Ok(result) = rx.recv().await {
            set_text(&output, &result.unwrap_or_else(|error| error));
        }
        spinner.set_spinning(false);
    });
}

fn run_prune_volumes(handle: AppHandle, spinner: gtk::Spinner, output: gtk::TextBuffer) {
    let target = handle.docker_target();
    let client = handle.state.lock().unwrap().daemon.clone();
    let Some(client) = client else {
        set_text(&output, "Not connected");
        return;
    };
    spinner.set_spinning(true);
    let mut client = client.docker;
    let (tx, rx) = async_channel::bounded(1);
    handle.rt.spawn(async move {
        let result = client
            .prune_volumes(target.scope(false))
            .await
            .map_err(|error| format!("Prune volume error: {error}"))
            .and_then(|response| {
                let response = response.into_inner();
                if response.error.is_empty() {
                    Ok(response.json)
                } else {
                    Err(response.error)
                }
            });
        let _ = tx.send(result).await;
    });
    glib::spawn_future_local(async move {
        if let Ok(result) = rx.recv().await {
            set_text(&output, &result.unwrap_or_else(|error| error));
        }
        spinner.set_spinning(false);
    });
}
