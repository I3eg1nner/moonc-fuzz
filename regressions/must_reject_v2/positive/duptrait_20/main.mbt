trait T20 { f(Self) -> Int }
struct S20 { x20 : Int }
impl T20 for S20 with f(self) { self.x20 }
impl T20 for S20 with f(self) { self.x20 }
fn main { println(S20::{x20:20}.f()) }
