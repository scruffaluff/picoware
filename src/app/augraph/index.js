import * as echarts from "https://unpkg.com/echarts@5.6.0/dist/echarts.esm.min.js";
import * as vue from "https://unpkg.com/vue@3/dist/vue.esm-browser.js";

let chart;

vue
  .createApp({
    setup() {
      async function plot(_) {
        const audio = await pywebview.api.read(path.value);
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

      const path = vue.ref("");
      const element = vue.useTemplateRef("chart");
      vue.onMounted(() => {
        chart = echarts.init(element.value);
      });
      return { element, path, plot };
    },
  })
  .mount("#app");
