// Copyright 2026 Juns-g
// SPDX-License-Identifier: Apache-2.0
// Compile-only API declarations; excluded from runtime DEX.
package android.view.accessibility;
public class AccessibilityNodeInfo {
 public static AccessibilityNodeInfo obtain(AccessibilityNodeInfo other) { return null; }
 public int getWindowId() { return 0; }
 public boolean isEditable() { return false; }
 public int getInputType() { return 0; }
 public int getMaxTextLength() { return 0; }
 public int getChildCount() { return 0; }
 public AccessibilityNodeInfo getChild(int index) { return null; }
 public CharSequence getText() { return null; }
 public CharSequence getContentDescription() { return null; }
 public CharSequence getClassName() { return null; }
 public CharSequence getPackageName() { return null; }
 public String getViewIdResourceName() { return null; }
 public boolean isCheckable() { return false; }
 public boolean isChecked() { return false; }
 public boolean isClickable() { return false; }
 public boolean isEnabled() { return false; }
 public boolean isFocusable() { return false; }
 public boolean isFocused() { return false; }
 public boolean isScrollable() { return false; }
 public boolean isLongClickable() { return false; }
 public boolean isPassword() { return false; }
 public boolean isSelected() { return false; }
 public boolean isVisibleToUser() { return false; }
 public void getBoundsInScreen(android.graphics.Rect rect) {}
 public void getBoundsInParent(android.graphics.Rect rect) {}
 public void recycle() {}
}
