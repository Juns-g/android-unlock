// Copyright 2026 Robby Wang
// SPDX-License-Identifier: MIT
package page.juns.androidunlock;

import android.app.UiAutomation;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import com.android.uiautomator.core.UiDevice;
import com.android.uiautomator.core.UiAutomatorBridge;
import com.android.uiautomator.testrunner.UiAutomatorTestCase;
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;

/** Bounded, read-only diagnostic. Never requests node/event text, performs input, or reports digits. */
public final class HyperOSProgressProbe extends UiAutomatorTestCase {
    private static final String PREFIX = "com.android.systemui:id/";
    private static final String[] CHAIN = {"keyguard_bouncer_container", "keyguard_security_container",
        "view_flipper", "keyguard_pin_view", "pin_container"};
    private AccessibilityNodeInfo field;
    private int fields, cancel, delete, visited, events;
    private long deadline;
    private boolean closed;
    private String stage = "stdout_guard";

    private static boolean shape(AccessibilityNodeInfo n) {
        return "com.android.systemui".contentEquals(n.getPackageName() == null ? "" : n.getPackageName()) &&
            (PREFIX + "pinEntry").equals(n.getViewIdResourceName()) &&
            "com.android.keyguard.PasswordTextView".contentEquals(n.getClassName() == null ? "" : n.getClassName()) &&
            n.isPassword() && n.isEnabled() && n.isFocused() && n.isFocusable() &&
            !n.isClickable() && n.isVisibleToUser();
    }
    private void walk(AccessibilityNodeInfo n, List<String> ancestors, int depth) {
        if (++visited > 512 || depth > 32 || System.nanoTime() > deadline) throw new IllegalStateException();
        String id = n.getViewIdResourceName();
        if ((PREFIX + "pinEntry").equals(id)) {
            int next = 0;
            for (String ancestor : ancestors) {
                if (next < CHAIN.length && (PREFIX + CHAIN[next]).equals(ancestor)) next++;
            }
            if (++fields != 1 || next != CHAIN.length || !shape(n)) throw new IllegalStateException();
            field = AccessibilityNodeInfo.obtain(n);
        }
        if (!ancestors.isEmpty() && (PREFIX + "keyguard_selector_fade_container").equals(ancestors.get(ancestors.size() - 1))) {
            if ((PREFIX + "cancel_button").equals(id)) cancel++;
            if ((PREFIX + "delete_button").equals(id)) delete++;
        }
        ancestors.add(id);
        try {
            for (int i = 0; i < n.getChildCount(); i++) {
                AccessibilityNodeInfo child = n.getChild(i);
                if (child == null) throw new IllegalStateException();
                try { if (child.isVisibleToUser()) walk(child, ancestors, depth + 1); }
                finally { child.recycle(); }
            }
        } finally { ancestors.remove(ancestors.size() - 1); }
    }
    private synchronized void event(AccessibilityEvent e) {
        AccessibilityNodeInfo source = null;
        try {
            if (closed || events >= 8 || e.getEventType() != 16 ||
                !"com.android.systemui".contentEquals(e.getPackageName() == null ? "" : e.getPackageName())) return;
            source = e.getSource();
            if (source == null || !(PREFIX + "pinEntry").equals(source.getViewIdResourceName())) return;
            events++;
            System.out.println("__AU_HYPEROS_PROBE_EVENT__ " + events + " " +
                (source.equals(field) ? 1 : 0) + " " + (shape(source) ? 1 : 0) + " " +
                (e.getWindowId() == field.getWindowId() && source.getWindowId() == field.getWindowId() ? 1 : 0) + " " +
                (e.isPassword() ? 1 : 0) + " " +
                ("android.widget.EditText".contentEquals(e.getClassName() == null ? "" : e.getClassName()) ? 1 : 0) + " " +
                e.getFromIndex() + " " + e.getRemovedCount() + " " + e.getAddedCount());
            System.out.flush();
        } catch (Throwable ignored) {
            closed = true; System.out.println("__AU_HYPEROS_PROBE_FAILED__ event"); System.out.flush();
        } finally { if (source != null) source.recycle(); e.recycle(); }
    }
    public void testObserve() {
        UiAutomatorBridge bridge = null;
        try {
            if (!Files.readSymbolicLink(Paths.get("/proc/self/fd/1")).toString().startsWith("pipe:[")) throw new SecurityException();
            stage = "bridge_lookup";
            UiDevice device = getUiDevice(); device.setCompressedLayoutHeirarchy(false);
            Method accessor = UiDevice.class.getDeclaredMethod("getAutomatorBridge"); accessor.setAccessible(true);
            Object object = accessor.invoke(device);
            if (!(object instanceof UiAutomatorBridge)) throw new IllegalStateException();
            bridge = (UiAutomatorBridge)object;
            stage = "root_query";
            AccessibilityNodeInfo root;
            long rootDeadline = System.nanoTime() + 500000000L;
            do {
                root = bridge.getRootInActiveWindow();
                if (root != null || System.nanoTime() >= rootDeadline) break;
                Thread.sleep(10);
            } while (true);
            if (root == null) throw new IllegalStateException();
            deadline = System.nanoTime() + 1500000000L;
            try {
                stage = "field_walk";
                walk(root, new ArrayList<String>(), 0);
                stage = "field_footer_binding";
                if (fields != 1 || field == null || field.getWindowId() != root.getWindowId() ||
                    !((cancel == 1 && delete == 0) || (cancel == 0 && delete == 1))) throw new IllegalStateException();
            } finally { root.recycle(); }
            stage = "listener_registration";
            bridge.setOnAccessibilityEventListener(new UiAutomation.OnAccessibilityEventListener() {
                public void onAccessibilityEvent(AccessibilityEvent e) { event(e); }
            });
            System.out.println("__AU_HYPEROS_PROBE_READY__ " + cancel + " " + delete);
            System.out.flush();
            stage = "observe";
            long until = System.nanoTime() + 180000000000L;
            for (;;) {
                synchronized (this) { if (closed || events >= 8 || System.nanoTime() >= until) break; }
                Thread.sleep(50);
            }
        } catch (Throwable failure) {
            String kind = failure instanceof LinkageError ? "linkage" :
                failure instanceof SecurityException ? "security" : "context";
            System.out.println("__AU_HYPEROS_PROBE_FAILED__ " + stage + " " + kind); System.out.flush();
        } finally {
            synchronized (this) { closed = true; }
            if (bridge != null) { try { bridge.setOnAccessibilityEventListener(null); } catch (Throwable ignored) {} }
            if (field != null) field.recycle();
            System.out.println("__AU_HYPEROS_PROBE_DONE__"); System.out.flush();
        }
    }
}
