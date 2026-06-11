#!/usr/bin/env rust-script
//! ```cargo
//! [dependencies]
//! clap = "^4.6.1"
//! eyre = "^0.6.12"
//! tao = "^0.35.3"
//! wry = { features = ["devtools", "protocol"], version = "^0.55.1" }
//! [target.'cfg(target_os = "linux")'.dependencies]
//! gtk = "^0.18.2"
//! ```

use clap::Command;
use eyre::{self, OptionExt};
use std::path::{Path, PathBuf};
use std::{env, fs};
use tao::{
    event::{Event, WindowEvent},
    event_loop::{ControlFlow, EventLoop},
    window::{Window, WindowBuilder},
};
use wry::{WebView, WebViewBuilder};

fn build_webview(window: &Window) -> eyre::Result<WebView> {
    let folder = script_folder()?;
    let js = fs::read_to_string(folder.join("index.js"))?;

    let builder = WebViewBuilder::new()
        .with_url("https://strudel.cc/")
        .with_initialization_script(js)
        .with_devtools(true);

    #[cfg(not(target_os = "linux"))]
    let webview = builder.build(&window)?;
    #[cfg(target_os = "linux")]
    let webview = {
        use gtk::prelude::WidgetExt;
        use tao::platform::unix::WindowExtUnix;
        use wry::WebViewBuilderExtUnix;

        let vbox = window
            .default_vbox()
            .ok_or_eyre("Unable to get program window.")?;
        builder.build_gtk(&vbox)?
    };

    Ok(webview)
}

fn main() -> eyre::Result<()> {
    let _args = Command::new("Strudel")
        .about("Live coding platform.")
        .bin_name("strudel")
        .version("0.0.1")
        .get_matches();

    let event_loop = EventLoop::new();
    let window = WindowBuilder::new()
        .with_title("Strudel")
        .with_maximized(true)
        .build(&event_loop)?;
    let _webview = build_webview(&window)?;

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

fn script_folder() -> eyre::Result<PathBuf> {
    let buffer = env::var("RUST_SCRIPT_PATH")?;
    let executable = Path::new(&buffer);
    let folder = executable
        .parent()
        .ok_or_eyre("Unable to get program folder.")?;
    Ok(folder.to_path_buf())
}
