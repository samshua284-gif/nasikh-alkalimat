#!/bin/bash
# بناء APK «ناسخ الكلمات من الصور» — غلاف WebView + محرك Tesseract ولغاته مدمجة للأوفلاين
set -e
exec > >(tee -a "$HOME/workspace/image-to-text-copier/android/build.log") 2>&1
echo "=== NASIKH BUILD (APK 1.0) START $(date) ==="

PROJ="$HOME/workspace/image-to-text-copier/android"
SRC="$HOME/workspace/image-to-text-copier"
SDK="$HOME/android-sdk"
export JAVA_HOME="$HOME/jdk"
export PATH="$HOME/jdk/bin:$PATH"
AJAR="$SDK/platforms/android-34/android.jar"
BT="$SDK/build-tools/34.0.0"
ls -la "$AJAR" "$BT/aapt2"

cd "$PROJ"
mkdir -p assets/www gen classes dex src/com/hilalsameer/nasikh res/values

# نسخة الـAPK من الصفحة: محرك محلي + OCR_LOCAL + اللغات المدمجة فقط
python3 - <<'PYEOF'
import re
html = open('/home/hatch/workspace/image-to-text-copier/index.html', encoding='utf-8').read()
apk = html.replace('<script src="https://cdn.jsdelivr.net/npm/tesseract.js@5/dist/tesseract.min.js"></script>',
                   '<script src="tess/tesseract.min.js"></script>\n<script>window.OCR_LOCAL = true;</script>')
for code in ['fra', 'spa', 'deu', 'rus']:
    apk = re.sub(r'\s*<label class="chip"><input type="checkbox" value="' + code + r'"><span>[^<]*</span></label>', '', apk)
open('/home/hatch/workspace/image-to-text-copier/android/assets/www/index.html', 'w', encoding='utf-8').write(apk)
print('variant ok, OCR_LOCAL:', 'OCR_LOCAL = true' in apk)
PYEOF
cp "$SRC/manifest.webmanifest" "$SRC/icon.svg" assets/www/
rm -rf assets/www/tess
cp -r "$PROJ/tess" assets/www/tess
du -sh assets/www

cat > AndroidManifest.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.hilalsameer.nasikh"
    android:versionCode="1" android:versionName="1.0">
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
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

public class MainActivity extends Activity {
  private WebView w;
  private ValueCallback<Uri[]> fileCallback;
  private static final int FILE_REQ = 1001;

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
    w.setWebViewClient(new WebViewClient());
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
    w.loadUrl("file:///android_asset/www/index.html");
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

# مفتاح توقيع خاص بهذا التطبيق
if [ ! -f nasikh-release.keystore ]; then
  KSPASS="$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 32)"
  echo -n "$KSPASS" > keystore-password.txt
  keytool -genkeypair -keystore nasikh-release.keystore -alias nasikh -keyalg RSA -keysize 2048 \
    -validity 10000 -storepass "$KSPASS" -keypass "$KSPASS" -dname "CN=Hilal Sameer" 2>&1 | tail -1
fi

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
echo "=== NASIKH BUILD OK ==="
