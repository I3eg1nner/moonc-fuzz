trait T18 { f(Self) -> Int }
struct S18 { x18 : Int }
impl T18 for S18 with f(self) { self.x18 }
impl T18 for S18 with f(self) { self.x18 }
fn main { println(S18::{x18:18}.f()) }
