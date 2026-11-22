trait T11 { f(Self) -> Int }
struct S11 { x11 : Int }
impl T11 for S11 with f(self) { self.x11 }
impl T11 for S11 with f(self) { self.x11 }
fn main { println(S11::{x11:11}.f()) }
