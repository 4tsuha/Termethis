import { Terminal } from '@xterm/xterm';
import { FitAddon } from '@xterm/addon-fit';
import { SerializeAddon } from '@xterm/addon-serialize';
import { Unicode11Addon } from '@xterm/addon-unicode11';
import { WebglAddon } from '@xterm/addon-webgl';
import '@xterm/xterm/css/xterm.css';

const host = document.getElementById('terminal');
const decoder = new TextDecoder('utf-8');
const encoder = new TextEncoder();
let active = true;
let disposed = false;
let writeChain = Promise.resolve();
let lastCommandOutput = '';
let commandOutputStart;
let promptActive = false;
let interaction = {
  mouseInput: false,
  longPressRightClick: false,
  tapToMovePromptCursor: false,
};

window.addEventListener('error', (event) => {
  post({ type: 'fatal', message: event.message || 'JavaScript error' });
});
window.addEventListener('unhandledrejection', (event) => {
  post({ type: 'fatal', message: String(event.reason || 'Unhandled rejection') });
});

const terminal = new Terminal({
  allowProposedApi: true,
  convertEol: false,
  cursorBlink: true,
  cursorStyle: 'block',
  drawBoldTextInBrightColors: true,
  fontFamily: 'CascadiaMono, Mejiro, Koruri, monospace',
  fontSize: 14,
  letterSpacing: 0,
  lineHeight: 1.15,
  scrollback: 5000,
  smoothScrollDuration: 0,
  theme: {
    background: '#000000',
    foreground: '#f2f2f2',
    cursor: '#f2f2f2',
    cursorAccent: '#000000',
    selectionBackground: '#264f78aa',
  },
});
const fitAddon = new FitAddon();
const serializeAddon = new SerializeAddon();
const unicodeAddon = new Unicode11Addon();
terminal.loadAddon(fitAddon);
terminal.loadAddon(serializeAddon);
terminal.loadAddon(unicodeAddon);
terminal.unicode.activeVersion = '11';
terminal.open(host);

let renderer = 'dom';
let webglAddon;
try {
  // Android WebView screenshots and surface hand-off need the last frame to
  // remain available after compositing. This also avoids partial glyph atlases
  // on software-rendered emulators.
  webglAddon = new WebglAddon(true);
  webglAddon.onContextLoss(() => {
    webglAddon.dispose();
    renderer = 'dom';
    post({ type: 'renderer', renderer });
  });
  terminal.loadAddon(webglAddon);
  renderer = 'webgl';
} catch (error) {
  post({ type: 'rendererError', message: String(error) });
}

terminal.onData((data) => {
  if (active && !disposed) post({ type: 'input', data });
});
terminal.onResize(({ cols, rows }) => post({ type: 'resize', cols, rows }));
terminal.onTitleChange((title) => post({ type: 'title', title }));
terminal.parser.registerOscHandler(133, (data) => {
  const marker = data.split(';', 1)[0];
  const buffer = terminal.buffer.active;
  const row = buffer.baseY + buffer.cursorY;
  if (marker === 'A') {
    promptActive = true;
  } else if (marker === 'C') {
    promptActive = false;
    commandOutputStart = row + 1;
  } else if (marker === 'D' && commandOutputStart !== undefined) {
    const lines = [];
    for (let index = commandOutputStart; index < row; index += 1) {
      const line = buffer.getLine(index);
      if (line) lines.push(line.translateToString(true));
    }
    lastCommandOutput = lines.join('\n').replace(/\s+$/, '');
    commandOutputStart = undefined;
  }
  return true;
});

function post(message) {
  if (window.VBTerminal?.postMessage) {
    window.VBTerminal.postMessage(JSON.stringify(message));
  }
}

function decodeBase64(value) {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return decoder.decode(bytes);
}

function encodeBase64(value) {
  const bytes = encoder.encode(value);
  const chunks = [];
  for (let offset = 0; offset < bytes.length; offset += 0x8000) {
    chunks.push(
      String.fromCharCode(...bytes.subarray(offset, offset + 0x8000)),
    );
  }
  return btoa(chunks.join(''));
}

function enqueueWrite(value, reset, id) {
  const data = decodeBase64(value);
  writeChain = writeChain
    .then(
      () =>
        new Promise((resolve) => {
          if (disposed) {
            post({ type: 'writeAck', id });
            resolve();
            return;
          }
          if (reset) terminal.reset();
          terminal.write(data, () => {
            post({ type: 'writeAck', id });
            resolve();
          });
        }),
    )
    .catch((error) => {
      post({ type: 'fatal', message: String(error) });
    });
}

function fit() {
  if (!active || host.clientWidth === 0 || host.clientHeight === 0) return;
  fitAddon.fit();
}

window.vbTerminal = {
  writeBase64(value, reset = false, id = 0) {
    enqueueWrite(value, reset, id);
  },
  pasteBase64(value) {
    terminal.paste(decodeBase64(value));
  },
  setOptions(options) {
    if (Number.isInteger(options.scrollback)) {
      terminal.options.scrollback = options.scrollback;
    }
    if (typeof options.fontFamily === 'string') {
      terminal.options.fontFamily = options.fontFamily;
    }
    if (Number.isFinite(options.fontSize)) {
      terminal.options.fontSize = options.fontSize;
    }
    interaction = {
      mouseInput: options.mouseInput === true,
      longPressRightClick: options.longPressRightClick === true,
      tapToMovePromptCursor: options.tapToMovePromptCursor === true,
    };
    host.style.touchAction = interaction.mouseInput ? 'none' : 'pan-y';
    fit();
  },
  copyLastOutputBase64() {
    return lastCommandOutput ? encodeBase64(lastCommandOutput) : '';
  },
  fit,
  focus() {
    if (active) terminal.focus();
  },
  setActive(value) {
    active = value === true;
    terminal.options.cursorBlink = active;
    if (active) {
      fit();
      terminal.focus();
    } else {
      terminal.blur();
    }
  },
  requestSnapshot(id, throughSequence, scrollback) {
    writeChain = writeChain
      .then(() => {
        if (disposed) return;
        const snapshot = serializeAddon.serialize({ scrollback });
        post({
          type: 'snapshot',
          id,
          throughSequence,
          data: encodeBase64(snapshot),
        });
      })
      .catch((error) => {
        post({ type: 'snapshotError', id, message: String(error) });
      });
  },
  dispose() {
    disposed = true;
    resizeObserver.disconnect();
    cancelAnimationFrame(resizeFrame);
    terminal.dispose();
  },
};

let resizeFrame;
const resizeObserver = new ResizeObserver(() => {
  cancelAnimationFrame(resizeFrame);
  resizeFrame = requestAnimationFrame(fit);
});
resizeObserver.observe(host);

let pointerStart;
let longPressTimer;
let longPressSent = false;

function dispatchMouse(event, button) {
  const target = host.querySelector('.xterm-screen') || host;
  const options = {
    bubbles: true,
    cancelable: true,
    clientX: event.clientX,
    clientY: event.clientY,
    button,
    buttons: 1 << button,
  };
  target.dispatchEvent(new MouseEvent('mousedown', options));
  target.dispatchEvent(new MouseEvent('mouseup', { ...options, buttons: 0 }));
}

function movePromptCursor(event) {
  if (!interaction.tapToMovePromptCursor || !promptActive) return false;
  const rect = host.getBoundingClientRect();
  const cellWidth = rect.width / terminal.cols;
  const cellHeight = rect.height / terminal.rows;
  const row = Math.floor((event.clientY - rect.top) / cellHeight);
  if (row !== terminal.buffer.active.cursorY) return false;
  const targetColumn = Math.max(
    0,
    Math.min(terminal.cols - 1, Math.floor((event.clientX - rect.left) / cellWidth)),
  );
  const delta = targetColumn - terminal.buffer.active.cursorX;
  if (delta !== 0) {
    terminal.input((delta < 0 ? '\x1b[D' : '\x1b[C').repeat(Math.abs(delta)));
  }
  return true;
}

host.addEventListener('pointerdown', (event) => {
  terminal.focus();
  if (event.pointerType !== 'touch') return;
  pointerStart = { x: event.clientX, y: event.clientY };
  longPressSent = false;
  if (interaction.mouseInput && interaction.longPressRightClick) {
    longPressTimer = window.setTimeout(() => {
      dispatchMouse(event, 2);
      longPressSent = true;
    }, 500);
  }
});

host.addEventListener('pointerup', (event) => {
  window.clearTimeout(longPressTimer);
  if (event.pointerType !== 'touch' || longPressSent) return;
  const moved = pointerStart &&
    Math.hypot(event.clientX - pointerStart.x, event.clientY - pointerStart.y) > 12;
  if (moved) return;
  if (movePromptCursor(event)) return;
  if (interaction.mouseInput) dispatchMouse(event, 0);
});

host.addEventListener('pointercancel', () => window.clearTimeout(longPressTimer));
host.addEventListener('contextmenu', (event) => {
  if (interaction.longPressRightClick) event.preventDefault();
});
document.fonts.ready.then(() => {
  fit();
  terminal.focus();
  post({
    type: 'ready',
    renderer,
    cols: terminal.cols,
    rows: terminal.rows,
  });
});
