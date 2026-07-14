use gtk::prelude::*;
use gtk::{Application, ApplicationWindow, Box as GtkBox, Label, Orientation, StackSwitcher, Stack};

mod client;

const SURFACES: &[&str] = &[
    "Dashboard", "Containers", "Images", "Volumes", "Networks",
    "Kubernetes", "Profiles", "Configuration", "AI", "Monitoring",
    "Machines", "Runtime Controls", "Community",
];

fn main() {
    let app = Application::builder()
        .application_id("dev.colima.desktop")
        .build();
    app.connect_activate(build_ui);
    app.run();
}

fn build_ui(app: &Application) {
    let stack = Stack::new();
    for name in SURFACES {
        let page = GtkBox::new(Orientation::Vertical, 8);
        let label = Label::new(Some(&format!("{name} — wired to daemon (gRPC)")));
        label.set_widget_name(&format!("surface_{}", name.to_lowercase().replace(' ', "_")));
        page.append(&label);
        stack.add_titled(&page, Some(name), name);
    }
    let switcher = StackSwitcher::new();
    switcher.set_stack(Some(&stack));

    let root = GtkBox::new(Orientation::Vertical, 0);
    root.append(&switcher);
    root.append(&stack);

    let window = ApplicationWindow::builder()
        .application(app)
        .title("Colima Desktop")
        .default_width(1000)
        .default_height(680)
        .child(&root)
        .build();
    window.present();
}
