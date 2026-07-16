/// Machines (Lima) view — ListMachines.
///
/// CONTRACT Part A: ListMachines.
use gtk::prelude::*;
use gtk::{Box as GtkBox, ListBox, ListBoxRow, Label, Orientation};

use crate::app_state::AppHandle;
use crate::client::proto::Empty;
use crate::ui_helpers::{make_output_view, make_surface_header, set_text};

pub fn build(handle: AppHandle) -> GtkBox {
    let root = GtkBox::new(Orientation::Vertical, 0);
    root.set_widget_name("view_machines");
    root.update_property(&[gtk::accessible::Property::Label("Machines")]);

    let (header, spinner, refresh_btn) = make_surface_header("Machines (Lima)", "machines");
    root.append(&header);

    let list_box = ListBox::new();
    list_box.set_widget_name("machines_list");
    list_box.update_property(&[gtk::accessible::Property::Label("Machine list")]);
    let sw_list = gtk::ScrolledWindow::builder().child(&list_box).vexpand(true).build();
    root.append(&sw_list);

    let (sw_out, log_buf) = make_output_view("machines_output");
    root.append(&sw_out);

    {
        let h = handle.clone(); let lb = log_buf.clone(); let sp = spinner.clone();
        let list = list_box.clone();
        refresh_btn.connect_clicked(move |_| {
            sp.set_spinning(true);
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.colima.clone();
                let lb2 = lb.clone(); let sp2 = sp.clone(); let list2 = list.clone();
                h.rt.spawn(async move {
                    let res = c.list_machines(Empty {}).await;
                    glib::idle_add_once(move || {
                        sp2.set_spinning(false);
                        while let Some(child) = list2.first_child() { list2.remove(&child); }
                        match res {
                            Ok(r) => {
                                for m in r.into_inner().machines {
                                    let lbl = Label::new(Some(&format!(
                                        "{}  status={}  arch={}  cpus={}  mem={:.1}GiB  disk={:.1}GiB",
                                        m.name, m.status, m.arch, m.cpus,
                                        m.memory as f64 / 1_073_741_824.0,
                                        m.disk as f64 / 1_073_741_824.0,
                                    )));
                                    lbl.set_halign(gtk::Align::Start); lbl.set_margin_start(8); lbl.set_margin_top(4); lbl.set_margin_bottom(4);
                                    let row = ListBoxRow::new();
                                    row.set_widget_name(&m.name);
                                    row.update_property(&[gtk::accessible::Property::Label(&m.name)]);
                                    row.set_child(Some(&lbl));
                                    list2.append(&row);
                                }
                            }
                            Err(e) => set_text(&lb2, &format!("Error: {e}")),
                        }
                    });
                });
            } else { sp.set_spinning(false); set_text(&lb, "Not connected"); }
        });
    }

    root
}
