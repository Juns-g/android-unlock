// Copyright 2026 Juns-g
// SPDX-License-Identifier: Apache-2.0
// Compile-only API declarations; excluded from runtime DEX.
package android.view.accessibility;
public class AccessibilityEvent {
 public int getEventType() { return 0; }
 public long getEventTime() { return 0; }
 public int getWindowId() { return 0; }
 public CharSequence getPackageName() { return null; }
 public CharSequence getClassName() { return null; }
 public boolean isPassword() { return false; }
 public AccessibilityNodeInfo getSource() { return null; }
 public int getFromIndex() { return 0; }
 public int getAddedCount() { return 0; }
 public int getRemovedCount() { return 0; }
 public void recycle() {}
}
