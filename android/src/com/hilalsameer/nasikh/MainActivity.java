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
  private Uri cameraUri;
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
        if (params != null && android.os.Build.VERSION.SDK_INT >= 26 && params.isCaptureEnabled()){
          try {
            android.content.ContentValues cv = new android.content.ContentValues();
            cv.put(android.provider.MediaStore.Images.Media.DISPLAY_NAME, "nasikh_" + System.currentTimeMillis() + ".jpg");
            cv.put(android.provider.MediaStore.Images.Media.MIME_TYPE, "image/jpeg");
            cameraUri = getContentResolver().insert(android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI, cv);
            if (cameraUri != null){
              Intent cam = new Intent(android.provider.MediaStore.ACTION_IMAGE_CAPTURE);
              cam.putExtra(android.provider.MediaStore.EXTRA_OUTPUT, cameraUri);
              cam.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION | Intent.FLAG_GRANT_READ_URI_PERMISSION);
              startActivityForResult(cam, FILE_REQ);
              return true;
            }
          } catch (Exception e) { cameraUri = null; }
        }
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
      if (res == RESULT_OK && cameraUri != null){
        results = new Uri[]{ cameraUri };
      } else if (res == RESULT_OK && data != null && data.getData() != null){
        results = new Uri[]{ data.getData() };
      }
      cameraUri = null;
      fileCallback.onReceiveValue(results);
      fileCallback = null;
    }
  }

  @Override public void onBackPressed(){
    if (w != null && w.canGoBack()) w.goBack(); else super.onBackPressed();
  }
}
