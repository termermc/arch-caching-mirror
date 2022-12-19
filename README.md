# arch-caching-mirror
An Arch Linux mirror that proxies packages from other mirrors and caches them locally

# What is it?
This project exposes an HTTP server that serves Arch Linux packages.
It doesn't require a full copy of every package; instead, it requires only a location to store packages, and a mirrorlist to fetch packages from.
In this way, it can act as a caching package proxy.
This is very useful if you want to create a local package cache for LAN use, or anywhere else where you don't need to have a full mirror.

# How does this differ from other projects?
The main advantage of this software is the very minimal configuration it requires.
To set up a server, you only need to run the binary with the desired bind host and port, and optionally your cache directory and mirrorlist file.
Running without additional options will cause the software to use your system's mirrorlist and local package cache.
This enables you to turn an Arch Linux computer at your house into a local mirror instantly, with no additional configuration.

This doesn't mean you have to run the software on an Arch Linux computer, though!
You can run it on any machine with an Internet connection and storage, including on Windows/MacOS/BSD machines (if you compile it for them).

# How to use
Usage: `arch_caching_mirror <host> <port> [package cache path = /var/cache/pacman/pkg] [mirrorlist path = /etc/pacman.d/mirrorlist]`

Make sure that the software has permission to write into the cache folder it's using, otherwise it won't be able to fetch new packages.
You can use any valid Pacman mirrorlist file, and any writable directory for caching.

# Building
To build the project, you need Nim 1.6.10 or higher installed.
Once you have Nim, run `nimble build -d:release`. The compiled binary will be in the root of the project as `arch_caching_mirror`.