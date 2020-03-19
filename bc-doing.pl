#!/bin/perl

# I often end up doing one thing and then subtasking into another
# thing. The ~/DOING file will tell me what I am doing at a given
# time, with timestamps. I can manually edit it when items are
# completed or I abandon them

# Usage: doing <thing>
# Add <thing> to ~/DOING with timestamp;
# If <thing> is blank, show undone items in reverse order

require "/usr/local/lib/bclib.pl";

$file = "$bclib{home}/DOING";

# thing given?

# TODO: this is incorrect-- must check 2nd field only for words below

# "DONE:" indicates item is done and not to be shown, NOT: = abandoned
unless (@ARGV) {system("tac $file | egrep -v 'DONE:|NOT:|OK:|FIXED:|NOTED:|ASKED:|DEFER:' | less"); exit(0);}

# <h>time and item are anagrams</h>
my($item) = join(" ",@ARGV);
my($time) = strftime("%Y%m%d.%H%M%S", localtime());
append_file("$time $item\n", $file);
