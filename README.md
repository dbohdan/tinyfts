# tinyfts

![CI badge](https://github.com/dbohdan/tinyfts/workflows/CI/badge.svg)

A very small standalone full-text search HTTP/SCGI server.

![A screenshot of what the unofficial tinyfts search service for the
Tcler's Wiki looked like](screenshot.png)


## Contents

* [Dependencies](#dependencies)
* [Usage](#usage)
* [Query syntax](#query-syntax)
* [Setup](#setup)
* [Operating notes](#operating-notes)
* [License](#license)


## Dependencies

### Server

* Tcl 8.6
* tclsqlite3 with [FTS5](https://sqlite.org/fts5.html)

### Building, tools, and tests

The above and
* Tcllib
* kill(1), make(1), sqlite3(1)
* tDOM and file(1) to run `tools/dir2json`

On recent Debian and Ubuntu install the dependencies with

```sh
sudo apt install libsqlite3-tcl make sqlite3 tcl tcllib tdom
```

On FreeBSD with sudo install the dependencies with

```sh
sudo pkg install sqlite3 tcl-sqlite3 tcl86 tcllib tdom
cd /usr/local/bin
sudo ln -s tclsh8.6 tclsh
```


## Usage

```none
Usage:
    tinyfts --db-file path [option ...] [wapp-arg ...]
Options:
    --css-file ''
    --credits <HTML>
    --header <HTML>
    --footer <HTML>
    --title tinyfts
    --subtitle <HTML>
    --table tinyfts
    --rate-limit 60
    --result-limit 100
    --log 'access bad-request error rate'
    --behind-reverse-proxy false
    --snippet-size 20
    --title-weight 1000.0
    --query-min-length 2
    --query-syntax web
```


## Query syntax

### Default or "web"

The default full-text search query syntax in tinyfts resembles that of a Web
search engine.  It can handle the following types of expressions.

* `foo` — search for the word *foo*.
* `"foo bar"` — search for the phrase *foo bar*.
* `foo AND bar`, `foo OR bar`, `NOT foo` — search for both *foo* and *bar*, at
least one of *foo* and *bar*, documents without *foo* respectively.
*foo AND bar* is identical to *foo bar*.  The operators *AND*, *OR*, and *NOT*
must be in all caps.
* `-foo`, `-"foo bar"` — the same as `NOT foo`, `NOT "foo bar"`.

### FTS5

You can allow your users to write full
[FTS5 queries](https://www.sqlite.org/fts5.html#full_text_query_syntax)
with the command line option `--query-syntax fts5`.  FTS5 queries are more
powerful but expose the technical details of the underlying database.  (For
example, the column names.)  Users who are unfamiliar with the FTS5 syntax
will find it surprising and run into errors because they did not quote a word
that has a special meaning.


## Setup

Tinyfts searches the contents of an SQLite database table with a particular
schema.  The bundled import tool `tools/import` can import serialized data
(text files with one JSON object or Tcl dictionary per line) and wiki pages
from a [Wikit](https://wiki.tcl-lang.org/page/Wikit)/Nikit database into
a tinyfts database.

### Example

This example shows how to set up search for a backup copy of the
[Tcler's Wiki](https://wiki.tcl-lang.org/page/About+the+WIki).  The
instructions should work on most Linux distributions and FreeBSD with the
dependencies and Git installed.

1\. Go to <https://sourceforge.net/project/showfiles.php?group_id=211498>.
Download and extract the last Wikit  database snapshot of the Tcler's Wiki.
Currently that is `wikit-20141112.zip`.  Let's assume you have extracted the
database file to `~/Downloads/wikit.tkd`.

2\. Download, build, and test tinyfts.  In this example we use Git to get the
latest development version.

```sh
git clone https://github.com/dbohdan/tinyfts
cd tinyfts
make
```

3\. Create a tinyfts search database from the Tcler's Wiki database.  The
repository includes an import tool that supports Wikit databases.  Depending
on your hardware, this may take up to several minutes with an input database
size in the hundreds of megabytes.

```sh
./tools/import wikit ~/Downloads/wikit.tkd /tmp/fts.sqlite3
```

4\. Start tinyfts on <http://localhost:8080>.  The server URL should open
automatically in your browser.  Try searching.

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

MIT.  [Wapp](https://wapp.tcl.tk/) is copyright (c) 2017-2022 D. Richard Hipp
and is distributed under the Simplified BSD License.
[Tacit](https://github.com/yegor256/tacit) is copyright (c) 2015-2020
Yegor Bugayenko and is distributed under the MIT license.
