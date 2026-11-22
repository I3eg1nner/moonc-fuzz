type I = Int

fn abs(n : I) -> Int = "Math" "abs"
extern "js" fn abs_ffi(n : I) -> Int = "(n) => Math.abs(n)"
