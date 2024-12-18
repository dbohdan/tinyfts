#! /usr/bin/env tclsh
# tinyfts: a very small standalone full-text search HTTP server.
# ==============================================================================
# Copyright (c) 2019-2022, 2024 D. Bohdan
# and contributors listed in AUTHORS
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

package require Tcl 8.6 9
package require sqlite3 3.9


### Configuration and globals

if {![info exists state]} {
    set state {}
}
set state [dict merge {
    css {}

    flags {
        hide db-file

        html-value {credits header footer subtitle}

        validator {
            query-syntax {
                set validSyntaxes [lmap x [info commands translate-query::*] {
                    namespace tail $x
                }]

                if {$value ni $validSyntaxes} {
                    error [list invalid query syntax: $value]
                }
            }
        }
    }

    rate {}
    version 0.8.0
} $state]

set config {
    db-file {}

    css-file {}

    credits {Powered by <a\
        href="https://github.com/dbohdan/tinyfts">tinyfts</a>}

    header {<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
    <title>$documentTitle</title>
    <link rel="stylesheet" type="text/css" href="/css">
</head>
<body>
}

    footer {</body>
</html>
}

    title tinyfts

    subtitle {Full-text search.}

    table tinyfts

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

    query-min-length 2

    query-syntax web
}


proc accessor {name varName} {
    namespace eval $name [format {
        proc exists args {
            return [dict exists $%1$s {*}$args]
        }


        proc for {varNames body} {
            uplevel 1 [list dict for $varNames $%1$s $body]
        }


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

namespace eval view {}
foreach ns {html json tcl} {
    namespace eval view::$ns {
        namespace path [namespace parent]
    }
}
unset ns


proc view::extract-marked {startMarker endMarker text} {
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


proc view::html::header pageTitle {
    set documentTitle [config::get title]
    if {$pageTitle ne {}} {
        set documentTitle "$pageTitle | $documentTitle"
    }

    set map [list \$documentTitle [wappInt-enc-html $documentTitle]]
    wapp-unsafe [string map $map [config::get header]]
}


proc view::html::footer {} {
    wapp-unsafe [config::get footer]
}


proc view::html::credits {} {
    set credits [config::get credits]
    if {$credits ne {}} {
        wapp-unsafe <footer><p>$credits</p></footer>
    }
}


proc view::html::form query {
    wapp-trim {
        <form action="/search">
            <input type="search" name="query" value="%html($query)">
            <input type="submit" value="Search">
        </form>
    }
}


proc view::html::default {} {
    header {}
    wapp-trim {
        <header>
            <h1>%html([config::get title])</h1>
            <p>%unsafe([config::get subtitle])</p>
        </header>
    }
    wapp \n<main>\n
    form {}
    wapp \n</main>\n
    credits
    footer
}


proc view::html::error {code message} {
    wapp-reply-code $code

    header {}
    wapp-subst {<header><h1>Error</h1><p>%html($message)</p></header>\n}
    credits
    footer
}


proc view::html::results {query startMatch endMatch results counter} {
    header $query
    wapp <main>\n
    form $query
    wapp-subst {\n<ol start="%html($counter)">\n}

    foreach result $results {
        set date [clock format [dict get $result timestamp] \
                                -format {%Y-%m-%d} \
                                -timezone :Etc/UTC]
        wapp-trim {
            <li>
                <dl>
                    <dt>
                        <a href="%html([dict get $result url])">
                            %html([dict get $result title])
                        </a>
                        (%html($date))
                    </dt>
                    <dd>
        }
        wapp \n

        set marked [extract-marked $startMatch \
                                   $endMatch \
                                   [dict get $result snippet]]
        foreach {before marked} $marked {
            wapp-subst {%html($before)<strong>%html($marked)</strong>}
        }

        wapp \n</dd>\n</dl>\n</li>\n
    }

    wapp </ol>\n
    if {[llength $results] == 0} {
        wapp "No results.\n"
    }

    if {[llength $results] == [config::get result-limit]} {
        set next [dict get [lindex $results end] rank]
        set nextCounter [expr {$counter + [llength $results]}]
        wapp-subst {<p><a class="next-page" href="/search?query=%html($query)}
        wapp-subst {&amp;start=%html($next)}
        wapp-subst {&amp;counter=%html($nextCounter)">Next page</a></p>\n}
    }

    wapp </main>\n
    credits
    footer
}

proc view::json::error {code message} {
    wapp-mimetype application/json
    wapp-reply-code $code

    wapp-subst {{"error": "%string($message)"}}
}


proc view::json::results {query startMatch endMatch results} {
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

        foreach key {url title timestamp} {
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


proc view::json::string-to-json s {
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


proc view::tcl::error {code message} {
    wapp-mimetype text/plain
    wapp-reply-code $code

    wapp-trim [list error $message]
}


proc view::tcl::results {query startMatch endMatch results} {
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

        foreach key {url title timestamp} {
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
        state::set rate $client last $m
        state::set rate $client count 0

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

    # A crude query tokenizer. Doesn't understand escaped double quotes.
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

    view::html::default
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

    set translated [translate-query::[config::get query-syntax] $query]

    foreach {badParamCheck msgTemplate} {
        {$format ni {html json tcl}}
        {Unknown format.}

        {[string length [string trim $query]] < [config::get query-min-length]}
        {Query must be at least [config::get query-min-length] characters long.}

        {![string is integer -strict $counter] || $counter <= 0}
        {"counter" must be a positive integer.}
    } {
        if $badParamCheck {
            set msg [subst $msgTemplate]
            view::html::error 400 $msg
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
                timestamp,
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
                -- Column weight: url, title, timestamp, content.
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

        view::${format}::error 400 $msg
        log error $msg

        return
    }

    set viewArgs [list $query $startMatch $endMatch $results]
    if {$format eq {html}} {
        lappend viewArgs $counter
    }
    view::${format}::results {*}$viewArgs
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

    config::for {k v} {
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
        set wappArgs {}
        foreach {flag v} $argv {
            regsub ^--? $flag {} k

            if {[config::exists $k]} {
                set validator [state::get-default {} flags validator $k]
                apply [list value $validator] $v

                config::set $k $v
            } else {
                lappend wappArgs $flag $v
            }
        }

        if {[config::get db-file] eq {}} {
            error {no --db-file given}
        }

        sqlite3 db [config::get db-file] -create false -readonly true
        cd [file dirname [info script]]

        if {[config::get css-file] eq {}} {
            # Only read the default CSS file if no CSS is not already loaded
            # (like it is in a bundle).
            if {[state::get-default {} css] eq {}} {
                state::set css [read-file vendor/tacit/tacit.css]
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
