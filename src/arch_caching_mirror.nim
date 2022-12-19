import std/[asyncdispatch, os, strutils, strformat]
import "."/[server, constants]

proc main() {.async.} =
    if paramCount() < 2:
        echo fmt"Usage: {getAppFilename()} <host> <port> [package cache path = {DEFAULT_PACKAGE_CACHE_PATH}] [mirrorlist path = {DEFAULT_MIRRORLIST_PATH}]"
        quit(1)
    
    let host = paramStr(1)
    let port = parseInt(paramStr(2)).Port
    let cachePath = if paramCount() > 2: paramStr(3) else: DEFAULT_PACKAGE_CACHE_PATH
    let mirrorlistPath = if paramCount() > 3: paramStr(3) else: DEFAULT_MIRRORLIST_PATH

    await startServer(host, port, cachePath, mirrorlistPath)

when isMainModule:
    waitFor main()
