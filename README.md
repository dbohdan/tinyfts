# tinyfts

![CI badge](https://github.com/dbohdan/tinyfts/workflows/CI/badge.svg)

A very small standalone full-text search HTTP/SCGI server.


## Dependencies

### Server

* Tcl 8.6
* tclsqlite3 with [FTS5](https://sqlite.org/fts5.html)

### Building, tools, and tests

The above and
* Tcllib
* curl(1), kill(1), make(1), sqlite3(1)

On recent Debian and Ubuntu install the dependencies with

```sh
sudo apt install curl libsqlite3-tcl make sqlite3 tcl tcllib
```

On FreeBSD with sudo install the dependencies with

```sh
sudo pkg install curl sqlite3 tcl-sqlite3 tcl86 tcllib
cd /usr/local/bin
sudo ln -s tclsh8.6 tclsh
```


## Usage

```none
Usage:
    ./tinyfts-dev.tcl --db-file path [option ...] [wapp-arg ...]
Options:
    --css-file ''
    --header <HTML>
    --footer <HTML>
    --title tinyfts
    --subtitle <HTML>
    --table tinyfts
    --min-length 2
    --rate-limit 60
    --result-limit 100
    --log 'access bad-request error rate'
    --behind-reverse-proxy false
    --snippet-size 20
    --title-weight 1000.0
    --query-syntax web
```


## Query syntax (default or "web")

* `foo`
* `"foo bar"`
* `foo AND bar`, `foo OR bar`, `NOT foo`
* `-foo`, `-"foo bar"`


## Setup example

The following instructions should work on most Linux distributions and FreeBSD
with the dependencies and Git installed.

1\. Go to <https://sourceforge.net/project/showfiles.php?group_id=211498>.
Download and extract the last [Wikit](https://wiki.tcl-lang.org/page/Wikit)
database snapshot of the Tcler's Wiki.  Currently that is `wikit-20141112.zip`.
Let's say you have extracted the database file as `~/Downloads/wikit.tkd`.

2\. Download, build, and test tinyfts.  In this example we will use Git to get
the latest development version.

```sh
git clone https://github.com/dbohdan/tinyfts
cd tinyfts
make
```

3\. Create a tinyfts search database from the Tcler's Wiki database.  Depending
on the hardware, this may take up to several minutes with an input database
size in the hundreds of megabytes.

```sh
./tools/import wikit ~/Downloads/wikit.tkd /tmp/fts.sqlite3
```

4\. Start tinyfts on <http://localhost:8080>.  The server URL should open
automatically in your browser.  Check that the search works.

```sh
./tinyfts --db-file /tmp/fts.sqlite3 --title 'tinyfts demo' --local 8080
```


## Operating notes

* If you put tinyfts behind a reverse proxy, remember to start it with the
command line option `--behind-reverse-proxy true`.  It is necessary for
correct client IP address detection, which rate limiting depends on.  Do
**not** enable `--behind-reverse-proxy` if tinyfts is not behind a reverse
proxy.  It will let clients spoof their IP with the header `X-Real-IP` or
`X-Forwarded-For` and evade rate limiting themselves and rate limit others.


## License

MIT.  [Wapp](https://wapp.tcl.tk/) is copyright (c) 2017 D. Richard Hipp and is
distributed under the Simplified BSD License.
[Tacit](https://github.com/yegor256/tacit) is copyright (c) 2015-2019
Yegor Bugayenko and is distributed under the MIT license.
