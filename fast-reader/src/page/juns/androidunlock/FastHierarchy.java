package page.juns.androidunlock;
import com.android.uiautomator.testrunner.UiAutomatorTestCase;
import com.android.uiautomator.core.UiDevice;
import com.android.uiautomator.core.UiAutomatorBridge;
import android.view.accessibility.AccessibilityNodeInfo;
import android.graphics.Rect;
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.Arrays;

/** Read-only node walker. No framework dumper, node formatting, UI actions or logging. */
public final class FastHierarchy extends UiAutomatorTestCase {
    private final StringBuilder xml = new StringBuilder();
    private int nodes;
    private long deadline;
    private String stage = "stdout_guard";
    private String failure = "validation_failed";
    public void testDump() {
        try {
            if (!Files.readSymbolicLink(Paths.get("/proc/self/fd/1")).toString().startsWith("pipe:[")) fail();
            // Only the runner's own bridge accessor; no other reflected/hidden API or exemption.
            stage = "device_config";
            UiDevice device = getUiDevice();
            device.setCompressedLayoutHeirarchy(false);
            stage = "bridge_lookup";
            Method accessor = UiDevice.class.getDeclaredMethod("getAutomatorBridge");
            stage = "bridge_accessor";
            accessor.setAccessible(true);
            Object bridge = accessor.invoke(device);
            stage = "bridge_type";
            if (!(bridge instanceof UiAutomatorBridge)) fail("bridge_type_unverified");
            stage = "root_query";
            long rootDeadline = System.nanoTime() + 500000000L;
            AccessibilityNodeInfo root;
            do {
                root = ((UiAutomatorBridge) bridge).getRootInActiveWindow();
                if (root != null || System.nanoTime() >= rootDeadline) break;
                Thread.sleep(10);
            } while (true);
            if (root == null) fail("null_root");
            deadline = System.nanoTime() + 2000000000L;
            stage = "xml_walk";
            xml.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?><hierarchy>");
            try { walk(root,0,0); } finally { root.recycle(); }
            xml.append("</hierarchy>");
            stage = "output";
            byte[] bytes = xml.toString().getBytes("UTF-8");
            if (bytes.length > 1048576) fail();
            try { System.out.write(bytes); System.out.flush(); } finally { Arrays.fill(bytes,(byte)0); xml.setLength(0); }
        } catch (Throwable error) {
            xml.setLength(0);
            String category = failure;
            if (error instanceof NoSuchMethodException) category = "no_such_method";
            else if (error instanceof IllegalAccessException) category = "illegal_access";
            else if (error instanceof SecurityException) category = "security_denied";
            else if (error instanceof java.lang.reflect.InvocationTargetException) category = "accessor_invocation_failed";
            else if (error instanceof LinkageError) category = "linkage_unavailable";
            else if (error instanceof java.io.IOException) category = "io_failed";
            else if (error instanceof InterruptedException) category = "interrupted";
            else if (error instanceof NullPointerException) category = "null_reference";
            else if (!(error instanceof IllegalStateException)) category = "unknown_failure";
            throw new IllegalStateException("collector_blocked:" + stage + ":" + category);
        }
    }
    byte[] dump(AccessibilityNodeInfo root) {
        nodes = 0; deadline = System.nanoTime() + 1500000000L; xml.setLength(0);
        try {
            xml.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?><hierarchy>");
            walk(root, 0, 0); xml.append("</hierarchy>");
            return xml.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8);
        } finally { xml.setLength(0); }
    }
    private void fail() { fail("validation_failed"); }
    private void fail(String code) { failure = code; throw new IllegalStateException("collector_blocked"); }
    private void attr(String name, CharSequence value) {
        stage = "field";
        xml.append(' ').append(name).append("=\"");
        if (value != null) {
            if (value.length() > 16384) { stage = "limits"; fail("field_limit"); }
            for (int i=0;i<value.length();i++) {
                char c=value.charAt(i);
                if (c=='&') xml.append("&amp;"); else if(c=='<') xml.append("&lt;");
                else if(c=='>') xml.append("&gt;"); else if(c=='\"') xml.append("&quot;");
                else if(c=='\n') xml.append("&#10;"); else if(c=='\r') xml.append("&#13;"); else if(c=='\t') xml.append("&#9;");
                else if(c<32 || c==0xfffe || c==0xffff) fail("invalid_xml_value");
                else if(Character.isHighSurrogate(c)) {
                    if(i+1>=value.length() || !Character.isLowSurrogate(value.charAt(i+1))) fail();
                    xml.append(c).append(value.charAt(++i));
                } else if(Character.isLowSurrogate(c)) fail(); else xml.append(c);
            }
        }
        xml.append('"'); if(xml.length()>262144) { stage = "limits"; fail("output_limit"); }
    }
    private void flag(String key,boolean value) { attr(key,value ? "true" : "false"); }
    private void walk(AccessibilityNodeInfo n,int depth,int index) {
        stage = "xml_walk";
        if(depth>64 || ++nodes>4096 || System.nanoTime()>deadline) { stage = "limits"; fail("walk_limit"); }
        xml.append("<node"); attr("index",Integer.toString(index));
        stage = "field";
        attr("text",n.getText()); attr("resource-id",n.getViewIdResourceName()); attr("class",n.getClassName());
        attr("package",n.getPackageName()); attr("content-desc",n.getContentDescription());
        flag("checkable",n.isCheckable()); flag("checked",n.isChecked()); flag("clickable",n.isClickable());
        flag("enabled",n.isEnabled()); flag("focusable",n.isFocusable()); flag("focused",n.isFocused());
        flag("scrollable",n.isScrollable()); flag("long-clickable",n.isLongClickable());
        flag("password",n.isPassword()); flag("selected",n.isSelected());
        flag("editable",n.isEditable());
        attr("input-type",Integer.toString(n.getInputType()));
        attr("max-text-length",Integer.toString(n.getMaxTextLength()));
        stage = "bounds";
        Rect b=new Rect(); n.getBoundsInScreen(b);
        attr("bounds","["+b.left+","+b.top+"]["+b.right+","+b.bottom+"]");
        if ("com.android.systemui".contentEquals(n.getPackageName()) &&
                "com.android.systemui:id/lockPattern".equals(n.getViewIdResourceName()) &&
                "android.view.View".contentEquals(n.getClassName())) {
            Rect local=new Rect(); n.getBoundsInParent(local);
            attr("bounds-parent","["+local.left+","+local.top+"]["+local.right+","+local.bottom+"]");
        }
        xml.append('>');
        stage = "xml_walk";
        int count=n.getChildCount(); if(count<0 || count>4096) fail();
        for(int i=0;i<count;i++) {
            AccessibilityNodeInfo child=n.getChild(i);
            if(child==null) fail("null_child");
            try { if(child.isVisibleToUser()) walk(child,depth+1,i); } finally { child.recycle(); }
        }
        xml.append("</node>");
    }
}
