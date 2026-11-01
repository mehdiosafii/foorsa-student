package com.pichillilorenzo.flutter_inappwebview_android.webview.in_app_webview;

import android.os.Build;
import android.util.Log;
import android.webkit.WebSettings;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.webkit.WebSettingsCompat;
import androidx.webkit.WebViewFeature;

import java.util.Set;

/**
 * Foorsa patch (foorsa-student, 1 Nov 2026): every androidx.webkit settings call the web view makes,
 * guarded.
 *
 * On some phones the framework hands back an `android.webkit.WebSettingsWrapper`, and the installed
 * Android System WebView's glue casts it to its own `ContentSettingsAdapter`: every
 * `WebSettingsCompat` call then throws a ClassCastException. The plugin made those calls unguarded
 * in `InAppWebView.prepare()`, so on those phones the web view was never created and the Foorsa app
 * stayed on its loading screen (22 reports on the crash board on 1 Nov 2026, builds 1.2.30 to
 * 1.2.33; upstream flutter_inappwebview issues #2397 and #2893). Here a refused compat call falls
 * back to the framework's own setter where there is one, and is skipped otherwise: the portal sets
 * none of these to anything but its default, so nothing it relies on is lost.
 */
public final class SafeWebSettings {
  private static final String LOG_TAG = "SafeWebSettings";

  private SafeWebSettings() {}

  private static void refused(String what, RuntimeException e) {
    Log.w(LOG_TAG, what + " refused by this WebView: " + e);
  }

  public static void setSafeBrowsingEnabled(@NonNull WebSettings settings, boolean enabled) {
    try {
      if (WebViewFeature.isFeatureSupported(WebViewFeature.SAFE_BROWSING_ENABLE)) {
        WebSettingsCompat.setSafeBrowsingEnabled(settings, enabled);
        return;
      }
    } catch (RuntimeException e) {
      refused("setSafeBrowsingEnabled", e);
    }
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) settings.setSafeBrowsingEnabled(enabled);
    } catch (RuntimeException e) {
      refused("WebSettings.setSafeBrowsingEnabled", e);
    }
  }

  @Nullable
  public static Boolean getSafeBrowsingEnabled(@NonNull WebSettings settings) {
    try {
      if (WebViewFeature.isFeatureSupported(WebViewFeature.SAFE_BROWSING_ENABLE)) {
        return WebSettingsCompat.getSafeBrowsingEnabled(settings);
      }
    } catch (RuntimeException e) {
      refused("getSafeBrowsingEnabled", e);
    }
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) return settings.getSafeBrowsingEnabled();
    } catch (RuntimeException e) {
      refused("WebSettings.getSafeBrowsingEnabled", e);
    }
    return null;
  }

  public static void setDisabledActionModeMenuItems(@NonNull WebSettings settings, int items) {
    try {
      if (WebViewFeature.isFeatureSupported(WebViewFeature.DISABLED_ACTION_MODE_MENU_ITEMS)) {
        WebSettingsCompat.setDisabledActionModeMenuItems(settings, items);
        return;
      }
    } catch (RuntimeException e) {
      refused("setDisabledActionModeMenuItems", e);
    }
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) settings.setDisabledActionModeMenuItems(items);
    } catch (RuntimeException e) {
      refused("WebSettings.setDisabledActionModeMenuItems", e);
    }
  }

  @Nullable
  public static Integer getDisabledActionModeMenuItems(@NonNull WebSettings settings) {
    try {
      if (WebViewFeature.isFeatureSupported(WebViewFeature.DISABLED_ACTION_MODE_MENU_ITEMS)) {
        return WebSettingsCompat.getDisabledActionModeMenuItems(settings);
      }
    } catch (RuntimeException e) {
      refused("getDisabledActionModeMenuItems", e);
    }
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) return settings.getDisabledActionModeMenuItems();
    } catch (RuntimeException e) {
      refused("WebSettings.getDisabledActionModeMenuItems", e);
    }
    return null;
  }

  @SuppressWarnings("deprecation")
  public static void setForceDark(@NonNull WebSettings settings, int forceDark) {
    try {
      if (WebViewFeature.isFeatureSupported(WebViewFeature.FORCE_DARK)) {
        WebSettingsCompat.setForceDark(settings, forceDark);
        return;
      }
    } catch (RuntimeException e) {
      refused("setForceDark", e);
    }
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) settings.setForceDark(forceDark);
    } catch (RuntimeException e) {
      refused("WebSettings.setForceDark", e);
    }
  }

  @Nullable
  @SuppressWarnings("deprecation")
  public static Integer getForceDark(@NonNull WebSettings settings) {
    try {
      if (WebViewFeature.isFeatureSupported(WebViewFeature.FORCE_DARK)) {
        return WebSettingsCompat.getForceDark(settings);
      }
    } catch (RuntimeException e) {
      refused("getForceDark", e);
    }
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) return settings.getForceDark();
    } catch (RuntimeException e) {
      refused("WebSettings.getForceDark", e);
    }
    return null;
  }

  @SuppressWarnings("deprecation")
  public static void setForceDarkStrategy(@NonNull WebSettings settings, int strategy) {
    try {
      if (WebViewFeature.isFeatureSupported(WebViewFeature.FORCE_DARK_STRATEGY)) {
        WebSettingsCompat.setForceDarkStrategy(settings, strategy);
      }
    } catch (RuntimeException e) {
      refused("setForceDarkStrategy", e);
    }
  }

  @Nullable
  @SuppressWarnings("deprecation")
  public static Integer getForceDarkStrategy(@NonNull WebSettings settings) {
    try {
      if (WebViewFeature.isFeatureSupported(WebViewFeature.FORCE_DARK_STRATEGY)) {
        return WebSettingsCompat.getForceDarkStrategy(settings);
      }
    } catch (RuntimeException e) {
      refused("getForceDarkStrategy", e);
    }
    return null;
  }

  public static void setOffscreenPreRaster(@NonNull WebSettings settings, boolean enabled) {
    try {
      if (WebViewFeature.isFeatureSupported(WebViewFeature.OFF_SCREEN_PRERASTER)) {
        WebSettingsCompat.setOffscreenPreRaster(settings, enabled);
        return;
      }
    } catch (RuntimeException e) {
      refused("setOffscreenPreRaster", e);
    }
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) settings.setOffscreenPreRaster(enabled);
    } catch (RuntimeException e) {
      refused("WebSettings.setOffscreenPreRaster", e);
    }
  }

  @Nullable
  public static Boolean getOffscreenPreRaster(@NonNull WebSettings settings) {
    try {
      if (WebViewFeature.isFeatureSupported(WebViewFeature.OFF_SCREEN_PRERASTER)) {
        return WebSettingsCompat.getOffscreenPreRaster(settings);
      }
    } catch (RuntimeException e) {
      refused("getOffscreenPreRaster", e);
    }
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) return settings.getOffscreenPreRaster();
    } catch (RuntimeException e) {
      refused("WebSettings.getOffscreenPreRaster", e);
    }
    return null;
  }

  public static void setAlgorithmicDarkeningAllowed(@NonNull WebSettings settings, boolean allowed) {
    try {
      if (WebViewFeature.isFeatureSupported(WebViewFeature.ALGORITHMIC_DARKENING)
          && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        WebSettingsCompat.setAlgorithmicDarkeningAllowed(settings, allowed);
      }
    } catch (RuntimeException e) {
      refused("setAlgorithmicDarkeningAllowed", e);
    }
  }

  @Nullable
  public static Boolean isAlgorithmicDarkeningAllowed(@NonNull WebSettings settings) {
    try {
      if (WebViewFeature.isFeatureSupported(WebViewFeature.ALGORITHMIC_DARKENING)
          && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        return WebSettingsCompat.isAlgorithmicDarkeningAllowed(settings);
      }
    } catch (RuntimeException e) {
      refused("isAlgorithmicDarkeningAllowed", e);
    }
    return null;
  }

  public static void setEnterpriseAuthenticationAppLinkPolicyEnabled(@NonNull WebSettings settings, boolean enabled) {
    try {
      if (WebViewFeature.isFeatureSupported(WebViewFeature.ENTERPRISE_AUTHENTICATION_APP_LINK_POLICY)) {
        WebSettingsCompat.setEnterpriseAuthenticationAppLinkPolicyEnabled(settings, enabled);
      }
    } catch (RuntimeException e) {
      refused("setEnterpriseAuthenticationAppLinkPolicyEnabled", e);
    }
  }

  @Nullable
  public static Boolean getEnterpriseAuthenticationAppLinkPolicyEnabled(@NonNull WebSettings settings) {
    try {
      if (WebViewFeature.isFeatureSupported(WebViewFeature.ENTERPRISE_AUTHENTICATION_APP_LINK_POLICY)) {
        return WebSettingsCompat.getEnterpriseAuthenticationAppLinkPolicyEnabled(settings);
      }
    } catch (RuntimeException e) {
      refused("getEnterpriseAuthenticationAppLinkPolicyEnabled", e);
    }
    return null;
  }

  public static void setRequestedWithHeaderOriginAllowList(@NonNull WebSettings settings, @NonNull Set<String> allowList) {
    try {
      if (WebViewFeature.isFeatureSupported(WebViewFeature.REQUESTED_WITH_HEADER_ALLOW_LIST)) {
        WebSettingsCompat.setRequestedWithHeaderOriginAllowList(settings, allowList);
      }
    } catch (RuntimeException e) {
      refused("setRequestedWithHeaderOriginAllowList", e);
    }
  }

  @Nullable
  public static Set<String> getRequestedWithHeaderOriginAllowList(@NonNull WebSettings settings) {
    try {
      if (WebViewFeature.isFeatureSupported(WebViewFeature.REQUESTED_WITH_HEADER_ALLOW_LIST)) {
        return WebSettingsCompat.getRequestedWithHeaderOriginAllowList(settings);
      }
    } catch (RuntimeException e) {
      refused("getRequestedWithHeaderOriginAllowList", e);
    }
    return null;
  }
}
