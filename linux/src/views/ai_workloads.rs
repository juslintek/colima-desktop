/// AI Workloads view — ModelSetup (stream), ModelRun (stream), ModelServe, ModelStop.
///
/// CONTRACT Part A: ModelSetup(stream) · ModelRun(stream) · ModelServe · ModelStop.
use gtk::prelude::*;
use gtk::{Box as GtkBox, Entry, Label, Orientation, Separator, SpinButton, Adjustment};

use crate::app_state::AppHandle;
use crate::client::proto::{ModelRequest, ModelRunRequest, ModelServeRequest, ProfileRequest};
use crate::ui_helpers::{make_action_button, make_output_view, make_surface_header, set_text};

pub fn build(handle: AppHandle) -> GtkBox {
    let root = GtkBox::new(Orientation::Vertical, 0);
    root.set_widget_name("view_ai_workloads");
    root.update_property(&[gtk::accessible::Property::Label("AI Workloads")]);

    let (header, spinner, _) = make_surface_header("AI Workloads", "ai");
    root.append(&header);

    let grid = gtk::Grid::builder()
        .column_spacing(8).row_spacing(6)
        .margin_start(12).margin_end(12).margin_top(8)
        .build();

    macro_rules! lbl { ($t:expr) => {{ let l = Label::new(Some($t)); l.set_halign(gtk::Align::End); l.add_css_class("dim-label"); l }}; }

    let entry_model = Entry::builder().placeholder_text("model name (e.g. llama3)").build();
    entry_model.set_widget_name("ai_entry_model");
    entry_model.update_property(&[gtk::accessible::Property::Label("Model name")]);

    let entry_runner = Entry::builder().placeholder_text("docker").build();
    entry_runner.set_widget_name("ai_entry_runner");
    entry_runner.update_property(&[gtk::accessible::Property::Label("Runner (docker or ramalama)")]);

    let entry_prompt = Entry::builder().placeholder_text("prompt (optional for run)").build();
    entry_prompt.set_widget_name("ai_entry_prompt");
    entry_prompt.update_property(&[gtk::accessible::Property::Label("Prompt for model run")]);

    let adj_port = Adjustment::new(8080.0, 1024.0, 65535.0, 1.0, 100.0, 0.0);
    let spin_port = SpinButton::new(Some(&adj_port), 1.0, 0);
    spin_port.set_widget_name("ai_spin_port");
    spin_port.update_property(&[gtk::accessible::Property::Label("Serve port")]);

    grid.attach(&lbl!("Model"),  0, 0, 1, 1); grid.attach(&entry_model,  1, 0, 1, 1);
    grid.attach(&lbl!("Runner"), 0, 1, 1, 1); grid.attach(&entry_runner, 1, 1, 1, 1);
    grid.attach(&lbl!("Prompt"), 0, 2, 1, 1); grid.attach(&entry_prompt, 1, 2, 1, 1);
    grid.attach(&lbl!("Port"),   0, 3, 1, 1); grid.attach(&spin_port,    1, 3, 1, 1);
    root.append(&grid);

    root.append(&Separator::new(Orientation::Horizontal));

    let btn_row = GtkBox::new(Orientation::Horizontal, 4);
    btn_row.set_margin_start(12); btn_row.set_margin_end(12);
    btn_row.set_margin_top(8); btn_row.set_margin_bottom(8);

    let btn_setup = make_action_button("⬇ Setup",   "ai_btn_setup");
    let btn_run   = make_action_button("▶ Run",      "ai_btn_run");
    let btn_serve = make_action_button("🌐 Serve",   "ai_btn_serve");
    let btn_stop  = make_action_button("■ Stop",     "ai_btn_stop");
    btn_row.append(&btn_setup); btn_row.append(&btn_run);
    btn_row.append(&btn_serve); btn_row.append(&btn_stop);
    root.append(&btn_row);

    let (sw_out, log_buf) = make_output_view("ai_output");
    root.append(&sw_out);

    // Setup (streaming)
    {
        let h = handle.clone(); let lb = log_buf.clone(); let sp = spinner.clone();
        let er = entry_runner.clone();
        btn_setup.connect_clicked(move |_| {
            sp.set_spinning(true);
            let profile = h.profile();
            let model_req = ModelRequest { profile, runner: er.text().to_string() };
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.colima.clone(); let lb2 = lb.clone(); let sp2 = sp.clone();
                h.rt.spawn(async move {
                    match c.model_setup(model_req).await {
                        Ok(mut stream) => {
                            let mut log = String::new();
                            while let Ok(Some(evt)) = stream.get_mut().message().await {
                                log.push_str(&format!("[{}] {}\n", evt.stage, evt.message));
                            }
                            glib::idle_add_once(move || { sp2.set_spinning(false); set_text(&lb2, &log); });
                        }
                        Err(e) => glib::idle_add_once(move || { sp2.set_spinning(false); set_text(&lb2, &format!("Error: {e}")); }),
                    }
                });
            } else { sp.set_spinning(false); set_text(&lb, "Not connected"); }
        });
    }

    // Run (streaming)
    {
        let h = handle.clone(); let lb = log_buf.clone(); let sp = spinner.clone();
        let em = entry_model.clone(); let er = entry_runner.clone(); let ep = entry_prompt.clone();
        btn_run.connect_clicked(move |_| {
            let model = em.text().to_string();
            if model.is_empty() { set_text(&lb, "Enter a model name first"); return; }
            sp.set_spinning(true);
            let req = ModelRunRequest {
                profile: h.profile(),
                model,
                runner: er.text().to_string(),
                prompt: ep.text().to_string(),
            };
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.colima.clone(); let lb2 = lb.clone(); let sp2 = sp.clone();
                h.rt.spawn(async move {
                    match c.model_run(req).await {
                        Ok(mut stream) => {
                            let mut log = String::new();
                            while let Ok(Some(evt)) = stream.get_mut().message().await {
                                log.push_str(&format!("[{}] {}\n", evt.stage, evt.message));
                            }
                            glib::idle_add_once(move || { sp2.set_spinning(false); set_text(&lb2, &log); });
                        }
                        Err(e) => glib::idle_add_once(move || { sp2.set_spinning(false); set_text(&lb2, &format!("Error: {e}")); }),
                    }
                });
            } else { sp.set_spinning(false); set_text(&lb, "Not connected"); }
        });
    }

    // Serve
    {
        let h = handle.clone(); let lb = log_buf.clone(); let sp = spinner.clone();
        let em = entry_model.clone(); let er = entry_runner.clone(); let esp = spin_port.clone();
        btn_serve.connect_clicked(move |_| {
            let model = em.text().to_string();
            sp.set_spinning(true);
            let req = ModelServeRequest {
                profile: h.profile(),
                model,
                runner: er.text().to_string(),
                port: esp.value() as i32,
            };
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.colima.clone(); let lb2 = lb.clone(); let sp2 = sp.clone();
                h.rt.spawn(async move {
                    let res = c.model_serve(req).await;
                    glib::idle_add_once(move || { sp2.set_spinning(false); match res { Ok(r) => set_text(&lb2, &r.into_inner().message), Err(e) => set_text(&lb2, &format!("Error: {e}")), } });
                });
            } else { sp.set_spinning(false); set_text(&lb, "Not connected"); }
        });
    }

    // Stop
    {
        let h = handle.clone(); let lb = log_buf.clone(); let sp = spinner.clone();
        btn_stop.connect_clicked(move |_| {
            sp.set_spinning(true);
            let profile = h.profile();
            let mut state = h.state.lock().unwrap();
            if let Some(ref mut client) = state.daemon {
                let mut c = client.colima.clone(); let lb2 = lb.clone(); let sp2 = sp.clone();
                h.rt.spawn(async move {
                    let res = c.model_stop(ProfileRequest { profile }).await;
                    glib::idle_add_once(move || { sp2.set_spinning(false); match res { Ok(r) => set_text(&lb2, &r.into_inner().message), Err(e) => set_text(&lb2, &format!("Error: {e}")), } });
                });
            } else { sp.set_spinning(false); set_text(&lb, "Not connected"); }
        });
    }

    root
}
