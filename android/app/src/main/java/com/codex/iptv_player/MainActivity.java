package com.codex.iptv_player;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.view.Gravity;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.MediaController;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.VideoView;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.util.Map;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.StandardMessageCodec;
import io.flutter.plugin.platform.PlatformView;
import io.flutter.plugin.platform.PlatformViewFactory;

public class MainActivity extends FlutterActivity {
    private static final String STORAGE_CHANNEL = "iptv_player/storage";
    private static final String PLAYER_CHANNEL = "iptv_player/player";
    private static final String PLAYER_VIEW_TYPE = "iptv_player/video_view";
    private static final String PREFS_NAME = "iptv_player";

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        flutterEngine
            .getPlatformViewsController()
            .getRegistry()
            .registerViewFactory(PLAYER_VIEW_TYPE, new VideoPlayerViewFactory());

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
                    default:
                        result.notImplemented();
                    break;
                }
            });

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), PLAYER_CHANNEL)
            .setMethodCallHandler((call, result) -> {
                if (!"play".equals(call.method)) {
                    result.notImplemented();
                    return;
                }

                String name = call.argument("name");
                String url = call.argument("url");
                if (url == null || url.trim().isEmpty()) {
                    result.error("missing_url", "Channel URL is required", null);
                    return;
                }

                Intent intent = new Intent(this, VideoPlayerActivity.class);
                intent.putExtra("name", name == null ? "IPTV" : name);
                intent.putExtra("url", url);
                startActivity(intent);
                result.success(null);
            });
    }

    private static class VideoPlayerViewFactory extends PlatformViewFactory {
        VideoPlayerViewFactory() {
            super(StandardMessageCodec.INSTANCE);
        }

        @Override
        public PlatformView create(Context context, int viewId, @Nullable Object args) {
            String url = "";
            if (args instanceof Map<?, ?>) {
                Object rawUrl = ((Map<?, ?>) args).get("url");
                if (rawUrl instanceof String) {
                    url = (String) rawUrl;
                }
            }
            return new VideoPlayerPlatformView(context, url);
        }
    }

    private static class VideoPlayerPlatformView implements PlatformView {
        private final FrameLayout root;
        private final VideoView videoView;

        VideoPlayerPlatformView(Context context, String url) {
            root = new FrameLayout(context);
            root.setBackgroundColor(0xff000000);

            videoView = new VideoView(context);
            videoView.setLayoutParams(new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            ));

            ProgressBar progress = new ProgressBar(context);
            FrameLayout.LayoutParams progressParams = new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            );
            progress.setLayoutParams(progressParams);

            TextView error = new TextView(context);
            error.setTextColor(0xffffffff);
            error.setGravity(Gravity.CENTER);
            error.setPadding(32, 32, 32, 32);
            error.setVisibility(View.GONE);
            error.setLayoutParams(new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            ));

            MediaController controller = new MediaController(context);
            controller.setAnchorView(videoView);
            videoView.setMediaController(controller);
            videoView.setOnPreparedListener(player -> {
                progress.setVisibility(View.GONE);
                player.setLooping(false);
                videoView.start();
            });
            videoView.setOnErrorListener((player, what, extra) -> {
                progress.setVisibility(View.GONE);
                error.setText("No se pudo reproducir este canal.");
                error.setVisibility(View.VISIBLE);
                return true;
            });

            root.addView(videoView);
            root.addView(progress);
            root.addView(error);

            if (url == null || url.trim().isEmpty()) {
                progress.setVisibility(View.GONE);
                error.setText("URL de canal vacia.");
                error.setVisibility(View.VISIBLE);
            } else {
                videoView.setVideoURI(Uri.parse(url));
                videoView.requestFocus();
            }
        }

        @Override
        public View getView() {
            return root;
        }

        @Override
        public void dispose() {
            videoView.stopPlayback();
        }
    }
}
