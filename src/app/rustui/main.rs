#!/usr/bin/env rust-script
//! ```cargo
//! [dependencies]
//! clap = "^4.5.45"
//! eyre = "^0.6.0"
//! tao = "^0.34.2"
//! wry = "^0.53.0"
//! ```

use clap::{Arg, ArgAction, Command};
use eyre::{self, OptionExt};
use std::path::Path;
use std::{env, fs};
use tao::{
    event::{Event, WindowEvent},
    event_loop::{ControlFlow, EventLoop},
    platform::unix::WindowExtUnix,
    window::WindowBuilder,
};
use wry::{WebViewBuilder, WebViewBuilderExtUnix};

fn load_html() -> eyre::Result<String> {
    let foo = env::var("RUST_SCRIPT_PATH")?;
    let executable = Path::new(&foo);
    let folder = executable.parent().ok_or_eyre("static error message")?;
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

    let html = load_html()?;
    let event_loop = EventLoop::new();
    let window = WindowBuilder::new()
        .with_title("Rustui")
        .build(&event_loop)?;

    let builder = WebViewBuilder::new()
        .with_devtools(args.get_flag("debug"))
        .with_html(&html);
    #[cfg(not(target_os = "linux"))]
    let _webview = builder.build(&window).unwrap();
    #[cfg(target_os = "linux")]
    let _webview = builder.build_gtk(window.gtk_window()).unwrap();

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
