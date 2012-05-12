// Copyright 2012 Intel Corporation
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/// @defgroup wayland_platform wayland_platform
/// @ingroup wayland
/// @{

/// @file

#pragma once

#include <stdbool.h>

struct native_dispatch;
union native_platform;

union native_platform*
wayland_platform_create(
        int gl_api,
        const struct native_dispatch **dispatch);

bool
wayland_platform_destroy(union native_platform *self);

/// @}
