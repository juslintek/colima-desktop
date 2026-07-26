/// Shared UI helpers used across all surface views.
use gtk::prelude::*;
use gtk::{
    Box as GtkBox, Button, Label, Orientation, ScrolledWindow, Spinner, TextBuffer, TextView,
};
use std::cell::RefCell;
use std::rc::Rc;

use crate::client::proto::StatusResponse;

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

/// Maximum number of bytes retained in a streamed-output buffer before the
/// oldest content is dropped. Keeps long-running streams (AI model setup/run,
/// image transfers, stats) from growing the UI buffer without bound.
pub const STREAM_OUTPUT_LIMIT: usize = 100_000;

/// Append `chunk` to `log`, then trim from the front so the buffer never
/// exceeds `STREAM_OUTPUT_LIMIT` bytes. Trimming advances to the next UTF-8
/// char boundary so multi-byte content (e.g. arbitrary LLM output from an AI
/// model stream) can never be split mid-character — a plain
/// `String::drain(..n)` would panic if `n` fell inside a multi-byte scalar.
pub fn append_bounded(log: &mut String, chunk: &str) {
    log.push_str(chunk);
    if log.len() > STREAM_OUTPUT_LIMIT {
        let mut cut = log.len() - STREAM_OUTPUT_LIMIT;
        while cut < log.len() && !log.is_char_boundary(cut) {
            cut += 1;
        }
        log.drain(..cut);
    }
}

/// Render a DockerService `StatusResponse` (`{success, message, error}`) as
/// display text, surfacing the daemon's `error` field when the operation did
/// not succeed. The daemon reports a failed mutation as
/// `StatusResponse{success:false, error:<text>, message:""}`, so reading only
/// `message` would render an empty, success-looking result and silently drop
/// the error. This mirrors the `if error.is_empty() { Ok(json) } else { Err(error) }`
/// handling already used for `JsonResponse` mutations, so every Docker mutation
/// surfaces backend errors before any success is shown.
pub fn status_message(response: StatusResponse) -> Result<String, String> {
    if response.success {
        Ok(response.message)
    } else if response.error.is_empty() {
        Err("operation failed".to_owned())
    } else {
        Err(response.error)
    }
}

/// Classify a Docker container action id as destructive. Destructive actions
/// (`kill`, `remove`) must be routed through [`confirm_destructive`] before any
/// RPC is issued; reversible lifecycle actions (`start`/`stop`/`restart`/
/// `pause`/`unpause`) are not gated. Centralizing the decision keeps the
/// containers view's confirmation routing in one tested place (Property 13),
/// so a new container action cannot silently bypass the gate.
pub fn container_action_is_destructive(action: &str) -> bool {
    matches!(action, "kill" | "remove")
}

/// Require an explicit OK response before invoking a destructive callback.
/// The dialog and callback both live exclusively on GTK's main thread.
pub fn confirm_destructive(
    source: &impl IsA<gtk::Widget>,
    title: &str,
    detail: &str,
    confirmed: impl FnOnce() + 'static,
) {
    let dialog = gtk::MessageDialog::builder()
        .modal(true)
        .message_type(gtk::MessageType::Warning)
        .buttons(gtk::ButtonsType::OkCancel)
        .text(title)
        .secondary_text(detail)
        .build();
    if let Some(window) = source.root().and_downcast::<gtk::Window>() {
        dialog.set_transient_for(Some(&window));
    }
    dialog.set_widget_name("destructive_confirmation_dialog");
    dialog.update_property(&[gtk::accessible::Property::Label(title)]);
    let callback = Rc::new(RefCell::new(Some(confirmed)));
    dialog.connect_response(move |dialog, response| {
        if response == gtk::ResponseType::Ok {
            if let Some(callback) = callback.borrow_mut().take() {
                callback();
            }
        }
        dialog.close();
    });
    dialog.present();
}

#[cfg(test)]
mod tests {
    use super::{
        append_bounded, container_action_is_destructive, status_message, STREAM_OUTPUT_LIMIT,
    };
    use crate::client::proto::StatusResponse;

    #[test]
    fn container_action_is_destructive_gates_only_kill_and_remove() {
        // Destructive container actions MUST be gated behind confirm_destructive
        // (Property 13); reversible lifecycle actions must not be.
        assert!(container_action_is_destructive("kill"));
        assert!(container_action_is_destructive("remove"));
        assert!(!container_action_is_destructive("start"));
        assert!(!container_action_is_destructive("stop"));
        assert!(!container_action_is_destructive("restart"));
        assert!(!container_action_is_destructive("pause"));
        assert!(!container_action_is_destructive("unpause"));
        // An unrecognized action defaults to non-destructive (no accidental gate),
        // and — just as importantly — is never silently treated as destructive.
        assert!(!container_action_is_destructive("inspect"));
    }

    #[test]
    fn status_message_returns_message_on_success() {
        let response = StatusResponse {
            success: true,
            message: "removed".to_owned(),
            error: String::new(),
        };
        assert_eq!(status_message(response), Ok("removed".to_owned()));
    }

    #[test]
    fn status_message_surfaces_daemon_error_on_failure() {
        // The daemon reports a failed mutation as
        // StatusResponse{success:false, error:<text>, message:""}. Reading only
        // `message` would render an empty, success-looking result; the daemon
        // error must be surfaced instead.
        let response = StatusResponse {
            success: false,
            message: String::new(),
            error: "No such container: e2e-ctr".to_owned(),
        };
        assert_eq!(
            status_message(response),
            Err("No such container: e2e-ctr".to_owned())
        );
    }

    #[test]
    fn status_message_reports_generic_failure_when_error_is_empty() {
        let response = StatusResponse {
            success: false,
            message: String::new(),
            error: String::new(),
        };
        assert_eq!(status_message(response), Err("operation failed".to_owned()));
    }

    #[test]
    fn append_bounded_keeps_small_output_intact() {
        let mut log = String::from("hello ");
        append_bounded(&mut log, "world");
        assert_eq!(log, "hello world");
    }

    #[test]
    fn append_bounded_caps_length_and_never_splits_multibyte_chars() {
        // Each '★' is 3 bytes; 60_000 of them = 180_000 bytes, well over the cap.
        let mut log = String::new();
        append_bounded(&mut log, &"★".repeat(60_000));
        // Bounded: never exceeds the limit (drain keeps at most the last LIMIT bytes).
        assert!(log.len() <= STREAM_OUTPUT_LIMIT);
        // A fixed-byte drain would have panicked / produced invalid UTF-8 mid-'★';
        // char-boundary trimming keeps every retained scalar intact.
        assert!(log.chars().all(|c| c == '★'));
        // Trimming lands within one scalar (3 bytes) of the limit.
        assert!(log.len() > STREAM_OUTPUT_LIMIT - 3);
    }

    #[test]
    fn append_bounded_accumulates_across_calls_until_capped() {
        let mut log = String::new();
        for _ in 0..20 {
            append_bounded(&mut log, &"x".repeat(10_000));
        }
        // 200_000 bytes appended in 10k chunks, capped to the limit.
        assert_eq!(log.len(), STREAM_OUTPUT_LIMIT);
        assert!(log.chars().all(|c| c == 'x'));
    }

    #[test]
    fn append_bounded_at_exactly_the_limit_is_left_untrimmed() {
        // Boundary: a buffer that reaches exactly the limit must not be trimmed;
        // only growth strictly *beyond* the limit triggers front-trimming.
        let mut log = String::new();
        append_bounded(&mut log, &"a".repeat(STREAM_OUTPUT_LIMIT));
        assert_eq!(log.len(), STREAM_OUTPUT_LIMIT);
        assert!(log.chars().all(|c| c == 'a'));
    }

    #[test]
    fn append_bounded_drops_the_oldest_content_first() {
        // Front-trimming must drop the *oldest* bytes (FIFO), so a marker written
        // first disappears once the buffer overflows while newer content is kept.
        // This is the property the streaming log/stat/event views rely on: a
        // long-running stream keeps its most recent output, not its first.
        let mut log = String::from("OLDEST_MARKER");
        append_bounded(&mut log, &"z".repeat(STREAM_OUTPUT_LIMIT));
        assert!(log.len() <= STREAM_OUTPUT_LIMIT);
        assert!(!log.contains("OLDEST_MARKER"));
        assert!(log.ends_with('z'));
    }
}
