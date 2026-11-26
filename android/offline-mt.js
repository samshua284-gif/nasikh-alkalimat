// جسر الترجمة دون اتصال: يشغّل المحرك في خيط خلفي (mt-worker.js) كي تبقى الواجهة حية
// أثناء الترجمة. عند أي فشل تُستدعى fail() فتتحول الصفحة لترجمة الإنترنت.
// حارس زمني: إن صمت الخيط ١٢٠ ثانية (جملة عالقة في توليد لا ينتهي) يُقتل الخيط
// ويُبنى من جديد عند الطلب التالي، وتُفكّ الترجمة العالقة بسبب 'hung' بدل
// بقاء زر «ترجم» معطّلاً للأبد.
(function () {
  var OFFLINE_LANGS = { ar: true, en: true, hi: true, ur: true };
  var worker = null;
  var pending = null;
  var watchdog = null;

  function armWatchdog() {
    clearTimeout(watchdog);
    watchdog = setTimeout(function () {
      killWorker();
      if (pending) { var p = pending; pending = null; p.fail('hung'); }
    }, 120000);
  }
  function stopWatchdog() { clearTimeout(watchdog); watchdog = null; }
  function killWorker() {
    if (worker) { try { worker.terminate(); } catch (e) {} worker = null; }
  }

  function ensureWorker() {
    if (!worker) {
      worker = new Worker('mt/mt-worker.js', { type: 'module' });
      worker.onmessage = function (e) {
        if (!pending) return;
        var d = e.data || {};
        if (d.type === 'progress') {
          armWatchdog();
          if (pending.progress) pending.progress(d.text);
        } else if (d.type === 'done') {
          var p = pending; pending = null; stopWatchdog(); p.done(d.result);
        } else if (d.type === 'error') {
          var p2 = pending; pending = null; stopWatchdog(); p2.fail();
        }
      };
      worker.onerror = function () {
        killWorker();
        stopWatchdog();
        if (pending) { var p = pending; pending = null; p.fail(); }
      };
    }
    return worker;
  }

  window.OFFLINE_TRANSLATE = function (text, src, tgt, done, fail, progress) {
    if (!OFFLINE_LANGS[src] || !OFFLINE_LANGS[tgt]) { fail(); return; }
    if (pending) { fail(); return; }
    pending = { done: done, fail: fail, progress: progress };
    armWatchdog();
    try {
      ensureWorker().postMessage({ text: text, src: src, tgt: tgt });
    } catch (e) {
      pending = null;
      stopWatchdog();
      fail();
    }
  };
})();
