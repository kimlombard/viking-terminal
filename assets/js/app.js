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

    this.mainChart = createChart(mainEl, chartOptions);

    // --- 1. THE VAH BASE FILL (Bottom Layer) ---
    this.vahSeries = this.mainChart.addAreaSeries({ 
      lineColor: '#38bdf8', // Blue boundary
      topColor: 'rgba(56, 189, 248, 0.45)', // Semi-transparent blue fill
      bottomColor: 'rgba(56, 189, 248, 0.45)', 
      lineWidth: 1, 
      lineStyle: 2,     // Dashed line
      crosshairMarkerVisible: false,
      priceLineVisible: false
    });

    // --- 2. THE VAL MASK (Middle Layer) ---
    this.valSeries = this.mainChart.addAreaSeries({ 
      lineColor: '#38bdf8', // Blue boundary
      topColor: '#111827',  // SOLID BACKGROUND COLOR (Masks the VAH fill!)
      bottomColor: '#111827', 
      lineWidth: 1, 
      lineStyle: 2,     // Dashed line
      crosshairMarkerVisible: false,
      priceLineVisible: false
    });

    const channelOptions = {
      color: 'rgba(56, 189, 248, 0.45)', // Semi-transparent blue for the channels
      lineWidth: 1,
      lineStyle: 2, // Dashed line
      crosshairMarkerVisible: false,
      priceLineVisible: false
    };

    // --- 3. THE PRICE CANDLES (Foreground) ---
    this.mainSeries = this.mainChart.addCandlestickSeries();

    // --- 1. THE VAH BASE FILL (Bottom Layer) ---
    this.vahSeries = this.mainChart.addAreaSeries({ 
      lineColor: '#38bdf8', 
      topColor: 'rgba(56, 189, 248, 0.45)', 
      bottomColor: 'rgba(56, 189, 248, 0.45)', 
      lineWidth: 1, 
      lineStyle: 2,     
      crosshairMarkerVisible: false,
      priceLineVisible: false
    });

    // --- 2. THE VAL MASK (Middle Layer) ---
    this.valSeries = this.mainChart.addAreaSeries({ 
      lineColor: '#38bdf8', 
      topColor: '#111827',  
      bottomColor: '#111827', 
      lineWidth: 1, 
      lineStyle: 2,     
      crosshairMarkerVisible: false,
      priceLineVisible: false
    });

    // --- 3. THE PRICE CANDLES (Foreground) ---
    this.mainSeries = this.mainChart.addCandlestickSeries();
    
    // --- 4. THE ALMA CHANNELS ---
    this.alma20High = this.mainChart.addLineSeries({ color: '#38bdf8', lineWidth: 1, crosshairMarkerVisible: false, priceLineVisible: false });
    this.alma20Low = this.mainChart.addLineSeries({ color: '#38bdf8', lineWidth: 1, crosshairMarkerVisible: false, priceLineVisible: false });
    this.alma200High = this.mainChart.addLineSeries({ color: '#c084fc', lineWidth: 1, crosshairMarkerVisible: false, priceLineVisible: false });
    this.alma200Low = this.mainChart.addLineSeries({ color: '#c084fc', lineWidth: 1, crosshairMarkerVisible: false, priceLineVisible: false });

    // --- 5. THE POC RIBBON (Top Layer) ---
    this.pocSeries = this.mainChart.addLineSeries({
      color: '#facc15', lineWidth: 2, lineStyle: 0, crosshairMarkerVisible: false, priceLineVisible: false
    });
    
    // 2. Sub-Pane 1: Adaptive BSP (Line)
    this.subChart1 = createChart(sub1El, { ...chartOptions, height: 150, timeScale: { ...chartOptions.timeScale, visible: false } });
    this.bspSeries = this.subChart1.addLineSeries({ color: '#3b82f6', lineWidth: 2 });

    // NEW: The BSP Signal Line (EMA)
    this.bspEmaSeries = this.subChart1.addLineSeries({ 
      color: '#f59e0b', 
      lineWidth: 1, 
      lineStyle: 2 
    });

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
          
          const newMarker = {
              time: payload.time,
              position: isBuy ? 'belowBar' : 'aboveBar',
              color: isBuy ? '#26a69a' : '#ef5350',
              shape: isBuy ? 'arrowUp' : 'arrowDown',
              text: isBuy ? 'VIKING LONG' : 'VIKING SHORT',
          };

          this.markers.push(newMarker);
          this.mainSeries.setMarkers(this.markers);
          playVikingChime(payload.signal);
      }

      // --- ALMA Channels ---
      if (payload.alma20_high) this.alma20High.update({ time: payload.time, value: payload.alma20_high });
      if (payload.alma20_low) this.alma20Low.update({ time: payload.time, value: payload.alma20_low });
      if (payload.alma200_high) this.alma200High.update({ time: payload.time, value: payload.alma200_high });
      if (payload.alma200_low) this.alma200Low.update({ time: payload.time, value: payload.alma200_low });

      // --- Dynamic Channels (VAH & VAL) and POC Ribbon ---
      if (payload.vah) this.vahSeries.update({ time: payload.time, value: payload.vah });
      if (payload.val) this.valSeries.update({ time: payload.time, value: payload.val });
      if (payload.poc) this.pocSeries.update({ time: payload.time, value: payload.poc });

      // --- GHOST LEVELS (Mitigation Zones) ---
      // We use a Map to keep track of the lines we've drawn
      this.activeGhostLines = this.activeGhostLines || new Map();

      if (payload.ghosts) {
        // Create a Set of current active prices from the backend
        const currentPrices = new Set(payload.ghosts.map(g => g.price));

        // 1. Remove lines that are NO LONGER active (Mitigated by a Whale!)
        for (let [price, line] of this.activeGhostLines.entries()) {
          if (!currentPrices.has(price)) {
            this.mainSeries.removePriceLine(line);
            this.activeGhostLines.delete(price);
          }
        }

        // 2. Draw new Ghost Levels that just spawned
        payload.ghosts.forEach(g => {
          if (!this.activeGhostLines.has(g.price)) {
            const line = this.mainSeries.createPriceLine({
              price: g.price,
              color: g.is_bullish ? '#22c55e' : '#ef4444', // Neon Green / Neon Red
              lineWidth: 2,
              lineStyle: 1, // Dotted Line
              axisLabelVisible: true,
              title: g.is_bullish ? '🐳 BULL GHOST' : '🐋 BEAR GHOST',
            });
            this.activeGhostLines.set(g.price, line);
          }
        });
      }

      // --- WHALE ALERTS ---
      if (payload.whale_alert && payload.whale_alert !== "none") {
          const isAbs = payload.whale_alert === "ABSORPTION";
          
          this.markers.push({
              time: payload.time,
              position: 'inBar',
              color: isAbs ? '#facc15' : '#f43f5e', // Gold for Absorption, Rose for Exhaustion
              shape: 'circle',
              text: isAbs ? '🐋 ABSORPTION' : '💨 EXHAUSTION',
          });

          this.mainSeries.setMarkers(this.markers);
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
      // NEW: Update the Signal Line
      if (payload.bsp_ema) this.bspEmaSeries.update({ time: payload.time, value: payload.bsp_ema });
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