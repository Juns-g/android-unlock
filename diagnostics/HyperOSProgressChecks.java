package page.juns.androidunlock;

/** Exercises the same transition gate used by the on-device observer, without Android input. */
public final class HyperOSProgressChecks {
    private static int checks;
    private static void check(boolean ok) { checks++; if (!ok) throw new AssertionError("transition " + checks); }
    public static void main(String[] args) {
        for (int limit : new int[] {4, 6, 16}) {
            for (int count = 0; count < limit; count++) {
                check(HyperOSProgressSession.nextCount(count, limit, true, 0, 0, 1) == count + 1);
                check(HyperOSProgressSession.nextCount(count, limit, false, 0, 0, 1) == -1);
                check(HyperOSProgressSession.nextCount(count, limit, true, -1, 1, 0) == -1);
                check(HyperOSProgressSession.nextCount(count, limit, true, 0, 0, 0) == -1);
                check(HyperOSProgressSession.nextCount(count, limit, true, 0, 1, 1) == -1);
                check(HyperOSProgressSession.nextCount(count, limit, true, 0, 0, 2) == -1);
                check(HyperOSProgressSession.nextCount(count, limit, true, 1, 0, 1) == -1);
            }
            check(HyperOSProgressSession.nextCount(limit, limit, true, 0, 0, 1) == -1);
        }
        check(HyperOSProgressSession.nextCount(-1, 6, true, 0, 0, 1) == -1);
        check(HyperOSProgressSession.nextCount(0, 3, true, 0, 0, 1) == -1);
        check(HyperOSProgressSession.nextCount(0, 17, true, 0, 0, 1) == -1);
        System.out.println(checks + " HyperOS event transition checks passed; no Android input");
    }
}
