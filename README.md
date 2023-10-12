# wickindle

A super basic HTTP Server using libxev as the event loop and lib of choice for interacting with sockets. libxev provided a nice api that allowed me to use iouring with ease and a cross platform way to be built and used on Windows as well. Took some reference from Drogon when attempting to create a wrapper for it and had issues with shared_ptrs. This is mostly std HTTP Server but with libxev.

TODO:
- Awaiting Zig async fix in 0.12 before continuing much further
- Lots of missing features around chunked and partial content
- I am pretty sure the server is not waiting for content and is just gonna kill connections for not being fast enougha and reached EOL errors
- Need to upstream commit a fix to libxev for Windows errors
