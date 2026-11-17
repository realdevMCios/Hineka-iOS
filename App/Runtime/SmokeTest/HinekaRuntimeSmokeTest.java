import java.util.Set;
import java.util.TreeSet;
import java.util.stream.Collectors;

public final class HinekaRuntimeSmokeTest {
    private HinekaRuntimeSmokeTest() {}

    public static void main(String[] args) {
        System.out.println(run());
    }

    /// Emits a stable key/value protocol so Swift can inspect the VM that actually
    /// started, including the boot-layer modules from the bundled lib/modules image.
    public static String run() {
        Set<String> modules = ModuleLayer.boot().modules().stream()
            .map(Module::getName)
            .collect(Collectors.toCollection(TreeSet::new));

        StringBuilder result = new StringBuilder();
        result.append("HINEKA_RUNTIME_REPORT=1\n");
        append(result, "java.version", System.getProperty("java.version"));
        append(result, "java.major", Integer.toString(Runtime.version().feature()));
        append(result, "vm.name", System.getProperty("java.vm.name"));
        append(result, "vm.info", System.getProperty("java.vm.info"));
        append(result, "os.name", System.getProperty("os.name"));
        append(result, "os.arch", System.getProperty("os.arch"));
        append(result, "processors", Integer.toString(Runtime.getRuntime().availableProcessors()));
        append(result, "modules", String.join(",", modules));
        return result.toString();
    }

    private static void append(StringBuilder output, String key, String value) {
        String safeValue = value == null ? "" : value.replace("\n", " ").replace("\r", " ");
        output.append(key).append("=").append(safeValue).append("\n");
    }
}
