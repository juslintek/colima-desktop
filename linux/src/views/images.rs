/// Images view — list, pull, remove, inspect, history, tag, push, search, prune.
///
/// CONTRACT Part B: ListImages · PullImage(stream) · RemoveImage · InspectImage
/// · ImageHistory · TagImage · PushImage(stream) · SearchImages · PruneImages.
use gtk::prelude::*;
use gtk::{Box as GtkBox, Entry, Label, ListBox, ListBoxRow, Orientation, Separator};

use crate::app_state::AppHandle;
use crate::ui_helpers::{
    confirm_destructive, make_action_button, make_output_view, make_surface_header, set_text,
    status_message,
};

struct ImageInfo {
    /// "id::name" composite key used as widget name for selection
    widget_key: String,
    tags: String,
    size_mb: f64,
}

pub fn build(handle: AppHandle) -> GtkBox {
    let root = GtkBox::new(Orientation::Vertical, 0);
    root.set_widget_name("view_images");
    root.update_property(&[gtk::accessible::Property::Label("Images")]);

    let (header, spinner, refresh_btn) = make_surface_header("Images", "images");
    root.append(&header);

    // Image list
    let list_box = ListBox::new();
    list_box.set_widget_name("images_list");
    list_box.update_property(&[gtk::accessible::Property::Label("Image list")]);
    list_box.set_selection_mode(gtk::SelectionMode::Single);
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

    macro_rules! abtn {
        ($l:expr, $n:expr) => {{
            let b = make_action_button($l, $n);
            actions.append(&b);
            b
        }};
    }
    let btn_remove = abtn!("🗑 Remove", "images_btn_remove");
    let btn_inspect = abtn!("🔍 Inspect", "images_btn_inspect");
    let btn_history = abtn!("📜 History", "images_btn_history");
    let btn_prune = abtn!("🧹 Prune", "images_btn_prune");
    root.append(&actions);

    // Pull / search row
    let op_row = GtkBox::new(Orientation::Horizontal, 4);
    op_row.set_margin_start(12);
    op_row.set_margin_end(12);
    op_row.set_margin_bottom(6);

    let entry_img = Entry::builder()
        .placeholder_text("image:tag")
        .hexpand(true)
        .build();
    entry_img.set_widget_name("images_entry_image");
    entry_img.update_property(&[gtk::accessible::Property::Label("Image name or tag")]);

    let btn_pull = make_action_button("⬇ Pull", "images_btn_pull");
    let btn_search = make_action_button("🔎 Search", "images_btn_search");
    let btn_push = make_action_button("⬆ Push", "images_btn_push");
    let btn_cancel_transfer = make_action_button("Cancel", "images_btn_cancel_transfer");

    op_row.append(&entry_img);
    op_row.append(&btn_pull);
    op_row.append(&btn_search);
    op_row.append(&btn_push);
    op_row.append(&btn_cancel_transfer);
    root.append(&op_row);

    let tag_row = GtkBox::new(Orientation::Horizontal, 4);
    tag_row.set_margin_start(12);
    tag_row.set_margin_end(12);
    tag_row.set_margin_bottom(6);
    let entry_repo = Entry::builder()
        .placeholder_text("Repository")
        .hexpand(true)
        .build();
    entry_repo.set_widget_name("images_entry_repository");
    let entry_tag = Entry::builder().placeholder_text("Tag").build();
    entry_tag.set_widget_name("images_entry_tag");
    let btn_tag = make_action_button("Tag", "images_btn_tag");
    tag_row.append(&entry_repo);
    tag_row.append(&entry_tag);
    tag_row.append(&btn_tag);
    root.append(&tag_row);

    let (sw_out, log_buf) = make_output_view("images_output");
    root.append(&sw_out);

    let selected_id = std::rc::Rc::new(std::cell::RefCell::new(String::new()));
    let selected_name = std::rc::Rc::new(std::cell::RefCell::new(String::new()));
    let transfer_abort =
        std::rc::Rc::new(std::cell::RefCell::new(None::<tokio::task::AbortHandle>));

    {
        let sel_id = selected_id.clone();
        let sel_name = selected_name.clone();
        list_box.connect_row_selected(move |_, row| {
            if let Some(r) = row {
                let wn = r.widget_name().to_string();
                let mut parts = wn.splitn(2, "::");
                let id = parts.next().unwrap_or("").to_owned();
                let name = parts.next().unwrap_or("").to_owned();
                *sel_id.borrow_mut() = id;
                *sel_name.borrow_mut() = name;
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
                let (tx, rx) = async_channel::bounded::<Result<Vec<ImageInfo>, String>>(1);
                h.rt.spawn(async move {
                    let result = c
                        .list_images(target.scope(false))
                        .await
                        .map_err(|e| format!("Error: {e}"))
                        .and_then(|r| {
                            let j = r.into_inner();
                            serde_json::from_str::<serde_json::Value>(&j.json)
                                .map_err(|e| format!("JSON parse error: {e}"))
                                .map(|arr| {
                                    arr.as_array()
                                        .cloned()
                                        .unwrap_or_default()
                                        .iter()
                                        .map(|item| {
                                            let id = item["Id"].as_str().unwrap_or("").to_owned();
                                            let tags = item["RepoTags"]
                                                .as_array()
                                                .and_then(|a| a.first())
                                                .and_then(|v| v.as_str())
                                                .unwrap_or("<none>")
                                                .to_owned();
                                            let size = item["Size"].as_i64().unwrap_or(0);
                                            ImageInfo {
                                                widget_key: format!("{id}::{tags}"),
                                                tags,
                                                size_mb: size as f64 / 1_048_576.0,
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
                            Ok(images) => {
                                for img in images {
                                    let lbl = Label::new(Some(&format!(
                                        "{}  ({:.1} MB)",
                                        img.tags, img.size_mb
                                    )));
                                    lbl.set_halign(gtk::Align::Start);
                                    lbl.set_margin_start(8);
                                    lbl.set_margin_top(4);
                                    lbl.set_margin_bottom(4);
                                    let row = ListBoxRow::new();
                                    row.set_widget_name(&img.widget_key);
                                    row.update_property(&[gtk::accessible::Property::Label(
                                        &img.tags,
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
        let sel = selected_id.clone();
        btn_remove.connect_clicked(move |source| {
            let id = sel.borrow().clone();
            if id.is_empty() {
                set_text(&lb, "Select an image first");
                return;
            }
            let h2 = h.clone();
            let lb2 = lb.clone();
            let sp2 = sp.clone();
            confirm_destructive(
                source,
                "Remove image?",
                &format!("Remove image {id}?"),
                move || run_remove_image(h2, sp2, lb2, id),
            );
        });
    }

    // Inspect
    {
        let h = handle.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        let sel = selected_name.clone();
        btn_inspect.connect_clicked(move |_| {
            let name = sel.borrow().clone();
            if name.is_empty() {
                set_text(&lb, "Select an image first");
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
                        .inspect_image(target.name_request(name))
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

    // History
    {
        let h = handle.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        let sel = selected_name.clone();
        btn_history.connect_clicked(move |_| {
            let name = sel.borrow().clone();
            if name.is_empty() {
                set_text(&lb, "Select an image first");
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
                        .image_history(target.name_request(name))
                        .await
                        .map(|r| {
                            let j = r.into_inner();
                            if j.error.is_empty() {
                                j.json
                            } else {
                                j.error
                            }
                        })
                        .map_err(|e| format!("History error: {e}"));
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
                "Prune unused images?",
                "Remove dangling images in the selected provider/profile?",
                move || run_prune_images(h2, sp2, lb2),
            );
        });
    }

    // Pull stream with incremental progress and the shared transfer cancel.
    {
        let h = handle.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        let ei = entry_img.clone();
        let running = transfer_abort.clone();
        btn_pull.connect_clicked(move |_| {
            let name = ei.text().to_string();
            if name.is_empty() {
                set_text(&lb, "Enter image:tag first");
                return;
            }
            if let Some(abort) = running.borrow_mut().take() {
                abort.abort();
            }
            if let Some(abort) =
                start_image_transfer(h.clone(), sp.clone(), lb.clone(), name, ImageTransfer::Pull)
            {
                *running.borrow_mut() = Some(abort);
            } else {
                set_text(&lb, "Not connected");
            }
        });
    }

    // Search
    {
        let h = handle.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        let ei = entry_img.clone();
        btn_search.connect_clicked(move |_| {
            let term = ei.text().to_string();
            if term.is_empty() {
                set_text(&lb, "Enter search term first");
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
                        .search_images(target.search_request(term))
                        .await
                        .map(|r| {
                            let j = r.into_inner();
                            if j.error.is_empty() {
                                j.json
                            } else {
                                j.error
                            }
                        })
                        .map_err(|e| format!("Search error: {e}"));
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

    // Tag uses the same atomic provider snapshot as every other Docker action.
    {
        let h = handle.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        let selected = selected_name.clone();
        let repo = entry_repo.clone();
        let tag = entry_tag.clone();
        btn_tag.connect_clicked(move |_| {
            let name = selected.borrow().clone();
            let repo = repo.text().to_string();
            let tag = tag.text().to_string();
            if name.is_empty() || repo.trim().is_empty() || tag.trim().is_empty() {
                set_text(&lb, "Select an image and enter repository and tag");
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
                    .tag_image(target.tag_request(name, repo, tag))
                    .await
                    .map_err(|error| format!("Tag error: {error}"))
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

    // Push progress stream with an explicit cancellation handle.
    {
        let h = handle.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        let entry = entry_img.clone();
        let selected = selected_name.clone();
        let running = transfer_abort.clone();
        btn_push.connect_clicked(move |_| {
            let typed = entry.text().to_string();
            let name = if typed.trim().is_empty() {
                selected.borrow().clone()
            } else {
                typed
            };
            if name.is_empty() || name == "<none>" {
                set_text(&lb, "Enter or select a tagged image to push");
                return;
            }
            if let Some(abort) = running.borrow_mut().take() {
                abort.abort();
            }
            if let Some(abort) =
                start_image_transfer(h.clone(), sp.clone(), lb.clone(), name, ImageTransfer::Push)
            {
                *running.borrow_mut() = Some(abort);
            }
        });
    }
    {
        let running = transfer_abort.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        btn_cancel_transfer.connect_clicked(move |_| {
            if let Some(abort) = running.borrow_mut().take() {
                abort.abort();
                set_text(&lb, "Image transfer cancelled");
            }
            sp.set_spinning(false);
        });
    }

    root
}

fn run_remove_image(handle: AppHandle, spinner: gtk::Spinner, output: gtk::TextBuffer, id: String) {
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
        let result = c
            .remove_image(target.id_request(id))
            .await
            .map_err(|error| format!("Remove error: {error}"))
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

fn run_prune_images(handle: AppHandle, spinner: gtk::Spinner, output: gtk::TextBuffer) {
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
            .prune_images(target.scope(false))
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
enum ImageTransfer {
    Pull,
    Push,
}

fn start_image_transfer(
    handle: AppHandle,
    spinner: gtk::Spinner,
    output: gtk::TextBuffer,
    name: String,
    kind: ImageTransfer,
) -> Option<tokio::task::AbortHandle> {
    let target = handle.docker_target();
    let client = handle.state.lock().unwrap().daemon.clone()?;
    spinner.set_spinning(true);
    let mut c = client.docker;
    let (tx, rx) = async_channel::unbounded::<Result<String, String>>();
    let task = handle.rt.spawn(async move {
        let request = target.name_request(name);
        let response = match kind {
            ImageTransfer::Pull => c.pull_image(request).await,
            ImageTransfer::Push => c.push_image(request).await,
        };
        match response {
            Ok(mut stream) => loop {
                match stream.get_mut().message().await {
                    Ok(Some(event)) if event.error.is_empty() => {
                        if tx
                            .send(Ok(format!("[{}] {}", event.stage, event.message)))
                            .await
                            .is_err()
                        {
                            break;
                        }
                    }
                    Ok(Some(event)) => {
                        let _ = tx.send(Err(event.error)).await;
                        break;
                    }
                    Ok(None) => break,
                    Err(error) => {
                        let _ = tx.send(Err(format!("Image stream error: {error}"))).await;
                        break;
                    }
                }
            },
            Err(error) => {
                let _ = tx.send(Err(format!("Image transfer error: {error}"))).await;
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
            // Bound the transfer output like the other streams
            // (StreamEvents/StreamLogs/StreamStats): drop the oldest half once
            // past 100k so a long multi-layer pull/push cannot grow unbounded.
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
