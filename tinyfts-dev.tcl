#! /usr/bin/env tclsh
# tinyfts: a very small standalone full-text search HTTP server.
# ==============================================================================
# Copyright (c) 2019, 2020 D. Bohdan and contributors listed in AUTHORS
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

package require Tcl 8.6
package require sqlite3 3.9


### Configuration and globals

set state {
    css {}

    flags {
        hide db-file
        html-value {header footer subtitle}
    }

    rate {}
    version 0.3.0
}

set config {
    db-file {}

    css-file {}

    header {
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
            <title>$documentTitle</title>
            <link rel="stylesheet" type="text/css" href="/css">
        </head>
        <body>
    }

    footer {
        </body>
        </html>
    }

    title {
        tinyfts
    }

    subtitle {
        Full-text search.
        <a href="https://www.sqlite.org/fts5.html#full_text_query_syntax">Query
        syntax</a>.
    }

    table tinyfts

    min-length 2

    rate-limit 60

    result-limit 100

    log {
        access
        bad-request
        error
        rate
    }

    behind-reverse-proxy false

    snippet-size 20

    title-weight 1000.0

    query-dialect web
}


proc accessor {name varName} {
    namespace eval $name [format {
        proc get args {
            return [dict get $%1$s {*}$args]
        }


        proc get-default {default args} {
            if {[dict exists $%1$s {*}$args]} {
                return [dict get $%1$s {*}$args]
            } else {
                return $default
            }
        }


        proc set args {
            dict set %1$s {*}$args
        }


        proc update args {
            ::set updateScript [lindex $args end]
            ::set args [lrange $args 0 end-1]
            ::set updated [uplevel 1 [list {*}$updateScript \
                                           [dict get $%1$s {*}$args]]]
            dict set %1$s {*}$args $updated
        }
    } [list $varName]]
}


accessor config ::config
accessor state ::state


proc log {type {message {}}} {
    if {$type ni [config::get log]} return

    set timestamp [clock format [clock seconds] \
                                -format %Y-%m-%dT%H:%M:%SZ \
                                -timezone :Etc/UTC \
    ]

    puts \{[list \
        timestamp $timestamp \
        type $type \
        caller [dict get [info frame -1] proc] \
        message $message \
        remote [real-remote] \
        url [join [list [wapp-param SELF_URL] [wapp-param PATH_TAIL]] /] \
        query-string [wapp-param QUERY_STRING] \
        user-agent [wapp-param HTTP_USER_AGENT] \
    ]\}
}


proc real-remote {} {
    if {[config::get behind-reverse-proxy]} {
        return [wapp-param .hdr:X-REAL-IP [wapp-param .hdr:X-FORWARDED-FOR {}]]
    } else {
        return [wapp-param REMOTE_ADDR]
    }
}


proc gensym {} {
    return [format sym-%u-%08x \
                   [clock seconds] \
                   [expr {int(4294967296*rand())}]]
}


### Views

namespace eval view {
    namespace import ::config
}


proc view::header pageTitle {
    set documentTitle [config::get title]
    if {$pageTitle ne {}} {
        set documentTitle "$pageTitle | $documentTitle"
    }

    set map [list \$documentTitle [wappInt-enc-html $documentTitle]]
    wapp-unsafe [string map $map [config::get header]]
}


proc view::footer {} {
    wapp-unsafe [config::get footer]
}


proc view::form query {
    wapp-trim {
        <form action="/search">
            <input type="text" name="query" value="%html($query)">
            <input type="submit" value="Search">
        </form>
    }
}


proc view::default {} {
    header {}
    wapp-trim {
        <header>
            <h1>%html([config::get title])</h1>
            <p>%unsafe([config::get subtitle])</p>
        </header>
        <main>
    }
    form {}
    wapp </main>
    footer
}


namespace eval view::error {
    namespace path [namespace parent]
}


proc view::error::html {code message} {
    wapp-reply-code $code

    header {}
    wapp-trim {<header><h1>Error</h1><p>%html($message)</p></header>}
    footer
}


proc view::error::json {code message} {
    wapp-mimetype application/json
    wapp-reply-code $code

    wapp-trim {{"error": "%string($message)"}}
}


proc view::error::tcl {code message} {
    wapp-mimetype text/plain
    wapp-reply-code $code

    wapp-trim [list error $message]
}


namespace eval view::results {
    namespace path [namespace parent]
}


proc view::results::extract-marked {startMarker endMarker text} {
    set re (.*?)${startMarker}(.*?)${endMarker}

    set all {}

    set start 0
    while {[regexp -start $start -indices $re $text _ before marked]} {
        lappend all [string range $text {*}$before] \
                    [string range $text {*}$marked]

        set start [expr {[lindex $marked 1] + [string length $endMarker] + 1}]
    }

    set remainder [string range $text $start end]
    if {$remainder ne {}} {
        lappend all $remainder {}
    }

    return $all
}


proc view::results::html {query startMatch endMatch results counter} {
    header $query
    wapp \n<main>
    form $query
    wapp-subst {\n<ol start="%html($counter)">\n}

    foreach result $results {
        set date [clock format [dict get $result modified] \
                                -format {%Y-%m-%d} \
                                -timezone :Etc/UTC]
        wapp-trim {
            <li>
                <dl>
                    <dt>
                        <a href="%html([dict get $result url])">
                            %html([dict get $result title])</a>
                        (modified %html($date))
                    </dt>
                </dl>
                <dd>
        }

        set marked [extract-marked $startMatch \
                                   $endMatch \
                                   [dict get $result snippet]]
        foreach {before marked} $marked {
            wapp-trim {
                %html($before)<strong>%html($marked)</strong>
            }
        }

        wapp-trim </dd>\n</li>
    }

    wapp-trim </ol>
    if {[llength $results] == 0} {
        wapp-trim {No results.}
    }
    wapp-trim </main>

    if {[llength $results] == [config::get result-limit]} {
        set next [dict get [lindex $results end] rank]
        set nextCounter [expr {$counter + [llength $results]}]
        wapp \n<footer>\n
        wapp-subst {<a href="/search?query=%html($query)&start=%html($next)}
        wapp-subst {&counter=%html($nextCounter)">Next page</a>}
        wapp \n</footer>\n
    }

    footer
}


proc view::results::json {query startMatch endMatch results} {
    wapp-mimetype application/json

    wapp \{\n

    if {[llength $results] == [config::get result-limit]} {
        set next [dict get [lindex $results end] rank]
        wapp-subst {"next": "%unsafe([string-to-json $next])",\n}
    }

    wapp {"results": [}
    set first true
    foreach result $results {
        if {!$first} {
            wapp ,
        }
        wapp \{\n

        foreach key {url title modified} {
            set jsonValue [string-to-json [dict get $result $key]]
            wapp-subst {    "%unsafe($key)": "%unsafe($jsonValue)",\n}
        }

        set marked [extract-marked $startMatch \
                                   $endMatch \
                                   [dict get $result snippet]]
        wapp {    "snippet": [}
        set firstMarked true
        foreach x $marked {
            if {!$firstMarked} {
                wapp ,
            }
            wapp-subst {"%unsafe([string-to-json $x])"}

            set firstMarked false
        }
        wapp \]\n\}

        set first false
    }

    wapp \]\}\n
}


proc view::results::string-to-json s {
    return [string map {
        \x00 \\u0000
        \x01 \\u0001
        \x02 \\u0002
        \x03 \\u0003
        \x04 \\u0004
        \x05 \\u0005
        \x06 \\u0006
        \x07 \\u0007
        \x08 \\b
        \x09 \\t
        \x0a \\n
        \x0b \\u000b
        \x0c \\f
        \x0d \\r
        \x0e \\u000e
        \x0f \\u000f
        \x10 \\u0010
        \x11 \\u0011
        \x12 \\u0012
        \x13 \\u0013
        \x14 \\u0014
        \x15 \\u0015
        \x16 \\u0016
        \x17 \\u0017
        \x18 \\u0018
        \x19 \\u0019
        \x1a \\u001a
        \x1b \\u001b
        \x1c \\u001c
        \x1d \\u001d
        \x1e \\u001e
        \x1f \\u001f
        \" \\\"
        \\ \\\\
        </  <\\/
    } [encoding convertto utf-8 $s]]
}


proc view::results::tcl {query startMatch endMatch results} {
    wapp-mimetype text/plain

    if {[llength $results] == [config::get result-limit]} {
        set next [dict get [lindex $results end] rank]
        wapp-unsafe [list next $next]\n
    }

    wapp "results \{"

    set first true
    foreach result $results {
        if {!$first} {
            wapp { }
        }
        wapp \{\n

        foreach key {url title modified} {
            wapp-unsafe "    $key [list [dict get $result $key]]\n"
        }

        set marked [extract-marked $startMatch \
                                   $endMatch \
                                   [dict get $result snippet]]
        wapp-unsafe "    [list snippet $marked]"

        wapp \n\}

        set first false
    }

    wapp \}\n
}


### Controllers


namespace eval rate-limit {}


proc rate-limit::allow? client {
    set m [expr {[clock seconds] / 60}]

    if {[state::get-default -1 rate $client last] != $m} {
        dict set ::state rate $client last $m
        dict set ::state rate $client count 0

        return 1
    }

    state::update rate $client count {apply {x {
        incr x
    }}}

    set diff [expr {
        [state::get rate $client count] - [config::get rate-limit]
    }]
    if {$diff == 1} {
        log rate {temporarily blocked remote address}
    }
    if {$diff > 0} {
        return 0
    }

    return 1
}


namespace eval translate-query {}


proc translate-query::fts5 query {
    return $query
}


proc translate-query::web query {
    set not {}
    set translated {}

    # A crude query tokenizer.  Doesn't understand escaped double quotes.
    set start 0
    while {[regexp -indices \
                   -start $start \
                   {(?:^|\s)((?:[^\s]+|-?"[^"]*"))} \
                   $query \
                   _ tokenIdx]} {
        set token [string range $query {*}$tokenIdx]
        set start [lindex $tokenIdx 1]+1

        regexp {^(-)?"?(.*?)"?$} $token _ not token
        regsub -all {(\"|\\)} $token {\\\1}

        if {$not ne {}} {
            lappend translated NOT
        }

        if {$token ni {AND NOT OR}} {
            set token \"$token\"
        }

        lappend translated $token
    }

    return [join $translated { }]
}


proc wapp-default {} {
    log access

    view::default
}


proc wapp-page-css {} {
    wapp-mimetype text/css
    wapp-unsafe [state::get css]
}


proc wapp-page-search {} {
    wapp-allow-xorigin-params

    if {![rate-limit::allow? [real-remote]]} {
        wapp-mimetype text/plain
        wapp-reply-code 403

        wapp {Access denied.}

        return
    }

    log access

    set startMatch [gensym]
    set endMatch [gensym]

    set format [wapp-param format html]
    set query [wapp-param query {}]
    set start [wapp-param start -1000000]
    set counter [wapp-param counter 1]

    set translated [translate-query::[config::get query-dialect] $query]

    foreach {badParamCheck msgTemplate} {
        {$format ni {html json tcl}}
        {Unknown format.}

        {[string length [string trim $query]] < [config::get min-length]}
        {Query must be at least [config::get min-length] characters long.}

        {![string is integer -strict $counter] || $counter <= 0}
        {"counter" must be a positive integer.}
    } {
        if $badParamCheck {
            set msg [subst $msgTemplate]
            view::error::html 400 $msg
            log bad-request $msg

            return
        }
    }

    set results {}
    try {
        set selectStatement [format {
            SELECT
                url,
                title,
                modified,
                snippet(
                    "%1$s",
                    3,
                    :startMatch,
                    :endMatch,
                    '...',
                    %3$u
                ) AS snippet,
                rank
            FROM "%1$s"
            WHERE
                "%1$s" MATCH :translated AND
                -- Column weight: url, title, modified, content.
                rank MATCH 'bm25(0.0, %3$f, 0.0, 1.0)' AND
                rank > CAST(:start AS REAL)
            ORDER BY rank ASC
            LIMIT %2$u
        } [config::get table] \
          [config::get result-limit] \
          [config::get snippet-size] \
          [config::get title-weight]]

        db eval $selectStatement values {
            lappend results [array get values]
        }
    } on error {msg _} {
        regsub ^fts5: $msg {Invalid query:} msg

        view::error::$format 400 $msg
        log error $msg

        return
    }

    set viewArgs [list $query $startMatch $endMatch $results]
    if {$format eq {html}} {
        lappend viewArgs $counter
    }
    view::results::$format {*}$viewArgs
}


### CLI


namespace eval cli {
    namespace import ::config
}


proc cli::read-file args {
    if {[llength $args] == 0} {
        error "wrong # args: should be \"read-file ?options? path"
    }

    set path [lindex $args end]
    set options [lrange $args 0 end-1]

    set ch [open $path r]
    fconfigure $ch {*}$options
    set data [read $ch]
    close $ch

    return $data
}


proc cli::usage me {
    set padding {   }
    puts stderr "Usage:\n$padding $me --db-file path\
                 \[option ...\] \[wapp-arg ...\]"
    puts stderr Options:

    dict for {k v} $::config {
        if {$k in [state::get flags hide]} continue

        if {$k in [state::get flags html-value]} {
            set default <HTML>
        } else {
            set default [list {*}$v]
            if {$default eq {} || [regexp {\s} $default]} {
                set default '$default'
            }
        }

        puts stderr "$padding --$k $default"
    }
}


proc cli::start {argv0 argv} {
    if {$argv in {-v -version --version}} {
        puts stderr [state::get version]
        exit 0
    }

    if {$argv in {/? -? -h -help --help}} {
        usage $argv0
        exit 0
    }

    try {
        cd [file dirname [info script]]

        set wappArgs {}
        foreach {flag v} $argv {
            regsub ^--? $flag {} k

            if {[dict exists $::config $k]} {
                dict set ::config $k $v
            } else {
                lappend wappArgs $flag $v
            }
        }

        if {[config::get db-file] eq {}} {
            error {no --db-file given}
        }

        sqlite3 db [config::get db-file] -create false -readonly true

        if {[config::get css-file] eq {}} {
            # Only read the default CSS file if no CSS is not already loaded
            # (like it is in a bundle).
            if {[state::get-default {} css] eq {}} {
                state::set css [read-file vendor/tacit/tacit-css.min.css]
            }
        } else {
            state::set css [read-file [config::get css-file]]
        }

        try {
            package present wapp
        } trap {TCL LOOKUP PACKAGE wapp} _ {
            uplevel 1 {source vendor/wapp/wapp.tcl}
        }

        wapp-start $wappArgs
    } on error {msg opts} {
        puts stderr "startup error: [dict get $opts -errorinfo]"
        exit 1
    }
}


# If this is the main script...
if {[info exists argv0] && ([file tail [info script]] eq [file tail $argv0])} {
    cli::start $argv0 $argv
}
