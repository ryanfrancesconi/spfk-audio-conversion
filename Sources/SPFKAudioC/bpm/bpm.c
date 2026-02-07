/*
 * Copyright (C) 2013 Mark Hills <mark@xwax.org>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * version 2, as published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * General Public License version 2 for more details.
 *
 * You should have received a copy of the GNU General Public License
 * version 2 along with this program; if not, write to the Free
 * Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 * MA 02110-1301, USA.
 *
 */

#include <assert.h>
#include <math.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <sysexits.h>
#include <unistd.h>

#define BANNER   "bpm (C) Copyright 2013 Mark Hills <mark@xwax.org>"
#define NAME     "bpm"

#define LOWER    84.0
#define UPPER    146.0

#define BLOCK    4096
#define INTERVAL 128

#define ARRAY_SIZE(x) (sizeof(x) / sizeof(*(x)))

/*
 * Sample from the metered energy
 *
 * No need to interpolate and it makes a tiny amount of difference; we
 * take a random sample of samples, any errors are averaged out.
 */

static double sample(const float *data, size_t len, double offset) {
    double n;
    size_t i;

    n = floor(offset);
    i = (size_t)n;

    return (n >= 0.0 && n < (double)len) ? data[i] : 0.0;
}

/*
 * Test an autodifference for the given interval
 */

double autodifference(const float *data, size_t len, double interval) {
    size_t n;
    double mid, v, diff, total;

    static const double beats[] = {
        -32, -16, -8,  -4,  -2,   -1,
        1,   2,   4,   8,   16,   32
    };

    static const double nobeats[] = {
        -0.5, -0.25, 0.25, 0.5
    };

    mid = drand48() * len;
    v = sample(data, len, mid);

    diff = 0.0;
    total = 0.0;

    for (n = 0; n < ARRAY_SIZE(beats); n++) {
        double y, w;

        y = sample(data, len, mid + beats[n] * interval);

        w = 1.0 / fabs(beats[n]);
        diff += w * fabs(y - v);
        total += w;
    }

    for (n = 0; n < ARRAY_SIZE(nobeats); n++) {
        double y, w;

        y = sample(data, len, mid + nobeats[n] * interval);

        w = fabs(nobeats[n]);
        diff -= w * fabs(y - v);
        total += w;
    }

    return diff / total;
}

/*
 * Beats-per-minute to a sampling interval in energy space
 */

double bpm_to_interval(double bpm, double sample_rate) {
    double beats_per_second, samples_per_beat;

    beats_per_second = bpm / 60;
    samples_per_beat = sample_rate / beats_per_second;
    return samples_per_beat / INTERVAL;
}

/*
 * Sampling interval in enery space to beats-per-minute
 */

double interval_to_bpm(double interval, double sample_rate) {
    double samples_per_beat, beats_per_second;

    samples_per_beat = interval * INTERVAL;
    beats_per_second = sample_rate / samples_per_beat;
    return beats_per_second * 60;
}

/*
 * Scan a range of BPM values for the one with the
 * minimum autodifference
 */
double scan_for_bpm(
    const float  *data,
    size_t       len,
    double       sample_rate,
    unsigned int steps,
    unsigned int samples
    ) {
    double step, interval, trough, height;
    unsigned int s;

    double slowest = bpm_to_interval(LOWER, sample_rate);
    double fastest = bpm_to_interval(UPPER, sample_rate);

    step = (slowest - fastest) / steps;

    height = INFINITY;
    trough = NAN;

    for (interval = fastest; interval <= slowest; interval += step) {
        double t;

        t = 0.0;

        for (s = 0; s < samples; s++) {
            t += autodifference(data, len, interval);
        }

        /* Track the lowest value */

        if (t < height) {
            trough = interval;
            height = t;
        }
    }

    return interval_to_bpm(trough, sample_rate);
}

void usage(FILE *f) {
    fputs(BANNER "\n\n", f);

    fprintf(f, "Usage: " NAME " [options]\n"
            "Analyse the tempo (in beats-per-minute, BPM) of incoming audio\n\n"
            "  -g <path>  Output autodifference data to file\n"
            "  -e <path>  Output energy data to file\n"
            "  -f         Print format for final BPM value (default \"%%0.1f\")\n"
            "  -m <f>     Minimum detected BPM (default %0.0f)\n"
            "  -x <f>     Maximum detected BPM (default %0.0f)\n"
            "  -v         Print progress information to stderr\n"
            "  -h         Display this help message and exit\n\n",
            LOWER, UPPER);

    fprintf(f, "To view autodifference or energy data:\n"
            "  $ sox [...] | " NAME " -g file.dat\n"
            "  $ gnuplot\n"
            "  gnuplot> plot \"file.dat\"\n\n");
}

int main_bpm(int argc, char *argv[]) {
    float *data = NULL;
    size_t len = 0, buf = 0;
    off_t n = 0;
    double bpm, min = LOWER, max = UPPER, v = 0.0;
    const char *format = "%0.3f";
    FILE *fdiff = NULL, *fnrg = NULL;

    // dummy
    double sample_rate = 44100;

    for (;;) {
        int c;

        c = getopt(argc, argv, "vf:g:e:m:x:h");

        if (c == -1) {
            break;
        }

        switch (c) {
            case 'f':
                format = optarg;
                break;

            case 'g':
                fdiff = fopen(optarg, "w");

                if (fdiff == NULL) {
                    perror(optarg);
                    return -1;
                }

                break;

            case 'e':
                fnrg = fopen(optarg, "w");

                if (fnrg == NULL) {
                    perror(optarg);
                    return -1;
                }

                break;

            case 'm':
                min = atof(optarg);
                break;

            case 'x':
                max = atof(optarg);
                break;

            case 'h':
                usage(stdout);
                return 0;

            default:
                return EX_USAGE;
        }
    }

    argv += optind;
    argc -= optind;

    if (argc > 0) {
        fprintf(stderr, "%s: Too many arguments\n", NAME);
        return EX_USAGE;
    }

    for (;;) {
        float z;

        if (fread(&z, sizeof z, 1, stdin) != 1) {
            break;
        }

        z = fabsf(z);

        if (z > v) {
            v += (z - v) / 8;
        } else {
            v -= (v - z) / 512;
        }

        n++;

        if (n != INTERVAL) {
            continue;
        }

        n = 0;

        if (len == buf) {
            size_t n;

            n = buf + BLOCK;
            data = realloc(data, n * sizeof(*data));

            if (data == NULL) {
                perror("realloc");
                return -1;
            }

            buf = n;
        }

        if (fnrg != NULL) {
            fprintf(fnrg, "%lf\t%lf\n",
                    (double)len * INTERVAL / sample_rate, v);
        }

        data[len++] = v;
    }

    bpm = scan_for_bpm(data, sample_rate, len, 1024, 1024);

    printf(format, bpm);
    putc('\n', stdout);

    free(data);

    if (fdiff != NULL) {
        if (fclose(fdiff) != 0) {
            perror("fclose");
        }
    }

    if (fnrg != NULL) {
        if (fclose(fnrg) != 0) {
            perror("fclose");
        }
    }

    return 0;
}
