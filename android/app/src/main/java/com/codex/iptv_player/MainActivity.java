package com.codex.iptv_player;

import android.content.Context;
import android.content.SharedPreferences;

import androidx.annotation.NonNull;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String STORAGE_CHANNEL = "iptv_player/storage";
    private static final String PREFS_NAME = "iptv_player";

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), STORAGE_CHANNEL)
            .setMethodCallHandler((call, result) -> {
                SharedPreferences prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
                String key = call.argument("key");
                if (key == null) {
                    result.error("missing_key", "Storage key is required", null);
                    return;
                }

                switch (call.method) {
                    case "getString":
                        result.success(prefs.getString(key, null));
                        break;
                    case "setString":
                        String value = call.argument("value");
                        prefs.edit().putString(key, value == null ? "" : value).apply();
                        result.success(null);
                        break;
                    case "removeString":
                        prefs.edit().remove(key).apply();
                        result.success(null);
                        break;
                    default:
                        result.notImplemented();
                    break;
                }
            });
    }
}
