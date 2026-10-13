<p align="right"><b>English</b> · <a href="README.tr.md">Türkçe</a></p>

<p align="center">
  <img src="docs/images/icon.png" width="128" alt="Elva icon">
</p>

<h1 align="center">Elva Screenshot Tool for macOS</h1>

<p align="center">
  A simple, fast screenshot tool for your Mac.<br>
  Capture your whole screen or just the part you need, draw, write and highlight on it, and keep it in your archive.
</p>

<p align="center">
  <a href="https://github.com/qokalp/Elva-Screenshot/releases/latest/download/Elva-Screenshot.dmg"><b>⬇︎ Download Elva (DMG)</b></a>
  &nbsp;·&nbsp; Requires macOS 14 Sonoma or later
</p>

<p align="center">
  <img src="docs/images/popover.png" width="360" alt="Elva window in the menu bar">
  &nbsp;&nbsp;
  <img src="docs/images/editor.png" width="560" alt="Elva editing window">
</p>

> **Note:** The app's interface is currently in Turkish. This guide shows each button's Turkish label with its English meaning.

---

## What can you do?

- 📸 **Three ways to capture:** the whole screen, a rectangle, or a free-hand (lasso) shape
- ⏱️ **Timer:** capture automatically after 3, 5 or 10 seconds
- ✏️ **Draw on it:** pen, text and highlighter
- 📋 **Share in one click:** copy, save as PNG/JPG, or archive
- 🗂️ **A good-looking archive:** all your screenshots in the menu bar, laid out like Polaroid photos
- ⌨️ **Keyboard shortcuts:** capture without opening the menu

---

## Installation

1. Click the **“Download Elva”** link above.
2. Double-click the downloaded **Elva-Screenshot.dmg** file.
3. In the window that opens, drag the Elva icon onto the **Applications** folder.

   <img src="docs/images/dmg.png" width="520" alt="Drag Elva into the Applications folder">

4. Open **Elva Screenshot Tool for macOS** from your Applications folder.
   Elva lives in the menu bar: it doesn't appear in the Dock. Instead, a camera icon shows up at the top right of your screen.

> **If you see an “app can't be opened” warning:** open System Settings › Privacy & Security, scroll down, and click **“Open Anyway”** next to Elva. You only need to do this once, the first time you open it.

### Screen recording permission

macOS asks for permission before any app can take screenshots. On your first capture:

1. Click **Sistem Ayarlarını Aç** (Open System Settings) in the window that appears.
2. In the **Screen & System Audio Recording** list, turn on the switch next to Elva.
3. Quit and reopen Elva (menu bar icon › ⚙︎ › Quit, then open it again from Applications).

---

## User guide

### Taking a screenshot

Click the **camera icon** in the menu bar. You'll see four buttons at the top:

| Button | What it does |
|---|---|
| **Tam Ekran** (Full Screen) | Captures the whole screen your mouse is on. |
| **Kare** (Rectangle) | The screen dims; drag with the mouse to select a rectangular area. |
| **Lasso** | Draw freely with the mouse to select any shape you like. |
| **Gecikme** (Timer) | Choose how long to wait before capturing (Off / 3 / 5 / 10 seconds). A countdown appears in the middle of the screen. |

Press **Esc** to cancel while selecting.

### Keyboard shortcuts

| Shortcut | Action |
|---|---|
| **Control + Shift + 1** | Full screen |
| **Control + Shift + 2** | Rectangle selection |
| **Control + Shift + 3** | Lasso selection |

### The editing window

After each capture, the image opens with a small toolbar underneath:

| Icon | What it does |
|---|---|
| ✕ | Closes the window (**Esc** works too) |
| ✏️ Pen | Free drawing |
| Aa Text | Click on the image, type your text, press **Enter** |
| 🖍️ Highlighter | A see-through marker. Hold **Shift** to draw a perfectly straight line |
| ● Color | Pick a color and the thickness / text size |
| ↶ ↷ | Undo / redo |
| ⧉ Copy | Copies the image so you can paste it anywhere |
| ⤓ Save | Saves it to your Mac as PNG or JPG |
| 🗃️ Archive | Adds the image to your Elva archive |

To move the window, drag it by an empty spot on the toolbar.

### The archive

Every image you archive appears at the bottom of the menu bar window.

- **Hover** over an image: it gets bigger and straightens out.
- **Click** it: it opens in the editing window.
- **Right-click** it: copy, save, show in Finder, or delete.
- **Drag and drop** it onto your desktop or into an email.

**Working with several images:** press the ✓ (Select) button and pick the images. Then:

- ✏️ opens them all in the editing window (move between them with the ‹ › arrows on the toolbar),
- ⤓ saves them all to a folder at once, as PNG or JPG,
- 🗑️ deletes the selected images.

### Settings (⚙︎)

- **Arşiv klasörünü aç** (Open archive folder): shows the folder where your archived images are stored.
- **Oturum açılışında başlat** (Open at login): starts Elva automatically when you turn on your Mac.
- **Çıkış** (Quit): closes Elva.

---

## Frequently asked questions

**I can't see the Elva icon in the menu bar.**
If your menu bar is crowded, the icon may be hidden. Try removing a few other icons, or reopen Elva from your Applications folder.

**My screenshot comes out empty, or only shows the desktop.**
Screen recording permission hasn't been granted. Follow the *Screen recording permission* steps above and restart Elva.

**Where are my archived images kept?**
Use ⚙︎ › **Open archive folder** to see them. Images are stored only on your own Mac and are never sent anywhere.

**How do I uninstall Elva?**
Quit Elva, then drag it from your Applications folder to the Trash.

---

For developers: building from source and the project structure are described in [docs/TECHNICAL.md](docs/TECHNICAL.md).
