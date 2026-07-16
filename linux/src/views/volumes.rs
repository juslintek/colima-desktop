/// Volumes view — list, create, remove, inspect, prune.
///
/// CONTRACT Part B: ListVolumes · CreateVolume · RemoveVolume · InspectVolume · PruneVolumes.
use gtk::prelude::*;
use gtk::{Box as GtkBox, Entry, ListBox, ListBoxRow, Label, Orientation, Separator};

use crate::app_state::AppHandle;
use crate::client::proto::{DockerScope, NameRequest};
use crate::ui_helpers::{make_action_button, make_output_view, make_surface_header, set_text};

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
    let sw_list = gtk::ScrolledWindow::builder().child(&list_box).vexpand(true).build();
    root.append(&sw_list);

    root.append(&Separator::new(Orientation::Horizontal));

    let actions = GtkBox::new(Orientation::Horizontal, 4);
    actions.set_margin_start(12); actions.set_margin_end(12);
    actions.set_margin_top(6); actions.set_margin_bottom(6);

    macro_rules! abtn { ($l:expr, $n:expr) => {{ let b = make_action_button($l, $n); actions.append(&b); b }}; }
    let btn_remove  = abtn!("🗑 Remove",  "volumes_btn_remove");
    let btn_inspect = abtn!("🔍 Inspect", "volumes_btn_inspect");
    let btn_prune   = abtn!("🧹 Prune",   "volumes_btn_prune");
    root.append(&actions);

    let create_row = GtkBox::new(Orientation::Horizontal, 4);
    create_row.set_margin_start(12); create_row.set_margin_end(12); create_row.set_margin_bottom(6);
    let entry_name = Entry::builder().placeholder_text("Volume name").hexpand(true).build();
    entry_name.set_widget_name("volumes_entry_name");
    entry_name.update_property(&[gtk::accessible::Property::Label("Volume name")]);
    let btn_create = make_action_button("+ Create", "volumes_btn_create");
    create_row.append(&entry_name); create_row.append(&btn_create);
    root.append(&create_row);

    let (sw_out, log_buf) = make_output_view("volumes_output");
    root.append(&sw_out);

    let selected = std::rc::Rc::new(std::cell::RefCell::new(String::new()));
    {
        let sel = selected.clone();
        list_box.connect_row_selected(move |_, row| {
            if let Some(r) = row { *sel.borrow_mut() = r.widget_name().to_string(); }
        });
    }

    // Refresh
    {
        let h = handle.clone(); let lb = log_buf.clone(); let sp = spinner.clone();
        let list = list_box.clone();
        refresh_btn.connect_clicked(move |_| {
            sp.set_spinning(true);
            let profile = h.profile();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.docker.clone();
                let lb2 = lb.clone(); let sp2 = sp.clone(); let list2 = list.clone();
                h.rt.spawn(async move {
                    let res = c.list_volumes(DockerScope { profile, all: false, host: String::new(), wsl2: false }).await;
                    glib::idle_add_once(move || {
                        sp2.set_spinning(false);
                        while let Some(child) = list2.first_child() { list2.remove(&child); }
                        match res {
                            Ok(r) => {
                                let j = r.into_inner();
                                if let Ok(v) = serde_json::from_str::<serde_json::Value>(&j.json) {
                                    let items = v["Volumes"].as_array()
                                        .or_else(|| v.as_array())
                                        .cloned()
                                        .unwrap_or_default();
                                    for item in &items {
                                        let name = item["Name"].as_str().unwrap_or("").to_owned();
                                        let driver = item["Driver"].as_str().unwrap_or("").to_owned();
                                        let lbl = Label::new(Some(&format!("{name}  ({driver})")));
                                        lbl.set_halign(gtk::Align::Start); lbl.set_margin_start(8); lbl.set_margin_top(4); lbl.set_margin_bottom(4);
                                        let row = ListBoxRow::new();
                                        row.set_widget_name(&name);
                                        row.update_property(&[gtk::accessible::Property::Label(&name)]);
                                        row.set_child(Some(&lbl));
                                        list2.append(&row);
                                    }
                                } else { set_text(&lb2, &j.json); }
                            }
                            Err(e) => set_text(&lb2, &format!("Error: {e}")),
                        }
                    });
                });
            } else { sp.set_spinning(false); set_text(&lb, "Not connected"); }
        });
    }

    // Remove
    {
        let h = handle.clone(); let lb = log_buf.clone(); let sp = spinner.clone(); let sel = selected.clone();
        btn_remove.connect_clicked(move |_| {
            let name = sel.borrow().clone();
            if name.is_empty() { set_text(&lb, "Select a volume first"); return; }
            sp.set_spinning(true);
            let profile = h.profile();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.docker.clone(); let lb2 = lb.clone(); let sp2 = sp.clone();
                h.rt.spawn(async move {
                    let res = c.remove_volume(NameRequest { name, profile, host: String::new(), wsl2: false }).await;
                    glib::idle_add_once(move || { sp2.set_spinning(false); match res { Ok(r) => set_text(&lb2, &r.into_inner().message), Err(e) => set_text(&lb2, &format!("Error: {e}")), } });
                });
            } else { sp.set_spinning(false); set_text(&lb, "Not connected"); }
        });
    }

    // Inspect
    {
        let h = handle.clone(); let lb = log_buf.clone(); let sp = spinner.clone(); let sel = selected.clone();
        btn_inspect.connect_clicked(move |_| {
            let name = sel.borrow().clone();
            if name.is_empty() { set_text(&lb, "Select a volume first"); return; }
            sp.set_spinning(true);
            let profile = h.profile();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.docker.clone(); let lb2 = lb.clone(); let sp2 = sp.clone();
                h.rt.spawn(async move {
                    let res = c.inspect_volume(NameRequest { name, profile, host: String::new(), wsl2: false }).await;
                    glib::idle_add_once(move || {
                        sp2.set_spinning(false);
                        match res {
                            Ok(r) => { let j = r.into_inner(); let text = serde_json::from_str::<serde_json::Value>(&j.json).map(|v| serde_json::to_string_pretty(&v).unwrap_or(j.json.clone())).unwrap_or(j.json); set_text(&lb2, &text); }
                            Err(e) => set_text(&lb2, &format!("Error: {e}")),
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
                let mut c = client.docker.clone(); let lb2 = lb.clone(); let sp2 = sp.clone();
                h.rt.spawn(async move {
                    let res = c.prune_volumes(DockerScope { profile, all: false, host: String::new(), wsl2: false }).await;
                    glib::idle_add_once(move || { sp2.set_spinning(false); match res { Ok(r) => { let j = r.into_inner(); set_text(&lb2, if j.error.is_empty() { &j.json } else { &j.error }); } Err(e) => set_text(&lb2, &format!("Error: {e}")), } });
                });
            } else { sp.set_spinning(false); set_text(&lb, "Not connected"); }
        });
    }

    // Create
    {
        let h = handle.clone(); let lb = log_buf.clone(); let sp = spinner.clone();
        let en = entry_name.clone();
        btn_create.connect_clicked(move |_| {
            let name = en.text().to_string();
            if name.is_empty() { set_text(&lb, "Enter a volume name first"); return; }
            sp.set_spinning(true);
            let profile = h.profile();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.docker.clone(); let lb2 = lb.clone(); let sp2 = sp.clone();
                h.rt.spawn(async move {
                    let res = c.create_volume(NameRequest { name, profile, host: String::new(), wsl2: false }).await;
                    glib::idle_add_once(move || { sp2.set_spinning(false); match res { Ok(r) => { let j = r.into_inner(); set_text(&lb2, if j.error.is_empty() { &j.json } else { &j.error }); } Err(e) => set_text(&lb2, &format!("Error: {e}")), } });
                });
            } else { sp.set_spinning(false); set_text(&lb, "Not connected"); }
        });
    }

    root
}
