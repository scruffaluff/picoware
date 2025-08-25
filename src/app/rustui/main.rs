#!/usr/bin/env rust-script
//! ```cargo
//! [dependencies]
//! clap = "^4.5.45"
//! eyre = "^0.6.0"
//! tao = "^0.34.2"
//! wry = "^0.53.0"
//! [target.'cfg(target_os = "linux")'.dependencies]
//! gtk = "^0.18.2"
//! ```

use clap::{Arg, ArgAction, Command};
use eyre::{self, OptionExt};
use std::path::Path;
use std::{env, fs};
use tao::{
    event::{Event, WindowEvent},
    event_loop::{ControlFlow, EventLoop},
    platform::unix::WindowExtUnix,
    window::{Window, WindowBuilder},
};
use wry::{WebView, WebViewBuilder, WebViewBuilderExtUnix};

fn build_webview(window: &Window, debug: bool) -> eyre::Result<WebView> {
    let html = load_html()?;
    let builder = WebViewBuilder::new().with_devtools(debug).with_html(&html);

    #[cfg(not(target_os = "linux"))]
    let webview = builder.build(&window)?;
    #[cfg(target_os = "linux")]
    let webview = {
        use gtk::prelude::WidgetExt;
        let vbox = window
            .default_vbox()
            .ok_or_eyre("Unable to get program window.")?;
        vbox.set_hexpand(true);
        vbox.set_vexpand(true);
        vbox.show();
        builder.build_gtk(&vbox.clone())?
    };

    Ok(webview)
}

fn load_html() -> eyre::Result<String> {
    let buffer = env::var("RUST_SCRIPT_PATH")?;
    let executable = Path::new(&buffer);
    let folder = executable
        .parent()
        .ok_or_eyre("Unable to get program folder.")?;
    let html = fs::read_to_string(folder.join("index.html"))?;
    let js = fs::read_to_string(folder.join("index.js"))?;

    Ok(html.replace(
        "<script type=\"module\"></script>",
        &format!("<script type=\"module\">{}</script>", js),
    ))
}

fn main() -> eyre::Result<()> {
    let args = Command::new("Rustui")
        .about("Example GUI application with Rust.")
        .bin_name("rustui")
        .version("0.0.1")
        .arg(
            Arg::new("debug")
                .help("Launch application in debug mode")
                .long("debug")
                .short('d')
                .action(ArgAction::SetTrue),
        )
        .get_matches();

    let event_loop = EventLoop::new();
    let window = WindowBuilder::new()
        .with_title("Rustui")
        .build(&event_loop)?;
    let _webview = build_webview(&window, args.get_flag("debug"))?;

    event_loop.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::Wait;

        if let Event::WindowEvent {
            event: WindowEvent::CloseRequested,
            ..
        } = event
        {
            *control_flow = ControlFlow::Exit
        }
    });
}
