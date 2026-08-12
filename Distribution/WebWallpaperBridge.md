# AIWallpaperBridge Web-to-Client Contract

AIWallpaperEngineMac injects `window.AIWallpaperBridge` before a wallpaper page
starts running. Web wallpaper authors can use it without any browser plugin or
macOS permission.

```js
window.AIWallpaperBridge.onInput(({ x, y, width, height, buttons, timestamp }) => {
  // x/y are in CSS pixels for this display. Draw, move a camera, or update a shader.
  particleSystem.setPointer(x / width, y / height, buttons);
});

// The latest value is always available.
const pointer = window.AIWallpaperBridge.input;
```

The same input is also delivered as a browser event:

```js
window.addEventListener('aiwallpaperinput', event => {
  console.log(event.detail.x, event.detail.y);
});
```

`AIWallpaperBridge` is the supported interaction path for hosted web
wallpapers. Ordinary third-party URLs can be displayed, but their private
mouse-event implementations are not guaranteed to accept client-side input.
