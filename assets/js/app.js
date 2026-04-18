import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/trading_lab"
import topbar from "../vendor/topbar"
import { createChart } from 'lightweight-charts'

// 1. Define the Viking Terminal Hook
let Hooks = {};

Hooks.TradingTerminal = {
  mounted() {
    const chartOptions = {
      layout: { background: { color: '#111827' }, textColor: '#d1d5db' },
      grid: { vertLines: { color: '#1f2937' }, horzLines: { color: '#1f2937' } },
      timeScale: { timeVisible: true, borderVisible: false },
    };

    // 2. Initialize Main Price Chart
    this.mainChart = createChart(document.getElementById('main-chart'), {
      ...chartOptions,
      height: 500,
    });
    this.mainSeries = this.mainChart.addCandlestickSeries();

    // 3. Initialize Sub-Pane (For BSP/HMM)
    this.subChart = createChart(document.getElementById('sub-pane-1'), {
      ...chartOptions,
      height: 200,
      timeScale: { ...chartOptions.timeScale, visible: false }, // Hide time on bottom
    });
    this.bspSeries = this.subChart.addLineSeries({ color: '#3b82f6', lineWidth: 2 });

    // 4. Synchronization Logic (Time & Crosshairs)
    const mainTimeScale = this.mainChart.timeScale();
    const subTimeScale = this.subChart.timeScale();

    mainTimeScale.subscribeVisibleLogicalRangeChange(range => subTimeScale.setVisibleLogicalRange(range));
    subTimeScale.subscribeVisibleLogicalRangeChange(range => mainTimeScale.setVisibleLogicalRange(range));

    this.syncCrosshairs(this.mainChart, this.subChart);
    this.syncCrosshairs(this.subChart, this.mainChart);

    // 5. Handle Incoming Data from Odin Engine
    this.handleEvent("new_tick", (data) => {
      this.mainSeries.update({
        time: data.time,
        open: data.open,
        high: data.high,
        low: data.low,
        close: data.close
      });
      
      if (data.bsp) {
        this.bspSeries.update({ time: data.time, value: data.bsp });
      }
    });
  },

  syncCrosshairs(sourceChart, targetChart) {
    sourceChart.subscribeCrosshairMove(param => {
      if (!param.time) {
        targetChart.clearCrosshairPosition();
        return;
      }
      const targetSeries = targetChart.series()[0];
      targetChart.setCrosshairPosition(param.point.y, param.time, targetSeries);
    });
  }
};

// 2. Initialize LiveSocket with Merged Hooks
const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks}
})

topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

liveSocket.connect()
window.liveSocket = liveSocket