on logInfo(projectRoot, messageText)
  my writeLog(projectRoot, "INFO", messageText)
end logInfo

on logWarn(projectRoot, messageText)
  my writeLog(projectRoot, "WARN", messageText)
end logWarn

on logError(projectRoot, messageText)
  my writeLog(projectRoot, "ERROR", messageText)
end logError

on writeLog(projectRoot, levelText, messageText)
  set logPath to projectRoot & "/data/logs/sync.log"
  set timestamp to do shell script "date '+%Y-%m-%d %H:%M:%S'"
  set safeMessage to my shellQuote(timestamp & " [" & levelText & "] " & messageText)
  do shell script "mkdir -p " & quoted form of (projectRoot & "/data/logs")
  do shell script "printf %s\\n " & safeMessage & " >> " & quoted form of logPath
end writeLog

on shellQuote(t)
  return quoted form of t
end shellQuote
