/// Networks view — list, create, remove, inspect, connect, disconnect, prune.
///
/// CONTRACT Part B: ListNetworks · CreateNetwork · RemoveNetwork · InspectNetwork
/// · ConnectNetwork · DisconnectNetwork · PruneNetworks.
use gtk::prelude::*;
use gtk::{Box as GtkBox, Entry, ListBox, ListBoxRow, Label, Orientation, Separator};

use crate::app_state::AppHandle;
use crate::client::proto::{DockerScope, IdRequest, NameRequest, NetworkContainerRequest};
use crate::ui_helpers::{make_action_button, make_output_view, make_surface_header, set_text};

pub fn build(handle: AppHandle) -> GtkBox {
    let root = GtkBox::new(Orientation::Vertical, 0);
    root.set_widget_name("view_networks");
    root.update_property(&[gtk::accessible::Property::Label("Networks")]);

    let (header, spinner, refresh_btn) = make_surface_header("Networks", "networks");
    root.append(&header);

    let list_box = ListBox::new();
    list_box.set_widget_name("networks_list");
    list_box.update_property(&[gtk::accessible::Property::Label("Network list")]);
    list_box.set_selection_mode(gtk::SelectionMode::Single);
    let sw_list = gtk::ScrolledWindow::builder().child(&list_box).vexpand(true).build();
    root.append(&sw_list);

    root.append(&Separator::new(Orientation::Horizontal));

    let actions = GtkBox::new(Orientation::Horizontal, 4);
    actions.set_margin_start(12); actions.set_margin_end(12);
    actions.set_margin_top(6); actions.set_margin_bottom(6);

    macro_rules! abtn { ($l:expr, $n:expr) => {{ let b = make_action_button($l, $n); actions.append(&b); b }}; }
    let btn_remove   = abtn!("🗑 Remove",     "networks_btn_remove");
    let btn_inspect  = abtn!("🔍 Inspect",    "networks_btn_inspect");
    let btn_prune    = abtn!("🧹 Prune",      "networks_btn_prune");
    root.append(&actions);

    // Connect/Disconnect row
    let conn_row = GtkBox::new(Orientation::Horizontal, 4);
    conn_row.set_margin_start(12); conn_row.set_margin_end(12); conn_row.set_margin_bottom(6);
    let entry_cid = Entry::builder().placeholder_text("Container ID").hexpand(true).build();
    entry_cid.set_widget_name("networks_entry_container_id");
    entry_cid.update_property(&[gtk::accessible::Property::Label("Container ID for connect/disconnect")]);
    let btn_connect    = make_action_button("⬆ Connect",    "networks_btn_connect");
    let btn_disconnect = make_action_button("⬇ Disconnect", "networks_btn_disconnect");
    conn_row.append(&entry_cid); conn_row.append(&btn_connect); conn_row.append(&btn_disconnect);
    root.append(&conn_row);

    // Create row
    let create_row = GtkBox::new(Orientation::Horizontal, 4);
    create_row.set_margin_start(12); create_row.set_margin_end(12); create_row.set_margin_bottom(6);
    let entry_name = Entry::builder().placeholder_text("Network name").hexpand(true).build();
    entry_name.set_widget_name("networks_entry_name");
    entry_name.update_property(&[gtk::accessible::Property::Label("Network name")]);
    let btn_create = make_action_button("+ Create", "networks_btn_create");
    create_row.append(&entry_name); create_row.append(&btn_create);
    root.append(&create_row);

    let (sw_out, log_buf) = make_output_view("networks_output");
    root.append(&sw_out);

    let selected_id = std::rc::Rc::new(std::cell::RefCell::new(String::new()));
    {
        let sel = selected_id.clone();
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
                    let res = c.list_networks(DockerScope { profile, all: false, host: String::new(), wsl2: false }).await;
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
                                            let name = item["Name"].as_str().unwrap_or("").to_owned();
                                            let driver = item["Driver"].as_str().unwrap_or("").to_owned();
                                            let scope = item["Scope"].as_str().unwrap_or("").to_owned();
                                            let lbl = Label::new(Some(&format!("{name}  driver={driver}  scope={scope}")));
                                            lbl.set_halign(gtk::Align::Start); lbl.set_margin_start(8); lbl.set_margin_top(4); lbl.set_margin_bottom(4);
                                            let row = ListBoxRow::new();
                                            row.set_widget_name(&id);
                                            row.update_property(&[gtk::accessible::Property::Label(&name)]);
                                            row.set_child(Some(&lbl));
                                            list2.append(&row);
                                        }
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
        let h = handle.clone(); let lb = log_buf.clone(); let sp = spinner.clone(); let sel = selected_id.clone();
        btn_remove.connect_clicked(move |_| {
            let id = sel.borrow().clone();
            if id.is_empty() { set_text(&lb, "Select a network first"); return; }
            sp.set_spinning(true);
            let profile = h.profile();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.docker.clone(); let lb2 = lb.clone(); let sp2 = sp.clone();
                h.rt.spawn(async move {
                    let res = c.remove_network(IdRequest { id, profile, host: String::new(), wsl2: false }).await;
                    glib::idle_add_once(move || { sp2.set_spinning(false); match res { Ok(r) => set_text(&lb2, &r.into_inner().message), Err(e) => set_text(&lb2, &format!("Error: {e}")), } });
                });
            } else { sp.set_spinning(false); set_text(&lb, "Not connected"); }
        });
    }

    // Inspect
    {
        let h = handle.clone(); let lb = log_buf.clone(); let sp = spinner.clone(); let sel = selected_id.clone();
        btn_inspect.connect_clicked(move |_| {
            let id = sel.borrow().clone();
            if id.is_empty() { set_text(&lb, "Select a network first"); return; }
            sp.set_spinning(true);
            let profile = h.profile();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.docker.clone(); let lb2 = lb.clone(); let sp2 = sp.clone();
                h.rt.spawn(async move {
                    let res = c.inspect_network(IdRequest { id, profile, host: String::new(), wsl2: false }).await;
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
                    let res = c.prune_networks(DockerScope { profile, all: false, host: String::new(), wsl2: false }).await;
                    glib::idle_add_once(move || { sp2.set_spinning(false); match res { Ok(r) => { let j = r.into_inner(); set_text(&lb2, if j.error.is_empty() { &j.json } else { &j.error }); } Err(e) => set_text(&lb2, &format!("Error: {e}")), } });
                });
            } else { sp.set_spinning(false); set_text(&lb, "Not connected"); }
        });
    }

    // Connect
    {
        let h = handle.clone(); let lb = log_buf.clone(); let sp = spinner.clone();
        let sel = selected_id.clone(); let ecid = entry_cid.clone();
        btn_connect.connect_clicked(move |_| {
            let nid = sel.borrow().clone();
            let cid = ecid.text().to_string();
            if nid.is_empty() || cid.is_empty() { set_text(&lb, "Select a network and enter a container ID"); return; }
            sp.set_spinning(true);
            let profile = h.profile();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.docker.clone(); let lb2 = lb.clone(); let sp2 = sp.clone();
                h.rt.spawn(async move {
                    let res = c.connect_network(NetworkContainerRequest { network_id: nid, container_id: cid, profile }).await;
                    glib::idle_add_once(move || { sp2.set_spinning(false); match res { Ok(r) => set_text(&lb2, &r.into_inner().message), Err(e) => set_text(&lb2, &format!("Error: {e}")), } });
                });
            } else { sp.set_spinning(false); set_text(&lb, "Not connected"); }
        });
    }

    // Disconnect
    {
        let h = handle.clone(); let lb = log_buf.clone(); let sp = spinner.clone();
        let sel = selected_id.clone(); let ecid = entry_cid.clone();
        btn_disconnect.connect_clicked(move |_| {
            let nid = sel.borrow().clone();
            let cid = ecid.text().to_string();
            if nid.is_empty() || cid.is_empty() { set_text(&lb, "Select a network and enter a container ID"); return; }
            sp.set_spinning(true);
            let profile = h.profile();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.docker.clone(); let lb2 = lb.clone(); let sp2 = sp.clone();
                h.rt.spawn(async move {
                    let res = c.disconnect_network(NetworkContainerRequest { network_id: nid, container_id: cid, profile }).await;
                    glib::idle_add_once(move || { sp2.set_spinning(false); match res { Ok(r) => set_text(&lb2, &r.into_inner().message), Err(e) => set_text(&lb2, &format!("Error: {e}")), } });
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
            if name.is_empty() { set_text(&lb, "Enter a network name first"); return; }
            sp.set_spinning(true);
            let profile = h.profile();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.docker.clone(); let lb2 = lb.clone(); let sp2 = sp.clone();
                h.rt.spawn(async move {
                    let res = c.create_network(NameRequest { name, profile, host: String::new(), wsl2: false }).await;
                    glib::idle_add_once(move || { sp2.set_spinning(false); match res { Ok(r) => { let j = r.into_inner(); set_text(&lb2, if j.error.is_empty() { &j.json } else { &j.error }); } Err(e) => set_text(&lb2, &format!("Error: {e}")), } });
                });
            } else { sp.set_spinning(false); set_text(&lb, "Not connected"); }
        });
    }

    root
}
