## Installation
1. Add lifxlan as a dependency in your build.zig.zon:
```sh
zig fetch --save git+https://github.com/jmmoser/lifxlan.zig#main
```
2. In your build.zig, add the lifxlan module as a dependency to your program:
```zig
const lifxlan = b.dependency("lifxlan", .{
    .target = target,
    .optimize = optimize,
});

// the executable from your call to b.addExecutable(...)
exe.root_module.addImport("lifxlan", lifxlan.module("lifxlan"));
```