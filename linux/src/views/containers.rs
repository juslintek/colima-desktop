/// Containers view — list, start/stop/kill/restart/pause/unpause/remove/logs/inspect.
///
/// CONTRACT Part B: ListContainers · ContainerAction · ContainerLogs · InspectContainer
/// · ContainerTop · ContainerStats · ContainerChanges · PruneContainers · CreateContainer
/// · RenameContainer · StreamLogs (streaming).
use gtk::prelude::*;
use gtk::{Box as GtkBox, Entry, Label, ListBox, ListBoxRow, Orientation, Separator};

use crate::app_state::AppHandle;
use crate::ui_helpers::{
    confirm_destructive, container_action_is_destructive, make_action_button, make_output_view,
    make_surface_header, set_text, status_message,
};

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

    let details = GtkBox::new(Orientation::Horizontal, 4);
    details.set_margin_start(12);
    details.set_margin_end(12);
    details.set_margin_bottom(6);
    let btn_top = make_action_button("Top", "containers_btn_top");
    let btn_stats = make_action_button("Stats", "containers_btn_stats");
    let btn_changes = make_action_button("Changes", "containers_btn_changes");
    let btn_stream_logs = make_action_button("Live Logs", "containers_btn_stream_logs");
    let btn_stream_stats = make_action_button("Live Stats", "containers_btn_stream_stats");
    let btn_cancel_stream = make_action_button("Cancel Stream", "containers_btn_cancel_stream");
    for button in [
        &btn_top,
        &btn_stats,
        &btn_changes,
        &btn_stream_logs,
        &btn_stream_stats,
        &btn_cancel_stream,
    ] {
        details.append(button);
    }
    root.append(&details);

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
    let entry_rename = Entry::builder().placeholder_text("New name").build();
    entry_rename.set_widget_name("containers_entry_rename");
    entry_rename.update_property(&[gtk::accessible::Property::Label("New container name")]);
    let btn_rename = make_action_button("Rename", "containers_btn_rename");

    create_row.append(&entry_name);
    create_row.append(&entry_image);
    create_row.append(&btn_create);
    create_row.append(&entry_rename);
    create_row.append(&btn_rename);
    root.append(&create_row);

    // Output log
    let (sw_out, log_buf) = make_output_view("containers_output");
    root.append(&sw_out);

    let selected_id = std::rc::Rc::new(std::cell::RefCell::new(String::new()));
    let stream_abort = std::rc::Rc::new(std::cell::RefCell::new(None::<tokio::task::AbortHandle>));

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
            let target = h.docker_target();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.docker.clone();
                let lb2 = lb.clone();
                let sp2 = sp.clone();
                let list2 = list.clone();
                let (tx, rx) = async_channel::bounded::<Result<Vec<ContainerInfo>, String>>(1);
                h.rt.spawn(async move {
                    let result = c
                        .list_containers(target.scope(true))
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

    // Generic container action helper macro — only sends a plain String result via channel.
    // Whether an action is destructive (and therefore gated behind confirm_destructive) is
    // decided by the single tested `container_action_is_destructive` classifier, so no action
    // can silently bypass the confirmation gate (Requirement 6.6, Property 13).
    macro_rules! wire_action {
        ($btn:expr, $action:expr) => {{
            let h = handle.clone();
            let lb = log_buf.clone();
            let sp = spinner.clone();
            let sel = selected_id.clone();
            $btn.connect_clicked(move |source| {
                let id = sel.borrow().clone();
                if id.is_empty() {
                    set_text(&lb, "Select a container first");
                    return;
                }
                if container_action_is_destructive($action) {
                    let h2 = h.clone();
                    let lb2 = lb.clone();
                    let sp2 = sp.clone();
                    confirm_destructive(
                        source,
                        concat!("Confirm container ", $action),
                        &format!("Apply '{}' to container {}?", $action, id),
                        move || run_container_action(h2, sp2, lb2, id, $action),
                    );
                } else {
                    run_container_action(h.clone(), sp.clone(), lb.clone(), id, $action);
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
            let target = h.docker_target();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.docker.clone();
                let lb2 = lb.clone();
                let sp2 = sp.clone();
                let (tx, rx) = async_channel::bounded::<Result<String, String>>(1);
                h.rt.spawn(async move {
                    let result = c
                        .container_logs(target.id_request(id))
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
            let target = h.docker_target();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.docker.clone();
                let lb2 = lb.clone();
                let sp2 = sp.clone();
                let (tx, rx) = async_channel::bounded::<Result<String, String>>(1);
                h.rt.spawn(async move {
                    let result = c
                        .inspect_container(target.id_request(id))
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
        btn_prune.connect_clicked(move |source| {
            let h2 = h.clone();
            let lb2 = lb.clone();
            let sp2 = sp.clone();
            confirm_destructive(
                source,
                "Prune stopped containers?",
                "Remove all stopped containers in the selected provider/profile?",
                move || run_prune_containers(h2, sp2, lb2),
            );
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
            let target = h.docker_target();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.docker.clone();
                let lb2 = lb.clone();
                let sp2 = sp.clone();
                let (tx, rx) = async_channel::bounded::<Result<String, String>>(1);
                h.rt.spawn(async move {
                    let result = c
                        .create_container(target.create_container(name, image))
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

    // Rename propagates the same provider snapshot as every other Docker action.
    {
        let h = handle.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        let sel = selected_id.clone();
        let entry = entry_rename.clone();
        btn_rename.connect_clicked(move |_| {
            let id = sel.borrow().clone();
            let new_name = entry.text().to_string();
            if id.is_empty() || new_name.trim().is_empty() {
                set_text(&lb, "Select a container and enter a new name");
                return;
            }
            let target = h.docker_target();
            let client = h.state.lock().unwrap().daemon.clone();
            let Some(client) = client else {
                set_text(&lb, "Not connected");
                return;
            };
            sp.set_spinning(true);
            let mut c = client.docker;
            let lb2 = lb.clone();
            let sp2 = sp.clone();
            let (tx, rx) = async_channel::bounded(1);
            h.rt.spawn(async move {
                let result = c
                    .rename_container(target.rename_request(id, new_name))
                    .await
                    .map_err(|error| format!("Rename error: {error}"))
                    .and_then(|response| status_message(response.into_inner()));
                let _ = tx.send(result).await;
            });
            glib::spawn_future_local(async move {
                if let Ok(result) = rx.recv().await {
                    set_text(&lb2, &result.unwrap_or_else(|error| error));
                }
                sp2.set_spinning(false);
            });
        });
    }

    macro_rules! wire_query {
        ($button:expr, $kind:expr) => {{
            let h = handle.clone();
            let lb = log_buf.clone();
            let sp = spinner.clone();
            let sel = selected_id.clone();
            $button.connect_clicked(move |_| {
                let id = sel.borrow().clone();
                if id.is_empty() {
                    set_text(&lb, "Select a container first");
                } else {
                    run_container_query(h.clone(), sp.clone(), lb.clone(), id, $kind);
                }
            });
        }};
    }
    wire_query!(btn_top, ContainerQuery::Top);
    wire_query!(btn_stats, ContainerQuery::Stats);
    wire_query!(btn_changes, ContainerQuery::Changes);

    macro_rules! wire_stream {
        ($button:expr, $kind:expr) => {{
            let h = handle.clone();
            let lb = log_buf.clone();
            let sp = spinner.clone();
            let sel = selected_id.clone();
            let running = stream_abort.clone();
            $button.connect_clicked(move |_| {
                let id = sel.borrow().clone();
                if id.is_empty() {
                    set_text(&lb, "Select a container first");
                    return;
                }
                if let Some(abort) = running.borrow_mut().take() {
                    abort.abort();
                }
                if let Some(abort) =
                    start_container_stream(h.clone(), sp.clone(), lb.clone(), id, $kind)
                {
                    *running.borrow_mut() = Some(abort);
                }
            });
        }};
    }
    wire_stream!(btn_stream_logs, ContainerStream::Logs);
    wire_stream!(btn_stream_stats, ContainerStream::Stats);
    {
        let running = stream_abort.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        btn_cancel_stream.connect_clicked(move |_| {
            if let Some(abort) = running.borrow_mut().take() {
                abort.abort();
                set_text(&lb, "Stream cancelled");
            }
            sp.set_spinning(false);
        });
    }

    root
}

fn run_container_action(
    handle: AppHandle,
    spinner: gtk::Spinner,
    output: gtk::TextBuffer,
    id: String,
    action: &'static str,
) {
    let target = handle.docker_target();
    let client = handle.state.lock().unwrap().daemon.clone();
    let Some(client) = client else {
        spinner.set_spinning(false);
        set_text(&output, "Not connected");
        return;
    };
    spinner.set_spinning(true);
    let mut c = client.docker;
    let output2 = output.clone();
    let spinner2 = spinner.clone();
    let (tx, rx) = async_channel::bounded(1);
    handle.rt.spawn(async move {
        let result = c
            .container_action(target.container_action(id, action))
            .await
            .map_err(|error| format!("Container {action} error: {error}"))
            .and_then(|response| status_message(response.into_inner()));
        let _ = tx.send(result).await;
    });
    glib::spawn_future_local(async move {
        if let Ok(result) = rx.recv().await {
            set_text(&output2, &result.unwrap_or_else(|error| error));
        }
        spinner2.set_spinning(false);
    });
}

fn run_prune_containers(handle: AppHandle, spinner: gtk::Spinner, output: gtk::TextBuffer) {
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
            .prune_containers(target.scope(false))
            .await
            .map_err(|error| format!("Prune error: {error}"))
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

#[derive(Clone, Copy)]
enum ContainerQuery {
    Top,
    Stats,
    Changes,
}

fn run_container_query(
    handle: AppHandle,
    spinner: gtk::Spinner,
    output: gtk::TextBuffer,
    id: String,
    query: ContainerQuery,
) {
    let target = handle.docker_target();
    let client = handle.state.lock().unwrap().daemon.clone();
    let Some(client) = client else {
        set_text(&output, "Not connected");
        return;
    };
    spinner.set_spinning(true);
    let mut c = client.docker;
    let (tx, rx) = async_channel::bounded(1);
    handle.rt.spawn(async move {
        let request = target.id_request(id);
        let response = match query {
            ContainerQuery::Top => c.container_top(request).await,
            ContainerQuery::Stats => c.container_stats(request).await,
            ContainerQuery::Changes => c.container_changes(request).await,
        };
        let result = response
            .map_err(|error| format!("Container query error: {error}"))
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

#[derive(Clone, Copy)]
enum ContainerStream {
    Logs,
    Stats,
}

fn start_container_stream(
    handle: AppHandle,
    spinner: gtk::Spinner,
    output: gtk::TextBuffer,
    id: String,
    kind: ContainerStream,
) -> Option<tokio::task::AbortHandle> {
    let target = handle.docker_target();
    let client = handle.state.lock().unwrap().daemon.clone()?;
    spinner.set_spinning(true);
    let mut c = client.docker;
    let (tx, rx) = async_channel::unbounded::<Result<String, String>>();
    let task = handle.rt.spawn(async move {
        let request = target.id_request(id);
        let response = match kind {
            ContainerStream::Logs => c.stream_logs(request).await,
            ContainerStream::Stats => c.stream_stats(request).await,
        };
        match response {
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
                        let _ = tx.send(Err(format!("Stream error: {error}"))).await;
                        break;
                    }
                }
            },
            Err(error) => {
                let _ = tx.send(Err(format!("Stream start error: {error}"))).await;
            }
        }
    });
    let abort = task.abort_handle();
    glib::spawn_future_local(async move {
        let mut accumulated = String::new();
        while let Ok(item) = rx.recv().await {
            match item {
                Ok(line) => {
                    accumulated.push_str(&line);
                    accumulated.push('\n');
                    if accumulated.len() > 100_000 {
                        accumulated.drain(..50_000);
                    }
                    set_text(&output, &accumulated);
                }
                Err(error) => {
                    accumulated.push_str(&error);
                    set_text(&output, &accumulated);
                    break;
                }
            }
        }
        spinner.set_spinning(false);
    });
    Some(abort)
}
