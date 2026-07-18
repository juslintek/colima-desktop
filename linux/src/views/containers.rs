/// Containers view — list, start/stop/kill/restart/pause/unpause/remove/logs/inspect.
///
/// CONTRACT Part B: ListContainers · ContainerAction · ContainerLogs · InspectContainer
/// · ContainerTop · ContainerStats · ContainerChanges · PruneContainers · CreateContainer
/// · RenameContainer · StreamLogs (streaming).
use gtk::prelude::*;
use gtk::{Box as GtkBox, Entry, Label, ListBox, ListBoxRow, Orientation, Separator};

use crate::app_state::AppHandle;
use crate::client::proto::{
    ContainerActionRequest, CreateContainerRequest, DockerScope, IdRequest,
};
use crate::ui_helpers::{make_action_button, make_output_view, make_surface_header, set_text};

struct ContainerInfo {
    id: String,
    name: String,
    status: String,
    image: String,
}

pub fn build(handle: AppHandle) -> GtkBox {
    let root = GtkBox::new(Orientation::Vertical, 0);
    root.set_widget_name("view_containers");
    root.update_property(&[gtk::accessible::Property::Label("Containers")]);

    let (header, spinner, refresh_btn) = make_surface_header("Containers", "containers");
    root.append(&header);

    // Container list
    let list_box = ListBox::new();
    list_box.set_widget_name("containers_list");
    list_box.update_property(&[gtk::accessible::Property::Label("Container list")]);
    list_box.set_selection_mode(gtk::SelectionMode::Single);
    list_box.set_vexpand(true);

    let sw_list = gtk::ScrolledWindow::builder()
        .child(&list_box)
        .vexpand(true)
        .build();
    root.append(&sw_list);

    root.append(&Separator::new(Orientation::Horizontal));

    // Action row
    let actions = GtkBox::new(Orientation::Horizontal, 4);
    actions.set_margin_start(12);
    actions.set_margin_end(12);
    actions.set_margin_top(6);
    actions.set_margin_bottom(6);

    macro_rules! action_btn {
        ($label:expr, $name:expr) => {{
            let b = make_action_button($label, $name);
            actions.append(&b);
            b
        }};
    }

    let btn_start = action_btn!("▶ Start", "containers_btn_start");
    let btn_stop = action_btn!("■ Stop", "containers_btn_stop");
    let btn_kill = action_btn!("✕ Kill", "containers_btn_kill");
    let btn_restart = action_btn!("↺ Restart", "containers_btn_restart");
    let btn_pause = action_btn!("⏸ Pause", "containers_btn_pause");
    let btn_resume = action_btn!("⏵ Resume", "containers_btn_resume");
    let btn_remove = action_btn!("🗑 Remove", "containers_btn_remove");
    let btn_logs = action_btn!("📋 Logs", "containers_btn_logs");
    let btn_inspect = action_btn!("🔍 Inspect", "containers_btn_inspect");
    let btn_prune = action_btn!("🧹 Prune", "containers_btn_prune");
    root.append(&actions);

    // Create row
    let create_row = GtkBox::new(Orientation::Horizontal, 4);
    create_row.set_margin_start(12);
    create_row.set_margin_end(12);
    create_row.set_margin_bottom(6);

    let entry_name = Entry::builder().placeholder_text("Container name").build();
    entry_name.set_widget_name("containers_entry_name");
    entry_name.update_property(&[gtk::accessible::Property::Label("Container name")]);
    let entry_image = Entry::builder().placeholder_text("Image").build();
    entry_image.set_widget_name("containers_entry_image");
    entry_image.update_property(&[gtk::accessible::Property::Label("Image name")]);
    let btn_create = make_action_button("+ Create", "containers_btn_create");

    create_row.append(&entry_name);
    create_row.append(&entry_image);
    create_row.append(&btn_create);
    root.append(&create_row);

    // Output log
    let (sw_out, log_buf) = make_output_view("containers_output");
    root.append(&sw_out);

    let selected_id = std::rc::Rc::new(std::cell::RefCell::new(String::new()));

    // Track selection
    {
        let sel = selected_id.clone();
        list_box.connect_row_selected(move |_, row| {
            if let Some(r) = row {
                *sel.borrow_mut() = r.widget_name().to_string();
            }
        });
    }

    // Refresh list
    {
        let h = handle.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        let list = list_box.clone();
        refresh_btn.connect_clicked(move |_| {
            sp.set_spinning(true);
            let profile = h.profile();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.docker.clone();
                let lb2 = lb.clone();
                let sp2 = sp.clone();
                let list2 = list.clone();
                let (tx, rx) = async_channel::bounded::<Result<Vec<ContainerInfo>, String>>(1);
                h.rt.spawn(async move {
                    let result = c
                        .list_containers(DockerScope {
                            profile,
                            all: true,
                            host: String::new(),
                            wsl2: false,
                        })
                        .await
                        .map_err(|e| format!("Error: {e}"))
                        .and_then(|r| {
                            let j = r.into_inner();
                            if !j.error.is_empty() {
                                return Err(j.error);
                            }
                            serde_json::from_str::<serde_json::Value>(&j.json)
                                .map_err(|e| format!("JSON parse error: {e}"))
                                .map(|arr| {
                                    arr.as_array()
                                        .cloned()
                                        .unwrap_or_default()
                                        .iter()
                                        .map(|item| {
                                            let id = item["Id"].as_str().unwrap_or("").to_owned();
                                            let name = item["Names"]
                                                .as_array()
                                                .and_then(|a| a.first())
                                                .and_then(|v| v.as_str())
                                                .unwrap_or(&id)
                                                .trim_start_matches('/')
                                                .to_owned();
                                            ContainerInfo {
                                                id,
                                                name,
                                                status: item["Status"]
                                                    .as_str()
                                                    .unwrap_or("")
                                                    .to_owned(),
                                                image: item["Image"]
                                                    .as_str()
                                                    .unwrap_or("")
                                                    .to_owned(),
                                            }
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
                            Ok(containers) => {
                                for ct in containers {
                                    let row_lbl = Label::new(Some(&format!(
                                        "{}  [{}]  {}",
                                        ct.name, ct.status, ct.image
                                    )));
                                    row_lbl.set_halign(gtk::Align::Start);
                                    row_lbl.set_margin_start(8);
                                    row_lbl.set_margin_end(8);
                                    row_lbl.set_margin_top(4);
                                    row_lbl.set_margin_bottom(4);
                                    let row = ListBoxRow::new();
                                    row.set_widget_name(&ct.id);
                                    row.update_property(&[gtk::accessible::Property::Label(
                                        &ct.name,
                                    )]);
                                    row.set_child(Some(&row_lbl));
                                    list2.append(&row);
                                }
                            }
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

    // Generic container action helper macro — only sends a plain String result via channel
    macro_rules! wire_action {
        ($btn:expr, $action:expr) => {{
            let h = handle.clone();
            let lb = log_buf.clone();
            let sp = spinner.clone();
            let sel = selected_id.clone();
            $btn.connect_clicked(move |_| {
                let id = sel.borrow().clone();
                if id.is_empty() {
                    set_text(&lb, "Select a container first");
                    return;
                }
                sp.set_spinning(true);
                let profile = h.profile();
                let mut state = h.state.lock().unwrap();
                if let Some(ref mut client) = state.daemon {
                    let mut c = client.docker.clone();
                    let lb2 = lb.clone();
                    let sp2 = sp.clone();
                    let action = $action.to_string();
                    let (tx, rx) = async_channel::bounded::<Result<String, String>>(1);
                    h.rt.spawn(async move {
                        let result = c
                            .container_action(ContainerActionRequest {
                                id,
                                action,
                                profile,
                                host: String::new(),
                                wsl2: false,
                            })
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

    wire_action!(btn_start, "start");
    wire_action!(btn_stop, "stop");
    wire_action!(btn_kill, "kill");
    wire_action!(btn_restart, "restart");
    wire_action!(btn_pause, "pause");
    wire_action!(btn_resume, "unpause");
    wire_action!(btn_remove, "remove");

    // Logs
    {
        let h = handle.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        let sel = selected_id.clone();
        btn_logs.connect_clicked(move |_| {
            let id = sel.borrow().clone();
            if id.is_empty() {
                set_text(&lb, "Select a container first");
                return;
            }
            sp.set_spinning(true);
            let profile = h.profile();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.docker.clone();
                let lb2 = lb.clone();
                let sp2 = sp.clone();
                let (tx, rx) = async_channel::bounded::<Result<String, String>>(1);
                h.rt.spawn(async move {
                    let result = c
                        .container_logs(IdRequest {
                            id,
                            profile,
                            host: String::new(),
                            wsl2: false,
                        })
                        .await
                        .map(|r| {
                            let j = r.into_inner();
                            if j.error.is_empty() {
                                j.json
                            } else {
                                j.error
                            }
                        })
                        .map_err(|e| format!("Logs error: {e}"));
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

    // Inspect
    {
        let h = handle.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        let sel = selected_id.clone();
        btn_inspect.connect_clicked(move |_| {
            let id = sel.borrow().clone();
            if id.is_empty() {
                set_text(&lb, "Select a container first");
                return;
            }
            sp.set_spinning(true);
            let profile = h.profile();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.docker.clone();
                let lb2 = lb.clone();
                let sp2 = sp.clone();
                let (tx, rx) = async_channel::bounded::<Result<String, String>>(1);
                h.rt.spawn(async move {
                    let result = c
                        .inspect_container(IdRequest {
                            id,
                            profile,
                            host: String::new(),
                            wsl2: false,
                        })
                        .await
                        .map(|r| {
                            let j = r.into_inner();
                            serde_json::from_str::<serde_json::Value>(&j.json)
                                .map(|v| serde_json::to_string_pretty(&v).unwrap_or(j.json.clone()))
                                .unwrap_or(j.json)
                        })
                        .map_err(|e| format!("Inspect error: {e}"));
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
        btn_prune.connect_clicked(move |_| {
            sp.set_spinning(true);
            let profile = h.profile();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.docker.clone();
                let lb2 = lb.clone();
                let sp2 = sp.clone();
                let (tx, rx) = async_channel::bounded::<Result<String, String>>(1);
                h.rt.spawn(async move {
                    let result = c
                        .prune_containers(DockerScope {
                            profile,
                            all: false,
                            host: String::new(),
                            wsl2: false,
                        })
                        .await
                        .map(|r| {
                            let j = r.into_inner();
                            if j.error.is_empty() {
                                j.json
                            } else {
                                j.error
                            }
                        })
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

    // Create container
    {
        let h = handle.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        let en = entry_name.clone();
        let ei = entry_image.clone();
        btn_create.connect_clicked(move |_| {
            let name = en.text().to_string();
            let image = ei.text().to_string();
            if image.is_empty() {
                set_text(&lb, "Image name is required");
                return;
            }
            sp.set_spinning(true);
            let profile = h.profile();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.docker.clone();
                let lb2 = lb.clone();
                let sp2 = sp.clone();
                let (tx, rx) = async_channel::bounded::<Result<String, String>>(1);
                h.rt.spawn(async move {
                    let result = c
                        .create_container(CreateContainerRequest {
                            name,
                            image,
                            profile,
                            host: String::new(),
                            wsl2: false,
                        })
                        .await
                        .map(|r| {
                            let j = r.into_inner();
                            if j.error.is_empty() {
                                j.json
                            } else {
                                j.error
                            }
                        })
                        .map_err(|e| format!("Create error: {e}"));
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
