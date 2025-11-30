#!/usr/bin/env -S deno run --allow-all --no-config --quiet --node-modules-dir=none

import { Command } from "jsr:@cliffy/command@1.0.0-rc.8";
import * as path from "jsr:@std/path";
import { Webview } from "jsr:@webview/webview@0.9.0";

async function main(): Promise<void> {
  await new Command()
    .name("Denoui")
    .description("Example GUI application with Deno.")
    .version("0.0.1")
    .option("--dev", "Launch application in developer mode.")
    .action(async (options) => {
      await run(options.dev);
    })
    .parse(Deno.args);
}

async function run(dev: boolean): Promise<void> {
  const folder = import.meta.dirname!;
  let url: string;
  if (dev) {
    const command = new Deno.Command("deno", {
      args: ["run", "--allow-all", "npm:vite", "dev", "--port", "5173", folder],
    });
    command.spawn();
    url = "http://localhost:5173";
  } else {
    const js = await Deno.readTextFile(path.join(folder, "index.js"));
    const html = (
      await Deno.readTextFile(path.join(folder, "index.html"))
    ).replace(
      '<script src="/index.js" type="module"></script>',
      `<script type="module">${js}</script>`
    );
    url = `data:text/html,${encodeURIComponent(html)}`;
  }

  const webview = new Webview();
  webview.title = "Denoui";
  webview.bind("getGreeting", (name: string) => `Hello ${name}!`);
  webview.navigate(url);
  webview.run();
}

await main();
