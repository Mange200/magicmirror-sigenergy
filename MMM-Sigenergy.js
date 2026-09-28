Module.register("MMM-Sigenergy", {
  defaults: { updateInterval: 300000 },

  start: function () {
    this.energyData = null;
    this.error = null;
    this.lastUpdated = null;
    this.sendSocketNotification("SIGENERGY_START", this.config);
  },

  getStyles: function () {
    return ["MMM-Sigenergy.css"];
  },

  socketNotificationReceived: function (notification, payload) {
    if (notification === "SIGENERGY_DATA") {
      this.energyData = payload;
      this.error = null;
      this.lastUpdated = new Date();
      this.updateDom(700);
    }
    if (notification === "SIGENERGY_ERROR") {
      this.error = payload;
      this.updateDom(700);
    }
  },

  getDom: function () {
    const wrapper = document.createElement("div");
    wrapper.className = "sigenergy sigenergy-dashboard";

    if (this.error) {
      wrapper.innerHTML = '<div class="sig-title">SIGENERGY</div><div class="sig-message">' + this.error + "</div>";
      return wrapper;
    }

    if (!this.energyData) {
      wrapper.innerHTML = '<div class="sig-title">SIGENERGY</div><div class="sig-message">Hämtar energidata...</div>';
      return wrapper;
    }

    const d = this.energyData;
    const num = (value) => {
      const x = Number(value);
      return Number.isFinite(x) ? x : 0;
    };
    const kw = (value) => num(value).toFixed(1);
    const soc = Math.max(0, Math.min(100, Math.round(num(d.batterySoc))));
    const pv = num(d.pvPower);
    const load = num(d.loadPower);
    const battery = num(d.batteryPower);
    const grid = num(d.gridPower);
    const time = this.lastUpdated
      ? this.lastUpdated.toLocaleTimeString("sv-SE", { hour: "2-digit", minute: "2-digit" })
      : "--:--";

    wrapper.innerHTML = `
      <div class="sig-title">SIGENERGY</div>
      <div class="energy-scene">
        <div class="energy-card solar-card">
          <div class="energy-icon solar-icon">☀</div>
          <div class="energy-label">Solproduktion</div>
          <div class="energy-value">${kw(pv)} <span>kW</span></div>
        </div>

        <div class="flow flow-solar"><i></i><i></i><i></i></div>

        <div class="energy-card battery-card">
          <div class="energy-label">Batteri</div>
          <div class="battery-visual">
            <div class="battery-shell"><div class="battery-fill" style="height:${soc}%"></div></div>
            <div class="battery-percent">${soc}%</div>
          </div>
          <div class="energy-subvalue">${kw(Math.abs(battery))} kW</div>
        </div>

        <div class="flow flow-battery"><i></i><i></i><i></i></div>

        <div class="house-card">
          <div class="house"><div class="house-roof"></div><div class="house-body"><div class="house-window"></div><div class="house-door"></div></div></div>
          <div class="energy-label">Husets förbrukning</div>
          <div class="energy-value">${kw(load)} <span>kW</span></div>
        </div>

        <div class="flow flow-grid"><i></i><i></i><i></i></div>

        <div class="energy-card grid-card">
          <div class="energy-icon">⚡</div>
          <div class="energy-label">Elnät</div>
          <div class="energy-value">${kw(Math.abs(grid))} <span>kW</span></div>
        </div>
      </div>
      <div class="sig-updated">↻ Senast uppdaterad ${time}</div>
    `;
    return wrapper;
  }
});
