import std/[asyncdispatch, asynchttpserver, httpclient, asyncfile, asyncstreams, asyncnet, os, tables, strformat, nre, options, strutils]
import "."/[constants, utils]

# Server global state
var repoPathPattern {.threadvar.}: Regex
var pkgCachePath {.threadvar.}: string
var pkgMirrors {.threadvar.}: seq[string]
var mirrorClient {.threadvar.}: AsyncHttpClient
var pkgDlFutures {.threadvar.}: Table[string, Future[void]]

proc handleReq(req: Request) {.async, gcsafe.} =
    let url = req.url

    proc notFound(): Future[void] =
        return req.respond(Http404, "Not found")

    # Ensure this is a sensible method
    if req.reqMethod notin {HttpGet, HttpHead}:
        await notFound()
        return

    try:
        # Check if path is a valid repo path
        let findRes = url.path.find(repoPathPattern)
        if findRes.isNone:
            await notFound()
            return

        let pathCaptures = findRes.get.captures
        let pathRepo = pathCaptures[0]
        let pathArch = pathCaptures[1]
        let pathFile = pathCaptures[2]

        let isDbFile = pathFile.endsWith(".db")

        # Await an existing download Future for the requested file if present
        if pkgDlFutures.hasKey(pathFile):
            await pkgDlFutures[pathFile]

        # Check for file in local cache, and if so, send it
        let pkgFilePath = pkgCachePath / pathFile
        let fileInfoOption = getFileInfoOrNone(pkgFilePath)
        if not isDbFile and fileInfoOption.isSome:
            let fileInfo = fileInfoOption.get
            if fileInfo.kind in {pcFile, pcLinkToFile}:
                # Send HTTP response
                await req.respond(Http200, "", genPackageHeaders(fileInfo.size, fileInfo.lastWriteTime))

                # End request if the method was HEAD
                if req.reqMethod == HttpHead:
                    return
                
                # Open file
                var file = openAsync(pkgFilePath, fmRead)
                var buf: array[READ_BUF_SIZE, uint8]

                try:
                    # Send file
                    while not req.client.isClosed():
                        let bufLen = await file.readBuffer(addr buf, buf.len)
                        if bufLen < 1:
                            break

                        await req.client.send(addr buf, bufLen)
                
                finally:
                    # Clean up resources
                    file.close()
                    if not req.client.isClosed():
                        req.client.close()

                    return
        
        # The package wasn't found in the local cache; try to fetch it from a remote mirror
        for mirror in pkgMirrors:
            # Check if the mirror has the package
            let mirrorRes = await mirrorClient.requestPackage(mirror, pathRepo, pathArch, pathFile, req.reqMethod)

            var success = false

            try:
                if mirrorRes.status == "200 OK":
                    # Send HTTP response
                    let lastModified = mirrorRes.headers.getOrDefault("last-modified", HttpHeaderValues(@[nowUtcStr()]))
                    await req.respond(Http200, "", genPackageHeaders(mirrorRes.contentLength, lastModified))

                    # If this is a HEAD request, end right now
                    if req.reqMethod == HttpHead:
                        req.client.close()
                        return

                    # Create download Future
                    var future = Future[void]()
                    if not isDbFile:
                        pkgDlFutures[pathFile] = future

                    try:
                        # Open file for writing if it's not a DB file
                        var file: AsyncFile
                        if not isDbFile:
                            file = openAsync(pkgFilePath, fmWrite)
                            echo fmt"Package file {pathFile} was requested, but not in cache; downloading from mirror {mirror}..."
                        
                        try:
                            let stream = mirrorRes.bodyStream
                            block readMirror:
                                while true:
                                    let (ended, buf) = await stream.read()
                                    if not ended:
                                        break readMirror

                                    if not isDbFile:
                                        await file.write(buf)

                                    await req.client.send(buf)

                            if not isDbFile:
                                echo fmt"Successfully downloaded {pathFile} from mirror {mirror}"

                            success = true
                        finally:
                            if not isDbFile:
                                file.close()
                            if not req.client.isClosed:
                                req.client.close()

                            if not success:
                                removeFile(pkgFilePath)
                    finally:
                        if not future.finished:
                            future.complete()
                        
                        if not isDbFile:
                            pkgDlFutures.del(pathFile)
            except:
                stderr.writeLine(fmt"Request to mirror {mirror} failed:")
                stderr.writeLine(fmt"{getCurrentExceptionMsg()}: {repr(getCurrentException())}")
            
            if success:
                return

        # No mirror returned a 200 Found response; send not found
        await notFound()
        
    except:
        stderr.writeLine(fmt"Failed to handle request for {url.path}:")
        stderr.writeLine(fmt"{getCurrentExceptionMsg()}: {repr(getCurrentException())}")

        try:
            await req.respond(Http500, "Internal error")
        except:
            stderr.writeLine("Failed to send HTTP 500 to client")

proc startServer*(host: string, port: Port, cachePath: string, mirrorlistPath: string) {.async.} =
    ## Starts the server
    
    # Initialize server global data
    repoPathPattern = re"^\/(\w+)\/os\/(\w+)\/((?!\.\.)[\w\.-]+)$"
    pkgCachePath = cachePath
    pkgMirrors = await parseMirrorlistFile(mirrorlistPath)
    mirrorClient = newAsyncHttpClient()
    pkgDlFutures = Table[string, Future[void]]()

    var server = newAsyncHttpServer()
    server.listen(port, host)

    echo fmt"Listening on {host}:{port.uint16}"

    # Handle requests
    while true:
        if server.shouldAcceptRequest():
            await server.acceptRequest(handleReq)
        else:
            await sleepAsync(500)