#!/bin/perl

# Another "useful only to me" program (although you can make it useful
# to you by using bc-parse-qfx.pl, MySQL, and categorizing your
# expenses), this program tells me how much I am spending on various
# things, my cash flow, etc.

# This program gets most of its info from command line options

# --income=amount: income per month

# --fixed=cat1=val1,cat2=val2,cat3=val3: treat category spending as
# fixed per month

# --extra=name1=amt1,name2=amt2,name3=amt3,...: extra money I have (or
# owe if negative) that doesn't appear in my databases (the names are
# cosmetic ways of tagging these amounts)

# --exclcat=cat1,cat2,cat3,...: exclude categories from consideration (eg,
# refunded transactions, transactions that move money from one account
# to another, categories that I no longer use + expect no future
# charges for, etc)

# --exclbank=bank1,bank2,bank3,...: exclude these banks from consideration

# --exclcard=card1,card2,card3,...: exclude these credit card from
# consideration

# --start=date: how far back to go when making calculations (default =
# look at all categorized transactions)

# NOTE: this program intentionally excludes interest

require "/usr/local/lib/bclib.pl";

# if no start date set, set it to unix 0 time

defaults("start=1970-01-01");

# TODO: maybe warn if no arguments/options, normal invokation is via alias

# the current time

my($now) = time();

# compute how far back to go

my($maxdays) = floor(($now - str2time($globopts{start}))/86400 + 1);

# don't print if not set

unless ($globopts{start} eq "1970-01-01") {
  # TODO: print this elsewhere
#  print "MAXDAYS: $maxdays\n";
}

# convert options that are list values to hashes

my(%exclbank) = list2hash(split(/\,/,$globopts{exclbank}));
my(%exclcat) = list2hash(split(/\,/,$globopts{exclcat}));
my(%exclcard) = list2hash(split(/\,/,$globopts{exclcard}));

# this hideous code splits globopts{fixed} using commas and equals,
# resulting in a list that Perl will auto-convert to a hash when
# assigned to a hash (TODO: should I avoid language-specific hacks
# like this?)

my(%fixed) = split(/[\,|\=]\s*/, $globopts{fixed});

# same for extra

my(%extra) = split(/[\,|\=]\s*/, $globopts{extra});

# compute total fixed spending

my($fixedPerMonth) = 0;

for $i (keys %fixed) {$fixedPerMonth += $fixed{$i};}

my($fixedPerDay) = $fixedPerMonth/$DAYSPERMONTH;

debug("FIXED: $fixedPerMonth .... $fixedPerDay");

# TODO: subroutinize?

# how much do I currently owe on my credit cards

# TODO: should really get mysqlval into bclib.pl instead of ugly
# extraction here

# NOTE: breaking this down by card is theoretically unnecessary, but
# helps with debugging

# NOTE: credcardstatements is obsolete, so the '2' below is correct

# TODO: rounding here or should i round later?

# TODO: this amount is slightly wrong because it includes gift cards
# and other weirdnesses; however, it is fairly close

my(@ccowed) = mysqlhashlist("SELECT whichcard, ROUND(SUM(amount),2) AS
total FROM credcardstatements2 GROUP BY whichcard", "test", "user");

# compute total

my($ccowed) = 0; 

for $i (@ccowed) {
  if ($exclcard{$i->{whichcard}}) {next;}
  debug("CC: $i->{whichcard}, $i->{total}");
  $ccowed += $i->{total};
}

# now, bankstatements (my bank balance, hopefully positive)

my(@bankbals) = mysqlhashlist("SELECT bank, ROUND(SUM(amount),2) AS
total FROM bankstatements GROUP BY bank", "test", "user");

# and total

my($bankbal) = 0;

debug("EXCL", %bankexcl);

for $i (@bankbals) {
  debug("BANK: $i->{bank}, $i->{total}");
  if ($exclbank{$i->{bank}}) {next;}
  $bankbal += $i->{total};
}

# total extra

my($extra) = 0;

for $i (keys %extra) {$extra += $extra{$i};}

debug("TOTAL EXTRA: $extra");

my($liquidAssets) = $bankbal + $ccowed + $extra;

debug("LA: $liquidAssets");

# TODO: don't print here

# print "CC Bal: $ccowed\n";
# print "Bn Bal: $bankbal\n";

# TODO: currently assuming I have 0 cash on hand (pretty close to
# true), but try to compute cashtotal accurately later

# this mega query selects all my bank, credit, and cash transactions
# reverse ordered by date

# I don't need all fields, but they are useful for debugging

# TODO: could make the below a view for more flexibility

# TODO: the 'comments' are multiline and not useful at least for now

# TODO: neither HEX nor QUOTE work on strings with ctrl-ms in them

# TODO: my version of MySQL doesn't support TO_BASE64 which might work

# NOTE: in cashstatements, positive = money I give to others

my($query) = << "MARK";

SELECT amount, date, description AS merchant, category, comments, "bank", oid 
 FROM bankstatements UNION
SELECT amount, date, merchant, category, comments, "credit", oid 
 FROM credcardstatements2 UNION
SELECT -amount, date, merchant, category, comments, "cash", oid
 FROM cashstatements
ORDER BY date DESC
MARK
;

my(@res) = mysqlhashlist($query, "test", "user");

# TODO: if --start isn't set, find the oldest day and use that

my(%catperday);

for $i (@res) {

  # TODO: there are many many reasons to not count a transaction, add
  # them below

  # categories I ignore
  if ($exclcat{$i->{category}}) {next;}

  # categories that I treat as fixed
  if ($fixed{$i->{category}}) {next;}

  # don't include positive amounts (TODO: maybe allow later)
  if ($i->{amount} > 0) {next;}

  # find high value transactions which I perhaps should exclude or something
  if ($i->{amount} < -500) {
    debug("HIGH VALUE:", unfold($i));
  }

  # number of days ago for this transaction
  my($daysago) = floor(($now - str2time($i->{date}))/86400);

  # to avoid division by 0
  if ($daysago == 0) {$daysago = 1;}

  # TODO: in theory, could just break out of loop here (since sorted)

  if ($daysago > $maxdays) {next;}

#  print "$daysago $i->{category} $i->{amount}\n";
  debug("ALPHA: $daysago $i->{category} $i->{amount}");

  # record spending per category per day
  $catperday{$daysago}{$i->{category}} += $i->{amount};

  # TODO: this is just temporary
  $totalSpending{$daysago} += $i->{amount};

}


# TODO: just for fun temporary

my($incomePerDay) = $globopts{income}/$DAYSPERMONTH;

my $cumTotal, $avg;

for $i (sort {$a <=> $b} keys %totalSpending) {

  $cumTotal += $totalSpending{$i};

  # includes fixed daily expenses
  $avg = $cumTotal/$i + $fixedPerDay;

  # years I have left given money I have
  my($yearsLeft) = -$liquidAssets/($avg+$incomePerDay)/$DAYSPERMONTH/12;

  print "$i $yearsLeft\n";

  debug("BETA: DAYS: $i, TOTAL: $totalSpending{$i}, CUM: $cumTotal, AVG: $avg, YL: $yearsLeft");
}

die "TESTING";

# go through days in order (most recent first)

# TODO: this loop is fixed for now, but make it depend on --start

my(%runningTotal);

for $i (0..366) {

  debug("I: $i");

  # TODO: this may NOT be a total list of categories (ie, fixed amounts)

  my(%dayhash) = %{$catperday{$i}};

  debug("DAYHASH <HASH>", %dayhash, "</HASH>");

  for $j (sort keys %dayhash) {

    debug("J: $j");

    $runningTotal{$j} += $dayhash{$j};

#    debug("DAYHASH: $dayhash{$i}{$j}");

    debug("$i, $j, $runningTotal{$j}");
  }


}  

# debug(@res);

# debug(var_dump("catsperday", \%catperday));
