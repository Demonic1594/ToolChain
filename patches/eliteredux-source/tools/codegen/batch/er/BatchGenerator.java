package er;

/**
 * Batch driver for the codegen pipeline.
 *
 * Runs many generators in a single JVM instead of one JVM per file, so the
 * proto textproto parsing (GeneratorUtils' lazy singletons) happens once and
 * JVM startup/classloading cost is paid once instead of ~57 times.
 *
 * Usage: java -cp codegen.jar:codegenkt.jar:protobuf-java.jar:protobuf-kotlin.jar:batch \
 *          er.BatchGenerator <type1> <path1> [<type2> <path2> ...]
 *
 * Arguments are (generator-name, output-path) pairs, same names as
 * er.FileGenerator accepts. Every generator runs even if an earlier one
 * fails; failures are reported at the end and the process exits non-zero,
 * so `make` still stops on a broken proto.
 */
public final class BatchGenerator {
    public static void main(String[] args) {
        if (args.length == 0 || args.length % 2 != 0) {
            System.err.println("Usage: er.BatchGenerator <type> <path> [<type> <path> ...]");
            System.exit(2);
        }
        int failed = 0;
        long start = System.nanoTime();
        for (int i = 0; i + 1 < args.length; i += 2) {
            String type = args[i];
            String path = args[i + 1];
            long t0 = System.nanoTime();
            try {
                er.FileGenerator.main(new String[] {type, path});
                System.out.printf("[codegen] %-28s %8.2fs  %s%n",
                        type, (System.nanoTime() - t0) / 1e9, path);
            } catch (Throwable t) {
                failed++;
                System.err.printf("[codegen] FAILED %-24s (%s)%n   %s%n",
                        type, path, t);
                Throwable cause = t.getCause();
                while (cause != null) {
                    System.err.println("   caused by: " + cause);
                    cause = cause.getCause();
                }
            }
        }
        double total = (System.nanoTime() - start) / 1e9;
        if (failed > 0) {
            System.err.printf("[codegen] %d/%d generators FAILED in %.2fs%n",
                    failed, args.length / 2, total);
            System.exit(1);
        }
        System.out.printf("[codegen] all %d generators OK in %.2fs%n",
                args.length / 2, total);
    }
}
