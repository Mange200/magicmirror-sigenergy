#!/usr/bin/env bash
set -e

echo "======================================"
echo " MagicMirror - Sigenergy installation"
echo "======================================"

MM="$HOME/MagicMirror"
MOD="$MM/modules/MMM-Sigenergy"
SECRET="$HOME/.config/magicmirror-sigenergy.env"

if [ ! -d "$MM" ]; then
  echo "FEL: Hittar inte MagicMirror i $MM"
  exit 1
fi

echo
read -p "Sigenergy e-postadress: " SIGUSER
read -s -p "Sigenergy lösenord: " SIGPASS
echo
read -p "Sigenergy System ID: " SYSTEMID

mkdir -p "$MOD"
mkdir -p "$HOME/.config"

cat > "$SECRET" <<EOF
SIGUSER=$SIGUSER
SIGPASS=$SIGPASS
SYSTEMID=$SYSTEMID
EOF

chmod 600 "$SECRET"

cat > "$MOD/package.json" <<'EOF'
{
  "name": "mmm-sigenergy",
  "version": "1.0.0",
  "dependencies": {
    "axios": "^1.7.0"
  }
}
EOF

cat > "$MOD/MMM-Sigenergy.js" <<'EOF'
Module.register("MMM-Sigenergy", {

  defaults: {
    updateInterval: 300000
  },

  start: function () {
    this.data = null;
    this.error = null;

    this.sendSocketNotification(
      "SIGENERGY_START",
      this.config
    );
  },

  getStyles: function () {
    return ["MMM-Sigenergy.css"];
  },

  socketNotificationReceived: function (notification, payload) {

    if (notification === "SIGENERGY_DATA") {
      this.data = payload;
      this.error = null;
      this.updateDom();
    }

    if (notification === "SIGENERGY_ERROR") {
      this.error = payload;
      this.updateDom();
    }
  },

  getDom: function () {

    const wrapper = document.createElement("div");
    wrapper.className = "sigenergy";

    if (this.error) {
      wrapper.innerHTML =
        "<h2>SIGENERGY</h2>" +
        "<div class='dimmed'>" +
        this.error +
        "</div>";

      return wrapper;
    }

    if (!this.data) {
      wrapper.innerHTML =
        "<h2>SIGENERGY</h2>" +
        "<div class='dimmed'>Hämtar energidata...</div>";

      return wrapper;
    }

    const d = this.data;

    const n = function(value) {
      const x = Number(value);
      return Number.isFinite(x) ? x.toFixed(1) : "0.0";
    };

    wrapper.innerHTML = `
      <h2>SIGENERGY</h2>

      <div class="siggrid">

        <div class="sigbox">
          <div class="icon">☀️</div>
          <b>${n(d.pvPower)} kW</b>
          <small>Solproduktion</small>
        </div>

        <div class="sigbox">
          <div class="icon">🏠</div>
          <b>${n(d.loadPower)} kW</b>
          <small>Husets förbrukning</small>
        </div>

        <div class="sigbox">
          <div class="icon">🔋</div>
          <b>${Math.round(Number(d.batterySoc || 0))}%</b>
          <small>${n(Math.abs(Number(d.batteryPower || 0)))} kW</small>
        </div>

        <div class="sigbox">
          <div class="icon">⚡</div>
          <b>${n(Math.abs(Number(d.gridPower || 0)))} kW</b>
          <small>Elnät</small>
        </div>

      </div>
    `;

    return wrapper;
  }
});
EOF

cat > "$MOD/MMM-Sigenergy.css" <<'EOF'
.sigenergy {
  min-width: 500px;
  text-align: center;
}

.sigenergy h2 {
  letter-spacing: 4px;
  margin-bottom: 20px;
}

.siggrid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 15px;
}

.sigbox {
  border: 1px solid #555;
  border-radius: 15px;
  padding: 15px;
}

.sigbox .icon {
  font-size: 30px;
}

.sigbox b {
  display: block;
  font-size: 30px;
  margin: 5px;
}

.sigbox small {
  display: block;
  color: #aaa;
  font-size: 16px;
}
EOF

cat > "$MOD/node_helper.js" <<'EOF'
const NodeHelper = require("node_helper");
const axios = require("axios");
const fs = require("fs");
const os = require("os");
const path = require("path");

const BASE =
  "https://openapi-eu.sigencloud.com";

function readSecrets() {

  const file =
    path.join(
      os.homedir(),
      ".config/magicmirror-sigenergy.env"
    );

  const result = {};

  fs.readFileSync(file, "utf8")
    .split(/\r?\n/)
    .forEach(line => {

      const i = line.indexOf("=");

      if (i > 0) {
        result[line.substring(0, i)] =
          line.substring(i + 1);
      }
    });

  return result;
}

function unpack(value) {

  if (typeof value === "string") {

    try {
      return JSON.parse(value);
    }
    catch (e) {
      return value;
    }
  }

  return value;
}

module.exports = NodeHelper.create({

  start: function () {

    this.token = null;
    this.expires = 0;
    this.timer = null;
  },

  socketNotificationReceived:
  function(notification, config) {

    if (notification !== "SIGENERGY_START")
      return;

    this.updateInterval =
      Math.max(
        Number(config.updateInterval) || 300000,
        300000
      );

    this.update();

    this.timer =
      setInterval(
        () => this.update(),
        this.updateInterval
      );
  },

  login: async function(secrets) {

    if (
      this.token &&
      Date.now() < this.expires - 300000
    ) {
      return this.token;
    }

    const response =
      await axios.post(

        BASE +
        "/openapi/auth/login/password",

        {
          username: secrets.SIGUSER,
          password: secrets.SIGPASS
        },

        {
          headers: {
            "Content-Type": "application/json",
            "sigen-region": "eu"
          },

          timeout: 20000
        }
      );

    if (response.data.code !== 0) {
      throw new Error(
        response.data.msg ||
        "Sigenergy-inloggningen misslyckades"
      );
    }

    const auth =
      unpack(response.data.data);

    this.token =
      auth.accessToken;

    this.expires =
      Date.now() +
      Number(auth.expiresIn || 43199) * 1000;

    return this.token;
  },

  update: async function () {

    try {

      const secrets =
        readSecrets();

      const token =
        await this.login(secrets);

      const response =
        await axios.get(

          BASE +
          "/openapi/systems/" +
          secrets.SYSTEMID +
          "/energyFlow",

          {
            headers: {
              Authorization:
                "Bearer " + token,

              "sigen-region": "eu"
            },

            timeout: 20000
          }
        );

      if (response.data.code !== 0) {
        throw new Error(
          response.data.msg ||
          "Sigenergy API-fel"
        );
      }

      const data =
        unpack(response.data.data);

      this.sendSocketNotification(
        "SIGENERGY_DATA",
        data
      );
    }

    catch (error) {

      console.error(
        "[MMM-Sigenergy]",
        error.response?.data ||
        error.message
      );

      this.sendSocketNotification(
        "SIGENERGY_ERROR",
        error.response?.data?.msg ||
        error.message
      );
    }
  }
});
EOF

cd "$MOD"
npm install

echo
echo "======================================"
echo " Sigenergy-modulen är installerad!"
echo "======================================"
echo
echo "Nästa steg:"
echo "Vi lägger in MMM-Sigenergy i config.js."
echo
