import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/trading_lab"
import topbar from "../vendor/topbar"

// 1. One clean import
import { createChart } from 'lightweight-charts'

// --- VIKING AUDIO ENGINE ---
// We initialize this lazily because browsers block audio until a user clicks the page.
let audioCtx;

function playVikingChime(type) {
  if (!audioCtx) {
    audioCtx = new (window.AudioContext || window.webkitAudioContext)();
  }
  
  // Browsers suspend audio context if it wasn't started by a user gesture.
  if (audioCtx.state === 'suspended') {
    audioCtx.resume();
  }

  const oscillator = audioCtx.createOscillator();
  const gainNode = audioCtx.createGain();

  oscillator.connect(gainNode);
  gainNode.connect(audioCtx.destination);

  const now = audioCtx.currentTime;

  if (type === "BUY") {
    // A clean, high-pitched double-chime for Longs
    oscillator.type = 'sine';
    oscillator.frequency.setValueAtTime(880, now); // A5 note
  } else {
    // A lower, deeper tone for Shorts
    oscillator.type = 'triangle';
    oscillator.frequency.setValueAtTime(330, now); // E4 note
  }

  // The "Ping" Envelope: Fast attack, exponential fade out
  gainNode.gain.setValueAtTime(0, now);
  gainNode.gain.linearRampToValueAtTime(0.3, now + 0.02); // Quick volume spike
  gainNode.gain.exponentialRampToValueAtTime(0.001, now + 0.8); // Fade out over 0.8 seconds

  oscillator.start(now);
  oscillator.stop(now + 1);
}

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
    this.handleEvent("new_tick", (payload) => {
      if (!this.mainSeries) return;

      // 1. Initialize a markers array outside the event if it doesn't exist
      this.markers = this.markers || [];

      // 2. Check the incoming payload for a signal
      if (payload.signal) {
          const isBuy = payload.signal === "BUY";
          
          // Create the marker object
          const newMarker = {
              time: payload.time,
              position: isBuy ? 'belowBar' : 'aboveBar',
              color: isBuy ? '#26a69a' : '#ef5350',
              shape: isBuy ? 'arrowUp' : 'arrowDown',
              text: isBuy ? 'VIKING LONG' : 'VIKING SHORT',
          };

          // Add it to our collection
          this.markers.push(newMarker);

          // 3. Tell the price series to render the updated markers
          this.mainSeries.setMarkers(this.markers);

          // --- RING THE BELL ---
          playVikingChime(payload.signal);
      }

      const colors = {
        [2]:  { candle: '#00ff00', wick: '#00ff00' }, 
        [1]:  { candle: '#22c55e', wick: '#22c55e' }, 
        [-1]: { candle: '#ef4444', wick: '#ef4444' }, 
        [-2]: { candle: '#ff0000', wick: '#ff0000' }, 
        [0]:  { candle: '#9ca3af', wick: '#9ca3af' }  
      };

      const stateStyle = colors[payload.state] || colors[0];

      this.mainSeries.update({
        time: payload.time, open: payload.open, high: payload.high, low: payload.low, close: payload.close,
        color: stateStyle.candle, wickColor: stateStyle.wick, borderColor: stateStyle.candle,
      });
      
      if (payload.bsp) this.bspSeries.update({ time: payload.time, value: payload.bsp });
      if (payload.probability) this.hmmSeries.update({ time: payload.time, value: payload.probability, color: stateStyle.candle });
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