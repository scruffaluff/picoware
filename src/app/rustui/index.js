import * as vue from "https://cdn.jsdelivr.net/npm/vue@3/dist/vue.esm-browser.prod.js";

vue
  .createApp({
    setup() {
      async function greet(_) {
        window.ipc.postMessage(name.value);
      }

      const message = vue.ref("");
      const name = vue.ref("");
      return { greet, message, name };
    },
  })
  .mount("#app");
