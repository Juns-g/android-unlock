// Copyright 2026 Juns-g
// SPDX-License-Identifier: MIT
package page.juns.androidunlock;

import android.app.UiAutomation;
import android.os.SystemClock;
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
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FileDescriptor;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

/** One finite own-process observer. Its stdin contains only snapshot/arm/count controls, never PIN or coordinates. */
public final class FlymeProgressSession extends UiAutomatorTestCase {
    private static final String PREFIX = "com.android.systemui:id/";
    private static final String[] CHAIN = {"keyguard_bouncer_container", "keyguard_host_view",
        "keyguard_security_container", "view_flipper", "mz_keyguard_pin_view",
        "keyguard_bouncer_frame", "keyguard_bouncer_rl", "inputBox"};
    private AccessibilityNodeInfo field;
    private int fieldTotal, visited;
    private long deadline, registeredAt;
    private boolean closed, invalidSource, contextChanged, overflow;
    private boolean armed, completed;
    private int accepted, error, sequence;
    private int sourceEvents, foreignEvents, appendEvents, removalEvents, emptyResetEvents;
    private int lastFrom = -1, lastAdded = -1, lastRemoved = -1;
    private String stage = "stdout_guard";

    static int nextCount(int current, boolean armed, int from, int removed, int added) {
        return armed && current >= 0 && current < 4 && from == current && removed == 0 && added == 1 ? current + 1 : -1;
    }
    private static boolean fieldShape(AccessibilityNodeInfo n) {
        return "com.android.systemui".contentEquals(n.getPackageName() == null ? "" : n.getPackageName()) &&
            (PREFIX + "passwordEntry").equals(n.getViewIdResourceName()) &&
            "android.widget.EditText".contentEquals(n.getClassName() == null ? "" : n.getClassName()) &&
            n.isPassword() && n.isEditable() && n.isEnabled() && n.isFocused() && n.isFocusable() &&
            !n.isClickable() && n.isVisibleToUser() && n.getInputType() == 16 && n.getMaxTextLength() == -1;
    }
    private void walk(AccessibilityNodeInfo n, List<String> ancestors, int depth) {
        if (++visited > 512 || depth > 32 || System.nanoTime() > deadline) throw new IllegalStateException();
        String id = n.getViewIdResourceName();
        if ((PREFIX + "passwordEntry").equals(id)) {
            fieldTotal++;
            if (!fieldShape(n) || ancestors.size() < CHAIN.length) throw new IllegalStateException();
            for (int i = 0; i < CHAIN.length; i++) {
                if (!(PREFIX + CHAIN[i]).equals(ancestors.get(ancestors.size() - CHAIN.length + i))) throw new IllegalStateException();
            }
            if (field != null) throw new IllegalStateException();
            field = AccessibilityNodeInfo.obtain(n);
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
    private void bind(UiAutomatorBridge bridge) {
        AccessibilityNodeInfo root = bridge.getRootInActiveWindow();
        if (root == null) throw new IllegalStateException();
        visited = 0; fieldTotal = 0; deadline = System.nanoTime() + 1500000000L;
        try {
            walk(root, new ArrayList<String>(), 0);
            if (fieldTotal != 1 || field == null || root.getWindowId() != field.getWindowId()) throw new IllegalStateException();
        } finally { root.recycle(); }
    }

    private synchronized void event(AccessibilityEvent e) {
        AccessibilityNodeInfo source = null;
        try {
            if (closed) return;
            if (e.getEventType() == 32 || e.getEventType() == 4194304) {
                contextChanged = true; if (!completed) error = 1; return;
            }
            if (e.getEventType() != 16 || !"com.android.systemui".contentEquals(e.getPackageName() == null ? "" : e.getPackageName())) return;
            if (++sourceEvents + foreignEvents > 64) { error = 7; return; }
            source = e.getSource();
            if (source == null) { if (!completed) error = 2; return; }
            if (!source.equals(field)) { sourceEvents--; foreignEvents++; return; }
            if (!fieldShape(source) || source.getWindowId() != field.getWindowId() || e.getWindowId() != field.getWindowId() ||
                !e.isPassword() || !"android.widget.EditText".contentEquals(e.getClassName() == null ? "" : e.getClassName()) || e.getEventTime() < registeredAt) {
                if (!completed) error = 2; return;
            }
            int from = e.getFromIndex(), added = e.getAddedCount(), removed = e.getRemovedCount();
            // Normal auto-authentication may remove/reset its field AFTER the fourth proven append.
            if (completed && added == 0) return;
            int next = nextCount(accepted, armed, from, removed, added);
            if (next < 0) { error = 3; return; }
            accepted = next; armed = false; completed = accepted == 4; notifyAll();
        } catch (Throwable ignored) { if (!completed) error = 2; }
        finally { if (source != null) source.recycle(); e.recycle(); }
    }
    private String command(InputStream input) throws java.io.IOException {
        StringBuilder line = new StringBuilder();
        for (;;) {
            int c = input.read(); if (c < 0) return null;
            if (c == 10) return line.toString();
            if (c < 32 || c > 126 || line.length() >= 16) throw new IllegalStateException();
            line.append((char)c);
        }
    }
    private synchronized void await(int expected) throws InterruptedException {
        long until = SystemClock.uptimeMillis() + 800;
        while (error == 0 && accepted < expected && SystemClock.uptimeMillis() < until) wait(10);
        if (accepted != expected || armed) error = 4;
    }
    private void frame(OutputStream output, byte[] xml) throws java.io.IOException {
        synchronized (this) {
            String header = "__AU_FLYME_V1__ " + (++sequence) + " " + accepted + " " + error + " " + (error == 0 ? xml.length : 0) + "\n";
            output.write(header.getBytes(StandardCharsets.US_ASCII));
            if (error == 0) output.write(xml);
            output.flush();
        }
        Arrays.fill(xml, (byte)0);
    }
    public void testProgress() {
        UiAutomatorBridge bridge = null;
        try {
            if (!Files.readSymbolicLink(Paths.get("/proc/self/fd/1")).toString().startsWith("pipe:[") ||
                !(Files.readSymbolicLink(Paths.get("/proc/self/fd/0")).toString().startsWith("pipe:[") || Files.readSymbolicLink(Paths.get("/proc/self/fd/0")).toString().startsWith("socket:["))) throw new SecurityException();
            UiDevice device = getUiDevice(); device.setCompressedLayoutHeirarchy(false);
            Method accessor = UiDevice.class.getDeclaredMethod("getAutomatorBridge"); accessor.setAccessible(true);
            Object object = accessor.invoke(device);
            if (!(object instanceof UiAutomatorBridge)) throw new IllegalStateException();
            bridge = (UiAutomatorBridge)object; bind(bridge);
            registeredAt = SystemClock.uptimeMillis();
            bridge.setOnAccessibilityEventListener(new UiAutomation.OnAccessibilityEventListener() {
                public void onAccessibilityEvent(AccessibilityEvent e) { event(e); }
            });
            InputStream input = new FileInputStream(FileDescriptor.in);
            OutputStream output = new FileOutputStream(FileDescriptor.out);
            long until = SystemClock.uptimeMillis() + 80000;
            FastHierarchy reader = new FastHierarchy();
            for (int requests = 0; requests < 20 && SystemClock.uptimeMillis() < until; requests++) {
                String command = command(input); if (command == null || command.equals("QUIT")) break;
                if (command.matches("ARM [0-3]")) {
                    int expected = command.charAt(4) - '0';
                    synchronized (this) {
                        if (error != 0 || armed || completed || accepted != expected) error = 3;
                        else { armed = true; registeredAt = SystemClock.uptimeMillis(); }
                    }
                    frame(output, new byte[0]);
                } else if (command.matches("SNAP [0-3]") || command.equals("ACK 4")) {
                    int expected = command.charAt(command.length() - 1) - '0';
                    if (expected > 0) await(expected);
                    if (expected == 4) { frame(output, new byte[0]); continue; }
                    AccessibilityNodeInfo root = bridge.getRootInActiveWindow();
                    if (root == null) throw new IllegalStateException();
                    FlymeProgressSession finder = new FlymeProgressSession();
                    byte[] xml;
                    try {
                        finder.visited = 0; finder.fieldTotal = 0; finder.deadline = System.nanoTime() + 1500000000L;
                        finder.walk(root, new ArrayList<String>(), 0);
                        synchronized (this) {
                            if (finder.fieldTotal != 1 || finder.field == null || !finder.field.equals(field) || finder.field.getWindowId() != root.getWindowId()) error = 5;
                        }
                        xml = reader.dump(root);
                    } finally { root.recycle(); if (finder.field != null) finder.field.recycle(); }
                    frame(output, xml);
                } else { error = 6; frame(output, new byte[0]); break; }
                synchronized (this) { if (error != 0) break; }
            }
        } catch (Throwable ignored) {
            // Constant fail-closed protocol metadata; never exception/event/node formatting.
            try { synchronized (this) { error = 7; } frame(new FileOutputStream(FileDescriptor.out), new byte[0]); } catch (Throwable suppressed) {}
        } finally {
            synchronized (this) { closed = true; }
            if (bridge != null) { try { bridge.setOnAccessibilityEventListener(null); } catch (Throwable ignored) {} }
            if (field != null) field.recycle();
        }
    }
}
