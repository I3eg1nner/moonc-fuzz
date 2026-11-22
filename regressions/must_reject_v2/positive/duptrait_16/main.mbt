trait T16 { f(Self) -> Int }
struct S16 { x16 : Int }
impl T16 for S16 with f(self) { self.x16 }
impl T16 for S16 with f(self) { self.x16 }
fn main { println(S16::{x16:16}.f()) }
