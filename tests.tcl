#! /usr/bin/env tclsh
# ==============================================================================
# Copyright (c) 2019 D. Bohdan and contributors listed in AUTHORS
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
package require json 1
package require tcltest 2
package require textutil

cd [file dirname [info script]]

set td(sample) {
    {
        url https://fts.example.com/foo
        title Foo
        modified 1
        content {Now this is a story}
    }
    {
        url https://fts.example.com/bar
        title Bar
        modified 2
        content {all about how}
    }
    {
        url https://fts.example.com/baz
        title Baz
        modified 3
        content {My life got flipped turned upside down}
    }
    {
        url https://fts.example.com/qux
        title Qux
        modified 4
        content {Don't quote}
    }
    {
        url https://fts.example.com/quux
        title Quux
        modified 5
        content {too much}
    }
}


proc curl args {
    exec curl --silent {*}$args 2>@1
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


tcltest::test tools-import-1.1 {} -body {
    tclsh tools/import tcl - $td(dbFile) << $td(sample)
} -cleanup $td(cleanup) -result {}

tcltest::test tools-import-1.2 {} -cleanup $td(cleanup) -body {
    tclsh tools/import tcl - $td(dbFile) --table blah \
          << $td(sample)

    exec sqlite3 $td(dbFile) .schema
} -match glob -result {*CREATE VIRTUAL TABLE "blah"*USING fts5*}

tcltest::test tools-import-1.3 {} -cleanup $td(cleanup) -body {
    tclsh tools/import tcl - $td(dbFile) --url-prefix http://example.com/ \
          << $td(sample)

    exec sqlite3 $td(dbFile) {SELECT url FROM tinyfts LIMIT 2}
} -match glob -result https://fts.example.com/foo\nhttps://fts.example.com/bar

tcltest::test tools-import-2.1 {} -cleanup $td(cleanup) -body {
    tclsh tools/import tcl /tmp/this/file/does/not/exit $td(dbFile)
} -returnCodes 1 -match glob -result {*Cannot read file*}

tcltest::test tools-import-2.2 {} -cleanup $td(cleanup) -body {
    tclsh tools/import nikit $td(dbFile) $td(dbFile)
} -returnCodes 1 -match glob -result {*unable to open database file*}

tcltest::test tools-import-2.3 {} -cleanup $td(cleanup) -body {
    tclsh tools/import tcl - $td(dbFile) << \x00\x01\x02\x03\x04\x05\x06\x07
} -returnCodes 1 -match glob -result *


set td(port) [expr 8000+int(rand()*1000)]
tclsh tools/import tcl - $td(dbFile) << $td(sample)
set td(pid) [tclsh tinyfts --db-file $td(dbFile) \
                           --server $td(port) \
                           --title Hello \
                           --subtitle World \
                           --rate-limit 10 \
                           --result-limit 3 \
                           --min-length 3 \
                           --log {} \
                           & \
]
for {set i 0} {$i < 10} {incr i} {
    try {
        curl http://127.0.0.1:$td(port)
    } on ok _ break on error _ {}
    after [expr {$i * 10}]
}
unset i


tcltest::test default-1.1 {} -body {
    curl http://127.0.0.1:$td(port)/
} -match glob -result {*<form action="/search">*}


set td(query) http://127.0.0.1:$td(port)/search/?query


tcltest::test search-1.1 {HTML result} -body {
    curl $td(query)=foo
} -match glob -result {*Foo*modified 1970-01-01*Now this is a story*}

tcltest::test search-1.2 {JSON result} -body {
    json::json2dict [curl $td(query)=foo&format=json]
} -result {results {{url https://fts.example.com/foo\
                     title Foo\
                     modified 1\
                     snippet {{Now this is a story} {}}}}}

tcltest::test search-1.3 {Tcl result} -cleanup {unset raw} -body {
    set raw [curl $td(query)=foo&format=tcl]
    dict create {*}[lindex [dict get $raw results] 0]
} -result {url https://fts.example.com/foo\
           title Foo\
           modified 1\
           snippet {{Now this is a story} {}}}

tcltest::test search-1.4 {3 results} -cleanup {unset raw} -body {
    set raw [curl $td(query)=fts+NOT+Qu*&format=tcl]
    lsort [lmap x [dict get $raw results] {
        dict get $x title
    }]
} -result {Bar Baz Foo}

tcltest::test search-1.5 {Pagination} -cleanup {
    unset next raw1 raw2
} -body {
    set raw1 [curl $td(query)=fts&format=tcl]
    set next [dict get $raw1 next]
    set raw2 [curl $td(query)=fts&format=tcl&start=$next]

    lsort [lmap x [concat [dict get $raw1 results] [dict get $raw2 results]] {
        dict get $x title
    }]
} -result {Bar Baz Foo Quux Qux}

tcltest::test search-1.6 {Document title} -body {
    curl $td(query)=foo&format=html
} -match glob -result {*<title>foo | Hello</title>*}


tcltest::test search-2.1 {No results} -body {
    curl $td(query)=111
} -match glob -result {*No results.*}

tcltest::test search-2.2 {Unknown format} -body {
    curl $td(query)=foo&format=bar
} -match glob -result {*Unknown format.*}

tcltest::test search-2.3 {Short query} -body {
    curl $td(query)=xy
} -match glob -result {*Query must be at least 3 characters long.*}


kill $td(pid)
file delete $td(dbFile)


# Exit with a nonzero status if there are failed tests.
set failed [expr {$tcltest::numTests(Failed) > 0}]

tcltest::cleanupTests
if {$failed} {
    exit 1
}
