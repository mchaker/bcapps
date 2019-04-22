// determine when a given object is between two given elevations for a
// given location; this is primarily for sun and moon rise
// calculations, since most other objects have virtually 0 angular width

// START TESTING

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "SpiceUsr.h"
#include "SpiceZfc.h"
#include "/home/user/BCGIT/ASTRO/bclib.h"

// END TESTING

int main(void) {

  furnsh_c("/home/user/BCGIT/ASTRO/standard.tm");

  double stime = 1419984000, etime = 1451692800;
  double lat, lon;

  for (lat=89.80; lat<=90.00; lat+=0.01) {
    for (lon=-180; lon<=180; lon+=10) {

      double *results = bc_between(lat*rpd_c(), lon*rpd_c(), 0, stime, etime,
				   "Sun", -5/6.*rpd_c(), -3/10.*rpd_c());

      for (int i=2; i<1000; i++) {

	// if we start seeing 0s, we are out of true answers
	if (results[2*i] < .001) {break;}

	// if the end result is too close to etime, result is inaccurate
	if (abs(results[2*i+1]-etime)<1) {continue;}
    
	// the "day" and length of sunrise/sunset
	printf("%f %f %f %f\n", lat, lon,
	       ((results[2*i+1]+results[2*i])/2.-stime)/86400., 
	       results[2*i+1]-results[2*i]);
      }
    }
  }
  return 0;
}
