package com.codex.iptv_player;

import android.app.Activity;
import android.net.Uri;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.ImageButton;
import android.widget.MediaController;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.VideoView;

public class VideoPlayerActivity extends Activity {
    private VideoView videoView;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        String name = getIntent().getStringExtra("name");
        String url = getIntent().getStringExtra("url");

        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(0xff000000);

        videoView = new VideoView(this);
        root.addView(videoView, new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ));

        ProgressBar progress = new ProgressBar(this);
        FrameLayout.LayoutParams progressParams = new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.CENTER
        );
        root.addView(progress, progressParams);

        TextView title = new TextView(this);
        title.setText(name == null ? "IPTV" : name);
        title.setTextColor(0xffffffff);
        title.setTextSize(18);
        title.setGravity(Gravity.CENTER_VERTICAL);
        title.setPadding(72, 20, 20, 20);
        title.setBackgroundColor(0x66000000);
        FrameLayout.LayoutParams titleParams = new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.TOP
        );
        root.addView(title, titleParams);

        ImageButton back = new ImageButton(this);
        back.setImageResource(android.R.drawable.ic_media_previous);
        back.setBackgroundColor(0x00000000);
        back.setColorFilter(0xffffffff);
        back.setOnClickListener(view -> finish());
        FrameLayout.LayoutParams backParams = new FrameLayout.LayoutParams(64, 64, Gravity.TOP | Gravity.START);
        backParams.setMargins(4, 8, 0, 0);
        root.addView(back, backParams);

        TextView error = new TextView(this);
        error.setTextColor(0xffffffff);
        error.setGravity(Gravity.CENTER);
        error.setTextSize(16);
        error.setPadding(32, 32, 32, 32);
        error.setVisibility(View.GONE);
        root.addView(error, new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ));

        MediaController controller = new MediaController(this);
        controller.setAnchorView(videoView);
        videoView.setMediaController(controller);
        videoView.setOnPreparedListener(player -> {
            progress.setVisibility(View.GONE);
            videoView.start();
        });
        videoView.setOnErrorListener((player, what, extra) -> {
            progress.setVisibility(View.GONE);
            error.setText("No se pudo reproducir este canal.");
            error.setVisibility(View.VISIBLE);
            return true;
        });

        setContentView(root);

        if (url == null || url.trim().isEmpty()) {
            progress.setVisibility(View.GONE);
            error.setText("URL de canal vacia.");
            error.setVisibility(View.VISIBLE);
            return;
        }

        videoView.setVideoURI(Uri.parse(url));
        videoView.requestFocus();
    }

    @Override
    protected void onDestroy() {
        if (videoView != null) {
            videoView.stopPlayback();
        }
        super.onDestroy();
    }
}
