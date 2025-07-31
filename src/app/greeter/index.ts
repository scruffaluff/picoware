#!/usr/bin/env -S deno run --allow-all --no-config --node-modules-dir=none

import { Command } from "jsr:@cliffy/command@1.0.0-rc.8";
import * as path from "jsr:@std/path";
import { Webview } from "jsr:@webview/webview@0.9.0";

async function main(): Promise<void> {
  await new Command()
    .name("Greeter")
    .description("Greeter example application.")
    .version("0.0.1")
    .action(async () => {
      await run();
    })
    .parse();
}

async function run(): Promise<void> {
  const js = await Deno.readTextFile(
    path.join(import.meta.dirname!, "index.js")
  );
  const html = (
    await Deno.readTextFile(path.join(import.meta.dirname!, "index.html"))
  ).replace(
    '<script type="module"></script>',
    `<script type="module">${js}</script>`
  );

  const webview = new Webview();
  webview.title = "Greeter";
  webview.bind("getGreeting", (name: string) => `Hello ${name}!`);
  webview.navigate(`data:text/html,${encodeURIComponent(html)}`);
  webview.run();
}

await main();
