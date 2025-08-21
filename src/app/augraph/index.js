import * as echarts from "https://cdn.jsdelivr.net/npm/echarts@6/dist/echarts.esm.min.js";
import * as vue from "https://cdn.jsdelivr.net/npm/vue@3/dist/vue.esm-browser.prod.js";

let audio;
let chart;

async function plot() {
  audio = await pywebview.api.load();
  chart.setOption({
    series: [
      {
        data: audio,
        name: "amplitude",
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
        chart.setOption({
          animation: false,
          dataZoom: [
            { type: "inside", xAxisIndex: [0] },
            { type: "inside", yAxisIndex: [0] },
          ],
          grid: { right: "12%" },
          legend: {
            data: [{ icon: "circle", name: "amplitude" }],
            orient: "vertical",
            right: "1%",
            top: "12%",
          },
          series: [],
          title: { text: "Audio Signal" },
          toolbox: {
            feature: {
              dataZoom: {},
              restore: {},
              saveAsImage: {},
            },
          },
          xAxis: { name: "Time", nameLocation: "middle", type: "value" },
          yAxis: {
            max: 1.0,
            min: -1.0,
            name: "Amplitude",
            nameLocation: "middle",
            type: "value",
          },
        });
      });
      return { element, path };
    },
  })
  .mount("#app");

globalThis.plot = plot;
