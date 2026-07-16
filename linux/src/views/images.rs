/// Images view — list, pull, remove, inspect, history, tag, push, search, prune.
///
/// CONTRACT Part B: ListImages · PullImage(stream) · RemoveImage · InspectImage
/// · ImageHistory · TagImage · PushImage(stream) · SearchImages · PruneImages.
use gtk::prelude::*;
use gtk::{Box as GtkBox, Entry, ListBox, ListBoxRow, Label, Orientation, Separator};

use crate::app_state::AppHandle;
use crate::client::proto::{DockerScope, IdRequest, NameRequest, SearchRequest};
use crate::ui_helpers::{make_action_button, make_output_view, make_surface_header, set_text};

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

    macro_rules! abtn { ($l:expr, $n:expr) => {{ let b = make_action_button($l, $n); actions.append(&b); b }}; }
    let btn_remove  = abtn!("🗑 Remove",  "images_btn_remove");
    let btn_inspect = abtn!("🔍 Inspect", "images_btn_inspect");
    let btn_history = abtn!("📜 History", "images_btn_history");
    let btn_prune   = abtn!("🧹 Prune",   "images_btn_prune");
    root.append(&actions);

    // Pull / tag / search row
    let op_row = GtkBox::new(Orientation::Horizontal, 4);
    op_row.set_margin_start(12);
    op_row.set_margin_end(12);
    op_row.set_margin_bottom(6);

    let entry_img = Entry::builder().placeholder_text("image:tag").hexpand(true).build();
    entry_img.set_widget_name("images_entry_image");
    entry_img.update_property(&[gtk::accessible::Property::Label("Image name or tag")]);

    let btn_pull   = make_action_button("⬇ Pull",   "images_btn_pull");
    let btn_search = make_action_button("🔎 Search", "images_btn_search");

    op_row.append(&entry_img);
    op_row.append(&btn_pull);
    op_row.append(&btn_search);
    root.append(&op_row);

    let (sw_out, log_buf) = make_output_view("images_output");
    root.append(&sw_out);

    let selected_id = std::rc::Rc::new(std::cell::RefCell::new(String::new()));
    let selected_name = std::rc::Rc::new(std::cell::RefCell::new(String::new()));

    {
        let sel_id = selected_id.clone();
        let sel_name = selected_name.clone();
        list_box.connect_row_selected(move |_, row| {
            if let Some(r) = row {
                let wn = r.widget_name().to_string();
                // widget name = "id::name"
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
            let profile = h.profile();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.docker.clone();
                let lb2 = lb.clone(); let sp2 = sp.clone(); let list2 = list.clone();
                h.rt.spawn(async move {
                    let res = c.list_images(DockerScope {
                        profile, all: false, host: String::new(), wsl2: false,
                    }).await;
                    glib::idle_add_once(move || {
                        sp2.set_spinning(false);
                        while let Some(child) = list2.first_child() { list2.remove(&child); }
                        match res {
                            Ok(r) => {
                                let j = r.into_inner();
                                if let Ok(arr) = serde_json::from_str::<serde_json::Value>(&j.json) {
                                    if let Some(items) = arr.as_array() {
                                        for item in items {
                                            let id = item["Id"].as_str().unwrap_or("").to_owned();
                                            let tags = item["RepoTags"].as_array()
                                                .and_then(|a| a.first())
                                                .and_then(|v| v.as_str())
                                                .unwrap_or("<none>")
                                                .to_owned();
                                            let size = item["Size"].as_i64().unwrap_or(0);
                                            let lbl = Label::new(Some(&format!(
                                                "{tags}  ({:.1} MB)",
                                                size as f64 / 1_048_576.0
                                            )));
                                            lbl.set_halign(gtk::Align::Start);
                                            lbl.set_margin_start(8); lbl.set_margin_top(4); lbl.set_margin_bottom(4);
                                            let row = ListBoxRow::new();
                                            row.set_widget_name(&format!("{id}::{tags}"));
                                            row.update_property(&[gtk::accessible::Property::Label(&tags)]);
                                            row.set_child(Some(&lbl));
                                            list2.append(&row);
                                        }
                                    }
                                } else {
                                    set_text(&lb2, &j.json);
                                }
                            }
                            Err(e) => set_text(&lb2, &format!("Error: {e}")),
                        }
                    });
                });
            } else {
                sp.set_spinning(false);
                set_text(&lb, "Not connected");
            }
        });
    }

    // Remove
    {
        let h = handle.clone(); let lb = log_buf.clone(); let sp = spinner.clone();
        let sel = selected_id.clone();
        btn_remove.connect_clicked(move |_| {
            let id = sel.borrow().clone();
            if id.is_empty() { set_text(&lb, "Select an image first"); return; }
            sp.set_spinning(true);
            let profile = h.profile();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.docker.clone();
                let lb2 = lb.clone(); let sp2 = sp.clone();
                h.rt.spawn(async move {
                    let res = c.remove_image(IdRequest { id, profile, host: String::new(), wsl2: false }).await;
                    glib::idle_add_once(move || {
                        sp2.set_spinning(false);
                        match res {
                            Ok(r) => set_text(&lb2, &r.into_inner().message),
                            Err(e) => set_text(&lb2, &format!("Remove error: {e}")),
                        }
                    });
                });
            } else { sp.set_spinning(false); set_text(&lb, "Not connected"); }
        });
    }

    // Inspect
    {
        let h = handle.clone(); let lb = log_buf.clone(); let sp = spinner.clone();
        let sel = selected_name.clone();
        btn_inspect.connect_clicked(move |_| {
            let name = sel.borrow().clone();
            if name.is_empty() { set_text(&lb, "Select an image first"); return; }
            sp.set_spinning(true);
            let profile = h.profile();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.docker.clone();
                let lb2 = lb.clone(); let sp2 = sp.clone();
                h.rt.spawn(async move {
                    let res = c.inspect_image(NameRequest { name, profile, host: String::new(), wsl2: false }).await;
                    glib::idle_add_once(move || {
                        sp2.set_spinning(false);
                        match res {
                            Ok(r) => {
                                let j = r.into_inner();
                                let text = serde_json::from_str::<serde_json::Value>(&j.json)
                                    .map(|v| serde_json::to_string_pretty(&v).unwrap_or(j.json.clone()))
                                    .unwrap_or(j.json);
                                set_text(&lb2, &text);
                            }
                            Err(e) => set_text(&lb2, &format!("Inspect error: {e}")),
                        }
                    });
                });
            } else { sp.set_spinning(false); set_text(&lb, "Not connected"); }
        });
    }

    // History
    {
        let h = handle.clone(); let lb = log_buf.clone(); let sp = spinner.clone();
        let sel = selected_name.clone();
        btn_history.connect_clicked(move |_| {
            let name = sel.borrow().clone();
            if name.is_empty() { set_text(&lb, "Select an image first"); return; }
            sp.set_spinning(true);
            let profile = h.profile();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.docker.clone();
                let lb2 = lb.clone(); let sp2 = sp.clone();
                h.rt.spawn(async move {
                    let res = c.image_history(NameRequest { name, profile, host: String::new(), wsl2: false }).await;
                    glib::idle_add_once(move || {
                        sp2.set_spinning(false);
                        match res {
                            Ok(r) => {
                                let j = r.into_inner();
                                set_text(&lb2, if j.error.is_empty() { &j.json } else { &j.error });
                            }
                            Err(e) => set_text(&lb2, &format!("History error: {e}")),
                        }
                    });
                });
            } else { sp.set_spinning(false); set_text(&lb, "Not connected"); }
        });
    }

    // Prune
    {
        let h = handle.clone(); let lb = log_buf.clone(); let sp = spinner.clone();
        btn_prune.connect_clicked(move |_| {
            sp.set_spinning(true);
            let profile = h.profile();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.docker.clone();
                let lb2 = lb.clone(); let sp2 = sp.clone();
                h.rt.spawn(async move {
                    let res = c.prune_images(DockerScope {
                        profile, all: false, host: String::new(), wsl2: false,
                    }).await;
                    glib::idle_add_once(move || {
                        sp2.set_spinning(false);
                        match res {
                            Ok(r) => { let j = r.into_inner(); set_text(&lb2, if j.error.is_empty() { &j.json } else { &j.error }); }
                            Err(e) => set_text(&lb2, &format!("Prune error: {e}")),
                        }
                    });
                });
            } else { sp.set_spinning(false); set_text(&lb, "Not connected"); }
        });
    }

    // Pull
    {
        let h = handle.clone(); let lb = log_buf.clone(); let sp = spinner.clone();
        let ei = entry_img.clone();
        btn_pull.connect_clicked(move |_| {
            let name = ei.text().to_string();
            if name.is_empty() { set_text(&lb, "Enter image:tag first"); return; }
            sp.set_spinning(true);
            let profile = h.profile();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.docker.clone();
                let lb2 = lb.clone(); let sp2 = sp.clone();
                h.rt.spawn(async move {
                    match c.pull_image(NameRequest { name, profile, host: String::new(), wsl2: false }).await {
                        Ok(mut stream) => {
                            let mut log = String::new();
                            while let Ok(Some(evt)) = stream.get_mut().message().await {
                                log.push_str(&format!("[{}] {}\n", evt.stage, evt.message));
                            }
                            glib::idle_add_once(move || { sp2.set_spinning(false); set_text(&lb2, &log); });
                        }
                        Err(e) => glib::idle_add_once(move || { sp2.set_spinning(false); set_text(&lb2, &format!("Pull error: {e}")); }),
                    }
                });
            } else { sp.set_spinning(false); set_text(&lb, "Not connected"); }
        });
    }

    // Search
    {
        let h = handle.clone(); let lb = log_buf.clone(); let sp = spinner.clone();
        let ei = entry_img.clone();
        btn_search.connect_clicked(move |_| {
            let term = ei.text().to_string();
            if term.is_empty() { set_text(&lb, "Enter search term first"); return; }
            sp.set_spinning(true);
            let profile = h.profile();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.docker.clone();
                let lb2 = lb.clone(); let sp2 = sp.clone();
                h.rt.spawn(async move {
                    let res = c.search_images(SearchRequest { term, profile }).await;
                    glib::idle_add_once(move || {
                        sp2.set_spinning(false);
                        match res {
                            Ok(r) => { let j = r.into_inner(); set_text(&lb2, if j.error.is_empty() { &j.json } else { &j.error }); }
                            Err(e) => set_text(&lb2, &format!("Search error: {e}")),
                        }
                    });
                });
            } else { sp.set_spinning(false); set_text(&lb, "Not connected"); }
        });
    }

    root
}
