trait T2 { f(Self) -> Int }
struct S2 { x2 : Int }
impl T2 for S2 with f(self) { self.x2 }
impl T2 for S2 with f(self) { self.x2 }
fn main { println(S2::{x2:2}.f()) }
