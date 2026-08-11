package jp.yts.termethis;

interface IDiagnosticsUserService {
    boolean startLogcatCapture(int maxLines) = 1;
    void stopLogcatCapture() = 2;
    boolean isLogcatCapturing() = 3;
    List<String> getRecentLogcatLines(int limit) = 4;
    void clearLogcatCapture() = 5;

    boolean startShell() = 6;
    boolean writeShellInput(in byte[] input) = 7;
    byte[] readShellOutput(int maxBytes) = 8;
    boolean isShellRunning() = 9;
    void stopShell() = 10;

    void destroy() = 16777114;
}
