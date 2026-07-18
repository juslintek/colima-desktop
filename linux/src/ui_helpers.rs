/// Shared UI helpers used across all surface views.
use gtk::prelude::*;
use gtk::{
    Box as GtkBox, Button, Label, Orientation, ScrolledWindow, Spinner, TextBuffer, TextView,
};

/// Create a titled section box with a spinner and a refresh button.
/// Sets AT-SPI accessible names on every interactive widget.
pub fn make_surface_header(title: &str, at_spi_prefix: &str) -> (GtkBox, Spinner, Button) {
    let hbox = GtkBox::new(Orientation::Horizontal, 8);
    hbox.set_margin_start(12);
    hbox.set_margin_end(12);
    hbox.set_margin_top(8);
    hbox.set_margin_bottom(8);

    let lbl = Label::new(Some(title));
    lbl.set_halign(gtk::Align::Start);
    lbl.set_hexpand(true);
    // AT-SPI role comes from Label's default role; set name for automation.
    lbl.set_widget_name(&format!("{at_spi_prefix}_header_label"));
    lbl.update_property(&[gtk::accessible::Property::Label(title)]);

    let spinner = Spinner::new();
    spinner.set_widget_name(&format!("{at_spi_prefix}_spinner"));
    spinner.update_property(&[gtk::accessible::Property::Label("Loading")]);

    let refresh_btn = Button::with_label("↻ Refresh");
    refresh_btn.set_widget_name(&format!("{at_spi_prefix}_btn_refresh"));
    refresh_btn.update_property(&[gtk::accessible::Property::Label("Refresh")]);
    refresh_btn.add_css_class("flat");

    hbox.append(&lbl);
    hbox.append(&spinner);
    hbox.append(&refresh_btn);

    (hbox, spinner, refresh_btn)
}

/// Create a scrollable TextView for displaying JSON / text output.
/// Sets AT-SPI name so screen readers can identify the region.
pub fn make_output_view(at_spi_name: &str) -> (ScrolledWindow, TextBuffer) {
    let buf = TextBuffer::new(None::<&gtk::TextTagTable>);
    let tv = TextView::with_buffer(&buf);
    tv.set_editable(false);
    tv.set_monospace(true);
    tv.set_vexpand(true);
    tv.set_widget_name(at_spi_name);
    tv.update_property(&[gtk::accessible::Property::Label(at_spi_name)]);

    let sw = ScrolledWindow::builder().child(&tv).vexpand(true).build();
    sw.set_widget_name(&format!("{at_spi_name}_scroll"));
    (sw, buf)
}

/// Create a simple action button with an AT-SPI accessible label.
pub fn make_action_button(label: &str, at_spi_name: &str) -> Button {
    let btn = Button::with_label(label);
    btn.set_widget_name(at_spi_name);
    btn.update_property(&[gtk::accessible::Property::Label(label)]);
    btn
}

/// Set text in a TextBuffer, replacing all existing content.
pub fn set_text(buf: &TextBuffer, text: &str) {
    buf.set_text(text);
}
