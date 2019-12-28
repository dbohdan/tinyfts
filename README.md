# tinyfts

A very small self-contained full text search HTTP server.

## Dependencies

### Server

* Tcl 8.6
* tclsqlite3 with [FTS5](https://sqlite.org/fts5.html)

### Tools and tests

The above and
* Tcllib
* curl(1)
* kill(1)
* sqlite3(1)

On recent Debian and Ubuntu install the dependencies with

```none
sudo apt install tcl tcllib libsqlite3-tcl
```

## License

MIT.  [Wapp](wapp.tcl.tk/) is copyright (c) 2017 D. Richard Hipp and is
distributed under the Simplified BSD License.
[Tacit](https://github.com/yegor256/tacit) is copyright (c) 2015-2019
Yegor Bugayenko and is distributed under the MIT license.
