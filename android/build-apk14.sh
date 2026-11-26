#!/bin/bash
# بناء APK «ناسخ الكلمات» 2.0 — ترجمة دون اتصال (نماذج opus-mt مدمجة) + تقديم الأصول عبر نطاق https محلي
set -e
exec > >(tee -a "$HOME/workspace/image-to-text-copier/android/build.log") 2>&1
echo "=== NASIKH BUILD14 (APK 3.11) START $(date) ==="

PROJ="$HOME/workspace/image-to-text-copier/android"
SRC="$HOME/workspace/image-to-text-copier"
SDK="$HOME/android-sdk"
export JAVA_HOME="$HOME/jdk"
export PATH="$HOME/jdk/bin:$PATH"
AJAR="$SDK/platforms/android-34/android.jar"
BT="$SDK/build-tools/34.0.0"

cd "$PROJ"
mkdir -p assets/www gen classes dex src/com/hilalsameer/nasikh res/values

# نسخة الـAPK من الصفحة: محرك محلي + OCR_LOCAL + لغات مدمجة فقط + وحدة الترجمة دون اتصال
python3 - <<'PYEOF'
import re
html = open('/home/hatch/workspace/image-to-text-copier/index.html', encoding='utf-8').read()
apk = html.replace('<script src="https://cdn.jsdelivr.net/npm/tesseract.js@5/dist/tesseract.min.js"></script>',
                   '<script src="tess/tesseract.min.js"></script>\n<script>window.OCR_LOCAL = true;</script>')
for code in ['fra', 'spa', 'deu', 'rus']:
    apk = re.sub(r'\s*<label class="chip"><input type="checkbox" value="' + code + r'"><span>[^<]*</span></label>', '', apk)
apk = apk.replace('القراءة والنسخ يعملان على جهازك دون اتصال (بعد تحميل كل لغة قراءة أول مرة). الترجمة هنا تحتاج اتصالاً — أما داخل التطبيق فتعمل دون اتصال بين العربية والإنجليزية والهندية والأردية.',
                  'في هذا التطبيق: القراءة والنسخ والترجمة بين العربية والإنجليزية والهندية تعمل دون اتصال — المحرك واللغات والنماذج مدمجة داخله. الأردية وبقية اللغات تُترجم عبر الإنترنت.')
apk = apk.replace('</body>', '<script src="mt/offline-mt.js"></script>\n</body>')
open('/home/hatch/workspace/image-to-text-copier/android/assets/www/index.html', 'w', encoding='utf-8').write(apk)
print('variant ok | OCR_LOCAL:', 'OCR_LOCAL = true' in apk, '| MT module:', 'offline-mt.js' in apk)
PYEOF
cp "$SRC/manifest.webmanifest" "$SRC/icon.svg" assets/www/
rm -rf assets/www/tess
cp -r "$PROJ/tess" assets/www/tess

# أصول الترجمة دون اتصال
rm -rf assets/www/mt
mkdir -p assets/www/mt/models
X="$HOME/workspace/mt-test/node_modules/@xenova/transformers/dist"
cp "$X/transformers.min.js" assets/www/mt/
cp "$X/ort-wasm.wasm" "$X/ort-wasm-simd.wasm" "$X/ort-wasm-threaded.wasm" "$X/ort-wasm-simd-threaded.wasm" assets/www/mt/
cp "$HOME/workspace/mt-test/node_modules/onnxruntime-web/dist/ort-wasm-threaded.worker.js" assets/www/mt/
cp "$PROJ/offline-mt.js" assets/www/mt/
cp "$PROJ/mt-worker.js" assets/www/mt/
sed -i 's/var OFFLINE_LANGS = { ar: true, en: true, hi: true, ur: true };/var OFFLINE_LANGS = { ar: true, en: true, hi: true };/' assets/www/mt/offline-mt.js
for d in opus-mt-en-ar opus-mt-ar-en opus-mt-en-hi opus-mt-hi-en; do
  mkdir -p "assets/www/mt/models/$d/onnx"
  cp "$PROJ/mt-models/$d"/*.json "assets/www/mt/models/$d/"
  cp "$PROJ/mt-models/$d/onnx/encoder_model_quantized.onnx" "$PROJ/mt-models/$d/onnx/decoder_model_merged_quantized.onnx" "assets/www/mt/models/$d/onnx/"
done
du -sh assets/www assets/www/mt

cat > AndroidManifest.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.hilalsameer.nasikh"
    android:versionCode="14" android:versionName="3.11">
  <uses-sdk android:minSdkVersion="24" android:targetSdkVersion="34"/>
  <uses-permission android:name="android.permission.INTERNET"/>
  <application android:label="@string/app_name" android:icon="@mipmap/ic_launcher"
      android:theme="@android:style/Theme.Material.NoActionBar" android:allowBackup="true">
    <activity android:name=".MainActivity" android:exported="true"
        android:configChanges="orientation|screenSize|keyboardHidden">
      <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
      </intent-filter>
    </activity>
  </application>
</manifest>
EOF

cat > res/values/strings.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources><string name="app_name">ناسخ الكلمات</string></resources>
EOF

cat > src/com/hilalsameer/nasikh/MainActivity.java <<'EOF'
package com.hilalsameer.nasikh;
import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import java.io.InputStream;
import java.util.HashMap;
import java.util.Map;

public class MainActivity extends Activity {
  private WebView w;
  private ValueCallback<Uri[]> fileCallback;
  private static final int FILE_REQ = 1001;
  private static final String HOST = "app.nasikh";

  private static final Map<String, String> MIME = new HashMap<>();
  static {
    MIME.put("html", "text/html");
    MIME.put("js", "text/javascript");
    MIME.put("mjs", "text/javascript");
    MIME.put("json", "application/json");
    MIME.put("wasm", "application/wasm");
    MIME.put("svg", "image/svg+xml");
    MIME.put("png", "image/png");
    MIME.put("jpg", "image/jpeg");
    MIME.put("css", "text/css");
    MIME.put("webmanifest", "application/manifest+json");
    MIME.put("gz", "application/gzip");
    MIME.put("onnx", "application/octet-stream");
    MIME.put("traineddata", "application/octet-stream");
  }

  @Override protected void onCreate(Bundle s){
    super.onCreate(s);
    w = new WebView(this);
    WebSettings st = w.getSettings();
    st.setJavaScriptEnabled(true);
    st.setDomStorageEnabled(true);
    st.setAllowFileAccess(true);
    st.setAllowFileAccessFromFileURLs(true);
    st.setAllowUniversalAccessFromFileURLs(true);
    st.setAllowContentAccess(true);
    w.setWebViewClient(new WebViewClient(){
      @Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request){
        Uri url = request.getUrl();
        if (url != null && HOST.equals(url.getHost())){
          String path = url.getPath();
          if (path == null || path.equals("/")) path = "/index.html";
          String asset = "www" + path;
          try {
            InputStream is = getAssets().open(asset);
            String ext = "";
            int dot = asset.lastIndexOf('.');
            if (dot >= 0) ext = asset.substring(dot + 1).toLowerCase();
            String mime = MIME.containsKey(ext) ? MIME.get(ext) : "application/octet-stream";
            boolean text = mime.startsWith("text/") || mime.equals("application/json") || mime.equals("text/javascript");
            Map<String, String> headers = new HashMap<>();
            headers.put("Cross-Origin-Opener-Policy", "same-origin");
            headers.put("Cross-Origin-Embedder-Policy", "credentialless");
            headers.put("Cross-Origin-Resource-Policy", "same-origin");
            return new WebResourceResponse(mime, text ? "UTF-8" : null, 200, "OK", headers, is);
          } catch (Exception e) {
            return new WebResourceResponse("text/plain", "UTF-8", new java.io.ByteArrayInputStream(new byte[0]));
          }
        }
        return super.shouldInterceptRequest(view, request);
      }
    });
    w.setWebChromeClient(new WebChromeClient(){
      @Override public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback, WebChromeClient.FileChooserParams params){
        fileCallback = callback;
        try {
          Intent i = new Intent(Intent.ACTION_GET_CONTENT);
          i.addCategory(Intent.CATEGORY_OPENABLE);
          i.setType("image/*");
          startActivityForResult(Intent.createChooser(i, "اختر صورة"), FILE_REQ);
        } catch (Exception e) {
          fileCallback = null;
          return false;
        }
        return true;
      }
    });
    setContentView(w);
    w.loadUrl("https://" + HOST + "/index.html");
  }

  @Override protected void onActivityResult(int req, int res, Intent data){
    super.onActivityResult(req, res, data);
    if (req == FILE_REQ && fileCallback != null){
      Uri[] results = null;
      if (res == RESULT_OK && data != null && data.getData() != null){
        results = new Uri[]{ data.getData() };
      }
      fileCallback.onReceiveValue(results);
      fileCallback = null;
    }
  }

  @Override public void onBackPressed(){
    if (w != null && w.canGoBack()) w.goBack(); else super.onBackPressed();
  }
}
EOF

"$BT/aapt2" compile --dir res -o res.zip
"$BT/aapt2" link -o unsigned.apk -I "$AJAR" --manifest AndroidManifest.xml -A assets res.zip
javac -encoding UTF-8 -cp "$AJAR" -d classes src/com/hilalsameer/nasikh/MainActivity.java
"$BT/d8" --min-api 24 --lib "$AJAR" --output dex $(find classes -name '*.class')
jar uf unsigned.apk -C dex classes.dex
"$BT/zipalign" -f 4 unsigned.apk aligned.apk

KSPASS="$(cat keystore-password.txt)"
"$BT/apksigner" sign --ks nasikh-release.keystore --ks-pass "pass:$KSPASS" --key-pass "pass:$KSPASS" \
  --out "$SRC/nasikh.apk" aligned.apk
"$BT/apksigner" verify --print-certs "$SRC/nasikh.apk" | head -3
"$BT/aapt2" dump badging "$SRC/nasikh.apk" 2>/dev/null | grep -E "package:|application-label:" | head -2
ls -la "$SRC/nasikh.apk"
sha256sum "$SRC/nasikh.apk"
echo "=== NASIKH BUILD14 OK ==="
