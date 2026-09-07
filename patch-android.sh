#!/usr/bin/env bash
# Patches the freshly-generated android/ project so the app's camera
# (used for barcode/sticker detection and stack photos) actually works
# inside the native WebView. Runs once, right after `npx cap add android`.
set -e

MANIFEST="android/app/src/main/AndroidManifest.xml"
if [ -f "$MANIFEST" ] && ! grep -q "android.permission.CAMERA" "$MANIFEST"; then
  python3 - "$MANIFEST" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    content = f.read()
if 'android.permission.CAMERA' not in content:
    idx = content.index('>', content.index('<manifest')) + 1
    inject = (
        '\n    <uses-permission android:name="android.permission.CAMERA" />\n'
        '    <uses-feature android:name="android.hardware.camera" android:required="false" />\n'
    )
    content = content[:idx] + inject + content[idx:]
    with open(path, 'w') as f:
        f.write(content)
    print("Patched AndroidManifest.xml with CAMERA permission")
PYEOF
fi

JAVA_FILE=$(find android/app/src/main/java -name "MainActivity.java" 2>/dev/null | head -1)
KT_FILE=$(find android/app/src/main/java -name "MainActivity.kt" 2>/dev/null | head -1)

if [ -n "$JAVA_FILE" ]; then
  PACKAGE=$(grep -m1 '^package ' "$JAVA_FILE" | sed 's/package //; s/;//')
  cat > "$JAVA_FILE" <<EOF
package $PACKAGE;

import android.Manifest;
import android.os.Bundle;
import android.webkit.PermissionRequest;
import androidx.core.app.ActivityCompat;
import com.getcapacitor.BridgeActivity;
import com.getcapacitor.BridgeWebChromeClient;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        ActivityCompat.requestPermissions(this, new String[]{ Manifest.permission.CAMERA }, 1001);

        this.bridge.getWebView().setWebChromeClient(new BridgeWebChromeClient(this.bridge) {
            @Override
            public void onPermissionRequest(final PermissionRequest request) {
                runOnUiThread(() -> request.grant(request.getResources()));
            }
        });
    }
}
EOF
  echo "Patched MainActivity.java ($PACKAGE) with camera permission handling"
elif [ -n "$KT_FILE" ]; then
  PACKAGE=$(grep -m1 '^package ' "$KT_FILE" | sed 's/package //')
  cat > "$KT_FILE" <<EOF
package $PACKAGE

import android.Manifest
import android.os.Bundle
import android.webkit.PermissionRequest
import androidx.core.app.ActivityCompat
import com.getcapacitor.BridgeActivity
import com.getcapacitor.BridgeWebChromeClient

class MainActivity : BridgeActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CAMERA), 1001)

        bridge.webView.webChromeClient = object : BridgeWebChromeClient(bridge) {
            override fun onPermissionRequest(request: PermissionRequest) {
                runOnUiThread { request.grant(request.resources) }
            }
        }
    }
}
EOF
  echo "Patched MainActivity.kt ($PACKAGE) with camera permission handling"
else
  echo "!! Could not find MainActivity.java or .kt to patch."
  echo "!! Camera may not work inside the app — see README's manual patch steps."
fi
