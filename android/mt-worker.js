// محرك الترجمة دون اتصال — يعمل في خيط خلفي (Worker) كي لا يتجمد التطبيق أثناء الترجمة
// نماذج Helsinki-NLP opus-mt عبر Transformers.js، من أصول التطبيق المحلية فقط.
import { pipeline, env } from './transformers.min.js';

var BASE = new URL('./', self.location.href).href; // .../mt/
env.allowRemoteModels = false;
env.allowLocalModels = true;
env.localModelPath = BASE + 'models/';
if (env.backends && env.backends.onnx && env.backends.onnx.wasm) {
  env.backends.onnx.wasm.wasmPaths = BASE;
  env.backends.onnx.wasm.numThreads = Math.min(4, self.navigator.hardwareConcurrency || 2);
}

var DIRECT = {
  'ar-en': 'opus-mt-ar-en', 'en-ar': 'opus-mt-en-ar',
  'en-hi': 'opus-mt-en-hi', 'hi-en': 'opus-mt-hi-en'
};

var pipes = {};
function getPipe(model) {
  if (!pipes[model]) pipes[model] = pipeline('translation', model);
  return pipes[model];
}

function westernDigits(s) {
  return s.replace(/[٠-٩]/g, function (ch) { return String('٠١٢٣٤٥٦٧٨٩'.indexOf(ch)); })
          .replace(/[۰-۹]/g, function (ch) { return String('۰۱۲۳۴۵۶۷۸۹'.indexOf(ch)); });
}

function splitSentences(t) {
  var raw = t.split(/(?<=[.!?؟])\s+|\n+/);
  var out = [];
  for (var i = 0; i < raw.length; i++) {
    var s = raw[i].trim();
    while (s.length > 400) {
      var cut = s.lastIndexOf('،', 400);
      if (cut < 150) cut = s.lastIndexOf(' ', 400);
      if (cut < 150) cut = 400;
      out.push(s.slice(0, cut).trim());
      s = s.slice(cut).trim();
    }
    if (s) out.push(s);
  }
  return out.length ? out : [t];
}

function progress(text) { self.postMessage({ type: 'progress', text: text }); }

// دمج الجمل القصيرة في أجزاء أكبر (≤350 حرفاً): استدعاءات أقل للمحرك وسياق أتمّ — أسرع
function mergeChunks(parts) {
  var out = [];
  var cur = '';
  parts.forEach(function (s) {
    if (!cur) { cur = s; return; }
    if ((cur + ' ' + s).length <= 350) cur += ' ' + s;
    else { out.push(cur); cur = s; }
  });
  if (cur) out.push(cur);
  return out;
}

function runModel(model, text, label) {
  var chunks = mergeChunks(splitSentences(text));
  return getPipe(model).then(function (pipe) {
    var out = [];
    var chain = Promise.resolve();
    chunks.forEach(function (ch, idx) {
      chain = chain.then(function () {
        progress(label + ' — جزء ' + (idx + 1) + ' من ' + chunks.length);
        // بحث أحادي (كانت 4 ثم 2): فكّ الترميز هو زمن الترجمة، والأحادي أسرعها بفارق واضح في الجمل القصيرة
        return pipe(ch, { max_new_tokens: 160, num_beams: 1 }).then(function (r) {
          out.push((r && r[0] && r[0].translation_text) || '');
        }).catch(function () { out.push(ch); });
      });
    });
    return chain.then(function () { return out.join(' '); });
  });
}

self.onmessage = function (e) {
  var d = e.data || {};
  var src = d.src, tgt = d.tgt;
  var clean = westernDigits(String(d.text || ''));
  progress('جارٍ تحميل نموذج الترجمة… (مرة واحدة عند أول استخدام)');
  var direct = DIRECT[src + '-' + tgt];
  var job;
  if (direct) {
    job = runModel(direct, clean, 'جارٍ الترجمة دون اتصال');
  } else {
    var leg1 = DIRECT[src + '-en'];
    var leg2 = DIRECT['en-' + tgt];
    if (!leg1 || !leg2) { self.postMessage({ type: 'error' }); return; }
    job = runModel(leg1, clean, 'جارٍ الترجمة دون اتصال (المرحلة ١ من ٢: إلى الإنجليزية)')
      .then(function (mid) {
        return runModel(leg2, mid, 'جارٍ الترجمة دون اتصال (المرحلة ٢ من ٢)');
      });
  }
  job.then(function (result) { self.postMessage({ type: 'done', result: result }); })
     .catch(function () { self.postMessage({ type: 'error' }); });
};
