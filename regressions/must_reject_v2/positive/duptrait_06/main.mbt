trait T6 { f(Self) -> Int }
struct S6 { x6 : Int }
impl T6 for S6 with f(self) { self.x6 }
impl T6 for S6 with f(self) { self.x6 }
fn main { println(S6::{x6:6}.f()) }
