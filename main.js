const { app, BrowserWindow, ipcMain, screen, clipboard, Tray, Menu, nativeImage, shell } = require('electron');
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

const WIN_W = 520;
const WIN_H = 420;

// bunyi pengingat (timer, to-do, minum) boleh diputar tanpa klik dulu
app.commandLine.appendSwitch('autoplay-policy', 'no-user-gesture-required');

let win, tray, trayIcon;

// posisi terakhir disimpan supaya island tetap di tempat yang dipilih setelah dibuka ulang
const configFile = () => path.join(app.getPath('userData'), 'posisi.json');
function loadPos() {
  try { return JSON.parse(fs.readFileSync(configFile(), 'utf8')); } catch { return null; }
}
function savePos() {
  const [x, y] = win.getPosition();
  try { fs.writeFileSync(configFile(), JSON.stringify({ x, y })); } catch {}
}
const themeFile = () => path.join(app.getPath('userData'), 'tema.json');
const THEMES = [['gelap', 'Abu gelap'], ['putih', 'Putih'], ['biru', 'Biru'], ['ungu', 'Ungu'], ['hitam', 'Hitam (asli iPhone)']];
const settings = { theme: 'gelap', mascot: true };
try { Object.assign(settings, JSON.parse(fs.readFileSync(themeFile(), 'utf8'))); } catch {}
function saveSettings() { try { fs.writeFileSync(themeFile(), JSON.stringify(settings)); } catch {} }
function setTheme(t) {
  settings.theme = t; saveSettings();
  if (win) win.webContents.send('theme', t);
}
function setMascot(on) {
  settings.mascot = on; saveSettings();
  if (win) win.webContents.send('setting', { mascot: on });
}

function defaultPos() {
  const { bounds } = screen.getPrimaryDisplay();
  return { x: Math.round(bounds.x + (bounds.width - WIN_W) / 2), y: bounds.y + 6 };
}
// jaga agar island tidak keluar layar (termasuk ruang untuk membesar ke bawah)
function clamp({ x, y }) {
  const b = screen.getDisplayNearestPoint({ x: x + WIN_W / 2, y }).bounds;
  return {
    x: Math.round(Math.min(Math.max(x, b.x - WIN_W / 2 + 80), b.x + b.width - WIN_W / 2 - 80)),
    y: Math.round(Math.min(Math.max(y, b.y), b.y + b.height - WIN_H)),
  };
}

function createWindow() {
  const pos = clamp(loadPos() || defaultPos());
  win = new BrowserWindow({
    width: WIN_W,
    height: WIN_H,
    x: pos.x,
    y: pos.y,
    frame: false,
    transparent: true,
    resizable: false,
    movable: false,
    skipTaskbar: true,
    alwaysOnTop: true,
    hasShadow: false,
    focusable: false,
    show: false,
    webPreferences: { preload: path.join(__dirname, 'preload.js') },
  });
  win.setAlwaysOnTop(true, 'screen-saver');
  win.setIgnoreMouseEvents(true, { forward: true });
  win.webContents.on('console-message', (_e, level, msg, line) => { if (level >= 2) console.log(`[renderer] ${msg} (line ${line})`); });
  win.webContents.on('did-finish-load', () => {
    win.webContents.send('theme', settings.theme);
    win.webContents.send('setting', { mascot: settings.mascot });
    pageReady = true;
    Object.values(lastStatus).forEach((d) => win.webContents.send(d.type, d));
    win.showInactive();
  });
  win.loadFile('index.html');
  setInterval(followCursor, 40);
}

// Mouse hanya "ditangkap" saat kursor di atas island; selain itu klik tembus ke aplikasi di bawahnya.
// Posisi kursor dicek terus dari sini (bukan dari halaman) supaya file yang sedang ditarik juga bisa dijatuhkan.
let islandSize = { w: 150, h: 34 }, capturing = false;
ipcMain.on('island-size', (_e, size) => { islandSize = size; });
function followCursor() {
  if (!win || !win.isVisible()) return;
  const c = screen.getCursorScreenPoint();
  const [x, y] = win.getPosition();
  const left = x + (WIN_W - islandSize.w) / 2, pad = 6;
  const inside = drag || (c.x >= left - pad && c.x <= left + islandSize.w + pad && c.y >= y - pad && c.y <= y + islandSize.h + pad);
  if (inside === capturing) return;
  capturing = inside;
  if (inside) win.setIgnoreMouseEvents(false);
  else win.setIgnoreMouseEvents(true, { forward: true });
}

// halaman to-do butuh keyboard; selain itu island tidak pernah merebut fokus dari aplikasi lain
ipcMain.on('focusable', (_e, yes) => {
  if (!win || win.isFocusable() === yes) return;
  win.setFocusable(yes);
  if (yes) win.focus();
  // mengubah fokus mereset status klik-tembus di Windows, jadi pasang ulang
  capturing = null;
  followCursor();
});

// shelf
ipcMain.handle('stat', (_e, p) => {
  try { const st = fs.statSync(p); return { dir: st.isDirectory(), size: st.size }; } catch { return { dir: false, size: 0 }; }
});
ipcMain.on('open-path', (_e, p) => { shell.openPath(p); });
ipcMain.on('start-drag', async (e, p) => {
  let icon = trayIcon;
  try { icon = await app.getFileIcon(p, { size: 'normal' }); } catch {}
  e.sender.startDrag({ file: p, icon });
});

// sembunyi otomatis saat ada aplikasi layar penuh (video, presentasi, game)
let hiddenByUser = false;
function onFullscreen(on) {
  if (!win || hiddenByUser) return;
  if (on) win.hide(); else win.showInactive();
}

// geser island: posisi dihitung dari kursor di main process supaya aman dari skala DPI
let drag = null;
ipcMain.on('drag', (_e, phase) => {
  if (!win) return;
  const c = screen.getCursorScreenPoint();
  if (phase === 'start') {
    const [x, y] = win.getPosition();
    drag = { dx: c.x - x, dy: c.y - y };
  } else if (phase === 'move' && drag) {
    const p = clamp({ x: c.x - drag.dx, y: c.y - drag.dy });
    win.setBounds({ x: p.x, y: p.y, width: WIN_W, height: WIN_H });
  } else if (phase === 'end') {
    drag = null;
    savePos();
  }
});

ipcMain.on('media-cmd', (_e, cmd) => sendHelper('media', cmd));
ipcMain.on('system-cmd', (_e, cmd) => sendHelper('system', cmd));

// skrip PowerShell yang terus berjalan: media.ps1 (lagu) dan system.ps1 (volume & WiFi).
// Tiap baris JSON yang dikirim diteruskan ke tampilan sesuai "type"-nya.
const helpers = {};
// status terakhir disimpan, lalu dikirim ulang begitu halaman island selesai dimuat
const lastStatus = {};
let pageReady = false;
function startHelper(name) {
  const proc = spawn('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(__dirname, name + '.ps1')], { windowsHide: true });
  helpers[name] = proc;
  let buf = '';
  proc.stdout.setEncoding('utf8');
  proc.stdout.on('data', (chunk) => {
    buf += chunk;
    let i;
    while ((i = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, i).trim();
      buf = buf.slice(i + 1);
      if (!line) continue;
      try {
        const d = JSON.parse(line);
        if (d.type === 'fullscreen') onFullscreen(d.on);
        else {
          lastStatus[d.type] = d;
          if (win && pageReady) win.webContents.send(d.type, d);
        }
      } catch {}
    }
  });
  proc.on('exit', () => { if (!app.isQuitting) setTimeout(() => startHelper(name), 3000); });
}
function sendHelper(name, cmd) {
  const proc = helpers[name];
  if (proc && proc.stdin.writable) proc.stdin.write(cmd + '\n');
}

function watchClipboard() {
  let last = clipboard.readText();
  setInterval(() => {
    const now = clipboard.readText();
    if (now && now !== last && win) win.webContents.send('copied', now.slice(0, 80));
    last = now;
  }, 700);
}

function createTray() {
  // ikon bulat putih 16x16 dibuat langsung tanpa file gambar
  const size = 16, data = Buffer.alloc(size * size * 4);
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    const inside = (x - 7.5) ** 2 + ((y - 7.5) * 2.2) ** 2 < 56;
    const o = (y * size + x) * 4;
    data[o] = data[o + 1] = data[o + 2] = 255;
    data[o + 3] = inside ? 255 : 0;
  }
  trayIcon = nativeImage.createFromBitmap(data, { width: size, height: size });
  tray = new Tray(trayIcon);
  tray.setToolTip('Dynamic Island');
  // electron.exe perlu diberi folder aplikasi ini sebagai argumen
  const login = { path: process.execPath, args: [app.getAppPath()] };
  const build = () => Menu.buildFromTemplate([
    { label: 'Sembunyikan', type: 'checkbox', checked: !win.isVisible(),
      click: (item) => { hiddenByUser = item.checked; item.checked ? win.hide() : win.showInactive(); } },
    { label: 'Kembalikan ke tengah atas', click: () => { const p = defaultPos(); win.setPosition(p.x, p.y); savePos(); } },
    { label: 'Warna', submenu: THEMES.map(([id, label]) => ({
      label, type: 'radio', checked: settings.theme === id, click: () => setTheme(id) })) },
    { label: 'Maskot mata saat diam', type: 'checkbox', checked: settings.mascot, click: (item) => setMascot(item.checked) },
    { type: 'separator' },
    { label: 'Jalankan saat Windows menyala', type: 'checkbox', checked: app.getLoginItemSettings(login).openAtLogin,
      click: (item) => { app.setLoginItemSettings({ ...login, openAtLogin: item.checked }); } },
    { type: 'separator' },
    { label: 'Keluar', click: () => app.quit() },
  ]);
  tray.setContextMenu(build());
  tray.on('click', () => { hiddenByUser = win.isVisible(); hiddenByUser ? win.hide() : win.showInactive(); tray.setContextMenu(build()); });
}

if (!app.requestSingleInstanceLock()) app.quit();
else {
  app.whenReady().then(() => {
    createWindow();
    startHelper('media');
    startHelper('system');
    watchClipboard();
    createTray();
  });
  app.on('before-quit', () => { app.isQuitting = true; Object.values(helpers).forEach((p) => p.kill()); });
}
