#!/bin/perl

# Trivial variant of bc-parse-ofx3.pl for qfx, which is what I
# shouldve been doing all along?

require "/usr/local/lib/bclib.pl";
require "/home/user/bc-private.pl";

($all,$name) = cmdfile();

for $i ("ACCTID","DTSERVER","DTSTART","DTEND") {
  $all=~s%<$i>(.*?)<%<$i>$1</$i>\n<%is;
}

# hash data that is fixed for entire file (not per-transaction)
$regex = "acctid|dtserver|dtstart|dtend";
$all=~s%<($regex)>\s*(.*?)\s*</\1>%$ofx{$1}=$2%iseg;

# only use last four digits
$ofx{ACCTID}=~s/^.*(.{4})$/$1/;

debug(%ofx);

# this is a hack just for me -- one of my credit cards is handled differently

if ($ofx{ACCTID} eq $private{notcreditcard}) {
  die "Can't use this program on that account";
}

# transactions
while ($all=~s%<STMTTRN>(.*?)</STMTTRN>%%is) {
  $trans = $1;
  %trans = ();
  $trans=~s%<(.*?)>(.*?)(?=<|$)%$trans{$1}=$2%iseg;

  # TODO: ugly hack to trim newlines, should do above
  for $i (keys %trans) {$trans{$i}=trim($trans{$i});}

  $trans{DTPOSTED}=~s/^(\d{4})(\d{2})(\d{2}).*$/$1-$2-$3/;
  unless ($trans{MEMO}=~s/^$ofx{ACCTID}: //) {$trans{MEMO}=$trans{NAME};}

  $trans{MEMO}=~s/\'//g;

  # query (credcardstatements2 is new version w/ good indicies, etc)
  push(@queries,
"INSERT IGNORE INTO credcardstatements2
 (whichcard, amount, type, date, transaction_id, merchant) VALUES
 ('$ofx{ACCTID}', $trans{TRNAMT}, '$trans{TRNTYPE}', '$trans{DTPOSTED}',
 '$trans{FITID}', '$trans{MEMO}')");
}

# this is probably overkill
# open(A,"|mysql test");
print "BEGIN;\n";
for $i (@queries) {print "$i;\n"}
print "COMMIT;\n";
# close(A);
