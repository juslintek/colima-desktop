/// Configuration view — GetConfig, SetConfig, GetTemplate, SetTemplate.
///
/// CONTRACT Part A: GetConfig · SetConfig · GetTemplate · SetTemplate.
/// Presents config as editable TOML-like text. Load fills the editor; Save parses
/// CPU/memory/disk fields and sends a SetConfig request.
use gtk::prelude::*;
use gtk::{Box as GtkBox, Entry, Label, Orientation, Separator, SpinButton, Adjustment};

use crate::app_state::AppHandle;
use crate::client::proto::{ColimaConfig, ProfileRequest, SetConfigRequest};
use crate::ui_helpers::{make_action_button, make_output_view, make_surface_header, set_text};

pub fn build(handle: AppHandle) -> GtkBox {
    let root = GtkBox::new(Orientation::Vertical, 0);
    root.set_widget_name("view_configuration");
    root.update_property(&[gtk::accessible::Property::Label("Configuration")]);

    let (header, spinner, _refresh) = make_surface_header("Configuration", "config");
    root.append(&header);

    // Fields
    let grid = gtk::Grid::builder().column_spacing(12).row_spacing(6).margin_start(12).margin_end(12).margin_top(8).build();

    macro_rules! lbl { ($t:expr) => {{ let l = Label::new(Some($t)); l.set_halign(gtk::Align::End); l.add_css_class("dim-label"); l }}; }
    macro_rules! spin { ($min:expr, $max:expr, $step:expr, $name:expr, $al:expr) => {{
        let adj = Adjustment::new(0.0, $min, $max, $step, $step * 10.0, 0.0);
        let s = SpinButton::new(Some(&adj), $step, 0);
        s.set_widget_name($name);
        s.update_property(&[gtk::accessible::Property::Label($al)]);
        s
    }}; }

    let spin_cpu  = spin!(1.0, 64.0, 1.0, "config_spin_cpu",  "CPU count");
    let spin_mem  = spin!(0.5, 128.0, 0.5, "config_spin_memory", "Memory in GiB");
    let spin_disk = spin!(10.0, 2000.0, 10.0, "config_spin_disk", "Disk in GiB");

    let entry_arch = Entry::builder().placeholder_text("aarch64").build();
    entry_arch.set_widget_name("config_entry_arch");
    entry_arch.update_property(&[gtk::accessible::Property::Label("Architecture")]);

    let entry_runtime = Entry::builder().placeholder_text("docker").build();
    entry_runtime.set_widget_name("config_entry_runtime");
    entry_runtime.update_property(&[gtk::accessible::Property::Label("Runtime")]);

    let entry_vmtype = Entry::builder().placeholder_text("vz").build();
    entry_vmtype.set_widget_name("config_entry_vmtype");
    entry_vmtype.update_property(&[gtk::accessible::Property::Label("VM type")]);

    grid.attach(&lbl!("CPUs"),       0, 0, 1, 1); grid.attach(&spin_cpu,      1, 0, 1, 1);
    grid.attach(&lbl!("Memory GiB"), 0, 1, 1, 1); grid.attach(&spin_mem,      1, 1, 1, 1);
    grid.attach(&lbl!("Disk GiB"),   0, 2, 1, 1); grid.attach(&spin_disk,     1, 2, 1, 1);
    grid.attach(&lbl!("Arch"),       0, 3, 1, 1); grid.attach(&entry_arch,    1, 3, 1, 1);
    grid.attach(&lbl!("Runtime"),    0, 4, 1, 1); grid.attach(&entry_runtime, 1, 4, 1, 1);
    grid.attach(&lbl!("VM Type"),    0, 5, 1, 1); grid.attach(&entry_vmtype,  1, 5, 1, 1);
    root.append(&grid);

    root.append(&Separator::new(Orientation::Horizontal));

    let btn_row = GtkBox::new(Orientation::Horizontal, 4);
    btn_row.set_margin_start(12); btn_row.set_margin_end(12);
    btn_row.set_margin_top(8); btn_row.set_margin_bottom(8);

    let btn_load_config    = make_action_button("⬇ Load Config",    "config_btn_load");
    let btn_save_config    = make_action_button("💾 Save Config",   "config_btn_save");
    let btn_load_template  = make_action_button("⬇ Load Template",  "config_btn_load_tpl");
    let btn_save_template  = make_action_button("💾 Save Template", "config_btn_save_tpl");
    btn_row.append(&btn_load_config);
    btn_row.append(&btn_save_config);
    btn_row.append(&btn_load_template);
    btn_row.append(&btn_save_template);
    root.append(&btn_row);

    let (sw_out, log_buf) = make_output_view("config_output");
    root.append(&sw_out);

    // Helper to populate fields from a ColimaConfig
    let populate = {
        let sc = spin_cpu.clone(); let sm = spin_mem.clone(); let sd = spin_disk.clone();
        let ea = entry_arch.clone(); let er = entry_runtime.clone(); let ev = entry_vmtype.clone();
        move |cfg: ColimaConfig| {
            sc.set_value(cfg.cpu as f64);
            sm.set_value(cfg.memory as f64);
            sd.set_value(cfg.disk as f64);
            ea.set_text(&cfg.arch);
            er.set_text(&cfg.runtime);
            ev.set_text(&cfg.vm_type);
        }
    };

    // Load Config
    {
        let h = handle.clone(); let lb = log_buf.clone(); let sp = spinner.clone();
        let pop = populate.clone();
        btn_load_config.connect_clicked(move |_| {
            sp.set_spinning(true);
            let profile = h.profile();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.colima.clone(); let lb2 = lb.clone(); let sp2 = sp.clone();
                let pop2 = pop.clone();
                h.rt.spawn(async move {
                    let res = c.get_config(ProfileRequest { profile }).await;
                    glib::idle_add_once(move || {
                        sp2.set_spinning(false);
                        match res {
                            Ok(r) => { pop2(r.into_inner()); set_text(&lb2, "Config loaded"); }
                            Err(e) => set_text(&lb2, &format!("Error: {e}")),
                        }
                    });
                });
            } else { sp.set_spinning(false); set_text(&lb, "Not connected"); }
        });
    }

    // Save Config
    {
        let h = handle.clone(); let lb = log_buf.clone(); let sp = spinner.clone();
        let sc = spin_cpu.clone(); let sm = spin_mem.clone(); let sd = spin_disk.clone();
        let ea = entry_arch.clone(); let er = entry_runtime.clone(); let ev = entry_vmtype.clone();
        btn_save_config.connect_clicked(move |_| {
            sp.set_spinning(true);
            let profile = h.profile();
            let cfg = ColimaConfig {
                cpu: sc.value() as i32,
                memory: sm.value() as f32,
                disk: sd.value() as i32,
                arch: ea.text().to_string(),
                runtime: er.text().to_string(),
                vm_type: ev.text().to_string(),
                ..Default::default()
            };
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.colima.clone(); let lb2 = lb.clone(); let sp2 = sp.clone();
                h.rt.spawn(async move {
                    let res = c.set_config(SetConfigRequest { profile, config: Some(cfg) }).await;
                    glib::idle_add_once(move || { sp2.set_spinning(false); match res { Ok(r) => set_text(&lb2, &r.into_inner().message), Err(e) => set_text(&lb2, &format!("Error: {e}")), } });
                });
            } else { sp.set_spinning(false); set_text(&lb, "Not connected"); }
        });
    }

    // Load Template
    {
        let h = handle.clone(); let lb = log_buf.clone(); let sp = spinner.clone();
        let pop = populate.clone();
        btn_load_template.connect_clicked(move |_| {
            sp.set_spinning(true);
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.colima.clone(); let lb2 = lb.clone(); let sp2 = sp.clone();
                let pop2 = pop.clone();
                h.rt.spawn(async move {
                    let res = c.get_template(crate::client::proto::Empty {}).await;
                    glib::idle_add_once(move || {
                        sp2.set_spinning(false);
                        match res {
                            Ok(r) => { pop2(r.into_inner()); set_text(&lb2, "Template loaded"); }
                            Err(e) => set_text(&lb2, &format!("Error: {e}")),
                        }
                    });
                });
            } else { sp.set_spinning(false); set_text(&lb, "Not connected"); }
        });
    }

    // Save Template
    {
        let h = handle.clone(); let lb = log_buf.clone(); let sp = spinner.clone();
        let sc = spin_cpu.clone(); let sm = spin_mem.clone(); let sd = spin_disk.clone();
        let ea = entry_arch.clone(); let er = entry_runtime.clone(); let ev = entry_vmtype.clone();
        btn_save_template.connect_clicked(move |_| {
            sp.set_spinning(true);
            let cfg = ColimaConfig {
                cpu: sc.value() as i32,
                memory: sm.value() as f32,
                disk: sd.value() as i32,
                arch: ea.text().to_string(),
                runtime: er.text().to_string(),
                vm_type: ev.text().to_string(),
                ..Default::default()
            };
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.colima.clone(); let lb2 = lb.clone(); let sp2 = sp.clone();
                h.rt.spawn(async move {
                    let res = c.set_template(cfg).await;
                    glib::idle_add_once(move || { sp2.set_spinning(false); match res { Ok(r) => set_text(&lb2, &r.into_inner().message), Err(e) => set_text(&lb2, &format!("Error: {e}")), } });
                });
            } else { sp.set_spinning(false); set_text(&lb, "Not connected"); }
        });
    }

    root
}
