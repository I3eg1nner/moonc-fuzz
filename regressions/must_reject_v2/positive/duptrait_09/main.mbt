trait T9 { f(Self) -> Int }
struct S9 { x9 : Int }
impl T9 for S9 with f(self) { self.x9 }
impl T9 for S9 with f(self) { self.x9 }
fn main { println(S9::{x9:9}.f()) }
