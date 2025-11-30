#!/usr/bin/env rust-script
//! ```cargo
//! [dependencies]
//! clap = "^4.5.45"
//! eyre = "^0.6.0"
//! tao = "^0.34.2"
//! wry = { features = ["devtools"], version = "^0.53.0" }
//! [target.'cfg(target_os = "linux")'.dependencies]
//! gtk = "^0.18.2"
//! ```

use clap::{Arg, ArgAction, Command};
use eyre::{self, OptionExt};
use std::path::{Path, PathBuf};
use std::process;
use std::{env, fs};
use tao::{
    event::{Event, WindowEvent},
    event_loop::{ControlFlow, EventLoop},
    window::{Window, WindowBuilder},
};
use wry::{http::Request, WebView, WebViewBuilder};

fn build_webview(window: &Window, dev: bool) -> eyre::Result<WebView> {
    let builder = if dev {
        WebViewBuilder::new()
            .with_devtools(true)
            .with_url("http://localhost:5173")
    } else {
        let html = load_html()?;
        WebViewBuilder::new().with_html(&html)
    }
    .with_ipc_handler(|request: Request<String>| {
        let response = format!("Hello {}!", request.body());
        println!("{}", response);
    });

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
        vbox.set_hexpand(true);
        vbox.set_vexpand(true);
        vbox.show();
        builder.build_gtk(&vbox.clone())?
    };

    Ok(webview)
}

fn load_html() -> eyre::Result<String> {
    let folder = script_folder()?;
    let html = fs::read_to_string(folder.join("index.html"))?;
    let js = fs::read_to_string(folder.join("index.js"))?;

    Ok(html.replace(
        "<script src=\"/index.js\" type=\"module\"></script>",
        &format!("<script type=\"module\">{}</script>", js),
    ))
}

fn main() -> eyre::Result<()> {
    let args = Command::new("Rustui")
        .about("Example GUI application with Rust.")
        .bin_name("rustui")
        .version("0.0.1")
        .arg(
            Arg::new("dev")
                .help("Launch application in developer mode")
                .long("dev")
                .action(ArgAction::SetTrue),
        )
        .get_matches();

    let dev = args.get_flag("dev");
    let event_loop = EventLoop::new();
    let window = WindowBuilder::new()
        .with_title("Rustui")
        .build(&event_loop)?;
    let _webview = build_webview(&window, dev)?;
    if dev {
        let folder = script_folder()?;
        process::Command::new("deno")
            .args([
                "run",
                "--allow-all",
                "npm:vite",
                "dev",
                "--port",
                "5173",
                &folder.to_string_lossy(),
            ])
            .spawn()?;
    }

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
