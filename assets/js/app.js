import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/trading_lab"
import topbar from "../vendor/topbar"

// 1. One clean import
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

    // Safely target the elements using data attributes instead of IDs
    const mainEl = this.el.querySelector('[data-target="main-chart"]');
    const sub1El = this.el.querySelector('[data-target="sub-pane-1"]');
    const sub2El = this.el.querySelector('[data-target="sub-pane-2"]');

    // 1. Main Price Chart
    this.mainChart = createChart(mainEl, { ...chartOptions, height: 400 });
    this.mainSeries = this.mainChart.addCandlestickSeries();

    // 2. Sub-Pane 1: Adaptive BSP (Line)
    this.subChart1 = createChart(sub1El, { ...chartOptions, height: 150, timeScale: { ...chartOptions.timeScale, visible: false } });
    this.bspSeries = this.subChart1.addLineSeries({ color: '#3b82f6', lineWidth: 2 });

    // 3. Sub-Pane 2: HMM Probability (Histogram)
    this.subChart2 = createChart(sub2El, { ...chartOptions, height: 150, timeScale: { ...chartOptions.timeScale, visible: false } });
    this.hmmSeries = this.subChart2.addHistogramSeries({ color: '#eab308' });

    // 4. Unified Synchronization
    const syncGroup = [
      { chart: this.mainChart, series: this.mainSeries },
      { chart: this.subChart1, series: this.bspSeries },
      { chart: this.subChart2, series: this.hmmSeries }
    ];
    
    syncGroup.forEach(source => {
      source.chart.timeScale().subscribeVisibleLogicalRangeChange(range => {
        syncGroup.forEach(target => { 
          if (target.chart !== source.chart) target.chart.timeScale().setVisibleLogicalRange(range); 
        });
      });
      
      source.chart.subscribeCrosshairMove(param => {
        syncGroup.forEach(target => {
          if (target.chart !== source.chart) {
            if (!param.time) { 
              target.chart.clearCrosshairPosition(); 
            } else { 
              target.chart.setCrosshairPosition(param.point.y, param.time, target.series); 
            }
          }
        });
      });
    });

    // 5. Handle Incoming Data
    this.handleEvent("new_tick", (data) => {
      if (!this.mainSeries) return;

      const colors = {
        [2]:  { candle: '#00ff00', wick: '#00ff00' }, 
        [1]:  { candle: '#22c55e', wick: '#22c55e' }, 
        [-1]: { candle: '#ef4444', wick: '#ef4444' }, 
        [-2]: { candle: '#ff0000', wick: '#ff0000' }, 
        [0]:  { candle: '#9ca3af', wick: '#9ca3af' }  
      };

      const stateStyle = colors[data.state] || colors[0];

      this.mainSeries.update({
        time: data.time, open: data.open, high: data.high, low: data.low, close: data.close,
        color: stateStyle.candle, wickColor: stateStyle.wick, borderColor: stateStyle.candle,
      });
      
      if (data.bsp) this.bspSeries.update({ time: data.time, value: data.bsp });
      if (data.probability) this.hmmSeries.update({ time: data.time, value: data.probability, color: stateStyle.candle });
    });

    // 6. Resize Observer (Using dataset checks)
    this.resizeObserver = new ResizeObserver(entries => {
      for (let entry of entries) {
        if (entry.target.dataset.target === 'main-chart') this.mainChart.resize(entry.contentRect.width, entry.contentRect.height);
        if (entry.target.dataset.target === 'sub-pane-1') this.subChart1.resize(entry.contentRect.width, entry.contentRect.height);
        if (entry.target.dataset.target === 'sub-pane-2') this.subChart2.resize(entry.contentRect.width, entry.contentRect.height);
      }
    });

    this.resizeObserver.observe(mainEl);
    this.resizeObserver.observe(sub1El);
    this.resizeObserver.observe(sub2El);
  },

  // Keep your destroyed cleanup!
  destroyed() {
    if (this.resizeObserver) this.resizeObserver.disconnect();
    if (this.mainChart) {
        this.mainChart.remove();
        this.mainSeries = null;
    }
    if (this.subChart1) this.subChart1.remove();
    if (this.subChart2) this.subChart2.remove();
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