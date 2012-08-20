// Copyright 2012 Intel Corporation
//
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// - Redistributions of source code must retain the above copyright notice, this
//   list of conditions and the following disclaimer.
//
// - Redistributions in binary form must reproduce the above copyright notice,
//   this list of conditions and the following disclaimer in the documentation
//   and/or other materials provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#include <assert.h>
#include <stdlib.h>
#include <string.h>

#include <waffle/waffle_enum.h>

#include <waffle/core/wcore_config_attrs.h>
#include <waffle/core/wcore_error.h>

#include "cgl_config.h"
#include "cgl_error.h"

static const struct wcore_config_vtbl cgl_config_wcore_vtbl;

static bool
cgl_config_destroy(struct wcore_config *wc_self)
{
    bool ok = true;

    if (wc_self == NULL)
        return ok;

    ok &= wcore_config_teardown(wc_self);
    free(cgl_config(wc_self));
    return ok;
}

/// @brief Check the values of `attrs->context_*`.
static bool
cgl_config_check_attrs(const struct wcore_config_attrs *attrs)
{
    int context_version = 10 * attrs->context_major_version
                        + attrs->context_minor_version;

    switch (attrs->context_api) {
        case WAFFLE_CONTEXT_OPENGL:
            switch (context_version) {
                case 10:
                    return true;
                case 32:
                    switch (attrs->context_profile) {
                        case WAFFLE_CONTEXT_CORE_PROFILE:
                            return true;
                        case WAFFLE_CONTEXT_COMPATIBILITY_PROFILE:
                            wcore_errorf(WAFFLE_UNSUPPORTED_ON_PLATFORM,
                                         "CGL does not support the OpenGL 3.2 "
                                         "Compatibility Profile");
                            return false;
                        default:
                            assert(false);
                            return false;
                    }
                default:
                    wcore_errorf(WAFFLE_UNSUPPORTED_ON_PLATFORM,
                                 "On CGL, the requested OpenGL version must "
                                 "be 1.0 or 3.2");
                    assert(false);
                    return false;
            }
        case WAFFLE_CONTEXT_OPENGL_ES1:
            wcore_errorf(WAFFLE_UNSUPPORTED_ON_PLATFORM,
                         "CGL does not support OpenGL ES1");
            return false;
        case WAFFLE_CONTEXT_OPENGL_ES2:
            wcore_errorf(WAFFLE_UNSUPPORTED_ON_PLATFORM,
                         "CGL does not support OpenGL ES2");
            return false;
        default:
            assert(false);
            return false;
    }
}

static bool
cgl_config_fill_pixel_format_attrs(
        const struct wcore_config_attrs *attrs,
        CGLPixelFormatAttribute pixel_attrs[])
{
    int i = 0;
    int context_version = 10 * attrs->context_major_version
                        + attrs->context_minor_version;

    // CGL does not have an analogue for EGL_DONT_CARE. Instead, one indicates
    // "don't care" by omitting the attribute.
    #define ADD_ATTR(name, value) \
        if ((value) != WAFFLE_DONT_CARE) { \
            pixel_attrs[i++] = (name); \
            pixel_attrs[i++] = (value); \
        }

    if (context_version == 10) {
        ADD_ATTR(kCGLPFAOpenGLProfile, (int) kCGLOGLPVersion_Legacy);
    }
    else if (context_version == 32
             && attrs->context_profile == WAFFLE_CONTEXT_CORE_PROFILE) {
        ADD_ATTR(kCGLPFAOpenGLProfile, (int) kCGLOGLPVersion_3_2_Core);
    }
    else {
        wcore_error_internal("version=%d profile=%#x",
                             context_version,
                             attrs->context_profile);
        return false;
    }

    ADD_ATTR(kCGLPFAColorSize,          attrs->rgb_size);
    ADD_ATTR(kCGLPFAAlphaSize,          attrs->alpha_size);
    ADD_ATTR(kCGLPFADepthSize,          attrs->depth_size);
    ADD_ATTR(kCGLPFAStencilSize,        attrs->stencil_size);
    ADD_ATTR(kCGLPFASampleBuffers,      attrs->sample_buffers);
    ADD_ATTR(kCGLPFASamples,            attrs->samples);

    if (context_version == 10)
        ADD_ATTR(kCGLPFAAccumSize,      attrs->accum_buffer);

    if (attrs->double_buffered)
        pixel_attrs[i++] = kCGLPFADoubleBuffer;

    pixel_attrs[i++] = 0;

    #undef ADD_ATTR

    return true;
}

struct wcore_config*
cgl_config_choose(struct wcore_platform *wc_plat,
                  struct wcore_display *wc_dpy,
                  const struct wcore_config_attrs *attrs)
{
    struct cgl_config *self;
    bool ok = true;
    int error = 0;
    int ignore;
    CGLPixelFormatAttribute pixel_attrs[64];

    if (!cgl_config_check_attrs(attrs))
        return NULL;

    self = calloc(1, sizeof(*self));
    if (!self) {
        wcore_error(WAFFLE_OUT_OF_MEMORY);
        return NULL;
    }

    ok = wcore_config_init(&self->wcore, wc_dpy);
    if (!ok)
        goto error;

    ok = cgl_config_fill_pixel_format_attrs(attrs, pixel_attrs);
    if (!ok)
        goto error;

    error = CGLChoosePixelFormat(pixel_attrs, &self->pixel_format, &ignore);
    if (error) {
        cgl_error_failed_func("CGLChoosePixelFormat", error);
        goto error;
    }
    if (!self->pixel_format) {
        wcore_errorf(WAFFLE_UNKNOWN_ERROR,
                     "CGLChoosePixelFormat failed to find a pixel format");
        goto error;
    }

    self->wcore.vtbl = &cgl_config_wcore_vtbl;
    return &self->wcore;

error:
    cgl_config_destroy(&self->wcore);
    return NULL;
}

static union waffle_native_config*
cgl_config_get_native(struct wcore_config *wc_self)
{
    wcore_error(WAFFLE_ERROR_UNSUPPORTED_ON_PLATFORM);
    return NULL;
}

static const struct wcore_config_vtbl cgl_config_wcore_vtbl = {
    .destroy = cgl_config_destroy,
    .get_native = cgl_config_get_native,
};
