# tinyfts

![CI badge](https://github.com/dbohdan/tinyfts/workflows/CI/badge.svg)

A very small standalone full-text search HTTP server.

## Dependencies

### Server

* Tcl 8.6
* tclsqlite3 with [FTS5](https://sqlite.org/fts5.html)

### Building, tools, and tests

The above and
* Tcllib
* curl(1)
* kill(1)
* make(1)
* sqlite3(1)

On recent Debian and Ubuntu install the dependencies with

```none
sudo apt install curl libsqlite3-tcl make sqlite3 tcl tcllib
```

## License

MIT.  [Wapp](wapp.tcl.tk/) is copyright (c) 2017 D. Richard Hipp and is
distributed under the Simplified BSD License.
[Tacit](https://github.com/yegor256/tacit) is copyright (c) 2015-2019
Yegor Bugayenko and is distributed under the MIT license.
