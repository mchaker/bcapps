#!/bin/perl

# Another program that helps only me (if that), this tracks my weight
# loss and estimates the time until I reach my non-obese and then
# non-overweight goals, starting from when I started tracking calories

# --start: start on this stardate
# --weights: comma separate list of target weights
# --until=stardate: only use data until stardate
# --nograph: dont display graph

# TODO: add exponential (in progress, but not working yet)

require "/usr/local/lib/bclib.pl";

# defaults
# defaults("start=20150930&weights=200,190,180,160,150,120");

# another try early 2019
# defaults("start=20190201&weights=210,200,190,180,160,155,150,120");
defaults("start=20190201&weights=210,200,180,155,120");

# if --start is in "stardate" format, fix it to change dot to space
# (str2time doesn't like stardate format)
$globopts{start}=~s/^(\d{8})\.(\d*)$/$1 $2/;

# plot using gnuplot
open(A,">/tmp/bwl.txt");

# allows for more complex fits using mathematica
open(B,">/tmp/bwl.m");
print B "data = {\n";

# convert to unix seconds
$stime = str2time($globopts{start});

# some useful calculated values
$now = time();

# obtain all weights and do linear regression
%weights = obtain_weights($stime, str2time($globopts{until}));

# to make life easier, converting times to days since $stime
for $i (sort keys %weights) {
  my($days) = ($i-$stime)/86400;
  my($days2) = ($i-$now)/86400;
  print A "$days2 $weights{$i}\n";
  print B "{$days2,$weights{$i}},\n";
  push(@x, $days);
  push(@y, $weights{$i});
  push(@z,log($weights{$i}));
  push(@z2,exp($weights{$i}));

  # keep track of lowest weight per day (day starts/ends at 1000 GMT for me)
  # TODO: maybe keep track of highest but that seems less useful
  $mday = int(($i-10*3600)/86400)-15594;
  debug("KEY: $i, MDAY: $mday");
  if ($weights{$i} < $low{$mday} || !$low{$mday}) {
    $low{$mday} = $weights{$i};
  }

  # keep track of min/max weights too
  if ($weights{$i} > $max || !$count) {
    push(@maxdays, $days);
    push(@maxvals, $weights{$i});
    $max = $weights{$i};
  }

  if ($weights{$i}<$min || !$count) {
    debug("MIN!");
    push(@mindays, $days);
    push(@minvals, $weights{$i});
    $min = $weights{$i};
  }

  $count++;
}

$sweight = $y[0];

debug("MINDY:",@mindays);
debug("MINVAL:",@minvals);

debug("MAXDY:",@maxdays);
debug("MAXVAL:",@maxvals);

close(A);

print B "};\ndata=Drop[data,-1];\n";
close(B);

# delete "low" weight for first day, since it was incomplete
delete $low{15594};

open(B,">/tmp/bwlm.txt");
for $i (sort {$a <=> $b} keys %low) {
  print B "$i $low{$i}\n";
  push(@lowx, $i);
  push(@lowy, $low{$i});
}
close(B);

($blow,$mlow) = linear_regression(\@lowx,\@lowy);
debug("LOW: $mlow slope, $blow offset");

# the regression coefficients for standard and log regression
($b,$m) = linear_regression(\@x,\@y);
# <h>I've always wanted to name a variable $blog for a good reason!</h>
($blog,$mlog) = linear_regression(\@x,\@z);
($bexp,$mexp) = linear_regression(\@x,\@z2);

# linear regression for min weights
($bmin, $mmin) = linear_regression(\@mindays, \@minvals);

debug("MIN: $mmin slope, $bmin offset");

# plot log/linear regression (to now, not just to last reading)
$daysago = ($stime-$now)/86400;
$linweight = $b - $m*$daysago;
# this should be an exponential curve, but close to linear for now
$logweight = exp($blog - $mlog*$daysago);
# $expweight = log($bexp - $mexp*$daysago);
write_file("$daysago $b\n0 $linweight\n","/tmp/bwl2.txt");
write_file("$daysago $b\n0 $logweight\n","/tmp/bwl3.txt");
write_file("$daysago $b\n0 $expweight\n","/tmp/bwl6.txt");

# and the straight line (very inaccurate) estimation
# TODO: getting loss in sea of variables
$mostrecent = $x[-1]-($now-$stime)/86400;
write_file("$daysago $y[0]\n$mostrecent $y[-1]\n", "/tmp/bwl4.txt");
# same for log (first two points)
write_file("$daysago $y[0]\n$mostrecent $y[-1]\n", "/tmp/bwl5.txt");

debug("DAYSAGO: $daysago, LINWT: $linweight");

# target weights (borders for obese, overweight, normal, and severely underweight) [added midpoints 30 Sep 2012 JFF]
# @t=(200,190,180,160,150,120);
@t = split(/\,/, $globopts{weights});

# when graphing, don't show beyond this value
# TODO: optionize this
$graphtarget = 120;

# TODO: with removal of 2nd fgrep, code can be efficientized
($secs,$wt) = ($x[-1]*86400+$stime,$y[-1]);
$stardate = stardate($secs,"localtime=1");
debug("SECS: $secs, wt: $wt");

# compute weight loss and targets time (linear)
$tloss = $sweight-$wt;
$days = ($secs-$stime)/86400;

$startime = strftime("%Y%m%d.%H%M%S", localtime($stime));
print "Starting weight: $sweight at $startime\nCurrent weight: $wt at $stardate\n\n";

printf("Loss of %0.2f lbs in %0.2f days (%0.2f lb per day, %0.2f lb per week)\n", $tloss, $days, $tloss/$days, $tloss/$days*7);

printf("Linear Regression: %0.2f + %0.4f*t = %0.2f\n\n", $b, $m, $b+$m*$days);

# time to targets (linear)
for $i (0..$#t) {
  $time[$i] = ($wt-$t[$i])/($tloss/$days)*86400+$secs;
  # rtime = linear w regression
  $rtime[$i] = ($t[$i]-$b)/$m*86400+$stime;

  # and plotting
  if ($t[$i] >= $graphtarget) {
    $daysfromnow = ($rtime[$i]-$now)/86400;
    append_file("$daysfromnow $t[$i]\n", "/tmp/bwl2.txt");

    $daysfromnow = ($time[$i]-$now)/86400;
    append_file("$daysfromnow $t[$i]\n", "/tmp/bwl4.txt");
  }

  print strftime("Achieve $t[$i] lbs (linear): %c\n",localtime($time[$i]));
  print strftime("Achieve $t[$i] lbs (linreg): %c\n",localtime($rtime[$i]));
  print "\n";
}

# weight loss (log)
$pctloss = $wt/$sweight;

printf("Loss of %0.2f%% in %0.2f days (%0.2f%% per day, %0.2f%% per week)\n", 100*(1-$pctloss), $days, 100*(1-($pctloss**(1/$days))), 100*(1-($pctloss**(7/$days))));

printf("Log regression: %0.2f*(%0.4f)^t = %0.2f\n\n", exp($blog), exp($mlog), exp($blog+$mlog*$days));

# time to targets (log)
for $i (0..$#t) {
  $ltime[$i] = (log($wt)-log($t[$i]))/(log($sweight)-log($wt))*$days*86400+$secs;
  # regressed
  $lrtime[$i] = (log($t[$i])-$blog)/$mlog*86400+$stime;

  # TODO: appending here is silly, should just keep file open longer
  # and plotting
  if ($t[$i] >= $graphtarget) {
    $daysfromnow = ($lrtime[$i]-$now)/86400;
    append_file("$daysfromnow $t[$i]\n", "/tmp/bwl3.txt");

    $daysfromnow = ($ltime[$i]-$now)/86400;
    append_file("$daysfromnow $t[$i]\n", "/tmp/bwl5.txt");
  }

  print strftime("Achieve $t[$i] lbs (strlog): %c\n",localtime($ltime[$i]));
  print strftime("Achieve $t[$i] lbs (logreg): %c\n\n",localtime($lrtime[$i]));
}

open(B,">/tmp/bwl.plt");
print B << "MARK";
# set xdata time
# set timefmt "%Y-%m-%d"
set style line 1 lc rgb "blue"
set style line 2 lc rgb "black"
set style line 3 lc rgb "purple"
set style line 4 lc rgb "green"
set xlabel "Days ago"
set ylabel "Weight"
plot "/tmp/bwl.txt" title "Weight" with linespoints, \\
"/tmp/bwl2.txt" title "LinReg" with linespoints ls 1, \\
"/tmp/bwl3.txt" title "LogReg" with linespoints ls 2, \\
"/tmp/bwl4.txt" title "Linear" with linespoints ls 3, \\
"/tmp/bwl5.txt" title "Log" with linespoints ls 4
pause mouse close
MARK
;

close(B);

# "gnuplot -persist" does not allow mouse-based zooming, so changing?
# unless ($globopts{nograph}) {system("gnuplot -persist /tmp/bwl.plt");}
unless ($globopts{nograph}) {system("gnuplot /tmp/bwl.plt &");}

=item mathematica

To use bwl.m in Mathematica:

f[x_] = a+b*Exp[c*x] /. FindFit[data,a+b*Exp[c*x],{a,b,c},x]

=cut
