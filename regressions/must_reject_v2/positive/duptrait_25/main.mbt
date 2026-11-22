trait T25 { f(Self) -> Int }
struct S25 { x25 : Int }
impl T25 for S25 with f(self) { self.x25 }
impl T25 for S25 with f(self) { self.x25 }
fn main { println(S25::{x25:25}.f()) }
