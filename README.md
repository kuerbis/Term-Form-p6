[![Build Status](https://travis-ci.org/kuerbis/Term-Form-p6.svg?branch=master)](https://travis-ci.org/kuerbis/Term-Form-p6)

NAME
====

Term::Form - Read lines from STDIN.

SYNOPSIS
========

    use Term::Form :readline, :fillform;

    my @aoa = (
        [ 'name'           ],
        [ 'year'           ],
        [ 'color', 'green' ],
        [ 'city'           ]
    );


    # Functional interface:

    my $line = readline( 'Prompt: ', default<abc> );

    my @filled_form = fillform( @aoa, :auto-up( 0 ) );


    # OO interface:

    my $new = Term::Form.new();

    $line = $new.readline( 'Prompt: ', :default<abc> );

    @filled_form = $new.fillform( @aoa, :auto-up( 0 ) );

DESCRIPTION
===========

`readline` reads a line from STDIN. As soon as `Return` is pressed `readline` returns the read string without the newline character - so no `chomp` is required.

`fillform` reads a list of lines from STDIN.

Keys
----

`BackSpace` or `Strg-H`: Delete the character behind the cursor.

`Delete` or `Strg-D`: Delete the character at point. Return nothing if the input puffer is empty.

`Strg-U`: Delete the text backward from the cursor to the beginning of the line.

`Strg-K`: Delete the text from the cursor to the end of the line.

`Right-Arrow`: Move forward a character.

`Left-Arrow`: Move back a character.

`Home` or `Strg-A`: Move to the start of the line.

`End` or `Strg-E`: Move to the end of the line.

Only in `fillform`:

`Up-Arrow`: Move up one row.

`Down-Arrow`: Move down one row.

`Page-Up` or `Strg-B`: Move back one page.

`Page-Down` or `Strg-F`: Move forward one page.

CONSTRUCTOR
===========

The constructor method `new` can be called with named arguments. For the valid options see [#OPTIONS](#OPTIONS). Setting the options in `new` overwrites the default values for the instance.

Additionally to the options mentioned below one can set the option [win](win). The opton [win](win) expects as its value a `WINDOW` object - the return value of [NCurses](NCurses) `initscr`.

If set, `readline` and `fillform` use this global window instead of creating their own without calling `endwin` to restores the terminal before returning.

ROUTINES
========

readline
--------

`readline` reads a line from STDIN.

The fist argument is the prompt string.

With the following arguments one can set the different options or instead it can be passed the default value (see option *default*) as string.

The options are

  * default

Set a initial value of input.

  * no-echo

    * if set to `0`, the input is echoed on the screen.

    * if set to `1`, "`*`" are displayed instead of the characters.

    * if set to `2`, no output is shown apart from the prompt string.

default: `0`

  * header

With the option *header* it can be set a header-string which is shown on top of the output.

fillform
--------

`fillform` reads a list of lines from STDIN.

The first argument is an array of arrays. The arrays have 1 or 2 elements: the first element is the key and the optional second element is the value. The key is used as the prompt string for the "readline", the value is used as the default value for the "readline" (initial value of input).

With the following arguments it can be set theses options:

  * header

With the option *header* it can be set a header-string which is shown on top of the output.

default: undefined

  * auto-up

With *auto-up* set to `0` or `1` pressing `ENTER` moves the cursor to the next line if the cursor is on a "readline". If the last "readline" row is reached, the cursor jumps to the first "readline" row if `ENTER` was pressed. If after an `ENTER` the cursor has jumped to the first "readline" row and *auto-up* is set to `1`, `ENTER` doesn't move the cursor to the next row until the cursor is moved with another key.

With *auto-up* set to `2` `ENTER` moves the cursor to the top menu entry if the cursor is on a "readline".

default: `0`

  * ro

Set form-rows to readonly.

Expected value: an array with the indexes of the rows which should be readonly.

default: empty array

  * confirm

Set the name of the "confirm" menu entry.

default: `E<lt>E<lt>`

  * back

Set the name of the "back" menu entry.

The "back" menu entry is not available if *back* is not defined or set to an empty string.

default: undefined

To close the form and get the modified list select the "confirm" menu entry. If the "back" menu entry is chosen to close the form, `fillform` returns nothing.

REQUIREMENTS
============

Requires `libncursesw.so.6`.

See also [Term::Choose#REQUIREMENTS](Term::Choose#REQUIREMENTS).

AUTHOR
======

Matthäus Kiem <cuer2s@gmail.com>

CREDITS
=======

Thanks to the people from [Perl-Community.de](http://www.perl-community.de), from [stackoverflow](http://stackoverflow.com) and from [#perl6 on irc.freenode.net](irc://irc.freenode.net/#perl6) for the help.

LICENSE AND COPYRIGHT
=====================

Copyright (C) 2016-2017 Matthäus Kiem.

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

