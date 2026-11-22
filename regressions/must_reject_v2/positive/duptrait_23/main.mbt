trait T23 { f(Self) -> Int }
struct S23 { x23 : Int }
impl T23 for S23 with f(self) { self.x23 }
impl T23 for S23 with f(self) { self.x23 }
fn main { println(S23::{x23:23}.f()) }
