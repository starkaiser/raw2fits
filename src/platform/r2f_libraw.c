/*
 * GNU Lesser General Public License version 2.1
 *
 * Copyright (c) 2026, Sorin Cătălin Păștiță
 *
 * Based on the LibRaw sample unprocessed_raw.cpp, Copyright (C) 2009-2024
 * LibRaw LLC, with FITS and TIFF output by Han Kleijn.
 *
 * This file may be used under the terms of either the GNU Lesser General
 * Public License version 2.1 or the Common Development and Distribution
 * License version 1.0, at your option. See LICENSE-NOTICE.md and the license
 * texts distributed with LibRaw.
 *
 * This software is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.
 */

/*
 * ==================================================================================================
 *
 * This file is part of raw2fits - Program to convert camera RAW files to FITS for stacking
 *
 * PURPOSE :
 *   Minimal ABI adapter between LibRaw and Fortran. LibRaw's C API has no
 *   getters for the unprocessed raw-buffer pointers, the row pitch and several
 *   geometry / maker-note fields. This file copies those fields out of the
 *   public libraw_data_t structure into a flat, interoperable struct (mirrored
 *   by raw_info_t in m_libraw.f90), so the Fortran side never depends on
 *   LibRaw's large, version-dependent layout.
 *
 *   Decoding stays inside LibRaw; all processing and file writing is Fortran.
 *
 * WRITTEN BY :
 *   Sorin Cătălin Păștiță, November 2026
 *
 * ==================================================================================================
 */

#include <stdint.h>
#include <string.h>
/* Debian/Ubuntu put the header in .../include/libraw/ and add .../include to
 * the search path; Homebrew's and FreeBSD's pkg-config add .../include/libraw. */
#if defined(__has_include)
#  if __has_include(<libraw/libraw.h>)
#    include <libraw/libraw.h>
#  else
#    include <libraw.h>
#  endif
#else
#  include <libraw/libraw.h>
#endif

/* Keep in sync with type raw_info_t in src/platform/m_libraw.f90. */
typedef struct r2f_raw_info {
    int32_t raw_width, raw_height;
    int32_t active_width, active_height;
    int32_t left_margin, top_margin;
    int32_t crop_left, crop_top, crop_width, crop_height;
    int32_t filters, colors, flip;
    int32_t raw_kind, raw_channels, raw_stride_channels, raw_pitch_bytes;
    int64_t timestamp;
    double timestamp_subsec;
    float shutter, iso_speed, aperture, focal_len;
    float sensor_temp, camera_temp;
    int32_t cblack[4], linear_max[4];
    char make[64], model[64], lens[128], cdesc[5];
    const void *raw_image;
} r2f_raw_info;

/* Raw buffer kinds (RAW_* constants in m_libraw.f90). */
enum {
    R2F_RAW_NONE = 0,
    R2F_RAW_U16_MONO = 1, R2F_RAW_U16_3 = 2, R2F_RAW_U16_4 = 3,
    R2F_RAW_F32_MONO = 4, R2F_RAW_F32_3 = 5, R2F_RAW_F32_4 = 6
};

static int logical_colors(const libraw_data_t *lr)
{
    return (lr->idata.colors >= 1 && lr->idata.colors <= 4) ? lr->idata.colors : 4;
}

int r2f_raw_get_info(libraw_data_t *lr, r2f_raw_info *out)
{
    if (!lr || !out) return -1;
    memset(out, 0, sizeof(*out));

    out->raw_width     = lr->sizes.raw_width;
    out->raw_height    = lr->sizes.raw_height;
    out->active_width  = lr->sizes.width;
    out->active_height = lr->sizes.height;
    out->left_margin   = lr->sizes.left_margin;
    out->top_margin    = lr->sizes.top_margin;
    out->crop_left     = lr->sizes.raw_inset_crops[0].cleft;
    out->crop_top      = lr->sizes.raw_inset_crops[0].ctop;
    out->crop_width    = lr->sizes.raw_inset_crops[0].cwidth;
    out->crop_height   = lr->sizes.raw_inset_crops[0].cheight;
    out->filters       = (int32_t)lr->idata.filters;
    out->colors        = lr->idata.colors;
    out->flip          = lr->sizes.flip;

    out->timestamp = (int64_t)lr->other.timestamp;
    /* timestamp_subsec is missing from some LibRaw releases: whole seconds. */
    out->timestamp_subsec = 0.0;
    out->shutter     = lr->other.shutter;
    out->iso_speed   = lr->other.iso_speed;
    out->aperture    = lr->other.aperture;
    out->focal_len   = lr->other.focal_len;
    out->sensor_temp = (float)lr->makernotes.common.SensorTemperature;
    out->camera_temp = (float)lr->makernotes.common.CameraTemperature;
    for (int i = 0; i < 4; ++i) {
        out->cblack[i]     = (int32_t)lr->color.cblack[i];
        out->linear_max[i] = (int32_t)lr->color.linear_max[i];
    }
    memcpy(out->make,  lr->idata.make,  sizeof(out->make));
    memcpy(out->model, lr->idata.model, sizeof(out->model));
    memcpy(out->lens,  lr->lens.Lens,   sizeof(out->lens));
    memcpy(out->cdesc, lr->idata.cdesc, sizeof(out->cdesc));
    out->make[sizeof(out->make) - 1]   = '\0';
    out->model[sizeof(out->model) - 1] = '\0';
    out->lens[sizeof(out->lens) - 1]   = '\0';
    out->cdesc[sizeof(out->cdesc) - 1] = '\0';

    /* After unpack() normally exactly one of these buffers is non-NULL. */
    const libraw_rawdata_t *rd = &lr->rawdata;
    if (rd->raw_image) {
        out->raw_kind = R2F_RAW_U16_MONO; out->raw_channels = 1; out->raw_stride_channels = 1;
        out->raw_image = rd->raw_image;
    } else if (rd->color3_image) {
        out->raw_kind = R2F_RAW_U16_3; out->raw_channels = 3; out->raw_stride_channels = 3;
        out->raw_image = rd->color3_image;
    } else if (rd->color4_image) {
        out->raw_kind = R2F_RAW_U16_4; out->raw_channels = logical_colors(lr); out->raw_stride_channels = 4;
        out->raw_image = rd->color4_image;
    } else if (rd->float_image) {
        out->raw_kind = R2F_RAW_F32_MONO; out->raw_channels = 1; out->raw_stride_channels = 1;
        out->raw_image = rd->float_image;
    } else if (rd->float3_image) {
        out->raw_kind = R2F_RAW_F32_3; out->raw_channels = 3; out->raw_stride_channels = 3;
        out->raw_image = rd->float3_image;
    } else if (rd->float4_image) {
        out->raw_kind = R2F_RAW_F32_4; out->raw_channels = logical_colors(lr); out->raw_stride_channels = 4;
        out->raw_image = rd->float4_image;
    } else {
        out->raw_kind = R2F_RAW_NONE;
    }

    /* Byte stride of the unpacked rows; prefer the rawdata copy. */
    out->raw_pitch_bytes = (int32_t)rd->sizes.raw_pitch;
    if (out->raw_pitch_bytes <= 0)
        out->raw_pitch_bytes = (int32_t)lr->sizes.raw_pitch;
    return 0;
}

void r2f_raw_set_shot_select(libraw_data_t *lr, int shot)
{
    if (lr && shot >= 0) lr->rawparams.shot_select = (unsigned)shot;
}
