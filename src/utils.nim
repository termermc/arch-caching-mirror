import std/[os, options, times, asyncdispatch, asynchttpserver, httpclient, nre, strutils, asyncfile]
import "."/[constants]

let mirrorlistServerLinePattern = re"^\W*Server\W*=\W*(https?:\/\/(?:[\w]+\.)*\w+\.\w+\/(?:[\w_]+\/)*\$repo\/(?:[\w_]+\/)*\$arch)\W*$"

proc getFileInfoOrNone*(path: string): Option[FileInfo] =
    ## Returns info about a file or None if it was not found
    
    try:
        return some(getFileInfo(path))
    except OSError as e:
        return none[FileInfo]()

proc toUtcStr*(time: Time): string =
    ## Converts a Time object into a UTC string
    
    return time.utc.format("ddd', 'dd' 'MMM' 'yyyy' 'HH':'mm':'ss' GMT'")

proc nowUtcStr*(): string =
    ## Gets a UTC string for the current time
    
    return getTime().toUtcStr()

proc genPackageHeaders*(size: SomeNumber, lastModified: Time | string): HttpHeaders {.inline.} =
    ## Generates package file response headers

    return newHttpHeaders({
        "content-type": PACKAGE_MIME,
        "content-length": $size,
        "date": nowUtcStr(),
        "last-modified": when lastModified is string: lastModified else: lastModified.toUtcStr()
    })

proc readFileAsync*(path: string): Future[string] =
    ## Reads an entiire file's contents and returns it as a string

    let file = openAsync(path, fmRead)

    try:
        return file.readAll()
    finally:
        file.close()

proc parseMirrorlistContent*(content: string): seq[string] =
    ## Parses a mirrorlist file's content
    
    var res: seq[string]

    for ln in content.split('\n'):
        let findRes = ln.find(mirrorlistServerLinePattern)
        if findRes.isSome: res.add(findRes.get.captures[0])

    return res

proc parseMirrorlistFile*(path: string): Future[seq[string]] {.async.} =
    ## Parses a mirrorlist file
    
    return parseMirrorlistContent(await readFileAsync(path))

proc requestPackage*(client: AsyncHttpClient, mirror: string, repo: string, arch: string, file: string, httpMethod: HttpMethod): Future[AsyncResponse] =
    ## Makes a request for a package from a specific mirror
    
    # Generate URL
    let url = mirror.multiReplace({
        "$repo": repo,
        "$arch": arch
    }) & '/' & file

    return client.request(url, httpMethod)
