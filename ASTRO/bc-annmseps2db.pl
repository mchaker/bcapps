#!/bin/perl

# The final final step of the quest to find conjunctions: this takes
# the annmsepsdump dump files and converts them to a MySQL database

require "/usr/local/lib/bclib.pl";

# for $i (glob "/home/barrycarter/SPICE/KERNELS/annmsepsdump*.txt") {

warn "TESTING WITH CURRENT FILE";

for $i (glob "/home/barrycarter/SPICE/KERNELS/annmsepsdump-2451536-2816816.txt") {
  my($all) = read_file($i);

  while ($all=~s/annminsep\[\{(.*?)\}\]\s*=\s*\{(\{.*?\})\}//s) {

    my($planets,$data) = ($1,$2);
    my(@planets) = split(/\,\s*/s,$planets);

    while ($data=~s/\{(.*?)\}//s) {
      my($jd, $sep, $sun, $star, $ssep) = split(/\,\s*/s,$1);

      # TODO: yuck!
      $jd=~s/\*\^/e/;
      $jd=sprintf("%0.6f",$jd);
      # TODO: serious yuck!
      my($out,$err,$res) = cache_command2("j2d $jd","age=9999999");
      chomp($out);
      debug("OUT: $out");

      debug("$planets/$jd/$sep/$sun/$star/$ssep");

      # TODO: turn this into an INSERT statement
      # TODO: breakup into year, month, day for searching
      # TODO: this won't work if more than 2 planets, fix
      # NOTE: including JD in final result can't use MySQL date, but also
      # doing year/month/day breakdown for ease of use
      print join("\t",@planets,$jd,$out,$sep,$sun,$star,$ssep),"\n";

    }
  }
}


