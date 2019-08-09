#!/bin/perl

# Gets local weather from wunderground API solely to print on X root window
# runs from cron every 1m

# -test: in testing mode, use cached data more

# in theory, could get KABQ data from aeris too, more consistent (but
# more delayed?)

# complete rewrite 3 Oct 2018

require "/usr/local/lib/bclib.pl";
require "$bclib{home}/bc-private.pl";

# cache for a long time if testing
# warn "TESTING"; $globopts{test} = 1;
if ($globopts{test}) {$age=3600;} else {$age=-1;}

my($out, $err, $res, $json, %output);

# get current data for KABQ

my($str1) = get_weather_data("KABQ");
my($str2) = get_weather_data("PWS_LORAXABQ");
my($forecasts) = get_forecasts();

# ($out, $err, $res) = cache_command2("$bclib{githome}/bc-quikbak.pl $bclib{home}/ERR/forecast.inf");

write_file_new("$str1$forecasts\n$str2", "$bclib{home}/ERR/forecast.inf");

# now to get forecast data
sub get_forecasts_old {

  my(%order, %data, @forecasts);

  # 102,118 is the grid where I live (in Albuquerque)
  my($out, $err, $res) = cache_command2("curl https://api.weather.gov/gridpoints/ABQ/102,118/forecast", "age=$age");

#  debug("OUT: $out");

  my($json) = JSON::from_json($out);

  for $i (@{$json->{properties}->{periods}}) {

#    debug("PERIOD: $i->{number}");

    # date and time
    $i->{startTime}=~m/(\d{4}-\d{2}-\d{2})T(\d{2})/;
    my($date, $time) = ($1, $2);
    # TODO: insanely ugly, convert m-d-y to unix time and then to localtime?!
    my($day) = strftime("%a%d", localtime(str2time($date)));
    # better way to check day/night
    my($tod) = ($i->{isDaytime} eq "true")?"day":"night";

#    debug("$date/$time/$day/$tod");

    # printing order for this date
    unless ($order{$day}) {$order{$day} = ++$count;}
    # only 7 days
    if ($count >= 8) {last;}

    # forecasted weather
    $data{$day}{$tod}{weather} = parse_forecast($i->{shortForecast});

    # temperature
    $data{$day}{$tod}{temp} = $i->{temperature};

    # TODO: could maybe parse icon for this
    if ($i->{detailedForecast}=~m/precipitation is (\d+%)/) {
      $data{$day}{$tod}{prec} = $1;
    } else {
      $data{$day}{$tod}{prec} = "0%";
    }
  }

  for $i (sort {$order{$a} <=> $order{$b}} keys %data) {
    my($str) = join("/", 
		    $data{$i}{day}{weather}, $data{$i}{night}{weather},
		    $data{$i}{day}{temp}, $data{$i}{night}{temp},
		    $data{$i}{day}{prec}, $data{$i}{night}{prec});

    # cleanup string, mostly for "tonight"
    $str=~s%^/+%%;
    $str=~s%/+%/%g;
    push(@forecasts, "$i:$str");
  }

  my($forecasts) = join("\n", @forecasts);
  return $forecasts;
}

# TODO: consider stopping if not enough good/recent data
# TODO: add heat index?

# this subroutine is specific to this program, do not confuse w/
# wind() in bclib.pl

sub windinfo {
  my($dir, $speed, $gust, $unit) = @_;

  if ($speed == 0 && $gust == 0) {return "CALM";}

  my(@winddirs) = ("N","NNE","NE","ENE", "E","ESE","SE","SSE", "S","SSW","SW","WSW", "W","WNW","NW","NNW","N");

  # tweak for unit
  my($mult);
  if ($unit eq "m/s") {
    $mult = 3600/1609.344;
  } elsif ($unit eq "mph") {
    $mult = 1;
  }

  # convert from m/s to mph
  $speed = sprintf("%0.0f", $speed*$mult);
  $gust = sprintf("%0.0f", $gust*$mult);
  $dir = $winddirs[round($dir/22.5)];
  my($ret) = "$dir $speed";
  if ($gust > $speed) {$ret .= "G$gust";}
  return $ret;
}

# parses shortForecast

sub parse_forecast_old {
  my($forecast) = @_;

  # handle special case "x then y"
  # TODO: can there be 3 or more here?
  if ($forecast=~m%(.*?)\s+then\s+(.*?)$%) {
    return parse_forecast($1)."->".parse_forecast($2);
  }

  # conversion hash
  # TODO: Chance and Slight Change conflict, do I just hope on order (ugh?)
  my(%hash) = (
	       "Rain" => "RA", "And" => "+", "Showers" => "SH",
	       "Thunderstorms" => "TS", "Cloudy" => "CLD",
	       "Partly" => "P", "Mostly" => "M",
	       "Clear" => "CLR", "Sunny" => "CLR",
	       "Slight Chance" => "??", "Scattered" => "SCT",
	       "Isolated" => "ISO", "Likely" => "!", "Snow" => "SN",
	       "Chance" => "?", "Light" => "LT", "T-storms" => "TS"
	       );

#  debug("HASH", keys %hash);

  for $i (keys %hash) {
    debug("OLD: $forecast, KEY: $i");
    $forecast=~s/\s*$i\s*/$hash{$i}/g;
    debug("NEW: $forecast, KEY WAS: $i");
  }

  # can't get this working as a key sigh

  $forecast=~s/Slight\?/??/g;

  return $forecast;
}

# NOTE: this is a subroutine purely for code cleanliness, and is
# specific to this program

# because weather.gov's API sucks (several hours behind on hourly
# data, using this subroutine for KABQ data too

# returns SLIGHTLY different data for PWS than for airports/METAR

sub get_weather_data {

  my($station) = @_;

  my(%output);

  # $age is global

  my($out, $err, $res) = cache_command2("curl 'https://api.aerisapi.com/observations/$station?&client_id=$private{aeris}{accessid}&client_secret=$private{aeris}{secretkey}'", "age=$age");

#  debug("OUT: $out");

  my($json) = JSON::from_json($out);

  my($data) = $json->{response}->{ob};

  $output{timestamp}=strftime("%Y%m%d.%H%M%S", localtime($data->{timestamp}));

  # only used for METAR
  $output{weather} = parse_forecast($data->{weatherShort});

  # convert to proper temperature units
  # truly horrible converting in place!
  for $i ("tempC", "windchillC", "dewpointC") {

  # special case if undefined
    if (defined($data->{$i})) {
      $output{$i} = sprintf("%0.1fF", $data->{$i}*1.8+32);
    } else {
      $output{$i} = "NAF";
    }
  }

  # ugly special case since station reports pointless windchill
  if (abs($output{windchillC}-$output{tempC}) < 1) {
    $output{windchillC} = "NAF";
  }

  $output{humidity} = sprintf("%0.0f%%", $data->{humidity});
  $output{pressure} = sprintf("%0.2fin", $data->{altimeterIN});

  # windspeed and gust are in m/s, direction is in degrees

  $output{wind} = windinfo($data->{'windDirDEG'}, $data->{'windSpeedMPH'},
			 $data->{'windGustSpeedMPH'}, "mph");

  # slightly different string for PWS

  my($str);
  if ($station=~/^PWS/) {
    $str = << "MARK";
Local/$output{tempC}/$output{windchillC}/$output{humidity} ($output{dewpointC}) [$output{timestamp}]
$output{wind} ($output{pressure})
MARK
;
  } else {
    $str = << "MARK";
\@ $output{timestamp}
$output{weather}/$output{tempC}/$output{windchillC}/$output{humidity} ($output{dewpointC})
$output{wind} ($output{pressure})
MARK
;
  }

#  debug("STR: $str");
  return $str;

}


sub get_forecasts {

  my(%order, %data, @forecasts);

  # intentionally setting age to 3600 long-term to avoid excessive API usage
  my($out, $err, $res) = cache_command2("curl 'https://api.aerisapi.com/forecasts/$private{latitude},$private{longitude}?&filter=daynight&limit=16&client_id=$private{aeris}{accessid}&client_secret=$private{aeris}{secretkey}'", "age=3600");

  my($json) = JSON::from_json($out);

#  debug(var_dump("json", $json));

  for $i (@{$json->{response}->[0]->{periods}}) {

    # date and time
#    $i->{startTime}=~m/(\d{4}-\d{2}-\d{2})T(\d{2})/;
    $i->{dateTimeISO}=~m/(\d{4}-\d{2}-\d{2})T(\d{2})/;
    my($date, $time) = ($1, $2);
    # TODO: insanely ugly, convert m-d-y to unix time and then to localtime?!
    my($day) = strftime("%a%d", localtime(str2time($date)));
    # better way to check day/night
#    my($tod) = ($i->{isDaytime} eq "true")?"day":"night";
#    debug("ISDAY: $i->{isDay}");
    my($tod) = $i->{isDay}?"day":"night";

#    debug("$date/$day/$tod");

    # printing order for this date
    unless ($order{$day}) {$order{$day} = ++$count;}
    # only 7 days
    if ($count >= 8) {last;}

    # forecasted weather
    $data{$day}{$tod}{weather} = parse_forecast($i->{weather});

    # temperature
    if ($tod eq "day") {
      $data{$day}{$tod}{temp} = $i->{maxTempF};
    } else {
      $data{$day}{$tod}{temp} = $i->{minTempF};
    }

    $data{$day}{$tod}{prec} = $i->{pop}."%";

    # TODO: could maybe parse icon for this
#    if ($i->{detailedForecast}=~m/precipitation is (\d+%)/) {
#      $data{$day}{$tod}{prec} = $1;
#    } else {
#      $data{$day}{$tod}{prec} = "0%";
#    }
  }

  for $i (sort {$order{$a} <=> $order{$b}} keys %data) {
    my($str) = join("/", 
		    $data{$i}{day}{weather}, $data{$i}{night}{weather},
		    $data{$i}{day}{temp}, $data{$i}{night}{temp},
		    $data{$i}{day}{prec}, $data{$i}{night}{prec});

    # cleanup string, mostly for "tonight"
    $str=~s%^/+%%;
    $str=~s%/+%/%g;
    push(@forecasts, "$i:$str");
  }

  my($forecasts) = join("\n", @forecasts);
  return $forecasts;
}


sub parse_forecast {
  my($forecast) = @_;

  # handle special case "x then y"
  # TODO: can there be 3 or more here?
  if ($forecast=~m%(.*?)\s+then\s+(.*?)$%) {
    return parse_forecast($1)."->".parse_forecast($2);
  }

  # conversion hash
  # TODO: Chance and Slight Change conflict, do I just hope on order (ugh?)
#  my(%hash) = (
#	       "Rain" => "RA", "And" => "+", "Showers" => "SH",
#	       "Thunderstorms" => "TS", "Cloudy" => "CLD",
#	       "Partly" => "P", "Mostly" => "M",
#	       "Clear" => "CLR", "Sunny" => "CLR",
#	       "Slight Chance" => "??", "Scattered" => "SCT",
#	       "Isolated" => "ISO", "Likely" => "!", "Snow" => "SN",
#	       "Chance" => "?", "Light" => "LT", "T-storms" => "TS",
#	       "with" => "+", "Widespread" => "SCT", "Storms" => "STRMS"
#	       );

  my(%hash) = (
	       "Cloudy" => "CLD", "Mostly" => "M", "with" => "+",
	       "Widespread" => "WSPR", "Rain" => "RA", "Showers" => "SH",
	       "Scattered" => "SCT", "Sunny" => "CLR", "Clear" => "CLR",
	       "Partly" => "P", "Isolated" => "ISO", "Storms" => "STRMS",
	       "Light" => "LT", "Chance of" => "?", "Slight Chance of" => "??",
	       "Snow" => "SN", "Wintry Mix" => "(RA+SN)", "Likely" => "LKLY",
	       "Very" => "V", "Windy" => "WNDY", "Numerous" => "NMRS",
	       "Possible" => "?", "Thunderstorms" => "TS"
	       );

#  debug("HASH", keys %hash);

  for $i (keys %hash) {
#    debug("OLD: $forecast, KEY: $i");
    $forecast=~s/\s*$i\s*/$hash{$i}/g;
#    debug("NEW: $forecast, KEY WAS: $i");
  }

  # can't get this working as a key sigh

#  $forecast=~s/Slight\?/??/g;

  return $forecast;
}
