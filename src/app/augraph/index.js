import * as echarts from "https://unpkg.com/echarts@5.6.0/dist/echarts.esm.min.js";
import * as vue from "https://unpkg.com/vue@3/dist/vue.esm-browser.js";

let audio;
let chart;

async function plot() {
  audio = await pywebview.api.load();
  chart.setOption({
    series: [
      {
        data: audio,
        showSymbol: false,
        type: "line",
      },
    ],
    xAxis: {
      type: "value",
    },
    yAxis: {
      max: 1.0,
      min: -1.0,
      type: "value",
    },
  });
}

vue
  .createApp({
    setup() {
      const path = vue.ref("");
      const element = vue.useTemplateRef("chart");
      vue.onMounted(() => {
        chart = echarts.init(element.value);
      });
      return { element, path };
    },
  })
  .mount("#app");

globalThis.plot = plot;
