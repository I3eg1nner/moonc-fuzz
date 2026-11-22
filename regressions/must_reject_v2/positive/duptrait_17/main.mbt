trait T17 { f(Self) -> Int }
struct S17 { x17 : Int }
impl T17 for S17 with f(self) { self.x17 }
impl T17 for S17 with f(self) { self.x17 }
fn main { println(S17::{x17:17}.f()) }
