use v6;
unit class Term::Form;

my $VERSION = '0.017';

use Term::Choose::NCurses;
use Term::Choose::LineFold :to-printwidth, :line-fold, :print-columns;


constant CONTROL_A  = -0x01;
constant CONTROL_B  = -0x02;
constant CONTROL_D  = -0x04;
constant CONTROL_E  = -0x05;
constant CONTROL_F  = -0x06;
constant CONTROL_H  = -0x08;
constant KEY_TAB    = -0x09;
constant KEY_RETURN = -0x0a;
constant CONTROL_K  = -0x0b;
constant CONTROL_U  = -0x15;
constant KEY_ESC    = -0x1b;


has %.defaults;
has %!o;

has Term::Choose::NCurses::WINDOW $.win;
has Term::Choose::NCurses::WINDOW $!win_local;

has @!pre;
has @!list;

has Int $!idx;
has Int $!start_idx;
has Int $!end_idx;

has Int $!avail_w;
has Int $!avail_h;
has Int $!val_w;

has Str $!sep;
has Str $!sep_ro;
has Int $!sep_w;

has Int @!len_keys;
has Int $!key_w;

has Str $!header;
has Int $!nr_header_lines;

has Int $!page;
has Int $!pages;



method new ( :%defaults, :$win=Term::Choose::NCurses::WINDOW ) {
    my %valid = (
        mark-curr => '<[ 0 1 ]>', #
        auto-up   => '<[ 0 1 2 ]>',
        no-echo   => '<[ 0 1 2 ]>',
        back      => 'Str',
        confirm   => 'Str',
        default   => 'Str',
        header    => 'Str',
        ro        => 'Array',
    );
    _validate_options( %defaults, %valid );
    _set_defaults( %defaults );
    self.bless( :%defaults, :$win );
}

sub _set_defaults ( %opt ) {
    %opt<auto-up>   //= 0;
    %opt<no-echo>   //= 0;
    %opt<mark-curr> //= Any;
    %opt<default>   //= '';
    %opt<header>    //= Str;
    %opt<confirm>   //= '<<';
    %opt<back>      //= Str;
    %opt<ro>        //= [];
}

sub _validate_options ( %opt, %valid, Int $list_end? ) {
    for %opt.kv -> $key, $value {
        when %valid{$key}:!exists { #
            die "'$key' is not a valid option name";
        }
        when ! $value.defined {
            next;
        }
        when %valid{$key} eq 'Array' {
            die "$key => not an ARRAY reference." if ! $value.isa( Array );
            die "$key => invalid array element"   if $value.grep( { / <-[0..9]> / } ); # Int;
            #if $key eq 'ro' {
                die "$key => value out of range." if $list_end.defined && $value.any > $list_end;
            #}
        }
        when %valid{$key} eq 'Str' {
            die "$key => not a string." if ! $value.isa( Str );
        }
        when $value !~~ / ^ <{%valid{$key}}> $ / {
            die "$key => '$value' is not a valid value.";
        }
    }
}


method !_init_term {
    if $!win {
        $!win_local = $!win;
    }
    else {
        my int32 constant LC_ALL = 6;
        setlocale( LC_ALL, "" );
        $!win_local = initscr;
    }
    noecho();
    cbreak;
    keypad( $!win_local, True );
    curs_set( 1 );
    # disable mouse:
    my Array[int32] $old;
    my $s = mousemask( 0, $old );
}


method !_end_term {
    return if $!win;
    endwin();
}


submethod DESTROY () {
    self!_end_term;
}


multi readline ( Str $prompt, Str $default ) is export( :DEFAULT, :readline ) { return Term::Form.new().readline( $prompt, $default ) }
multi readline ( Str $prompt, %opt? )        is export( :DEFAULT, :readline ) { return Term::Form.new().readline( $prompt, %opt ) }

multi method readline ( Str $prompt, Str $default ) { return self!_readline( $prompt, { default => $default } ) }
multi method readline ( Str $prompt, %opt? )        { return self!_readline( $prompt, %opt ) }

method !_readline ( $f-key = ': ', %!o? ) {
    my %valid = (
        no-echo => '<[ 0 1 2 ]>',
        default => 'Str',
        header  => 'Str',
    );
    _validate_options( %!o, %valid );
    for %valid.keys -> $key {
        %!o{$key} //= %!defaults{$key};
    }
    %!o<ro> = ();
    #$!nr_header_lines = 0;
    $!sep = '';
    $!sep_w = print-columns( $!sep );
    $!idx = 0;
    @!len_keys[0] = print-columns( $f-key );
    $!key_w = @!len_keys[0];
    my Str $str = %!o<default>;
    @!list = ( [ $f-key, $str ] );
    my Int $pos = $str.chars;
    self!_init_term();
    my $term_w = getmaxx( $!win_local );
    my $term_h = getmaxy( $!win_local );
    $!avail_w = $term_w - 1; #
    $!val_w = $!avail_w - ( $!key_w + $!sep_w );
    self!_nr_header_lines();
    clear();
    if $!header.defined {
        mvaddstr( 0, 0, $!header );
    }
    my Int $beep;

    GET_KEY: loop {
        if $beep {
            beep();
            $beep = 0;
        }
        $!avail_w = $term_w - 1; #
        $!val_w = $!avail_w - ( $!key_w + $!sep_w );
        self!_print_readline( $str, $!nr_header_lines, $pos );
        nc_refresh();
        my int32 $c-key;
        WAIT: loop {
            my Int $ct = get_wch( $c-key );
            if $ct == ERR {
                sleep 0.01;
                next WAIT;
            }
            elsif $ct != KEY_CODE_YES {
                $c-key = -$c-key;
            }
            last WAIT;
        }
        my $tmp_term_w = getmaxx( $!win_local );
        my $tmp_term_h = getmaxy( $!win_local );
        if $tmp_term_w != $term_w || $tmp_term_h != $term_h {
            ( $term_w, $term_h ) = ( $tmp_term_w, $tmp_term_h );
            $!avail_w = $term_w - 1; #
            $!val_w = $!avail_w - ( $!key_w + $!sep_w );
            self!_nr_header_lines();
            clear();
            if $!header.defined {
                mvaddstr( 0, 0, $!header );
            }
            next GET_KEY;
        }

        given $c-key {
            #when ! $c-key.defined {
            #    self!_end_term();
            #    die "EOT: $!";#
            #}
            when KEY_ESC | KEY_TAB {
                next GET_KEY;
            }
            when KEY_BACKSPACE | KEY_BTAB | CONTROL_H {
                if $pos {
                    $pos--;
                    $str.substr-rw( $pos, 1 ) = '';
                }
                else {
                    $beep = 1;
                }
            }
            when CONTROL_U {
                if $pos {
                    $str.substr-rw( 0, $pos ) = '';
                    $pos = 0;
                }
                else {
                    $beep = 1;
                }
            }
            when CONTROL_K {
                if $pos < $str.chars {
                    $str.substr-rw( $pos, $str.chars - $pos ) = '';####
                }
                else {
                    $beep = 1;
                }
            }
            when KEY_DC | CONTROL_D {
                if $str.chars {
                    if $pos < $str.chars {
                        $str.substr-rw( $pos, 1 ) = '';
                    }
                    else {
                        $beep = 1;
                    }
                }
                else {
                    self!_end_term();
                    return;
                }
            }
            when KEY_RIGHT | CONTROL_F {
                if $pos < $str.chars {
                    $pos++;
                }
                else {
                    $beep = 1;
                }
            }
            when KEY_LEFT | CONTROL_B {
                if $pos {
                    $pos--;
                }
                else {
                    $beep = 1;
                }
            }
            when KEY_END | CONTROL_E {
                if $pos < $str.chars {
                    $pos = $str.chars;
                }
                else {
                    $beep = 1;
                }
            }
            when KEY_HOME | CONTROL_A {
                if $pos > 0 {
                    $pos = 0;
                }
                else {
                    $beep = 1;
                }
            }
            when KEY_UP | KEY_DOWN {
                $beep = 1;
            }
            when KEY_RETURN | KEY_ENTER {
                self!_end_term();
                return $str;
            }
            default {
                $str.substr-rw( $pos, 0 ) = $c-key.abs.chr;
                $pos++;
            }
        }
    }
}





method !_print_readline ( Str $str is copy, Int $row, Int $pos is copy ) {
    my $n = min 20, $!val_w div 3;
    my ( $b, $e );
    while print-columns( $str ) > $!val_w {
        #if print-columns( $str.substr( 0, $pos ) ) > $!val_w / 4 {
        if $str.substr( 0, $pos ).chars > $!val_w / 4 {
            $n = min $n, ( $pos - 1 ); #
            $str.substr-rw( 0, $n ) = '';
            $pos -= $n;
            $b = 1;
        }
        else {
            $n = min $n, $str.chars - ( $pos + 1 ) ; #
            $str.substr-rw( *-$n, $n ) = '';
            $e = 1;
        }
    }
    if $b {
        $str.substr-rw( 0, 1 ) = '<';
    }
    if $e {
        $str.substr-rw( $str.chars, 1 ) = '>'; ##
    }

    my $f-key = self!_prepare_key( $!idx );
    if %!o<mark-curr> {
        attron( A_UNDERLINE );
        mvaddstr( $row, 0, $f-key );
        attroff( A_UNDERLINE );
    }
    else {
        mvaddstr( $row, 0, $f-key );
    }
    my $sep = $!sep;
    if %!o<ro>.any == $!idx - @!pre.elems {
        $sep = $!sep_ro;
    }
    if %!o<no-echo> {
        if %!o<no-echo> == 2 {
            mvaddstr( $row, $!key_w, $sep );
            return;
        }
        mvaddstr( $row, $!key_w, $sep ~ ( '*' x $str.chars ) );
    }
    else {
        mvaddstr( $row, $!key_w, $sep ~ $str );
    }
    clrtoeol();
    move(
        $row,
        $!key_w + $!sep_w + print-columns( $str.substr: 0, $pos )
    );
}


method !_prepare_key ( Int $idx ) {
    my Int $f-key_len = @!len_keys[$idx];
    my Str $f-key = @!list[$idx][0];
    $f-key.=subst(   / \s /, ' ', :g );
    $f-key.=subst( / <:C> /, '',  :g );
    if $f-key_len > $!key_w {
        return to-printwidth( $f-key, $!key_w, False ).[0];
    }
    elsif $f-key_len < $!key_w {
        return " " x ( $!key_w - $f-key_len ) ~ $f-key;
    }
    else {
        return $f-key;
    }
}


method !_length_longest_key {
    $!key_w = 0;
    for 0 .. @!list.end -> $i {
        @!len_keys[$i] = print-columns( @!list[$i][0] );
        if $i < @!pre.elems { ##
            next;
        }
        $!key_w = @!len_keys[$i] if @!len_keys[$i] > $!key_w;
    }
}


method !_prepare_size ( Int $term_w, Int $term_h ) {
    $!avail_w = $term_w - 1; #
    $!avail_h = $term_h;
    self!_nr_header_lines();
    if $!nr_header_lines {
        my Int $backup_h = $!avail_h;
        $!avail_h -= $!nr_header_lines;
        my Int $min_avail_h = 5;
        if $!avail_h < $min_avail_h {
            if $backup_h > $min_avail_h {
                $!avail_h = $min_avail_h;
            }
            else {
                $!avail_h = $backup_h;
            }
        }
    }
    if @!list.elems > $!avail_h {
        $!pages = @!list.elems div ( $!avail_h - 1 );
        if @!list.elems % ( $!avail_h - 1 ) {
            $!pages++;
        }
        $!avail_h--;
    }
    else {
        $!pages = 1;
    }
    return;
}


method !_nr_header_lines {
    if ! %!o<header>.defined || %!o<header> eq '' {
        $!header = Str;
        $!nr_header_lines = 0;
        return;
    }
    $!header = line-fold( %!o<header>, $!avail_w, '', '' );
    my $matches = $!header.subst-mutate( / \n /, "\n\r", :g ); #
    if ! $matches {
        $!nr_header_lines = 1;
        return;
    }
    $!nr_header_lines = $matches.elems + 1;
}


method !_str_and_pos {
    my $str = @!list[$!idx][1] // '';
    return $str, $str.chars;
}


method !_print_current_row ( Str $str, Int $pos ) {
    my $row = $!idx + $!nr_header_lines - $!avail_h * ( $!page - 1 );
    if $!idx < @!pre.elems {
        attron( A_REVERSE );
        mvaddstr( $row, 0, @!list[$!idx][0] );
        attroff( A_REVERSE );
        clrtoeol();
    }
    else {
        self!_print_readline( $str, $row, $pos );
        @!list[$!idx][1] = $str; #
    }
}


method !_get_print_row ( Int $idx ) {
    if $idx < @!pre.elems {
        return @!list[$idx][0];
    }
    else {
        my $val = @!list[$idx][1] // '';
        $val.=subst(   / \s /, ' ', :g );
        $val.=subst( / <:C> /, '',  :g );
        my $sep = $!sep;
        if %!o<ro>.any == $idx - @!pre.elems {
            $sep = $!sep_ro;
        }
        return self!_prepare_key( $idx ) ~ $sep ~ to-printwidth( $val, $!val_w, False ).[0];
    }
}


method !_write_screen {
    my $s = $!nr_header_lines;
    for $!start_idx .. $!end_idx -> $idx {
        mvaddstr( $s++, 0, self!_get_print_row: $idx );
    }
    if $!pages > 1 {
        $!page = $!end_idx div $!avail_h + 1;
        my Str $page_number = sprintf '- Page %d/%d -', $!page, $!pages;
        if $page_number.chars > $!avail_w {
            $page_number = sprintf( '%d/%d', $!page, $!pages ).substr( 0, $!avail_w );
        }
        mvaddstr( $!avail_h, 0, $page_number );
    }
    else {
        $!page = 1;
    }
}


method !_write_first_screen ( Int $curr_row ) {
    if $!key_w > $!avail_w div 3 {
        $!key_w = $!avail_w div 3;
    }
    $!val_w = $!avail_w - ( $!key_w + $!sep_w );
    $!idx = %!o<auto-up> == 2 ?? $curr_row !! @!pre.elems;
    $!start_idx = 0;
    $!end_idx  = $!avail_h - 1;
    if $!end_idx > @!list.end {
        $!end_idx = @!list.end;
    }
    clear();
    if $!header.defined {
        mvaddstr( 0, 0, $!header );
    }
    self!_write_screen();
}


method !_reset_pre_row ( Int $idx ) {
    if $idx == ( 0 .. @!pre.end ).any || %!o<mark-curr> {
        my $row = $idx + $!nr_header_lines - $!avail_h * ( $!page - 1 );
        mvaddstr( $row, 0, self!_get_print_row: $idx );
    }
}


method !_print_next_page {
    $!start_idx = $!end_idx + 1;
    $!end_idx   = $!end_idx + $!avail_h;
    $!end_idx   = @!list.end if $!end_idx > @!list.end;
    clear();
    self!_write_screen();
}


method !_print_previous_page {
    $!end_idx   = $!start_idx - 1;
    $!start_idx = $!start_idx - $!avail_h;
    $!start_idx = 0 if $!start_idx < 0;
    clear();
    self!_write_screen();
}


sub fillform ( @list, %opt? ) is export( :DEFAULT, :fillform ) { return Term::Form.new().fillform( @list, %opt ) }

method fillform ( @orig_list, %!o? ) {
    my %valid = (
        mark-curr => '<[ 0 1 ]>',
        auto-up   => '<[ 0 1 2 ]>',
        back      => 'Str',
        confirm   => 'Str',
        header    => 'Str',
        ro        => 'Array',
    );
    @!list = @orig_list.deepmap( -> $e is copy { $e } );
    _validate_options( %!o, %valid, @!list.end ); # 
    for %valid.keys -> $key {
        %!o{$key} //= %!defaults{$key};
    }

    $!sep    = ': ';
    $!sep_ro = '| ';
    $!sep_w = print-columns( $!sep );
    if %!o<ro>.elems {
        my $tmp = print-columns( $!sep_ro );
        $!sep_w = $tmp if $tmp > $!sep_w;
    }

    if %!o<back>.defined && %!o<back>.chars {
        @!pre.push: [ %!o<back> ];
    }
    @!pre.push: [ %!o<confirm> ];
    @!list.unshift: |@!pre;
    self!_length_longest_key();
    self!_init_term();

    my $term_w = getmaxx( $!win_local );
    my $term_h = getmaxy( $!win_local );
    self!_prepare_size( $term_w, $term_h );
    self!_write_first_screen( 0 );

    my ( $str, $pos ) = self!_str_and_pos();
    my Int $enter_col;
    my Int $enter_row;
    my Int $beep;

    LINE: loop {
        my Int $locked = 0;
        if %!o<ro>.any == $!idx - @!pre.elems {
            $locked = 1;
        }
        if $beep {
            beep();
            $beep = 0;
        }
        else {
            self!_print_current_row( $str, $pos );
        }
        nc_refresh();
        my int32 $c-key;
        WAIT: loop {
            my Int $ct = get_wch( $c-key );
            if $ct == ERR {
                sleep 0.01;
                next WAIT;
            }
            elsif $ct != KEY_CODE_YES {
                $c-key = -$c-key;
            }
            last WAIT;
        }
        my $tmp_term_w = getmaxx( $!win_local );
        my $tmp_term_h = getmaxy( $!win_local );
        if $tmp_term_w != $term_w || $tmp_term_h != $term_h && $tmp_term_h {
            ( $term_w, $term_h ) = ( $tmp_term_w, $tmp_term_h );
            self!_prepare_size( $term_w, $term_h );
            self!_write_first_screen( 1 );
            ( $str, $pos ) = self!_str_and_pos();
            next LINE; #
        }
        given $c-key {
            #when ! $c-key.defined {
            #    self!_end_term();
            #    die "EOT: $!";#
            #}
            when KEY_ESC | KEY_TAB {
                next;
            }
            when KEY_BACKSPACE | KEY_BTAB | CONTROL_H {
                if $locked {
                    $beep = 1;
                }
                elsif $pos {
                    $pos--;
                    $str.substr-rw( $pos, 1 ) = '';
                }
                else {
                    $beep = 1;
                }
            }
            when CONTROL_U {
                if $locked {
                    $beep = 1;
                }
                elsif $pos {
                    $str.substr-rw( 0, $pos ) = '';
                    $pos = 0;
                }
                else {
                    $beep = 1;
                }
            }
            when CONTROL_K {
                if $locked {
                    $beep = 1;
                }
                elsif $pos < $str.chars {
                    $str.substr-rw( $pos, $str.chars - $pos ) = '';
                }
                else {
                    $beep = 1;
                }
            }
            when KEY_DC | CONTROL_D {
                if $str.chars {
                    if $locked {
                        $beep = 1;
                    }
                    elsif $pos < $str.chars {
                        $str.substr-rw( $pos, 1 ) = '';
                    }
                    else {
                        $beep = 1;
                    }
                }
                else {
                    self!_end_term();
                    return;
                }
            }
            when KEY_RIGHT {
                if $pos < $str.chars {
                    $pos++;
                }
                else {
                    $beep = 1;
                }
            }
            when KEY_LEFT {
                if $pos {
                    $pos--;
                }
                else {
                    $beep = 1;
                }
            }
            when KEY_END | CONTROL_E {
                if $pos < $str.chars {
                    $pos = $str.chars;
                }
                else {
                    $beep = 1;
                }
            }
            when KEY_HOME | CONTROL_A {
                if $pos > 0 {
                    $pos = 0;
                }
                else {
                    $beep = 1;
                }
            }
            when KEY_UP {
                if $!idx == 0 {
                    $beep = 1;
                }
                else {
                    $!idx--;
                    ( $str, $pos ) = self!_str_and_pos();
                    if $!idx >= $!start_idx {
                        self!_reset_pre_row( $!idx + 1 );
                    }
                    else {
                        self!_print_previous_page();
                    }
                }
            }
            when KEY_DOWN {
                if $!idx == @!list.end {
                    $beep = 1;
                }
                else {
                    $!idx++;
                    ( $str, $pos ) = self!_str_and_pos();
                    if $!idx <= $!end_idx {
                        self!_reset_pre_row( $!idx - 1 );
                    }
                    else {
                        self!_print_next_page();
                    }
                }
            }
            when KEY_PPAGE | CONTROL_B {
                if $!page == 1 {
                    if $!idx == 0 {
                        $beep = 1;
                    }
                    else {
                        self!_reset_pre_row( $!idx );
                        $!idx = 0;
                        ( $str, $pos ) = self!_str_and_pos();
                    }
                }
                else {
                    $!idx = $!start_idx - $!avail_h;
                    ( $str, $pos ) = self!_str_and_pos();
                    self!_print_previous_page();
                }
            }
            when KEY_NPAGE | CONTROL_F {
                if $!page == $!pages {
                    if $!idx == @!list.end {
                        $beep = 1;
                    }
                    else {
                        self!_reset_pre_row( $!idx );
                        $!idx = $!end_idx;
                        ( $str, $pos ) = self!_str_and_pos();
                    }
                }
                else {
                    $!idx = $!end_idx + 1;
                    ( $str, $pos ) = self!_str_and_pos();
                    self!_print_next_page();
                }
            }
            when KEY_RETURN | KEY_ENTER {
                if %!o<back>.defined && @!list[$!idx][0] eq %!o<back> {
                    self!_end_term();
                    return;
                }
                elsif @!list[$!idx][0] eq %!o<confirm> {
                    self!_end_term();
                    @!list.splice( 0, @!pre.elems );
                    return @!list;
                }
                if %!o<auto-up> == 2 {
                    if $!idx == 0 {
                        $beep = 1;
                    }
                    else {
                        ( $str, $pos ) = self!_write_first_screen( 0 );
                        ( $str, $pos ) = self!_str_and_pos();
                    }
                }
                elsif $!idx == @!list.end {
                    ( $str, $pos ) = self!_write_first_screen( @!pre.elems );
                    ( $str, $pos ) = self!_str_and_pos();
                    $enter_col = $pos;
                    $enter_row = $!idx;
                }
                else {
                    if %!o<auto-up> == 1 {
                        if    $enter_row.defined && $enter_row == $!idx
                           && $enter_col.defined && $enter_col == $pos
                        {
                            $beep = 1;
                            next;
                        }
                        else {
                            $enter_row = Int;
                            $enter_col = Int;
                        }
                    }
                    $!idx++;
                    ( $str, $pos ) = self!_str_and_pos();
                    if $!idx <= $!end_idx {
                        self!_reset_pre_row( $!idx + $!nr_header_lines - 1 );
                    }
                    else {
                        self!_print_next_page();
                    }
                }
            }
            default {
                if $locked {
                    $beep = 1;
                }
                else {
                    $str.substr-rw( $pos, 0 ) = $c-key.abs.chr;
                    $pos++;
                }
            }
        }
    }
}



=begin pod

=head1 NAME

Term::Form - Read lines from STDIN.

=head1 VERSION

Version 0.017

=head1 SYNOPSIS

    use Term::Form :readline, :fillform;

    my @aoa = (
        [ 'name'           ],
        [ 'year'           ],
        [ 'color', 'green' ],
        [ 'city'           ]
    );


    # Functional interface:

    my $line = readline( 'Prompt: ', { default => 'abc' } );

    my @filled_form = fillform( @aoa, { auto-up => 0 } );


    # OO interface:

    my $new = Term::Form.new();

    $line = $new.readline( 'Prompt: ', { default => 'abc' } );

    @filled_form = $new.fillform( @aoa, { auto-up => 0 } );

=head1 FUNCTIONAL INTERFACE

Importing the subroutines explicitly (C<:name_of_the_subroutine>) might become compulsory (optional for now) with the
next release.

=head1 DESCRIPTION

C<readline> reads a line from STDIN. As soon as C<Return> is pressed C<readline> returns the read string without the
newline character - so no C<chomp> is required.

C<fillform> reads a list of lines from STDIN.

=head2 Keys

C<BackSpace> or C<Strg-H>: Delete the character behind the cursor.

C<Delete> or C<Strg-D>: Delete  the  character at point. Return nothing if the input puffer is empty.

C<Strg-U>: Delete the text backward from the cursor to the beginning of the line.

C<Strg-K>: Delete the text from the cursor to the end of the line.

C<Right-Arrow>: Move forward a character.

C<Left-Arrow>: Move back a character.

C<Home> or C<Strg-A>: Move to the start of the line.

C<End> or C<Strg-E>: Move to the end of the line.

Only in C<fillform>:

C<Up-Arrow>: Move up one row.

C<Down-Arrow>: Move down one row.

C<Page-Up> or C<Strg-B>: Move back one page.

C<Page-Down> or C<Strg-F>: Move forward one page.

=head1 CONSTRUCTOR

The constructor method C<new> can be called with optional named arguments:

=item defaults

Expects as its value a hash. Sets the defaults for the instance. See L<#OPTIONS>.

=item win

Expects as its value a window object created by ncurses C<initscr>.

If set, C<readline> and C<fillform> use this global window instead of creating their own without calling C<endwin> to
restores the terminal before returning.

=head1 ROUTINES

=head2 readline

C<readline> reads a line from STDIN.

The fist argument is the prompt string.

The optional second argument is a hash to set the different options. The keys/options are

With the optional second argument it can be passed the default value (see option I<default>) as string or it can be
passed the options as a hash. The options are

=item1 default

Set a initial value of input.

=item1 no-echo

=item2 if set to C<0>, the input is echoed on the screen.

=item2 if set to C<1>, "C<*>" are displayed instead of the characters.

=item2 if set to C<2>, no output is shown apart from the prompt string.

default: C<0>

=item1 header

With the option I<header> it can be set a header-string which is shown on top of the output.

=head2 fillform

C<fillform> reads a list of lines from STDIN.

The first argument is an array of arrays. The arrays have 1 or 2 elements: the first element is the key and the optional
second element is the value. The key is used as the prompt string for the "readline", the value is used as the default
value for the "readline" (initial value of input).

The optional second argument is a hash. The keys/options are

=item1 header

With the option I<header> it can be set a header-string which is shown on top of the output.

default: undefined

=item1 auto-up

With I<auto-up> set to C<0> or C<1> pressing C<ENTER> moves the cursor to the next line if the cursor is on a
"readline". If the last "readline" row is reached, the cursor jumps to the first "readline" row if C<ENTER> was pressed.
If after an C<ENTER> the cursor has jumped to the first "readline" row and I<auto-up> is set to C<1>, C<ENTER> doesn't
move the cursor to the next row until the cursor is moved with another key.

With I<auto-up> set to C<2> C<ENTER> moves the cursor to the top menu entry if the cursor is on a "readline".

default: C<0>

=item1 ro

Set form-rows to readonly.

Expected value: an array with the indexes of the rows which should be readonly.

default: empty array

=item1 confirm

Set the name of the "confirm" menu entry.

default: C<E<lt>E<lt>>

=item1 back

Set the name of the "back" menu entry.

The "back" menu entry is not available if I<back> is not defined or set to an empty string.

default: undefined

To close the form and get the modified list select the "confirm" menu entry. If the "back" menu entry is chosen to close
the form, C<fillform> returns nothing.

=head1 REQUIREMENTS

See L<Term::Choose#REQUIREMENTS>.

=head1 AUTHOR

Matthäus Kiem <cuer2s@gmail.com>

=head1 CREDITS

Thanks to the people from L<Perl-Community.de|http://www.perl-community.de>, from
L<stackoverflow|http://stackoverflow.com> and from L<#perl6 on irc.freenode.net|irc://irc.freenode.net/#perl6> for the
help.

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2016-2017 Matthäus Kiem.

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod
