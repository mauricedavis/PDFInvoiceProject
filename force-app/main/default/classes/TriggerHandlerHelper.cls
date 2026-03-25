public class TriggerHandlerHelper {
    private static Map<String, Boolean> triggerRunMap = new Map<String, Boolean>();

    public static Boolean isAlreadyRunning(String triggerName) {
        return triggerRunMap.containsKey(triggerName);
    }

    public static void markRunning(String triggerName) {
        triggerRunMap.put(triggerName, true);
    }
}