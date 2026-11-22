trait T15 { f(Self) -> Int }
struct S15 { x15 : Int }
impl T15 for S15 with f(self) { self.x15 }
impl T15 for S15 with f(self) { self.x15 }
fn main { println(S15::{x15:15}.f()) }
