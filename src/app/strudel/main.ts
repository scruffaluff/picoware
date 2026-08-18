#!/usr/bin/env -S deno desktop --allow-all --hmr --no-config --quiet --node-modules-dir=none

const script = `
localStorage.setItem("strudel-settingsfontFamily", "FiraCode");
localStorage.setItem("strudel-settingsfontSize", 16);
localStorage.setItem("strudel-settingsisAutoCompletionEnabled", true);
localStorage.setItem("strudel-settingsisMultiCursorEnabled", true);
localStorage.setItem("strudel-settingskeybindings", "vscode");
localStorage.setItem("strudel-settingstheme", "solarizedLight");
`;

/** Wait for webpage to finish loading. */
async function waitForPage(window: Deno.BrowserWindow): Promise<void> {
  for (let idx = 0; idx < 50; idx++) {
    const ready = await window.executeJs("document.readyState");
    if (ready === "complete") {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 200));
  }
}

async function main(): Promise<void> {
  const window = new Deno.BrowserWindow({
    title: "Strudel",
  });
  window.setApplicationMenu([
    {
      submenu: {
        label: "File",
        items: [
          {
            item: {
              accelerator: "CmdOrCtrl+N",
              enabled: true,
              id: "new",
              label: "New",
            },
          },
          {
            item: {
              accelerator: "CmdOrCtrl+O",
              enabled: true,
              id: "open",
              label: "Open",
            },
          },
          "separator",
          {
            item: {
              accelerator: "CmdOrCtrl+S",
              enabled: true,
              id: "save",
              label: "Save",
            },
          },
          { role: { role: "quit" } },
        ],
      },
    },
    {
      submenu: {
        label: "Edit",
        items: [
          { role: { role: "undo" } },
          { role: { role: "redo" } },
          "separator",
          { role: { role: "cut" } },
          { role: { role: "copy" } },
          { role: { role: "paste" } },
        ],
      },
    },
  ]);

  window.addEventListener("close", () => Deno.exit(0));
  window.navigate("https://strudel.cc/");
  window.show();
  window.focus();
  window.openDevtools();

  await waitForPage(window);
  window.executeJs(script);
}

await main();
