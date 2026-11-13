// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "I3eg1nner/mbtfuzz"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/I3eg1nner/moonc-fuzz"

license = "Apache-2.0"

keywords = [ ]

preferred_target = "native"

description = "MoonBit compiler fuzzing/analysis harness"

import {
  "moonbitlang/x@0.5.7",
}
