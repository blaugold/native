
#if _WIN32
#define FFI_EXPORT __declspec(dllexport)
#else
#define FFI_EXPORT
#endif

FFI_EXPORT int add(int a, int b) { return a + b; }
