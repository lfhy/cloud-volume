{{flutter_js}}
{{flutter_build_config}}

const bootShell = document.getElementById('boot-shell');
const bootStatusText = document.getElementById('boot-status-text');
const bootStatusPercent = document.getElementById('boot-status-percent');
const bootProgressBar = document.getElementById('boot-progress-bar');

const BOOT_PROGRESS_CAP = 95;
const BOOT_PROGRESS_DURATION_MS = 1 * 60 * 1000;
const BOOT_PROGRESS_TICK_MS = 120;

let bootProgressValue = 0;
let bootProgressTimer = null;
let bootFinished = false;
const bootStartedAt = Date.now();

function cubicBezier(t, p1, p2) {
  const u = 1 - t;
  return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t;
}

function stagedProgressCurve(ratio) {
  if (ratio <= 0) {
    return 0;
  }
  if (ratio >= 1) {
    return 1;
  }

  if (ratio < 0.25) {
    const local = ratio / 0.25;
    return 0.4 * cubicBezier(local, 0.55, 1);
  }

  if (ratio < 0.75) {
    const local = (ratio - 0.25) / 0.5;
    return 0.4 + 0.2 * cubicBezier(local, 0.08, 0.3);
  }

  const local = (ratio - 0.75) / 0.25;
  return 0.6 + 0.4 * cubicBezier(local, 0.72, 1);
}

function renderBootProgress() {
  if (bootStatusPercent) {
    bootStatusPercent.textContent = `${Math.round(bootProgressValue)}%`;
  }
  if (bootProgressBar) {
    bootProgressBar.style.width = `${bootProgressValue}%`;
  }
}

function setBootStatus(text) {
  if (bootStatusText) {
    bootStatusText.textContent = text;
  }
}

function syncBootProgressWithTime() {
  if (bootFinished) {
    return;
  }
  const elapsed = Date.now() - bootStartedAt;
  const ratio = Math.min(elapsed / BOOT_PROGRESS_DURATION_MS, 1);
  const easedRatio = stagedProgressCurve(ratio);
  const nextValue = Math.min(BOOT_PROGRESS_CAP, easedRatio * BOOT_PROGRESS_CAP);
  if (nextValue > bootProgressValue) {
    bootProgressValue = nextValue;
    renderBootProgress();
  }
}

function startBootProgress() {
  if (bootProgressTimer !== null) {
    return;
  }
  syncBootProgressWithTime();
  bootProgressTimer = window.setInterval(() => {
    syncBootProgressWithTime();
  }, BOOT_PROGRESS_TICK_MS);
}

function finishBootProgress() {
  bootFinished = true;
  if (bootProgressTimer !== null) {
    window.clearInterval(bootProgressTimer);
    bootProgressTimer = null;
  }
  bootProgressValue = 100;
  renderBootProgress();
}

setBootStatus('正在准备界面资源');
renderBootProgress();
startBootProgress();

_flutter.loader.load({
  onEntrypointLoaded: async function(engineInitializer) {
    setBootStatus('正在初始化渲染引擎');
    const appRunner = await engineInitializer.initializeEngine();
    setBootStatus('正在启动 Cloud Volume');
    await appRunner.runApp();
    setBootStatus('即将进入控制台');
    finishBootProgress();
    window.addEventListener(
      'flutter-first-frame',
      function () {
        if (bootShell) {
          bootShell.classList.add('boot-shell--done');
        }
      },
      { once: true },
    );
  },
});
