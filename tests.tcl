#! /usr/bin/env tclsh
# ==============================================================================
# Copyright (c) 2019-2021 D. Bohdan and contributors listed in AUTHORS
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
# ==============================================================================

package require fileutil 1
package require http 2
package require json 1
package require tcltest 2
package require textutil

cd [file dirname [info script]]

set td(json-sample) [string map [list \n\n \n \n {}] {
    {
        "url": "https://fts.example.com/foo",
        "title": "Foo",
        "modified": 1,
        "content": "Now this is a story UNO"
    }

    {
        "url": "https://fts.example.com/bar",
        "title": "Bar",
        "modified": 2,
        "content": "all about how UNO"
    }

    {
        "url": "https://fts.example.com/baz",
        "title": "Baz",
        "modified": 3,
        "content": "My life got flipped turned upside down UNO"
    }

    {
        "url": "https://fts.example.com/qux",
        "title": "Qux",
        "modified": 4,
        "content": "Don't quote UNO"
    }

    {
        "url": "https://fts.example.com/quux",
        "title": "Quux",
        "modified": 5,
        "content": "too much ウノ УНО UNO"
    }
}]

set td(tcl-sample) [join [lmap line [split $td(json-sample) \n] {
    json::json2dict $line
}] \n]


proc fetch args {
    try {
        set token [http::geturl {*}$args]
        http::data $token
    } finally {
        catch { http::cleanup $token }
    }
}


proc kill pid {
    exec kill $pid
}


proc tclsh args {
    exec [info nameofexecutable] {*}$args
}


close [file tempfile td(dbFile) .sqlite3]
tcltest::makeFile {} $td(dbFile)


set td(cleanup) {
    file delete $td(dbFile)
}


### Unit: tinyfts.

source tinyfts

tcltest::test translate-query-1.1 {} -body {
    translate-query::web {hello "very strange" world -foo -"foo bar"}
} -result {"hello" "very strange" "world" NOT "foo" NOT "foo bar"}

tcltest::test translate-query-1.2 {} -body {
    translate-query::web {foo bar OR baz}
} -result {"foo" "bar" OR "baz"}

tcltest::test translate-query-1.3 {} -body {
    translate-query::web foo\\\"bar
} -result \"foo\\\"bar\"



### Integration: tools.

tcltest::test tools-import-1.1.1 {Tcl import} -body {
    tclsh tools/import tcl - $td(dbFile) << $td(tcl-sample)
} -cleanup $td(cleanup) -result {}

tcltest::test tools-import-1.1.2 {Tcl import} -cleanup $td(cleanup) -body {
    tclsh tools/import tcl - $td(dbFile) --table blah \
          << $td(tcl-sample)

    exec sqlite3 $td(dbFile) .schema
} -match glob -result {*CREATE VIRTUAL TABLE "blah"*USING fts5*}

tcltest::test tools-import-1.1.3 {Tcl import} -cleanup $td(cleanup) -body {
    tclsh tools/import tcl - $td(dbFile) --url-prefix http://example.com/ \
          << $td(tcl-sample)

    exec sqlite3 $td(dbFile) {SELECT url FROM tinyfts LIMIT 2}
} -match glob -result https://fts.example.com/foo\nhttps://fts.example.com/bar


tcltest::test tools-import-1.2.1 {JSON import} -body {
    tclsh tools/import json - $td(dbFile) << $td(json-sample)
} -cleanup $td(cleanup) -result {}

tcltest::test tools-import-1.2.2 {JSON import} -cleanup $td(cleanup) -body {
    tclsh tools/import json - $td(dbFile) --table blah \
          << $td(json-sample)

    exec sqlite3 $td(dbFile) .schema
} -match glob -result {*CREATE VIRTUAL TABLE "blah"*USING fts5*}

tcltest::test tools-import-1.2.3 {JSON import} -cleanup $td(cleanup) -body {
    tclsh tools/import json - $td(dbFile) --url-prefix http://example.com/ \
          << $td(json-sample)

    exec sqlite3 $td(dbFile) {SELECT url FROM tinyfts LIMIT 2}
} -match glob -result https://fts.example.com/foo\nhttps://fts.example.com/bar


tcltest::test tools-import-2.1 {} -cleanup $td(cleanup) -body {
    tclsh tools/import tcl /tmp/this/file/does/not/exit $td(dbFile)
} -returnCodes 1 -match glob -result {*no such file*}

tcltest::test tools-import-2.2 {} -cleanup $td(cleanup) -body {
    tclsh tools/import nikit $td(dbFile) $td(dbFile)
} -returnCodes 1 -match glob -result {*unable to open database file*}

tcltest::test tools-import-2.3 {} -cleanup $td(cleanup) -body {
    tclsh tools/import tcl - $td(dbFile) << \x00\x01\x02\x03\x04\x05\x06\x07
} -returnCodes 1 -match glob -result *


### Integration: tinyfts.

set td(port) [expr 8000+int(rand()*1000)]
tclsh tools/import tcl - $td(dbFile) << $td(tcl-sample)
set td(pid) [tclsh tinyfts --db-file $td(dbFile) \
                           --server $td(port) \
                           --title Hello \
                           --subtitle World \
                           --rate-limit 20 \
                           --result-limit 3 \
                           --query-min-length 2 \
                           --log {} \
                           & \
]
for {set i 0} {$i < 10} {incr i} {
    try {
        fetch http://127.0.0.1:$td(port)
    } on ok _ break on error _ {}
    after [expr {$i * 10}]
}
unset i


tcltest::test default-1.1 {} -body {
    fetch http://127.0.0.1:$td(port)/
} -match glob -result {*<form action="/search">*}


set td(query) http://127.0.0.1:$td(port)/search/?query


tcltest::test search-1.1 {HTML result} -body {
    fetch $td(query)=foo
} -match glob -result {*Foo*modified 1970-01-01*Now this is a story*}

tcltest::test search-1.2 {JSON result} -body {
    json::json2dict [fetch $td(query)=foo&format=json]
} -result {results {{url https://fts.example.com/foo\
                     title Foo\
                     modified 1\
                     snippet {{Now this is a story UNO} {}}}}}

tcltest::test search-1.3 {Tcl result} -cleanup {unset raw} -body {
    set raw [fetch $td(query)=foo&format=tcl]
    dict create {*}[lindex [dict get $raw results] 0]
} -result {url https://fts.example.com/foo\
           title Foo\
           modified 1\
           snippet {{Now this is a story UNO} {}}}

tcltest::test search-1.4 {3 results} -cleanup {unset raw} -body {
    set raw [fetch $td(query)=fts+NOT+Qu*&format=tcl]
    lsort [lmap x [dict get $raw results] {
        dict get $x title
    }]
} -result {Bar Baz Foo}

tcltest::test search-1.5 {Pagination} -cleanup {
    unset next raw1 raw2
} -body {
    set raw1 [fetch $td(query)=uno&format=tcl]
    set next [dict get $raw1 next]
    set raw2 [fetch $td(query)=uno&format=tcl&start=$next]

    lsort [lmap x [concat [dict get $raw1 results] [dict get $raw2 results]] {
        dict get $x title
    }]
} -result {Bar Baz Foo Quux Qux}

tcltest::test search-1.6 {Document title} -body {
    fetch $td(query)=foo&format=html
} -match glob -result {*<title>foo | Hello</title>*}


tcltest::test search-1.7.1 {Unicode HTML} -body {
    fetch $td(query)=quux&format=html
} -match glob -result {*ウノ УНО UNO*}

tcltest::test search-1.7.2 {Unicode JSON} -body {
    encoding convertfrom utf-8 [fetch $td(query)=quux&format=json]
} -match glob -result {*ウノ УНО UNO*}

tcltest::test search-1.8.1 {Unicode HTML: "ウノ"} -body {
    fetch $td(query)=%E3%82%A6%E3%83%8E&format=html
} -match glob -result {*<strong>ウノ</strong>*}

tcltest::test search-1.8.2 {Unicode JSON: "ウノ"} -body {
    encoding convertfrom utf-8 [fetch \
        $td(query)=%E3%82%A6%E3%83%8E&format=json \
    ]
} -match glob -result {*,"ウノ",*}

tcltest::test search-1.9.1 {Unicode HTML: "УНО"} -body {
    fetch $td(query)=%D0%A3%D0%9D%D0%9E&format=html
} -match glob -result {*<strong>УНО</strong>*}

tcltest::test search-1.9.2 {Unicode JSON: "УНО"} -body {
    encoding convertfrom utf-8 [fetch \
         $td(query)=%D0%A3%D0%9D%D0%9E&format=json \
    ]
} -match glob -result {*,"УНО",*}

tcltest::test search-1.10.1 {Unicode HTML: "уно"} -body {
    fetch $td(query)=%D1%83%D0%BD%D0%BE&format=html
} -match glob -result {*<strong>УНО</strong>*}

tcltest::test search-1.10.2 {Unicode JSON: "уно"} -body {
    encoding convertfrom utf-8 [fetch \
         $td(query)=%D1%83%D0%BD%D0%BE&format=json \
    ]
} -match glob -result {*,"УНО",*}


tcltest::test search-2.1 {No results} -body {
    fetch $td(query)=111
} -match glob -result {*No results.*}

tcltest::test search-2.2 {Unknown format} -body {
    fetch $td(query)=foo&format=bar
} -match glob -result {*Unknown format.*}

tcltest::test search-2.3 {Short query} -body {
    fetch $td(query)=x
} -match glob -result {*Query must be at least 2 characters long.*}

tcltest::test search-2.4 {Hit rate limit} -cleanup {unset i result} -body {
    for {set i 0} {$i < 20} {incr i} {
        set result [fetch $td(query)=nope]
    }
    set result
} -result {Access denied.}


kill $td(pid)
file delete $td(dbFile)


# Exit with a nonzero status if there are failed tests.
set failed [expr {$tcltest::numTests(Failed) > 0}]

tcltest::cleanupTests
if {$failed} {
    exit 1
}
