const NodeHelper = require("node_helper");
const axios = require("axios");
const fs = require("fs");
const os = require("os");
const path = require("path");

const BASE = "https://openapi.eu.sigencloud.com";

function readSecrets() {
  const file = path.join(os.homedir(), ".config/magicmirror-sigenergy.env");
  const result = {};
  fs.readFileSync(file, "utf8").split(/\r?\n/).forEach(line => {
    const i = line.indexOf("=");
    if (i > 0) result[line.substring(0, i)] = line.substring(i + 1);
  });
  return result;
}
function unpack(value) {
  if (typeof value === "string") {
    try { return JSON.parse(value); } catch (e) { return value; }
  }
  return value;
}
module.exports = NodeHelper.create({
  start: function () { this.token=null; this.expires=0; this.timer=null; },
  socketNotificationReceived: function(notification, config) {
    if (notification !== "SIGENERGY_START") return;
    this.updateInterval = Math.max(Number(config.updateInterval)||300000,300000);
    this.update();
    this.timer=setInterval(()=>this.update(),this.updateInterval);
  },
  login: async function(secrets) {
    if (this.token && Date.now() < this.expires-300000) return this.token;
    const response=await axios.post(BASE+"/openapi/auth/login/password",
      {username:secrets.SIGUSER,password:secrets.SIGPASS},
      {headers:{"Content-Type":"application/json","sigen-region":"eu"},timeout:20000});
    if (response.data.code !== 0) throw new Error(response.data.msg||"Sigenergy-inloggningen misslyckades");
    const auth=unpack(response.data.data);
    this.token=auth.accessToken;
    this.expires=Date.now()+Number(auth.expiresIn||43199)*1000;
    return this.token;
  },
  getSpotPrice: async function() {
    const now=new Date();
    const y=now.getFullYear();
    const m=String(now.getMonth()+1).padStart(2,"0");
    const d=String(now.getDate()).padStart(2,"0");
    const url=`https://www.elprisetjustnu.se/api/v1/prices/${y}/${m}-${d}_SE3.json`;
    const r=await axios.get(url,{timeout:15000});
    const prices=Array.isArray(r.data)?r.data:[];
    const t=Date.now();
    let idx=prices.findIndex(p=>t>=new Date(p.time_start).getTime() && t<new Date(p.time_end).getTime());
    if(idx<0) idx=Math.max(0,prices.length-1);
    const vals=prices.map(p=>Number(p.SEK_per_kWh)).filter(Number.isFinite);
    const cur=prices[idx]||{};
    const next=prices[idx+1]||null;
    return {
      current:Number(cur.SEK_per_kWh),
      next:next?Number(next.SEK_per_kWh):null,
      start:cur.time_start||null,end:cur.time_end||null,
      min:vals.length?Math.min(...vals):null,
      max:vals.length?Math.max(...vals):null,
      avg:vals.length?vals.reduce((a,b)=>a+b,0)/vals.length:null,
      values:vals
    };
  },
  update: async function() {
    try {
      const secrets=readSecrets();
      const token=await this.login(secrets);
      const response=await axios.get(BASE+"/openapi/systems/"+secrets.SYSTEMID+"/energyFlow",
        {headers:{Authorization:"Bearer "+token,"sigen-region":"eu"},timeout:20000});
      if(response.data.code!==0) throw new Error(response.data.msg||"Sigenergy API-fel");
      const data=unpack(response.data.data);
      try { data.spotPrice=await this.getSpotPrice(); } catch(e) { console.error("[MMM-Sigenergy] Spotpris:",e.message); }
      this.sendSocketNotification("SIGENERGY_DATA",data);
    } catch(error) {
      console.error("[MMM-Sigenergy]",error.response?.data||error.message);
      this.sendSocketNotification("SIGENERGY_ERROR",error.response?.data?.msg||error.message);
    }
  }
});