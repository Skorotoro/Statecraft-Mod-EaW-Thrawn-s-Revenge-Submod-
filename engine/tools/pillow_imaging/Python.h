/* Stand-in for Python.h: Pillow's imaging core (libImaging, 11.2.1) is built here without Python. */
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <math.h>
#define HAVE_PROTOTYPES 1
#define STDC_HEADERS 1
typedef struct _object PyObject;
typedef ptrdiff_t Py_ssize_t;
#define INT8 int8_t
#define UINT8 uint8_t
#define INT16 int16_t
#define UINT16 uint16_t
#define INT32 int32_t
#define UINT32 uint32_t
#define Py_INCREF(o) ((void)(o))
#define Py_DECREF(o) ((void)(o))
#define PyCapsule_GetPointer(c, n) ((void *)0)
