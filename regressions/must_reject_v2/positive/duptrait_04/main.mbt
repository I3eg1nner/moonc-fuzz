trait T4 { f(Self) -> Int }
struct S4 { x4 : Int }
impl T4 for S4 with f(self) { self.x4 }
impl T4 for S4 with f(self) { self.x4 }
fn main { println(S4::{x4:4}.f()) }
