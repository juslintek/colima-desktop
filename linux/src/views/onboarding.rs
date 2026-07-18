/// Onboarding view — shown when colima is not detected on first launch.
///
/// CONTRACT Part C: isColimaInstalled() · installColima() · DependencyManager.
/// Lists all tracked dependencies with install status and provides install/update buttons.
use gtk::prelude::*;
use gtk::{Box as GtkBox, Label, Orientation, Separator};

use crate::dependency_manager::{DependencyManager, DEPS};
use crate::ui_helpers::{make_action_button, make_output_view, set_text};

pub fn build() -> GtkBox {
    let root = GtkBox::new(Orientation::Vertical, 0);
    root.set_widget_name("view_onboarding");
    root.update_property(&[gtk::accessible::Property::Label("Onboarding")]);

    // Title
    let title = Label::new(Some("Welcome to Colima Desktop"));
    title.set_widget_name("onboarding_title");
    title.add_css_class("title-1");
    title.set_margin_top(24);
    title.set_margin_bottom(8);
    root.append(&title);

    let subtitle = Label::new(Some("Let's check and install the required dependencies."));
    subtitle.set_widget_name("onboarding_subtitle");
    subtitle.add_css_class("dim-label");
    subtitle.set_margin_bottom(24);
    root.append(&subtitle);

    root.append(&Separator::new(Orientation::Horizontal));

    // Dependency status grid
    let dep_box = GtkBox::new(Orientation::Vertical, 8);
    dep_box.set_margin_start(24);
    dep_box.set_margin_end(24);
    dep_box.set_margin_top(16);

    let statuses = DependencyManager::check_all();

    let _dep_labels: Vec<Label> = statuses
        .iter()
        .map(|s| {
            let row = GtkBox::new(Orientation::Horizontal, 8);
            let name_lbl = Label::new(Some(s.dep));
            name_lbl.set_widget_name(&format!("onboarding_dep_{}", s.dep));
            name_lbl.set_halign(gtk::Align::Start);
            name_lbl.set_hexpand(true);

            let status_text = if s.installed {
                format!("✓  {}", s.version.as_deref().unwrap_or("installed"))
            } else {
                "✗  not found".to_owned()
            };
            let status_lbl = Label::new(Some(&status_text));
            status_lbl.set_widget_name(&format!("onboarding_dep_status_{}", s.dep));
            status_lbl.update_property(&[gtk::accessible::Property::Label(&format!(
                "{}: {}",
                s.dep, status_text
            ))]);
            if s.installed {
                status_lbl.add_css_class("success");
            } else {
                status_lbl.add_css_class("error");
            }

            row.append(&name_lbl);
            row.append(&status_lbl);
            dep_box.append(&row);
            status_lbl
        })
        .collect();

    root.append(&dep_box);

    root.append(&Separator::new(Orientation::Horizontal));

    // Actions
    let action_row = GtkBox::new(Orientation::Horizontal, 8);
    action_row.set_margin_start(24);
    action_row.set_margin_end(24);
    action_row.set_margin_top(16);
    action_row.set_margin_bottom(16);

    let btn_install_colima =
        make_action_button("⬇ Install Colima", "onboarding_btn_install_colima");
    let btn_install_all = make_action_button("⬇ Install All Deps", "onboarding_btn_install_all");
    let btn_update_all = make_action_button("⬆ Update All", "onboarding_btn_update_all");
    let btn_recheck = make_action_button("↺ Re-check", "onboarding_btn_recheck");

    action_row.append(&btn_install_colima);
    action_row.append(&btn_install_all);
    action_row.append(&btn_update_all);
    action_row.append(&btn_recheck);
    root.append(&action_row);

    let (sw_out, log_buf) = make_output_view("onboarding_output");
    root.append(&sw_out);

    // Install Colima — use async_channel so the background thread result reaches GTK safely.
    {
        let lb = log_buf.clone();
        btn_install_colima.connect_clicked(move |_| {
            set_text(&lb, "Installing colima, please wait…");
            let lb2 = lb.clone();
            let (tx, rx) = async_channel::bounded::<String>(1);
            std::thread::spawn(move || {
                let (ok, log) = DependencyManager::install_colima();
                let msg = if ok {
                    format!("✓ colima installed successfully\n\n{log}")
                } else {
                    format!("✗ Installation failed or incomplete\n\n{log}")
                };
                // blocking_send is fine from a std thread
                let _ = tx.send_blocking(msg);
            });
            glib::spawn_future_local(async move {
                if let Ok(msg) = rx.recv().await {
                    set_text(&lb2, &msg);
                }
            });
        });
    }

    // Install All
    {
        let lb = log_buf.clone();
        btn_install_all.connect_clicked(move |_| {
            set_text(&lb, "Installing all dependencies, please wait…");
            let lb2 = lb.clone();
            let (tx, rx) = async_channel::bounded::<String>(1);
            std::thread::spawn(move || {
                let mut log = String::new();
                for dep in DEPS {
                    if which::which(dep.binary).is_err() {
                        let (ok, out) = DependencyManager::install_dep(dep.name);
                        log.push_str(&format!(
                            "{}: {}\n{}\n\n",
                            dep.name,
                            if ok { "✓" } else { "✗" },
                            out
                        ));
                    } else {
                        log.push_str(&format!("{}: already installed ✓\n", dep.name));
                    }
                }
                let _ = tx.send_blocking(log);
            });
            glib::spawn_future_local(async move {
                if let Ok(msg) = rx.recv().await {
                    set_text(&lb2, &msg);
                }
            });
        });
    }

    // Update All
    {
        let lb = log_buf.clone();
        btn_update_all.connect_clicked(move |_| {
            set_text(&lb, "Updating dependencies, please wait…");
            let lb2 = lb.clone();
            let (tx, rx) = async_channel::bounded::<String>(1);
            std::thread::spawn(move || {
                let results = DependencyManager::update_all();
                let mut log = String::new();
                for (name, ok, out) in &results {
                    log.push_str(&format!(
                        "{}: {}\n{}\n\n",
                        name,
                        if *ok { "✓" } else { "✗" },
                        out
                    ));
                }
                if log.is_empty() {
                    log = "No installed dependencies to update.".to_owned();
                }
                let _ = tx.send_blocking(log);
            });
            glib::spawn_future_local(async move {
                if let Ok(msg) = rx.recv().await {
                    set_text(&lb2, &msg);
                }
            });
        });
    }

    // Re-check (synchronous — just reads system state)
    {
        let lb = log_buf.clone();
        btn_recheck.connect_clicked(move |_| {
            let statuses = DependencyManager::check_all();
            let mut report = String::new();
            for s in &statuses {
                report.push_str(&format!(
                    "{}: {}\n",
                    s.dep,
                    if s.installed {
                        format!("✓ {}", s.version.as_deref().unwrap_or("installed"))
                    } else {
                        "✗ not found".to_owned()
                    }
                ));
            }
            set_text(&lb, &report);
        });
    }

    root
}
