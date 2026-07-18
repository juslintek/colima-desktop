/// Colima Desktop — Linux (GTK4 / gtk4-rs)
///
/// Native Linux frontend mirroring every SwiftUI surface, wired to the Go daemon
/// over gRPC (CONTRACT v1: Parts A + B + C).
///
/// Surfaces: Dashboard · Containers · Images · Volumes · Networks · Machines ·
///           Kubernetes · Configuration · Runtime · AI Workloads · Profiles
///
/// DependencyManager (CONTRACT Part C): detects/installs colima + deps on first launch.
/// AT-SPI: every interactive widget carries a widget_name + accessible Property::Label.
mod app_state;
mod client;
mod dependency_manager;
mod ui_helpers;
mod views;

use gtk::prelude::*;
use gtk::{
    Application, ApplicationWindow, Box as GtkBox, Label, ListBox, ListBoxRow, Orientation, Paned,
    Stack, StackTransitionType,
};

use app_state::AppHandle;
use dependency_manager::DependencyManager;

const APP_ID: &str = "dev.colima.desktop";

fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let app = Application::builder().application_id(APP_ID).build();
    app.connect_activate(build_ui);
    app.run();
}

fn build_ui(app: &Application) {
    // Parse socket path from CLI args (--socket /path/to/sock)
    let socket = parse_socket_arg().unwrap_or_else(|| "/tmp/colima-desktop.sock".to_owned());

    let handle = AppHandle::new(socket);

    // Show onboarding if colima is missing; otherwise show main UI.
    if !DependencyManager::is_colima_installed() {
        build_onboarding_window(app, handle);
    } else {
        build_main_window(app, handle);
    }
}

fn build_onboarding_window(app: &Application, handle: AppHandle) {
    let content = views::onboarding::build();

    let window = ApplicationWindow::builder()
        .application(app)
        .title("Colima Desktop — Setup")
        .default_width(760)
        .default_height(540)
        .child(&content)
        .build();

    window.set_widget_name("window_onboarding");
    window.update_property(&[gtk::accessible::Property::Label("Colima Desktop Setup")]);
    window.present();
}

fn build_main_window(app: &Application, handle: AppHandle) {
    // Sidebar nav items
    const SURFACES: &[(&str, &str)] = &[
        ("dashboard", "Dashboard"),
        ("containers", "Containers"),
        ("images", "Images"),
        ("volumes", "Volumes"),
        ("networks", "Networks"),
        ("machines", "Machines"),
        ("kubernetes", "Kubernetes"),
        ("configuration", "Configuration"),
        ("runtime", "Runtime"),
        ("ai_workloads", "AI Workloads"),
        ("profiles", "Profiles"),
    ];

    // Stack (right panel)
    let stack = Stack::new();
    stack.set_widget_name("main_stack");
    stack.set_transition_type(StackTransitionType::None);

    // Build each surface view
    for (id, name) in SURFACES {
        let view: GtkBox = match *id {
            "dashboard" => views::dashboard::build(handle.clone()),
            "containers" => views::containers::build(handle.clone()),
            "images" => views::images::build(handle.clone()),
            "volumes" => views::volumes::build(handle.clone()),
            "networks" => views::networks::build(handle.clone()),
            "machines" => views::machines::build(handle.clone()),
            "kubernetes" => views::kubernetes::build(handle.clone()),
            "configuration" => views::configuration::build(handle.clone()),
            "runtime" => views::runtime::build(handle.clone()),
            "ai_workloads" => views::ai_workloads::build(handle.clone()),
            "profiles" => views::profiles::build(handle.clone()),
            _ => unreachable!(),
        };
        stack.add_named(&view, Some(id));
    }

    // Sidebar
    let sidebar = build_sidebar(SURFACES, &stack);

    // Connection status bar (bottom)
    let status_bar = build_status_bar(&handle);

    // Root layout: Paned(sidebar | stack) + status_bar
    let paned = Paned::new(Orientation::Horizontal);
    paned.set_position(200);
    paned.set_start_child(Some(&sidebar));
    paned.set_end_child(Some(&stack));
    paned.set_widget_name("main_paned");

    let root = GtkBox::new(Orientation::Vertical, 0);
    root.append(&paned);
    root.append(&status_bar);
    root.set_widget_name("main_root");

    let window = ApplicationWindow::builder()
        .application(app)
        .title("Colima Desktop")
        .default_width(1100)
        .default_height(720)
        .child(&root)
        .build();

    window.set_widget_name("window_main");
    window.update_property(&[gtk::accessible::Property::Label("Colima Desktop")]);
    window.present();

    // Kick off daemon connection after the window appears
    handle.connect_daemon();
}

fn build_sidebar(surfaces: &[(&str, &str)], stack: &Stack) -> gtk::ScrolledWindow {
    let list_box = ListBox::new();
    list_box.set_widget_name("sidebar_list");
    list_box.update_property(&[gtk::accessible::Property::Label("Navigation")]);
    list_box.set_selection_mode(gtk::SelectionMode::Single);
    list_box.add_css_class("navigation-sidebar");

    for (id, name) in surfaces {
        let lbl = Label::new(Some(name));
        lbl.set_halign(gtk::Align::Start);
        lbl.set_margin_start(12);
        lbl.set_margin_top(6);
        lbl.set_margin_bottom(6);
        lbl.set_widget_name(&format!("sidebar_label_{id}"));

        let row = ListBoxRow::new();
        row.set_widget_name(id);
        row.update_property(&[gtk::accessible::Property::Label(name)]);
        row.set_child(Some(&lbl));
        list_box.append(&row);
    }

    // Navigate on row selection
    {
        let st = stack.clone();
        list_box.connect_row_selected(move |_, row| {
            if let Some(r) = row {
                let id = r.widget_name();
                st.set_visible_child_name(&id);
            }
        });
    }

    // Select Dashboard by default
    list_box.select_row(list_box.row_at_index(0).as_ref());

    let sw = gtk::ScrolledWindow::builder()
        .child(&list_box)
        .hscrollbar_policy(gtk::PolicyType::Never)
        .vexpand(true)
        .build();
    sw.set_widget_name("sidebar_scroll");
    sw
}

fn build_status_bar(handle: &AppHandle) -> GtkBox {
    let bar = GtkBox::new(Orientation::Horizontal, 8);
    bar.set_margin_start(8);
    bar.set_margin_end(8);
    bar.set_margin_top(4);
    bar.set_margin_bottom(4);
    bar.set_widget_name("status_bar");
    bar.add_css_class("statusbar");

    let lbl = Label::new(Some("● Disconnected"));
    lbl.set_widget_name("status_bar_label");
    lbl.update_property(&[gtk::accessible::Property::Label("Daemon connection status")]);
    lbl.add_css_class("dim-label");

    bar.append(&lbl);

    // Poll connection state every 2 seconds and update label
    let h = handle.clone();
    glib::timeout_add_seconds_local(2, move || {
        let st = h.state.lock().unwrap();
        let text = match &st.connection {
            app_state::ConnectionState::Disconnected => "● Disconnected".to_owned(),
            app_state::ConnectionState::Connecting => "◌ Connecting…".to_owned(),
            app_state::ConnectionState::Connected => "● Connected".to_owned(),
            app_state::ConnectionState::Error(e) => {
                format!("✗ Error: {}", e.chars().take(60).collect::<String>())
            }
        };
        lbl.set_label(&text);
        glib::ControlFlow::Continue
    });

    bar
}

fn parse_socket_arg() -> Option<String> {
    let args: Vec<String> = std::env::args().collect();
    let idx = args.iter().position(|a| a == "--socket")?;
    args.get(idx + 1).cloned()
}
