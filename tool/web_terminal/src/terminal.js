import { Terminal } from '@xterm/xterm';
import { FitAddon } from '@xterm/addon-fit';
import { SerializeAddon } from '@xterm/addon-serialize';
import { Unicode11Addon } from '@xterm/addon-unicode11';
import { UnicodeGraphemesAddon } from '@xterm/addon-unicode-graphemes';
import { WebglAddon } from '@xterm/addon-webgl';
import '@xterm/xterm/css/xterm.css';

const host = document.getElementById('terminal');
const viewport = document.getElementById('terminal-scroll');
const textDecoder = new TextDecoder('utf-8');
const encoder = new TextEncoder();
const WIDE_TERMINAL_COLUMNS = 160;
const WRITE_SLICE_BYTES = 16 * 1024;
const NORMAL_WRITE_BUDGET_MILLIS = 3.25;
const INPUT_WRITE_BUDGET_MILLIS = 1.5;
const INPUT_PRIORITY_WINDOW_MILLIS = 80;
let active = true;
let disposed = false;
let dispatchingSpecialKey = false;
let writeChain = Promise.resolve();
let lastInputAt = Number.NEGATIVE_INFINITY;
let lastCommandOutput = '';
let commandOutputStart;
let promptActive = false;
let agentMode = false;
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
  allowTransparency: false,
  convertEol: false,
  customGlyphs: true,
  cursorBlink: true,
  cursorStyle: 'block',
  drawBoldTextInBrightColors: true,
  fontFamily: 'CascadiaMono, NotoSansJP, Mejiro, Koruri, NerdSymbolsMono, "Noto Color Emoji", monospace',
  fontSize: 14,
  fontWeight: '400',
  fontWeightBold: '600',
  letterSpacing: 0,
  lineHeight: 1.15,
  minimumContrastRatio: 1,
  logLevel: 'off',
  rescaleOverlappingGlyphs: true,
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
try {
  terminal.loadAddon(new UnicodeGraphemesAddon());
} catch (error) {
  post({ type: 'unicodeFallback', message: String(error) });
}
terminal.open(host);

let renderer = 'dom';
let webglAddon;
try {
  webglAddon = new WebglAddon(false);
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
  if (active && !disposed) {
    lastInputAt = performance.now();
    post({ type: dispatchingSpecialKey ? 'directInput' : 'input', data });
  }
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
  if (window.Termethis?.postMessage) {
    window.Termethis.postMessage(JSON.stringify(message));
  }
}

function decodeBase64Bytes(value) {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

function decodeBase64Text(value) {
  return textDecoder.decode(decodeBase64Bytes(value));
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
  writeChain = writeChain
    .then(async () => {
      const buffer = terminal.buffer.active;
      const followOutput = reset || buffer.viewportY >= buffer.baseY;
      if (disposed) {
        post({ type: 'writeAck', id });
        return;
      }
      if (reset) {
        terminal.reset();
      }
      const data = decodeBase64Bytes(value);
      let sliceStartedAt = performance.now();
      for (let offset = 0; offset < data.length; offset += WRITE_SLICE_BYTES) {
        const slice = data.subarray(offset, offset + WRITE_SLICE_BYTES);
        await new Promise((resolve) => terminal.write(slice, resolve));
        const now = performance.now();
        const writeBudget = now - lastInputAt < INPUT_PRIORITY_WINDOW_MILLIS
          ? INPUT_WRITE_BUDGET_MILLIS
          : NORMAL_WRITE_BUDGET_MILLIS;
        if (
          offset + WRITE_SLICE_BYTES < data.length &&
          now - sliceStartedAt >= writeBudget
        ) {
          await new Promise((resolve) => requestAnimationFrame(resolve));
          sliceStartedAt = performance.now();
        }
      }
      // xterm already follows output when the viewport starts at the bottom.
      // An explicit scroll on every batch forces another viewport update and
      // is especially expensive while a TUI repaints continuously.
      if (reset && followOutput) terminal.scrollToBottom();
      post({ type: 'writeAck', id });
    })
    .catch((error) => {
      post({ type: 'fatal', message: String(error) });
    });
}

function fit() {
  if (!active || viewport.clientWidth === 0 || viewport.clientHeight === 0) {
    return;
  }

  host.style.width = '100%';
  const visibleDimensions = fitAddon.proposeDimensions();
  if (
    !agentMode &&
    visibleDimensions &&
    visibleDimensions.cols > 0 &&
    visibleDimensions.cols < WIDE_TERMINAL_COLUMNS
  ) {
    const widthPerColumn = viewport.clientWidth / visibleDimensions.cols;
    host.style.width = `${Math.ceil(widthPerColumn * WIDE_TERMINAL_COLUMNS)}px`;
  }
  fitAddon.fit();
}

function specialKeySequence(key, control, alt) {
  const modifiers = (alt ? 2 : 0) | (control ? 4 : 0);
  const modifierParameter = modifiers + 1;
  const arrowFinal = {
    arrowUp: 'A',
    arrowDown: 'B',
    arrowRight: 'C',
    arrowLeft: 'D',
  }[key];
  if (arrowFinal) {
    if (modifiers !== 0) return `\x1b[1;${modifierParameter}${arrowFinal}`;
    return terminal.modes.applicationCursorKeysMode
      ? `\x1bO${arrowFinal}`
      : `\x1b[${arrowFinal}`;
  }

  const literal = { escape: '\x1b', tab: '\t', enter: '\r' }[key];
  if (literal === undefined) return undefined;
  if (control) {
    return `\x1b[${literal.charCodeAt(0)};${modifierParameter}u`;
  }
  return alt ? `\x1b${literal}` : literal;
}

window.termethisTerminal = {
  writeBase64(value, reset = false, id = 0) {
    enqueueWrite(value, reset, id);
  },
  pasteBase64(value) {
    terminal.paste(decodeBase64Text(value));
  },
  sendKey(key, control = false, alt = false) {
    const sequence = specialKeySequence(key, control, alt);
    if (active && sequence !== undefined) {
      dispatchingSpecialKey = true;
      try {
        terminal.input(sequence, true);
      } finally {
        dispatchingSpecialKey = false;
      }
    }
  },
  setOptions(options) {
    if (Number.isInteger(options.scrollback)) {
      terminal.options.scrollback = options.scrollback;
    }
    if (typeof options.fontFamily === 'string') {
      terminal.options.fontFamily = options.fontFamily;
      webglAddon?.clearTextureAtlas();
    }
    if (Number.isFinite(options.fontSize)) {
      terminal.options.fontSize = options.fontSize;
    }
    interaction = {
      mouseInput: options.mouseInput === true,
      longPressRightClick: options.longPressRightClick === true,
      tapToMovePromptCursor: options.tapToMovePromptCursor === true,
    };
    agentMode = options.agentMode === true;
    if (agentMode) viewport.scrollLeft = 0;
    host.style.touchAction = interaction.mouseInput ? 'none' : 'pan-x pan-y';
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
resizeObserver.observe(viewport);

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
