const { contextBridge, ipcRenderer, webUtils } = require('electron');

const on = (channel) => (fn) => ipcRenderer.on(channel, (_e, d) => fn(d));

contextBridge.exposeInMainWorld('islandApi', {
  setSize: (w, h) => ipcRenderer.send('island-size', { w, h }),
  setFocusable: (yes) => ipcRenderer.send('focusable', yes),
  drag: (phase) => ipcRenderer.send('drag', phase),
  mediaCmd: (cmd) => ipcRenderer.send('media-cmd', cmd),
  systemCmd: (cmd) => ipcRenderer.send('system-cmd', cmd),
  // shelf
  pathOf: (file) => webUtils.getPathForFile(file),
  statPath: (p) => ipcRenderer.invoke('stat', p),
  openPath: (p) => ipcRenderer.send('open-path', p),
  startDrag: (p) => ipcRenderer.send('start-drag', p),
  onMedia: on('media'),
  onVolume: on('volume'),
  onWifi: on('wifi'),
  onBrightness: on('brightness'),
  onCaps: on('caps'),
  onTheme: on('theme'),
  onSetting: on('setting'),
  onCopied: on('copied'),
});
