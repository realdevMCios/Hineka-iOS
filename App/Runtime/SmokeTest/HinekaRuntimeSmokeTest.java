public final class HinekaRuntimeSmokeTest {
    private HinekaRuntimeSmokeTest() {}

    public static String run() {
        StringBuilder result = new StringBuilder();
        result.append("Hineka Java runtime smoke test: PASS\n");
        result.append("Java version: ").append(System.getProperty("java.version")).append("\n");
        result.append("VM: ").append(System.getProperty("java.vm.name")).append("\n");
        result.append("OS: ").append(System.getProperty("os.name")).append(" ")
              .append(System.getProperty("os.arch")).append("\n");
        result.append("Available processors: ").append(Runtime.getRuntime().availableProcessors());
        return result.toString();
    }
}
