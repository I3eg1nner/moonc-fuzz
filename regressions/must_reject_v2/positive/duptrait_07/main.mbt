trait T7 { f(Self) -> Int }
struct S7 { x7 : Int }
impl T7 for S7 with f(self) { self.x7 }
impl T7 for S7 with f(self) { self.x7 }
fn main { println(S7::{x7:7}.f()) }
