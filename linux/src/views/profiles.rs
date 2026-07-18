/// Profiles view — ListProfiles, CreateProfile, DeleteProfile, CloneProfile, SSHConfig.
///
/// CONTRACT Part A: ListProfiles · CreateProfile · DeleteProfile · CloneProfile · SSHConfig.
use gtk::prelude::*;
use gtk::{Box as GtkBox, Entry, Label, ListBox, ListBoxRow, Orientation, Separator};

use crate::app_state::AppHandle;
use crate::client::proto::{
    CloneProfileRequest, CreateProfileRequest, DeleteProfileRequest, Empty, ProfileRequest,
};
use crate::ui_helpers::{make_action_button, make_output_view, make_surface_header, set_text};

struct ProfileInfo {
    name: String,
    status: String,
    runtime: String,
    arch: String,
    cpus: i32,
}

struct SshInfo {
    host: String,
    port: i32,
    user: String,
    identity_file: String,
    config: String,
}

pub fn build(handle: AppHandle) -> GtkBox {
    let root = GtkBox::new(Orientation::Vertical, 0);
    root.set_widget_name("view_profiles");
    root.update_property(&[gtk::accessible::Property::Label("Profiles")]);

    let (header, spinner, refresh_btn) = make_surface_header("Profiles", "profiles");
    root.append(&header);

    let list_box = ListBox::new();
    list_box.set_widget_name("profiles_list");
    list_box.update_property(&[gtk::accessible::Property::Label("Profile list")]);
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
    let btn_delete = abtn!("🗑 Delete", "profiles_btn_delete");
    let btn_ssh = abtn!("🔑 SSH Config", "profiles_btn_ssh");
    root.append(&actions);

    // Create / Clone row
    let op_row = GtkBox::new(Orientation::Horizontal, 4);
    op_row.set_margin_start(12);
    op_row.set_margin_end(12);
    op_row.set_margin_bottom(6);

    let entry_name = Entry::builder()
        .placeholder_text("New profile name")
        .hexpand(true)
        .build();
    entry_name.set_widget_name("profiles_entry_name");
    entry_name.update_property(&[gtk::accessible::Property::Label("New profile name")]);

    let entry_clone_dest = Entry::builder()
        .placeholder_text("Clone destination name")
        .hexpand(true)
        .build();
    entry_clone_dest.set_widget_name("profiles_entry_clone_dest");
    entry_clone_dest.update_property(&[gtk::accessible::Property::Label("Clone destination name")]);

    let btn_create = make_action_button("+ Create", "profiles_btn_create");
    let btn_clone = make_action_button("⊕ Clone", "profiles_btn_clone");

    op_row.append(&entry_name);
    op_row.append(&btn_create);
    op_row.append(&entry_clone_dest);
    op_row.append(&btn_clone);
    root.append(&op_row);

    let (sw_out, log_buf) = make_output_view("profiles_output");
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
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.colima.clone();
                let lb2 = lb.clone();
                let sp2 = sp.clone();
                let list2 = list.clone();
                let (tx, rx) = async_channel::bounded::<Result<Vec<ProfileInfo>, String>>(1);
                h.rt.spawn(async move {
                    let result = c
                        .list_profiles(Empty {})
                        .await
                        .map(|r| {
                            r.into_inner()
                                .profiles
                                .into_iter()
                                .map(|p| ProfileInfo {
                                    name: p.name,
                                    status: p.status,
                                    runtime: p.runtime,
                                    arch: p.arch,
                                    cpus: p.cpus,
                                })
                                .collect()
                        })
                        .map_err(|e| format!("Error: {e}"));
                    let _ = tx.send(result).await;
                });
                glib::spawn_future_local(async move {
                    sp2.set_spinning(false);
                    while let Some(child) = list2.first_child() {
                        list2.remove(&child);
                    }
                    if let Ok(result) = rx.recv().await {
                        match result {
                            Ok(profiles) => {
                                for p in profiles {
                                    let lbl = Label::new(Some(&format!(
                                        "{}  status={}  runtime={}  arch={}  cpus={}",
                                        p.name, p.status, p.runtime, p.arch, p.cpus
                                    )));
                                    lbl.set_halign(gtk::Align::Start);
                                    lbl.set_margin_start(8);
                                    lbl.set_margin_top(4);
                                    lbl.set_margin_bottom(4);
                                    let row = ListBoxRow::new();
                                    row.set_widget_name(&p.name);
                                    row.update_property(&[gtk::accessible::Property::Label(
                                        &p.name,
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

    // Delete
    {
        let h = handle.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        let sel = selected.clone();
        btn_delete.connect_clicked(move |_| {
            let name = sel.borrow().clone();
            if name.is_empty() {
                set_text(&lb, "Select a profile first");
                return;
            }
            sp.set_spinning(true);
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.colima.clone();
                let lb2 = lb.clone();
                let sp2 = sp.clone();
                let (tx, rx) = async_channel::bounded::<Result<String, String>>(1);
                h.rt.spawn(async move {
                    let result = c
                        .delete_profile(DeleteProfileRequest {
                            name,
                            data: false,
                            force: false,
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
    }

    // SSH Config
    {
        let h = handle.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        let sel = selected.clone();
        btn_ssh.connect_clicked(move |_| {
            let profile = sel.borrow().clone();
            if profile.is_empty() {
                set_text(&lb, "Select a profile first");
                return;
            }
            sp.set_spinning(true);
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.colima.clone();
                let lb2 = lb.clone();
                let sp2 = sp.clone();
                let (tx, rx) = async_channel::bounded::<Result<SshInfo, String>>(1);
                h.rt.spawn(async move {
                    let result = c
                        .ssh_config(ProfileRequest { profile })
                        .await
                        .map(|r| {
                            let s = r.into_inner();
                            SshInfo {
                                host: s.host,
                                port: s.port,
                                user: s.user,
                                identity_file: s.identity_file,
                                config: s.config,
                            }
                        })
                        .map_err(|e| format!("Error: {e}"));
                    let _ = tx.send(result).await;
                });
                glib::spawn_future_local(async move {
                    sp2.set_spinning(false);
                    if let Ok(result) = rx.recv().await {
                        match result {
                            Ok(s) => set_text(
                                &lb2,
                                &format!(
                                    "Host: {}  Port: {}  User: {}\nIdentityFile: {}\n\n{}",
                                    s.host, s.port, s.user, s.identity_file, s.config
                                ),
                            ),
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

    // Create
    {
        let h = handle.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        let en = entry_name.clone();
        btn_create.connect_clicked(move |_| {
            let name = en.text().to_string();
            if name.is_empty() {
                set_text(&lb, "Enter a profile name first");
                return;
            }
            sp.set_spinning(true);
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.colima.clone();
                let lb2 = lb.clone();
                let sp2 = sp.clone();
                let (tx, rx) = async_channel::bounded::<Result<String, String>>(1);
                h.rt.spawn(async move {
                    let result = c
                        .create_profile(CreateProfileRequest { name, config: None })
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

    // Clone
    {
        let h = handle.clone();
        let lb = log_buf.clone();
        let sp = spinner.clone();
        let sel = selected.clone();
        let ed = entry_clone_dest.clone();
        btn_clone.connect_clicked(move |_| {
            let source = sel.borrow().clone();
            let destination = ed.text().to_string();
            if source.is_empty() || destination.is_empty() {
                set_text(&lb, "Select a source profile and enter a destination name");
                return;
            }
            sp.set_spinning(true);
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.colima.clone();
                let lb2 = lb.clone();
                let sp2 = sp.clone();
                let (tx, rx) = async_channel::bounded::<Result<String, String>>(1);
                h.rt.spawn(async move {
                    let result = c
                        .clone_profile(CloneProfileRequest {
                            source,
                            destination,
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
    }

    root
}
