import * as vue from "https://unpkg.com/vue@3/dist/vue.esm-browser.js";

vue
  .createApp({
    setup() {
      async function greet(_) {
        message.value = await getGreeting(name.value);
      }

      const message = vue.ref("");
      const name = vue.ref("");
      return { greet, message, name };
    },
  })
  .mount("#app");
