---
name: Fix Qt xcb in Dockerfile
overview: Add missing xcb/X11 libraries to the isaacgym Dockerfile so cv2's Qt xcb plugin can load, enabling the OpenCV HUD window in the container.
todos:
  - id: add-xcb-deps
    content: Add xcb/X11 apt packages to Dockerfile apt-get install block
    status: completed
isProject: false
---

# Fix Qt xcb in isaacgym Dockerfile

## File to modify

- [docker/isaacgym/Dockerfile](docker/isaacgym/Dockerfile) -- add missing apt packages to the existing `apt-get install` block (line 11-30)

## Change

Append these packages to the `apt-get install` list:

```
libxcb-xinerama0 \
libxcb-icccm4 \
libxcb-image0 \
libxcb-keysyms1 \
libxcb-render-util0 \
libxcb-shape0 \
libxcb-xkb1 \
libxkbcommon-x11-0
```

These are the shared library dependencies that Qt5's xcb platform plugin (`/usr/local/lib/python3.8/dist-packages/cv2/qt/plugins/platforms/libqxcb.so`) needs to `dlopen` at runtime.

## What this does NOT change

- No Python dependencies change
- No Isaac Gym behavior changes (GLFW/EGL path is unaffected)
- The image needs to be rebuilt and pushed for the fix to be permanent. Until then, the same packages can be installed ad-hoc in the running container for immediate testing.
